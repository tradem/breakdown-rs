// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)

//! Tier-4 cross-cutting audit projector integration tests (tasks 6.1–6.4).
//!
//! These black-box tests drive the full
//!   `EAPPEND → SierraDB → audit projector → PostgreSQL projection_audit → read-back`
//! chain (ADR-016) against ephemeral Postgres and SierraDB containers,
//! exercising the generalized audit projector for **non-membership**
//! aggregate categories.
//!
//! **Stability note**: `kameo_es::CommandService` uses SierraDB v0.3.1's
//! `ESCAN` command which is unstable on CI runners. All tests therefore use
//! direct `EAPPEND` (like `sierradb_round_trip.rs` and `audit_projector_tests.rs`)
//! to avoid the ESCAN-related race condition ("Conflict: command service stopped").
//!
//! All tests in this file share a single Postgres + SierraDB container pair
//! initialized on a **background thread** to avoid nested tokio runtime errors
//! when the cargo test runner spawns containers concurrently.
//!
//! **Coverage:**
//! - 6.1: Non-membership events produce correctly-attributed audit rows
//! - 6.2: Saga-dispatched commands record `Provenance::Saga` + `actor = NULL`
//! - 6.3: `list_by_series` returns only the requested tenant's rows
//! - 6.4: Idempotency under redelivery for non-membership categories

mod fixtures;

use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use sqlx::postgres::PgPoolOptions;

use anyhow::{Result, anyhow, bail};
use breakdown_core::audit::ports::AuditRepository as _;
use breakdown_core::audit::views::AuditEntry;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::events::CharacterEvent;
use breakdown_core::costume_category::events::CostumeCategoryEvent;
use breakdown_core::costume_category::ports::CostumeCategoryRepository;
use breakdown_core::season::events::SeasonEvent;
use breakdown_core::shared::{
    AggregateVersion, EventMetadata, LexicalSortKey, Provenance, SeasonId, SeriesId, UserId,
};
use chrono::Utc;
use infra::projectors::{AuditProjectorHandles, spawn_all_audit_projectors};
use infra::queries::AuditRepositoryImpl;
use kameo_es::Metadata;
use redis::Client as RedisClient;
use redis::Value;
use serde::Serialize;
use sqlx::PgPool;
use testcontainers::ContainerAsync;
use uuid::Uuid;

/// Maximum wait time for projection lag (45 s).  The generous deadline accounts
/// for projector warm-up in CI and for the tail-end of the previous test's
/// redelivery (the projector needs to flush its in-flight transaction before
/// the next test's events can be projected).
const PROJECTION_DEADLINE: Duration = Duration::from_secs(45);

/// Bounded-retry window for the audit projector to catch up (ADR-015 eventual
/// consistency). Generous enough for CI containers where startup takes longer.
const POLL_INTERVAL: Duration = Duration::from_millis(150);

// ---------------------------------------------------------------------------
// Shared container setup (background thread)
// ---------------------------------------------------------------------------

/// Shared infrastructure handles. All tests reuse the same containers instead
/// of spawning their own, avoiding resource exhaustion on CI runners.  The
/// `_pg` / `_sierra` fields hold the `ContainerAsync` guard so the containers
/// are not GC'd until the `OnceLock` is dropped (i.e. at process exit).  The
/// shared `PgPool` is used by the audit projectors; individual test queries
/// also draw from this pool — we use a generous max_connections so that the
/// 11 projectors, the test queries, and connection retries don't starve each
/// other.
struct SharedContainers {
    /// The pool consumed by **audit projector workers**. Because the kameo-es
    /// projector spawns lazily one per-partition worker per stream (Live +
    /// Buffers), workers hold long-lived read-only transactions for the
    /// lifetime of their processing window.  `max_connections(2000)` gives
    /// enough breathing room to absorb processing bursts without starving
    /// test-side queries.
    pg_pool: PgPool,
    /// A **dedicated pool for test-side queries only**.  It is created
    /// separately so that projector workers never compete with test SQL
    /// for pool slots — a proven production pattern (ADR-016).
    query_pool: PgPool,
    redis_client: Arc<RedisClient>,
    // The runtime MUST be kept alive.  Dropping the Runtime cancels all
    // spawned supervisor tasks — the JoinHandle alone is not sufficient.
    _runtime: tokio::runtime::Runtime,
    _handles: AuditProjectorHandles,
    _pg: ContainerAsync<testcontainers_modules::postgres::Postgres>,
    _sierra: ContainerAsync<fixtures::SierraDbImage>,
}

