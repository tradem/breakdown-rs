// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Test-harness for integration and end-to-end tests.
//!
//! Provides ephemeral container helpers (`spawn_postgres`, `spawn_sierradb`)
//! and fixture structs (`TestApp`, `TestScene`) mirroring the former
//! `infra::testing` API, so that Tier-1 to Tier-4 tests can spin up
//! real Postgres and SierraDB instances deterministically.
#![allow(dead_code)] // public API consumed by various test binaries compiled separately

use std::collections::HashMap;
use std::env;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow};
use breakdown_core::error::DomainError;
use breakdown_core::photo::ports::PhotoRepository;
use breakdown_core::photo::views::PhotoView;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::shared::PhotoId;
use infra::photo::repository::PhotoRepositoryImpl;
use infra::photo::storage::OpenDalPhotoStorage;
use redis::Client as RedisClient;
use sqlx::PgPool;
use testcontainers::core::{ContainerPort, ExecCommand, Mount, WaitFor};
use testcontainers::runners::AsyncRunner;
use testcontainers::{ContainerAsync, ContainerRequest, Image, ImageExt, ReuseDirective};
use testcontainers_modules::postgres::Postgres as PostgresImage;

use kameo_es::command_service::CommandService;

// ---------------------------------------------------------------------------
// Container helpers
// ---------------------------------------------------------------------------

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
    sqlx::migrate!("../infra/migrations").run(&pool).await?;

    Ok((pool, container))
}

fn build_postgres_container_request() -> ContainerRequest<PostgresImage> {
    let image = PostgresImage::default();

    let base = if env::var("TESTCONTAINERS_REUSE")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        image.with_reuse(ReuseDirective::Always)
    } else {
        image.into()
    };
    base.with_startup_timeout(Duration::from_secs(120))
}

// ---------------------------------------------------------------------------
// SierraDB
// ---------------------------------------------------------------------------

/// SierraDB container image (tqwewe/sierradb:0.3.1, ADR-016).
pub const SIERRADB_IMAGE_TAG: &str = "0.3.1";

#[derive(Debug, Default, Clone, Copy)]
pub struct SierraDbImage;

impl Image for SierraDbImage {
    fn name(&self) -> &str {
        "tqwewe/sierradb"
    }
    fn tag(&self) -> &str {
        SIERRADB_IMAGE_TAG
    }

    fn ready_conditions(&self) -> Vec<WaitFor> {
        vec![WaitFor::message_on_either_std(
            "ready to receive connections",
        )]
    }

    fn expose_ports(&self) -> &[ContainerPort] {
        static PORTS: [ContainerPort; 1] = [ContainerPort::Tcp(9090)];
        &PORTS
    }

    fn env_vars(
        &self,
    ) -> impl IntoIterator<
        Item = (
            impl Into<std::borrow::Cow<'_, str>>,
            impl Into<std::borrow::Cow<'_, str>>,
        ),
    > {
        HashMap::from([("SIERRADB_NETWORK__CLUSTER_ENABLED", "false")])
    }
}

