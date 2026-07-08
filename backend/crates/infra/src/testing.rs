// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Test-only helpers for spinning up real external resources.
//!
//! Everything in this module is compiled only when the `testing` cargo feature is
//! enabled, so it never becomes part of a production build.

use std::collections::HashMap;
use std::env;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow};
use breakdown_core::error::DomainError;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use redis::Client as RedisClient;
use sqlx::PgPool;
use testcontainers::core::{ContainerPort, WaitFor};
use testcontainers::runners::AsyncRunner;
use testcontainers::{ContainerAsync, ContainerRequest, Image, ImageExt, ReuseDirective};
use testcontainers_modules::postgres::Postgres as PostgresImage;
use breakdown_core::scene::commands;

/// Starts an ephemeral Postgres container and returns a configured pool.
pub async fn spawn_postgres() -> Result<(PgPool, ContainerAsync<PostgresImage>)> {
    let request = build_postgres_container_request();
    let container = request.start().await?;

    let host = container.get_host().await?;
    let port = container.get_host_port_ipv4(5432).await?;
    let url = format!("postgres://postgres:postgres@{host}:{port}/postgres");

    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(&url)
        .await?;

    sqlx::query("SELECT 1").fetch_one(&pool).await?;
    sqlx::migrate!("./migrations").run(&pool).await?;

    Ok((pool, container))
}

fn build_postgres_container_request() -> ContainerRequest<PostgresImage> {
    let image = PostgresImage::default();

    if env::var("TESTCONTAINERS_REUSE")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        image.with_reuse(ReuseDirective::Always)
    } else {
        image.into()
    }
}

/// SierraDB container image (tqwewe/sierradb:0.3.1, ADR-016).
pub const SIERRADB_IMAGE_TAG: &str = "0.3.1";

#[derive(Debug, Default, Clone, Copy)]
pub struct SierraDbImage;

impl Image for SierraDbImage {
    fn name(&self) -> &str { "tqwewe/sierradb" }
    fn tag(&self) -> &str { SIERRADB_IMAGE_TAG }

    fn ready_conditions(&self) -> Vec<WaitFor> {
        vec![WaitFor::message_on_either_std("ready to receive connections")]
    }

    fn expose_ports(&self) -> &[ContainerPort] {
        static PORTS: [ContainerPort; 1] = [ContainerPort::Tcp(9090)];
        &PORTS
    }

    fn env_vars(&self) -> impl IntoIterator<
        Item = (impl Into<std::borrow::Cow<'_, str>>, impl Into<std::borrow::Cow<'_, str>>)
    > {
        HashMap::from([("SIERRADB_NETWORK__CLUSTER_ENABLED", "false")])
    }
}

/// Starts an ephemeral SierraDB container and returns the client + connection + guard.
pub async fn spawn_sierradb(
) -> Result<(Arc<RedisClient>, redis::aio::MultiplexedConnection, ContainerAsync<SierraDbImage>)> {
    let request = build_sierradb_container_request();
    let container = request.start().await?;

    let host = container.get_host().await?;
    let port = container.get_host_port_ipv4(9090).await?;
    let url = format!("redis://{host}:{port}/?protocol=resp3");

    let client = Arc::new(RedisClient::open(url.as_str())?);

    // Bounded-retry cluster-readiness probe (ESVER)
    let mut last_err = None;
    for _ in 0..60 {
        match client.get_multiplexed_tokio_connection().await {
            Ok(conn) => {
                match redis::cmd("ESVER").arg("__sierradb_probe__").query_async::<Option<u64>>(&mut conn.clone()).await {
                    Ok(_) => return Ok((client, conn, container)),
                    Err(err) => last_err = Some(err),
                }
            }
            Err(err) => last_err = Some(err),
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }

    Err(anyhow!(
        "SierraDB cluster did not become ready: {}",
        last_err.map(|e| e.to_string()).unwrap_or_else(|| "unknown".into())
    ))
}

fn build_sierradb_container_request() -> ContainerRequest<SierraDbImage> {
    let image = SierraDbImage;
    if env::var("TESTCONTAINERS_REUSE")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        image.with_reuse(ReuseDirective::Always)
    } else {
        image.into()
    }
}