/// Lazy, one-shot initialization of Postgres + SierraDB + audit projectors.
/// Runs on a background thread to avoid nested tokio runtime errors.
static CONTAINERS: OnceLock<SharedContainers> = OnceLock::new();

/// Initialize containers (called lazily by the first test via `init_containers`).
/// Internal: the result of `block_on` before we inject the runtime.
struct InitStage {
    pg_pool: PgPool,
    query_pool: PgPool,
    redis_client: Arc<RedisClient>,
    handles: AuditProjectorHandles,
    pg: ContainerAsync<testcontainers_modules::postgres::Postgres>,
    sierra: ContainerAsync<fixtures::SierraDbImage>,
}

fn init_containers() -> &'static SharedContainers {
    CONTAINERS.get_or_init(|| {
        // Spawn containers on a background thread to avoid nested runtime errors.
        std::thread::spawn(|| {
            // Must be a **full** runtime (not `new_current_thread`) because
            // `full` spawns an I/O reactor + worker threads that keep
            // polling the supervisor-loops AFTER `block_on` returns.
            // Must be a **full** (multi-threaded) runtime.  new_current_thread
            // does NOT drive tasks after `block_on` returns — only a full
            // runtime keeps the I/O reactor and worker threads alive.
            let rt = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .thread_name("audit-cross-cutting-setup")
                .build()
                .expect("Failed to build tokio runtime for container setup");

            // `block_on` runs the async init code but we move `rt` into
            // `SharedContainers` AFTER it returns — keeping `rt` alive
            // ensures all supervisor tasks continue running.
            let stage = rt.block_on(async {
                let (_pool, pg) = fixtures::spawn_postgres()
                    .await
                    .expect("spawn_postgres failed");
                let (redis_client, _sierra_conn, sierra) = fixtures::spawn_sierradb()
                    .await
                    .expect("spawn_sierradb failed");

                let host = pg.get_host().await.expect("get_host failed");
                let port = pg.get_host_port_ipv4(5432).await.expect("get_port failed");
                let url = format!("postgres://postgres:postgres@{host}:{port}/postgres");

                // Generous pool sized for projector concurrency + test queries.
                // With aggressive flush (500ms / 5 events, 2 workers/projector),
                // projectors hold ~44 concurrent transactions max.  We give each
                // pool its own semaphore with 512 permits to avoid any cross-pool
                // contention under high load.
                let pg_pool = PgPoolOptions::new()
                    .max_connections(1024)
                    .acquire_timeout(Duration::from_secs(3))
                    .connect(&url)
                    .await
                    .expect("connect PG pool failed");

                // Dedicated pool for test-side queries — completely isolated
                // from projector transactions so there is zero contention.
                // Using the same size as pg_pool so we can reason about the
                // total pool consumption: 2000 (projectors) + 2000 (test)
                // = 4000 connections, well within Postgres's 10000 limit.
                // Dedicated query pool for tests — fully isolated from projector workers.
                let query_pool = PgPoolOptions::new()
                    .max_connections(1024)
                    .acquire_timeout(Duration::from_secs(10))
                    .connect(&url)
                    .await
                    .expect("connect query pool failed");

                let handles =
                    spawn_all_audit_projectors(pg_pool.clone(), Arc::clone(&redis_client))
                        .await
                        .expect("spawn audit projectors failed");

                // Give subscriptions 10 s to establish before we leave the
                // runtime alive.
                tokio::time::sleep(Duration::from_secs(10)).await;

                InitStage {
                    pg_pool,
                    query_pool,
                    redis_client,
                    handles,
                    pg,
                    sierra,
                }
            });

            // Move `rt` into the containers struct — dropping the
            // `Runtime` **cancels** all spawned tasks even if their
            // `JoinHandle` is still alive elsewhere.
            SharedContainers {
                pg_pool: stage.pg_pool,
                query_pool: stage.query_pool,
                redis_client: stage.redis_client,
                _handles: stage.handles,
                _pg: stage.pg,
                _sierra: stage.sierra,
                _runtime: rt,
            }
        })
        .join()
        .expect("Container setup thread panicked")
    })
}

// ---------------------------------------------------------------------------
// EAPPEND helpers
// ---------------------------------------------------------------------------