/// Starts an ephemeral SierraDB container and returns the client + multiplexed connection + guard.
pub async fn spawn_sierradb() -> Result<(
    Arc<RedisClient>,
    redis::aio::MultiplexedConnection,
    ContainerAsync<SierraDbImage>,
)> {
    let request = build_sierradb_container_request();
    let container = request.start().await?;

    let host = container.get_host().await?;
    let port = container.get_host_port_ipv4(9090).await?;
    let url = format!("redis://{host}:{port}/0?protocol=resp3");

    let client = Arc::new(RedisClient::open(url.as_str())?);

    // Retry loop: SierraDB may need a few hundred milliseconds to fully initialise.
    let mut last_err = None;
    for _ in 0..60 {
        match client.get_multiplexed_tokio_connection().await {
            Ok(conn) => {
                match redis::cmd("ESVER")
                    .arg("__sierradb_probe__")
                    .query_async::<Option<u64>>(&mut conn.clone())
                    .await
                {
                    Ok(_) => return Ok((client.clone(), conn, container)),
                    Err(err) => last_err = Some(err),
                }
            }
            Err(err) => last_err = Some(err),
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }

    Err(anyhow!(
        "SierraDB did not become ready: {}",
        last_err
            .map(|e| e.to_string())
            .unwrap_or_else(|| "unknown".into())
    ))
}

fn build_sierradb_container_request() -> ContainerRequest<SierraDbImage> {
    let image = SierraDbImage;
    let base = if env::var("TESTCONTAINERS_REUSE")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        image.with_reuse(ReuseDirective::Always)
    } else {
        image.into()
    };
    base.with_startup_timeout(Duration::from_secs(120))
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Garage container image (dxflrs/garage:v1.0.1, ADR-019).
#[derive(Debug, Default, Clone, Copy)]
pub struct GarageImage;

impl Image for GarageImage {
    fn name(&self) -> &str {
        "dxflrs/garage"
    }
    fn tag(&self) -> &str {
        "v1.0.1"
    }

    fn ready_conditions(&self) -> Vec<WaitFor> {
        vec![WaitFor::message_on_either_std("S3 API server listening on")]
    }

    fn expose_ports(&self) -> &[ContainerPort] {
        static PORTS: [ContainerPort; 2] = [ContainerPort::Tcp(3900), ContainerPort::Tcp(3902)];
        &PORTS
    }

    fn env_vars(
        &self,
    ) -> impl IntoIterator<
        Item = (
            impl Into<std::borrow::Cow<'_, str>>,
            impl Into<std::borrow::Cow<'_, str>>,
        ),
    > {
        HashMap::from([
            ("GARAGE_ADMIN_TOKEN", "test_admin_token"),
            (
                "GARAGE_RPC_SECRET",
                "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
            ),
            ("GARAGE_METRICS_TOKEN", "test_metrics_token"),
        ])
    }
}

/// Credentials returned by [`spawn_garage`].
#[derive(Debug, Clone)]
pub struct GarageCredentials {
    pub endpoint: String,
    pub access_key: String,
    pub secret_key: String,
    pub bucket: String,
}

const GARAGE_ADMIN_TOKEN: &str = "test_admin_token";

/// Run a `garage` CLI command inside the container and return stdout as a string.
async fn garage_exec(container: &ContainerAsync<GarageImage>, args: &[&str]) -> Result<String> {
    let mut cmd = vec![
        "/garage".to_string(),
        "-c".to_string(),
        "/etc/garage/config.toml".to_string(),
    ];
    cmd.extend(args.iter().map(|s| s.to_string()));
    let exec = ExecCommand::new(cmd).with_env_vars([("GARAGE_ADMIN_TOKEN", GARAGE_ADMIN_TOKEN)]);
    let mut result = container.exec(exec).await?;
    let stdout = result.stdout_to_vec().await?;
    Ok(String::from_utf8_lossy(&stdout).to_string())
}

/// Start an ephemeral Garage container, provision it (layout, key, bucket),
/// and return the S3 credentials.
pub async fn spawn_garage() -> Result<(GarageCredentials, ContainerAsync<GarageImage>)> {
    let image = GarageImage;

    // Garage requires a config.toml at /etc/garage/config.toml.
    // We create one on the fly and mount it via a temp directory.
    let garage_cfg_dir = tempfile::tempdir()?;
    let config_path = garage_cfg_dir.path().join("config.toml");
    // Write config.toml with literal values (no env var references —
    // Garage v1.0.1 does not expand $VARIABLE in config files).
    // Garage v1.0.x expects a flat config structure (no TOML sections).
    let config_content = format!(
        r#"metadata_dir = "/tmp/garage/meta"
data_dir = "/tmp/garage/data"
db_engine = "sqlite"
block_size = 1048576
replication_mode = "none"

rpc_bind_addr = "0.0.0.0:{rpc_port}"
rpc_public_addr = "127.0.0.1:{rpc_port}"
rpc_secret = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
bootstrap_peers = []

[s3_api]
api_bind_addr = "0.0.0.0:{s3_port}"
s3_region = "garage"

[admin]
admin_token = "test_admin_token"
metrics_token = "test_metrics_token"
"#,
        s3_port = 3900,
        rpc_port = 3901,
    );
    std::fs::write(&config_path, &config_content)?;

    let request: ContainerRequest<GarageImage> = if env::var("TESTCONTAINERS_REUSE")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        image
            .with_reuse(ReuseDirective::Always)
            .with_mount(Mount::bind_mount(
                garage_cfg_dir.path().to_str().unwrap(),
                "/etc/garage",
            ))
            .with_cmd(["/garage", "-c", "/etc/garage/config.toml", "server"])
            .with_startup_timeout(Duration::from_secs(120))
    } else {
        image
            .with_mount(Mount::bind_mount(
                garage_cfg_dir.path().to_str().unwrap(),
                "/etc/garage",
            ))
            .with_cmd(["/garage", "-c", "/etc/garage/config.toml", "server"])
            .with_startup_timeout(Duration::from_secs(120))
    };

    let container = request.start().await?;
    let host = container.get_host().await?;
    let port = container.get_host_port_ipv4(3900).await?;
    let endpoint = format!("http://{host}:{port}");

    // Wait for Garage to be ready by checking the version command.
    for i in 0..60 {
        match garage_exec(&container, &["--version"]).await {
            Ok(v) if !v.is_empty() => break,
            _ => {
                if i == 59 {
                    anyhow::bail!("Garage did not become ready within 60s");
                }
                tokio::time::sleep(Duration::from_millis(1000)).await;
            }
        }
    }

    // Retrieve the node ID (Garage v1.0.1 requires the actual node hex ID,
    // not a container hostname, for layout assignment).
    let status_out = garage_exec(&container, &["status"]).await?;
    let node_id = status_out
        .lines()
        .find_map(|l| {
            let trimmed = l.trim();
            // Skip header/separator lines; a data line starts with a 16-char hex node ID.
            if trimmed.starts_with("====") || trimmed.starts_with("ID") || trimmed.is_empty() {
                return None;
            }
            let first = trimmed.split_whitespace().next()?;
            if first.len() == 16 && first.chars().all(|c| c.is_ascii_hexdigit()) {
                Some(first.to_string())
            } else {
                None
            }
        })
        .ok_or_else(|| anyhow!("Could not parse node ID from garage status:\n{status_out}"))?;

    // Configure the cluster layout (single node).
    garage_exec(
        &container,
        &["layout", "assign", "-z", "dc1", "-c", "1G", &node_id],
    )
    .await?;
    garage_exec(&container, &["layout", "apply", "--version", "1"]).await?;

    // Create an access key (positional name; Garage v1.0.1 removed the --name flag).
    let key_out = garage_exec(&container, &["key", "create", "breakdown-test"]).await?;
    let access_key = key_out
        .lines()
        .find_map(|l| l.trim().strip_prefix("Key ID:"))
        .map(|s| s.trim().to_string())
        .ok_or_else(|| anyhow!("Could not parse access key from: {key_out}"))?;
    let secret_key = key_out
        .lines()
        .find_map(|l| l.trim().strip_prefix("Secret key:"))
        .map(|s| s.trim().to_string())
        .ok_or_else(|| anyhow!("Could not parse secret key from: {key_out}"))?;

    // Create the bucket.
    let bucket = "costume-photos-test".to_string();
    let _ = garage_exec(&container, &["bucket", "create", &bucket]).await;

    // Grant the key read/write/owner permissions on the bucket.
    garage_exec(
        &container,
        &[
            "bucket",
            "allow",
            "--read",
            "--write",
            "--owner",
            "--key",
            &access_key,
            &bucket,
        ],
    )
    .await?;

    Ok((
        GarageCredentials {
            endpoint,
            access_key,
            secret_key,
            bucket,
        },
        container,
    ))
}