/// Test-only accessor for the pool backing a `SceneRepositoryImpl`.
pub fn scene_repo_pool(repo: &crate::queries::SceneRepositoryImpl) -> sqlx::PgPool {
    repo.pool().clone()
}

// ─────────────────────────────────────────────────────────────────────────────
// Test App — command → event → reply → projection round-trip harness
// ─────────────────────────────────────────────────────────────────────────────
//
// `CommandService` ist **nicht** `pub extern` (Rust: „pub bedeutet stabil").
// Stattdessen wird sie hinterm `testing`-Feature exportiert.

/// Re-export of `CommandService` from `kameo_es`.
/// Only available behind the `testing` feature.
pub use kameo_es::command_service::CommandService;

/// Holds a SierraDB RESP3 connection alongside the CommandService.
pub struct SierraConnGuard {
    pub conn: redis::aio::MultiplexedConnection,
    _container: ContainerAsync<SierraDbImage>,
}

/// Full test fixture: Postgres + SierraDB + command service + scene adapter.
pub struct TestScene {
    pub cmd_service: CommandService,
    pub scene_commands: crate::event_store::SceneCommandsImpl,
    pub pool: PgPool,
    pub scene_repo: crate::queries::SceneRepositoryImpl,
    _sierra_guard: SierraConnGuard,
    _pg_guard: ContainerAsync<PostgresImage>,
}

impl TestScene {
    /// Build a `TestScene` from a pre-built [`TestApp`].
    pub async fn new(mut app: TestApp) -> Result<Self> {
        let conn_for_cmd_service = app.sierra_client.get_multiplexed_tokio_connection().await?;
        let conn_guard = SierraConnGuard {
            conn: conn_for_cmd_service,
            _container: app.sierra_guard.take().ok_or_else(|| anyhow!("sierradb guard lost"))?,
        };

        let cmd_service = CommandService::new(conn_guard.conn.clone());

        let scene_commands = crate::event_store::SceneCommandsImpl::new(cmd_service.clone());
        let scene_repo = crate::queries::SceneRepositoryImpl::new(app.pool.clone());

        Ok(Self {
            cmd_service,
            scene_commands,
            pool: app.pool,
            scene_repo,
            _sierra_guard: conn_guard,
            _pg_guard: app.pg_guard.ok_or_else(|| anyhow!("pg guard lost"))?,
        })
    }

    /// Execute a `CreateScene` command and return `(scene_id, reply_version)`.
    pub async fn create_scene(
        &self,
        cmd: commands::CreateScene,
    ) -> Result<(uuid::Uuid, breakdown_core::shared::AggregateVersion), DomainError> {
        use SceneCommands;
        self.scene_commands.create(cmd).await
    }

    /// Execute an `UpdateSceneDetails` command and return `reply_version`.
    pub async fn update_scene(
        &self,
        cmd: commands::UpdateSceneDetails,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        use SceneCommands;
        self.scene_commands.update_details(cmd).await
    }

    /// Query the projection for a scene by ID.
    pub async fn find_by_id(&self, scene_id: uuid::Uuid) -> Result<breakdown_core::scene::views::SceneView, DomainError> {
        use SceneRepository;
        self.scene_repo.find_by_id(scene_id).await
    }
}

/// Pre-configured harness: Postgres + SierraDB + Redis client.
pub struct TestApp {
    pub pool: PgPool,
    pub sierra_client: Arc<RedisClient>,
    pg_guard: Option<ContainerAsync<PostgresImage>>,
    sierra_guard: Option<ContainerAsync<SierraDbImage>>,
}

impl TestApp {
    /// Start Postgres + SierraDB containers and return a ready-to-use fixture.
    pub async fn new() -> Result<Self> {
        let (pool, pg_guard) = spawn_postgres().await?;
        let (sierra_client, _conn, sierra_guard) = spawn_sierradb().await?;

        Ok(Self {
            pool,
            sierra_client,
            pg_guard: Some(pg_guard),
            sierra_guard: Some(sierra_guard),
        })
    }
}