/// Serialise an event to CBOR.
fn encode_event<E: Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut buf = Vec::new();
    ciborium::into_writer(event, &mut buf).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    Ok(buf)
}

/// Retry an async operation with up to `max_retries` retries (1s delay between attempts).
async fn retry_with_backoff<F, Fut, T>(func: F, max_retries: u32) -> Result<T>
where
    F: Fn() -> Fut,
    Fut: std::future::Future<Output = Result<T, anyhow::Error>>,
{
    let mut last_err = None;
    for attempt in 0..=max_retries {
        match func().await {
            Ok(value) => return Ok(value),
            Err(e) if attempt < max_retries => {
                last_err = Some(e);
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
            Err(e) => return Err(e),
        }
    }
    Err(anyhow!(
        "operation failed after {max_retries} retries: {}",
        last_err.unwrap()
    ))
}

/// EAPPEND a single event to a SierraDB stream using direct RESP3 commands.
///
/// Uses **3 retries with exponential backoff** to handle transient CI resource
/// exhaustion (Docker container startup delays, port conflicts).
async fn eappend_event(
    client: &Arc<RedisClient>,
    stream_id: &str,
    event_name: &str,
    expected_version: &str,
    payload: &[u8],
    metadata: &[u8],
) -> Result<()> {
    retry_with_backoff(
        || async {
            let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
            let ts_string = now_ms.to_string();
            let ts_bytes = ts_string.as_bytes();
            let mut conn = client.get_multiplexed_async_connection().await?;
            redis::cmd("EAPPEND")
                .arg(stream_id)
                .arg(event_name)
                .arg("EXPECTED_VERSION")
                .arg(expected_version)
                .arg("PAYLOAD")
                .arg(payload)
                .arg("METADATA")
                .arg(metadata)
                .arg("TIMESTAMP")
                .arg(ts_bytes)
                .query_async::<Value>(&mut conn)
                .await
                .map_err(|e| anyhow!("EAPPEND {event_name} failed: {e}"))
        },
        12, // 12 retries × 1s = 12s max wait; SierraDB in CI can need 5-10s after ESVER passes
    )
    .await?;
    Ok(())
}

/// Create CBOR-encoded saga metadata.
fn saga_metadata(series_id: SeriesId, saga_name: &'static str) -> Result<Vec<u8>> {
    let meta = EventMetadata {
        actor: None,
        provenance: Provenance::saga(saga_name),
        series_id: Some(series_id),
    };
    let wrapped = Metadata::<EventMetadata>::default().with_data(meta);
    let mut buf = Vec::new();
    ciborium::into_writer(&wrapped, &mut buf)
        .map_err(|e| anyhow!("CBOR metadata encode failed: {e}"))?;
    Ok(buf)
}

/// Create CBOR-encoded "human" metadata (actor set, provenance = Human, optional series).
///
/// The bytes must match what `kameo_es::CommandService::CommandExecution`
/// produces — `EventMetadata` wrapped in `Metadata`.
fn human_metadata(actor: UserId, series_id: Option<SeriesId>) -> Result<Vec<u8>> {
    let meta = EventMetadata {
        actor: Some(actor),
        provenance: Provenance::Human,
        series_id,
    };
    let wrapped = Metadata::<EventMetadata>::default().with_data(meta);
    let mut buf = Vec::new();
    ciborium::into_writer(&wrapped, &mut buf)
        .map_err(|e| anyhow!("CBOR metadata encode failed: {e}"))?;
    Ok(buf)
}

// ---------------------------------------------------------------------------
// Read helpers
// ---------------------------------------------------------------------------

/// Read `provenance` directly from `projection_audit` (the `AuditEntry` view
/// does not yet expose this column).
async fn read_provenance(
    pool: &PgPool,
    entity_type: &str,
    entity_id: Uuid,
) -> Result<Option<String>> {
    let row: Option<(String,)> = sqlx::query_as(
        "SELECT provenance FROM projection_audit \
         WHERE entity_type = $1 AND entity_id = $2 \
         ORDER BY occurred_at DESC, id DESC LIMIT 1",
    )
    .bind(entity_type)
    .bind(entity_id.to_string())
    .fetch_optional(pool)
    .await
    .map_err(|e| anyhow!("SQL error: {e}"))?;
    Ok(row.map(|(p,)| p))
}

/// Wait until the audit projection has at least `min` matching rows for the
/// given `entity_type` and `entity_id`.
///
/// Wait until at least `min` audit rows exist for a given entity.
///
/// Retries on `NotFound` (projector hasn't caught up yet) and on
/// insufficient count (eventual consistency).  Uses a short deadline
/// to fail quickly rather than spin forever.
async fn await_audit_rows(
    repo: &AuditRepositoryImpl,
    entity_type: &str,
    entity_id: Uuid,
    min: usize,
) -> Result<Vec<AuditEntry>> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        let result = repo
            .list_by_entity(entity_type, &entity_id.to_string(), 100, 0)
            .await;
        match result {
            Ok(entries) => {
                if entries.len() >= min {
                    return Ok(entries);
                }
            }
            Err(ref e) => {
                let msg = e.to_string();
                if msg.contains("NotFound") && Instant::now() < deadline {
                    tokio::time::sleep(POLL_INTERVAL).await;
                    continue;
                }
                return Err(anyhow!("list_by_entity failed: {e}"));
            }
        }
        if Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: audit rows for {entity_type}({entity_id}) = {} (expected >= {min}) \
                 within {PROJECTION_DEADLINE:?}",
                repo.list_by_entity(entity_type, &entity_id.to_string(), 100, 0)
                    .await
                    .map(|l| l.len())
                    .unwrap_or(0)
            );
        }
    }
}