// ---------------------------------------------------------------------------
// Shared photo-test helpers
// ---------------------------------------------------------------------------

/// Build a storage adapter from test Garage credentials.
pub fn build_storage(creds: &GarageCredentials) -> OpenDalPhotoStorage {
    let builder = opendal::services::S3::default()
        .endpoint(&creds.endpoint)
        .access_key_id(&creds.access_key)
        .secret_access_key(&creds.secret_key)
        .region("garage")
        .bucket(&creds.bucket);

    let op = opendal::Operator::new(builder)
        .expect("Failed to build S3 operator")
        .finish();

    OpenDalPhotoStorage::new(op)
}

/// Await a photo view from the projection (retry on NotFound).
pub async fn await_photo(
    repo: &PhotoRepositoryImpl,
    photo_id: PhotoId,
    deadline: tokio::time::Instant,
) -> Result<PhotoView> {
    loop {
        match repo.find_by_id(photo_id).await {
            Ok(view) => return Ok(view),
            Err(_) if tokio::time::Instant::now() > deadline => {
                anyhow::bail!("Timed out waiting for photo projection");
            }
            Err(_) => {
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
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

/// Full test fixture: Postgres + SierraDB + command service + scene adapter.
pub struct TestScene {
    pub cmd_service: CommandService,
    pub scene_commands: infra::event_store::SceneCommandsImpl,
    pub pool: PgPool,
    pub scene_repo: infra::queries::SceneRepositoryImpl,
    _sierra_guard: SierraConnGuard,
    _pg_guard: ContainerAsync<PostgresImage>,
}

impl TestScene {
    /// Build a `TestScene` from a pre-built [`TestApp`].
    /// The passed-in `app.pool` is cloned so the caller retains it for spawning projectors.
    pub async fn new(mut app: TestApp) -> Result<Self> {
        let pool_clone = app.pool.clone();
        let conn_for_cmd_service = app.sierra_client.get_multiplexed_tokio_connection().await?;
        let conn_guard = SierraConnGuard {
            conn: conn_for_cmd_service,
            _container: app
                .sierra_guard
                .take()
                .ok_or_else(|| anyhow!("sierradb guard lost"))?,
        };

        let cmd_service = CommandService::new(conn_guard.conn.clone());

        let scene_commands = infra::event_store::SceneCommandsImpl::new(cmd_service.clone());
        let scene_repo = infra::queries::SceneRepositoryImpl::new(pool_clone.clone());

        Ok(Self {
            cmd_service,
            scene_commands,
            pool: pool_clone,
            scene_repo,
            _sierra_guard: conn_guard,
            _pg_guard: app
                .pg_guard
                .take()
                .ok_or_else(|| anyhow!("pg guard lost"))?,
        })
    }

    /// Execute a `CreateScene` command and return `(scene_id, reply_version)`.
    pub async fn create_scene(
        &self,
        cmd: breakdown_core::scene::commands::CreateScene,
    ) -> Result<(uuid::Uuid, breakdown_core::shared::AggregateVersion), DomainError> {
        use SceneCommands;
        self.scene_commands.create(cmd).await
    }

    /// Execute an `UpdateSceneDetails` command and return `reply_version`.
    pub async fn update_scene(
        &self,
        cmd: breakdown_core::scene::commands::UpdateSceneDetails,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        use SceneCommands;
        self.scene_commands.update_details(cmd).await
    }

    /// Query the projection for a scene by ID.
    pub async fn find_by_id(
        &self,
        scene_id: uuid::Uuid,
    ) -> Result<breakdown_core::scene::views::SceneView, DomainError> {
        use SceneRepository;
        self.scene_repo.find_by_id(scene_id).await
    }
}

/// Holds a SierraDB RESP3 connection alongside the CommandService.
pub struct SierraConnGuard {
    pub conn: redis::aio::MultiplexedConnection,
    _container: ContainerAsync<SierraDbImage>,
}
