// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Test-only helpers for spinning up real external resources.
//!
//! Everything in this module is compiled only when the `testing` cargo feature is
//! enabled, so it never becomes part of a production build.
//!
//! # Postgres harness
//!
//! `spawn_postgres()` starts an ephemeral PostgreSQL container via the
//! [`testcontainers_modules::postgres::Postgres`] image and returns a
//! ready-to-use [`sqlx::PgPool`] together with the owning
//! [`ContainerAsync`](testcontainers::ContainerAsync) guard. Dropping the guard
//! tears the container down, guaranteeing isolation between tests.
//!
//! On return, the projection schema has already been applied through
//! [`sqlx::migrate!`] from `crates/infra/migrations`. Migration mismatches are
//! propagated as hard errors.
//!
//! ## Local container reuse
//!
//! Starting a fresh container per test adds a few seconds of overhead. For local
//! development speed you can opt into the Testcontainers reuse mechanism:
//!
//! ```bash
//! export TESTCONTAINERS_REUSE=1
//! cargo test -p integration-tests
//! ```
//!
//! When reuse is enabled the container may be kept alive across test runs. CI
//! runners must **never** set this variable; CI always uses fresh containers.

use std::collections::HashMap;
use std::env;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow};
use redis::Client as RedisClient;
use sqlx::PgPool;
use testcontainers::core::{ContainerPort, WaitFor};
use testcontainers::runners::AsyncRunner;
use testcontainers::{ContainerAsync, ContainerRequest, Image, ImageExt, ReuseDirective};
use testcontainers_modules::postgres::Postgres as PostgresImage;

/// Starts an ephemeral Postgres container and returns a configured pool.
///
/// The returned pool is connected to a fresh, empty Postgres instance. The
/// projection schema from `crates/infra/migrations` is applied before the
/// function returns. Dropping the `ContainerAsync` guard stops and removes the
/// container.
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

    // Wait until Postgres is actually accepting queries.
    sqlx::query("SELECT 1").fetch_one(&pool).await?;

    // Apply projection migrations. Mismatches intentionally fail the test.
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

// ---------------------------------------------------------------------------
// SierraDB harness (ADR-016 / Tier-4 round-trip tests)
// ---------------------------------------------------------------------------
//
// No upstream `testcontainers` module exists for SierraDB, so per ADR-014's
// one-harness rule we add a small local `Image` impl here (same crate as the
// Postgres helper) rather than introducing a parallel test-infrastructure crate.
// The image is pinned to `tqwewe/sierradb:0.3.1` (ADR-016). SierraDB speaks
// RESP3 only.

/// Pinned SierraDB image tag (ADR-016). Keep in sync with the dev/prod composes.
pub const SIERRADB_IMAGE_TAG: &str = "0.3.1";

/// RESP3 port exposed by the `tqwewe/sierradb` image.
const SIERRADB_PORT: u16 = 9090;

/// `testcontainers::Image` for the upstream `tqwewe/sierradb` image.
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
        // SierraDB logs `ready to receive connections on …` (tracing, either
        // stdout/stderr depending on image config). The spawn helper additionally
        // performs a bounded-retry ESVER probe as the real cluster-readiness gate.
        vec![WaitFor::message_on_either_std(
            "ready to receive connections",
        )]
    }

    fn expose_ports(&self) -> &[ContainerPort] {
        // The image already `EXPOSE`s 9090; re-declare it so testcontainers maps it
        // even when the image metadata is not inspected.
        static PORTS: [ContainerPort; 1] = [ContainerPort::Tcp(SIERRADB_PORT)];
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
        // Disable cluster networking in single-node mode (enabled by default in
        // sierra.default.toml). On CI runners the QUIC cluster listener may fail
        // to bind, preventing the cluster actor from initialising its topology.
        // Without this the ESCAN command (used by kameo_es EntityActor::resync_with_db)
        // returns PartitionUnavailable → broken pipe.
        HashMap::from([("SIERRADB_NETWORK__CLUSTER_ENABLED", "false")])
    }
}

/// Starts an ephemeral SierraDB container and returns a RESP3 `redis::Client`
/// (wrapped in `Arc` so it can be shared with the projector spawns, mirroring
/// `main.rs`) plus a pre-verified RESP3 `MultiplexedConnection` for the
/// `CommandService`, and the owning [`ContainerAsync`] guard.
///
/// Readiness is gated by two layers:
/// 1. The testcontainer's log-based `ready_conditions` (waits for
///    "ready to receive connections" in the SierraDB log).
/// 2. A bounded-retry cluster-readiness probe using the `ESVER` command on the
///    **same** connection that is returned to the caller. This avoids opening
///    and closing extra connections, which SierraDB v0.3.1 handles poorly.
pub async fn spawn_sierradb() -> Result<(
    Arc<RedisClient>,
    redis::aio::MultiplexedConnection,
    ContainerAsync<SierraDbImage>,
)> {
    let request = build_sierradb_container_request();
    let container = request.start().await?;

    let host = container.get_host().await?;
    let port = container.get_host_port_ipv4(SIERRADB_PORT).await?;
    let url = format!("redis://{host}:{port}/?protocol=resp3");

    let client = Arc::new(RedisClient::open(url.as_str())?);

    // Bounded-retry cluster-readiness probe on a single connection that we
    // will return to the caller. The probe uses `ESVER` which goes through
    // the cluster actor; if the topology isn't ready yet, it retries.
    let mut last_err = None;
    for _ in 0..60 {
        match client.get_multiplexed_tokio_connection().await {
            Ok(conn) => {
                // ESVER on the same connection — if the cluster is ready this
                // succeeds and we return the connection together with the client.
                match redis::cmd("ESVER")
                    .arg("__sierradb_probe__")
                    .query_async::<Option<u64>>(&mut conn.clone())
                    .await
                {
                    Ok(_) => return Ok((client, conn, container)),
                    Err(err) => {
                        last_err = Some(err);
                    }
                }
            }
            Err(err) => {
                last_err = Some(err);
            }
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }

    Err(anyhow!(
        "SierraDB cluster did not become ready within readiness window: {}",
        last_err
            .map(|e| e.to_string())
            .unwrap_or_else(|| "unknown".into())
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
///
/// Tier-4 round-trip tests need to open transactions against the same Postgres
/// pool the read adapter uses (e.g. to re-deliver events to a projector for
/// idempotency checks). `SceneRepositoryImpl` keeps its pool private for
/// production callers; this helper reaches into it from within the `infra`
/// crate (same-crate privacy) and is only compiled under the `testing` feature.
pub fn scene_repo_pool(repo: &crate::queries::SceneRepositoryImpl) -> sqlx::PgPool {
    repo.pool().clone()
}