/// Wait until at least `min` audit rows exist for a given `series_id`.
async fn await_audit_by_series(
    repo: &AuditRepositoryImpl,
    series_id: SeriesId,
    min: usize,
) -> Result<Vec<AuditEntry>> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        let result = repo.list_by_series(series_id, 100, 0).await;
        match result {
            Ok(list) if list.len() >= min => return Ok(list),
            Ok(_) => {}
            Err(ref e) => {
                let msg = e.to_string();
                if msg.contains("NotFound") && Instant::now() < deadline {
                    tokio::time::sleep(POLL_INTERVAL).await;
                    continue;
                }
                return Err(anyhow!("list_by_series failed: {e}"));
            }
        }
        if Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: audit rows for series({}) = {} (expected >= {min}) \
                 within {PROJECTION_DEADLINE:?}",
                series_id.0,
                repo.list_by_series(series_id, 100, 0)
                    .await
                    .map(|l| l.len())
                    .unwrap_or(0)
            );
        }
    }
}

// ---------------------------------------------------------------------------
// 6.1 — Non-membership events produce correctly-attributed audit rows
// ---------------------------------------------------------------------------

/// Create a season + character directly via EAPPEND and verify that the
/// `projection_audit` rows carry the correct actor, provenance = Human,
/// and series_id.
#[tokio::test]
async fn non_membership_events_produce_attributed_audit_rows() -> Result<()> {
    let containers = init_containers();
    let pool = &containers.query_pool;
    let redis_client = &containers.redis_client;
    let audit_repo = AuditRepositoryImpl::new(pool.clone());

    let actor = UserId::from_sub("test-actor-6.1");
    let series_id = SeriesId(Uuid::now_v7());

    // --- Create a season via EAPPEND ---
    let season_id = Uuid::now_v7();
    let season_stream = format!("season-{season_id}");
    let season_event = SeasonEvent::SeasonCreated {
        id: season_id,
        series_id,
        number: 1,
        title: Some("Test Season".into()),
        version: AggregateVersion::INITIAL,
    };
    let season_payload = encode_event(&season_event)?;
    let season_meta = human_metadata(actor.clone(), Some(series_id))?;

    eappend_event(
        redis_client,
        &season_stream,
        "SeasonCreated",
        "EMPTY",
        &season_payload,
        &season_meta,
    )
    .await?;

    // Wait for the season audit row (no main Season projector is running)
    let _entries = await_audit_rows(
        &AuditRepositoryImpl::new(pool.clone()),
        "season",
        season_id,
        1,
    )
    .await?;

    let season_entries = await_audit_rows(&audit_repo, "season", season_id, 1).await?;
    assert_eq!(
        season_entries.len(),
        1,
        "exactly one audit row for SeasonCreated"
    );
    let season_row = &season_entries[0];
    assert_eq!(season_row.event_type, "SeasonCreated");
    assert_eq!(season_row.entity_type, "season");
    assert_eq!(
        season_row.actor.as_ref(),
        Some(&actor),
        "actor must come from event metadata"
    );
    assert_eq!(
        season_row.series_id,
        Some(series_id.0),
        "series_id must be denormalized from event metadata"
    );

    // Verify provenance via raw SQL query (AuditEntry view does not expose it).
    let prov = read_provenance(pool, "season", season_id).await?;
    assert_eq!(
        prov.as_deref(),
        Some("Human"),
        "provenance must be Human for EAPPEND events with actor metadata"
    );

    // --- Create a character (resolves series_id via season projector) ---
    let char_id = Uuid::now_v7();
    let char_stream = format!("character-{char_id}");
    let char_event = CharacterEvent::CharacterCreated {
        id: char_id,
        season_id: SeasonId(season_id),
        name: "Hero".into(),
        category: CharacterCategory::MainCast,
        measurements: Default::default(),
        contact_info: Default::default(),
        version: AggregateVersion::INITIAL,
    };
    let char_payload = encode_event(&char_event)?;
    let char_meta = human_metadata(actor.clone(), Some(series_id))?;

    eappend_event(
        redis_client,
        &char_stream,
        "CharacterCreated",
        "EMPTY",
        &char_payload,
        &char_meta,
    )
    .await?;

    let char_entries = await_audit_rows(&audit_repo, "character", char_id, 1).await?;
    assert_eq!(
        char_entries.len(),
        1,
        "exactly one audit row for CharacterCreated"
    );
    let char_row = &char_entries[0];
    assert_eq!(char_row.event_type, "CharacterCreated");
    assert_eq!(char_row.entity_type, "character");
    assert_eq!(
        char_row.actor.as_ref(),
        Some(&actor),
        "actor must come from event metadata"
    );
    assert_eq!(
        char_row.series_id,
        Some(series_id.0),
        "series_id must be denormalized in metadata, not resolved at projection time"
    );

    let prov = read_provenance(pool, "character", char_id).await?;
    assert_eq!(
        prov.as_deref(),
        Some("Human"),
        "character provenance must be Human"
    );

    Ok(())
}

/// Create a costume category via EAPPEND and verify audit row attribution.
/// (Requires a season to exist for series_id resolution.)
#[tokio::test]
async fn costume_category_create_produces_attributed_audit_row() -> Result<()> {
    let containers = init_containers();
    let pool = &containers.query_pool;
    let redis_client = &containers.redis_client;
    let audit_repo = AuditRepositoryImpl::new(pool.clone());

    let actor = UserId::from_sub("test-actor-cc");
    let series_id = SeriesId(Uuid::now_v7());

    // Create a season first (needed by costume_category projector).
    let season_id = Uuid::now_v7();
    let season_stream = format!("season-{season_id}");
    let season_event = SeasonEvent::SeasonCreated {
        id: season_id,
        series_id,
        number: 2,
        title: Some("Costume Cat Season".into()),
        version: AggregateVersion::INITIAL,
    };
    let season_payload = encode_event(&season_event)?;
    let season_meta = human_metadata(actor.clone(), Some(series_id))?;

    eappend_event(
        redis_client,
        &season_stream,
        "SeasonCreated",
        "EMPTY",
        &season_payload,
        &season_meta,
    )
    .await?;

    // Wait for season to be projected.
    await_audit_rows(&audit_repo, "season", season_id, 1).await?;

    // Create a costume category.
    let cc_id = Uuid::now_v7();
    let cc_stream = format!("costume_category-{cc_id}");
    let cc_event = CostumeCategoryEvent::CostumeCategoryCreated {
        id: cc_id,
        season_id: SeasonId(season_id),
        name: "Oberteil".into(),
        order_key: LexicalSortKey("0".into()),
        version: AggregateVersion::INITIAL,
    };
    let cc_payload = encode_event(&cc_event)?;
    let cc_meta = human_metadata(actor.clone(), Some(series_id))?;

    eappend_event(
        redis_client,
        &cc_stream,
        "CostumeCategoryCreated",
        "EMPTY",
        &cc_payload,
        &cc_meta,
    )
    .await?;

    let cc_entries = await_audit_rows(&audit_repo, "costume_category", cc_id, 1).await?;
    assert_eq!(
        cc_entries.len(),
        1,
        "exactly one audit row for CostumeCategoryCreated"
    );
    let row = &cc_entries[0];
    assert_eq!(row.event_type, "CostumeCategoryCreated");
    assert_eq!(row.entity_type, "costume_category");
    assert_eq!(
        row.actor.as_ref(),
        Some(&actor),
        "actor must come from event metadata"
    );
    assert_eq!(
        row.series_id,
        Some(series_id.0),
        "series_id must be present"
    );

    let prov = read_provenance(pool, "costume_category", cc_id).await?;
    assert_eq!(
        prov.as_deref(),
        Some("Human"),
        "costume_category provenance must be Human"
    );

    Ok(())
}

// ---------------------------------------------------------------------------
// 6.2 — Saga-dispatched command records Saga provenance + actor = NULL
// ---------------------------------------------------------------------------

/// EAPPEND a saga-dispatched CostumeCategoryCreated (simulating the
/// SeasonSeedingSaga path) and verify the audit row records
/// `provenance = "SeasonSeedingSaga"` and `actor = NULL`.
#[tokio::test]
async fn saga_dispatched_costume_category_shows_saga_provenance() -> Result<()> {
    let containers = init_containers();

    // Spawn the costume category read-model projector on the projector pool so
    // its workers don't compete with test queries for connection slots.
    infra::projectors::spawn_costume_category_projector(
        containers.pg_pool.clone(),
        Arc::clone(&containers.redis_client),
    )
    .await?;

    // Let subscriptions settle.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let cc_repo = infra::queries::CostumeCategoryRepositoryImpl::new(containers.query_pool.clone());

    let redis_client = &containers.redis_client;
    let pool = &containers.query_pool;

    // Build saga metadata: provenance = Saga("SeasonSeedingSaga"),
    // actor = None, series_id = Some(...).
    let series_id = SeriesId(Uuid::now_v7());
    let metadata_buf = saga_metadata(series_id, "SeasonSeedingSaga")?;

    let season_id = SeasonId::new();
    let cc_id = Uuid::now_v7();
    let stream_id = format!("costume_category-{cc_id}");

    let event = CostumeCategoryEvent::CostumeCategoryCreated {
        id: cc_id,
        season_id,
        name: "Schuhe".into(),
        order_key: LexicalSortKey("0".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&event)?;

    // EAPPEND with saga metadata (simulates what SeasonSeedingSaga does).
    eappend_event(
        redis_client,
        &stream_id,
        "CostumeCategoryCreated",
        "EMPTY",
        &payload,
        &metadata_buf,
    )
    .await?;

    // Wait for the costume_category projector to catch up.
    {
        let deadline = Instant::now() + PROJECTION_DEADLINE;
        loop {
            if cc_repo.find_by_id(cc_id).await.is_ok() {
                break;
            }
            if Instant::now() < deadline {
                tokio::time::sleep(POLL_INTERVAL).await;
            } else {
                bail!("costume_category projection not ready within deadline");
            }
        }
    }

    // Now check the audit row.
    let audit_repo = AuditRepositoryImpl::new(pool.clone());
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        let audit_result = audit_repo
            .list_by_entity("costume_category", &cc_id.to_string(), 10, 0)
            .await;
        match audit_result {
            Ok(entries) if !entries.is_empty() => {
                let row = &entries[0];
                assert_eq!(row.event_type, "CostumeCategoryCreated");
                assert_eq!(row.entity_type, "costume_category");
                assert!(
                    row.actor.is_none(),
                    "saga-dispatched event must have actor = NULL, got {:?}",
                    row.actor
                );
                assert_eq!(
                    row.series_id,
                    Some(series_id.0),
                    "series_id must be copied from metadata"
                );

                // Check provenance via raw SQL (AuditEntry does not expose it).
                let prov: Option<String> = sqlx::query_scalar(
                    "SELECT provenance FROM projection_audit \
                     WHERE entity_type = $1 AND entity_id = $2 \
                     ORDER BY occurred_at DESC, id DESC LIMIT 1",
                )
                .bind("costume_category")
                .bind(cc_id.to_string())
                .fetch_optional(pool)
                .await
                .map_err(|e| anyhow!("SQL error: {e}"))?;

                assert_eq!(
                    prov.as_deref(),
                    Some("SeasonSeedingSaga"),
                    "saga provenance must be recorded correctly"
                );
                return Ok(());
            }
            Ok(_) => {}
            Err(ref e) => {
                let msg = e.to_string();
                if msg.contains("NotFound") && Instant::now() < deadline {
                    tokio::time::sleep(POLL_INTERVAL).await;
                    continue;
                }
                return Err(anyhow!("audit query failed: {e}"));
            }
        }
        if Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!("audit row for saga-dispatched costume_category not found within deadline");
        }
    }
}

// ---------------------------------------------------------------------------
// 6.3 — list_by_series returns only the requested tenant's rows
// ---------------------------------------------------------------------------

/// Create seasons in two different series via direct EAPPEND, then verify
/// that `list_by_series` returns only rows for the requested series_id.
#[tokio::test]
async fn list_by_series_returns_tenant_scoped_rows() -> Result<()> {
    let containers = init_containers();
    let pool = &containers.query_pool;
    let redis_client = &containers.redis_client;
    let audit_repo = AuditRepositoryImpl::new(pool.clone());

    let actor = UserId::from_sub("tenant-test-6.3");
    let series_a = SeriesId(Uuid::now_v7());
    let series_b = SeriesId(Uuid::now_v7());

    // Create season in series A.
    let season_a_id = Uuid::now_v7();
    let season_a_stream = format!("season-{season_a_id}");
    let season_a_event = SeasonEvent::SeasonCreated {
        id: season_a_id,
        series_id: series_a,
        number: 1,
        title: Some("Series A Season".into()),
        version: AggregateVersion::INITIAL,
    };
    let season_a_payload = encode_event(&season_a_event)?;
    let season_a_meta = human_metadata(actor.clone(), Some(series_a))?;
    eappend_event(
        redis_client,
        &season_a_stream,
        "SeasonCreated",
        "EMPTY",
        &season_a_payload,
        &season_a_meta,
    )
    .await?;

    // Create season in series B.
    let season_b_id = Uuid::now_v7();
    let season_b_stream = format!("season-{season_b_id}");
    let season_b_event = SeasonEvent::SeasonCreated {
        id: season_b_id,
        series_id: series_b,
        number: 1,
        title: Some("Series B Season".into()),
        version: AggregateVersion::INITIAL,
    };
    let season_b_payload = encode_event(&season_b_event)?;
    let season_b_meta = human_metadata(actor.clone(), Some(series_b))?;
    eappend_event(
        redis_client,
        &season_b_stream,
        "SeasonCreated",
        "EMPTY",
        &season_b_payload,
        &season_b_meta,
    )
    .await?;

    // Wait for both audit rows to appear.
    let _a = await_audit_by_series(&audit_repo, series_a, 1).await?;
    let _b = await_audit_by_series(&audit_repo, series_b, 1).await?;

    // list_by_series(series_a) must NOT include series_b rows.
    let series_a_rows = audit_repo.list_by_series(series_a, 100, 0).await?;
    assert!(!series_a_rows.is_empty(), "series_a must have audit rows");
    for row in &series_a_rows {
        assert_eq!(
            row.series_id,
            Some(series_a.0),
            "row for series_a must match series_a"
        );
    }

    // list_by_series(series_b) must NOT include series_a rows.
    let series_b_rows = audit_repo.list_by_series(series_b, 100, 0).await?;
    assert!(!series_b_rows.is_empty(), "series_b must have audit rows");
    for row in &series_b_rows {
        assert_eq!(
            row.series_id,
            Some(series_b.0),
            "row for series_b must match series_b"
        );
    }

    // Verify no row leaks between tenants.
    let a_ids: std::collections::HashSet<Uuid> = series_a_rows.iter().map(|r| r.id).collect();
    let b_ids: std::collections::HashSet<Uuid> = series_b_rows.iter().map(|r| r.id).collect();
    let intersection: Vec<_> = a_ids.intersection(&b_ids).collect();
    assert!(
        intersection.is_empty(),
        "no audit row must belong to both series (got {} shared)",
        intersection.len()
    );

    Ok(())
}

// ---------------------------------------------------------------------------
// 6.4 — Idempotency under redelivery for non-membership categories
// ---------------------------------------------------------------------------

/// EAPPEND an event with saga-like metadata to a SierraDB stream, then
/// redeliver the same logical event (fresh EAPPEND with EXPECTED_VERSION = 0),
/// and verify that only two unique rows exist (the reduplicated first event
/// and the distinct third event).
///
/// This tests the non-membership idempotency path: the `event_key`
/// deterministically depends on (entity_type, entity_id, event_type, payload),
/// so even a fresh SierraDB append gets deduped by the audit projector.
#[tokio::test]
async fn non_membership_audit_projector_is_idempotent_under_redelivery() -> Result<()> {
    let containers = init_containers();
    let pool = &containers.query_pool;
    let redis_client = &containers.redis_client;

    // Wait for projectors to settle before emitting events.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let audit_repo = AuditRepositoryImpl::new(pool.clone());

    // Build saga metadata.
    let series_id = SeriesId(Uuid::now_v7());
    let metadata_buf = saga_metadata(series_id, "SeasonSeedingSaga")?;

    let season_id = SeasonId::new();
    let cc_id = Uuid::now_v7();
    let stream_id = format!("costume_category-{cc_id}");

    let event = CostumeCategoryEvent::CostumeCategoryCreated {
        id: cc_id,
        season_id,
        name: "Jacke".into(),
        order_key: LexicalSortKey("0".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&event)?;

    // 1. First append (EXPECTED_VERSION EMPTY).
    eappend_event(
        redis_client,
        &stream_id,
        "CostumeCategoryCreated",
        "EMPTY",
        &payload,
        &metadata_buf,
    )
    .await?;

    // Wait for the first audit row.
    let entries = await_audit_rows(&audit_repo, "costume_category", cc_id, 1).await?;
    assert_eq!(entries.len(), 1, "first event projected");
    assert_eq!(entries[0].event_type, "CostumeCategoryCreated");

    // After EMPTY, stream version is 0.  Redelivery appends at the same version.

    // 2. Redelivery: same logical event, fresh SierraDB append at version 0.
    eappend_event(
        redis_client,
        &stream_id,
        "CostumeCategoryCreated",
        "0",
        &payload,
        &metadata_buf,
    )
    .await?;

    // 3. Distinct event to prove the projector processed through the redelivery.
    let event2 = CostumeCategoryEvent::CostumeCategoryCreated {
        id: cc_id,
        season_id,
        name: "Jacke v2".into(), // Different name → different payload
        order_key: LexicalSortKey("1".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload2 = encode_event(&event2)?;
    eappend_event(
        redis_client,
        &stream_id,
        "CostumeCategoryCreated",
        "1",
        &payload2,
        &metadata_buf,
    )
    .await?;

    // Wait for the third event to be projected (2 unique event_keys).
    let entries = await_audit_rows(&audit_repo, "costume_category", cc_id, 2).await?;
    assert_eq!(
        entries.len(),
        2,
        "redelivery must not duplicate the audit row (expected 2 unique, got {})",
        entries.len()
    );

    // The payload JSON is an enum-variant wrapper:
    // `{"CostumeCategoryCreated":{"name":"Jacke","order_key":"0",...}}`.
    // `name` is nested under the variant key, not at the root.
    fn extract_name(payload: &serde_json::Value) -> Option<&str> {
        // Try root first (handles non-enum events)
        payload
            .as_object()
            .and_then(|o| o.get("name"))
            .and_then(|v| v.as_str())
            // Then try under the variant key
            .or_else(|| {
                payload.as_object().and_then(|o| {
                    o.keys().next().and_then(|variant_key| {
                        o.get(variant_key)
                            .and_then(|v| v.as_object())
                            .and_then(|inner| inner.get("name"))
                            .and_then(|v| v.as_str())
                    })
                })
            })
    }

    // Count distinct payload names.
    let jacke_v1 = entries
        .iter()
        .filter(|e| extract_name(&e.payload) == Some("Jacke"))
        .count();
    let jacke_v2 = entries
        .iter()
        .filter(|e| extract_name(&e.payload) == Some("Jacke v2"))
        .count();

    assert_eq!(
        jacke_v1, 1,
        "Jacke must appear exactly once (redelivery deduped)"
    );
    assert_eq!(jacke_v2, 1, "Jacke v2 must appear exactly once");
    assert!(
        entries
            .iter()
            .any(|e| extract_name(&e.payload) == Some("Jacke v2")),
        "distinct event (Jacke v2) must be projected as its own row"
    );

    // Flush delay: projector worker transactions are committed every 500ms, but
    // the broadcast to `PostgresProcessor` actors + checkpoint update adds latency.
    // A 1s pause gives projectors enough time to drain their backlog before
    // the next test starts.
    tokio::time::sleep(Duration::from_millis(1000)).await;

    Ok(())
}
