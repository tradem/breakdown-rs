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
//! via `LazyLock` to avoid spawning multiple containers in parallel on CI
//! runners (which causes resource exhaustion / connection refused errors).
//!
//! **Coverage:**
//! - 6.1: Non-membership events produce correctly-attributed audit rows
//! - 6.2: Saga-dispatched commands record `Provenance::Saga` + `actor = NULL`
//! - 6.3: `list_by_series` returns only the requested tenant's rows
//! - 6.4: Idempotency under redelivery for non-membership categories

mod fixtures;

use std::sync::Arc;
use std::sync::LazyLock;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use breakdown_core::audit::ports::AuditRepository as _;
use breakdown_core::audit::views::AuditEntry;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::events::CharacterEvent;
use breakdown_core::costume_category::events::CostumeCategoryEvent;
use breakdown_core::costume_category::ports::CostumeCategoryRepository;
use breakdown_core::season::events::SeasonEvent;
use breakdown_core::season::ports::SeasonRepository;
use breakdown_core::shared::{
    AggregateVersion, EventMetadata, LexicalSortKey, Provenance, SeasonId, SeriesId, UserId,
};
use chrono::Utc;
use infra::projectors::spawn_all_audit_projectors;
use infra::queries::{AuditRepositoryImpl, SeasonRepositoryImpl};
use redis::Client as RedisClient;
use redis::Value;
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

/// Bounded-retry window for the audit projector to catch up (ADR-015 eventual
/// consistency). Generous enough for CI containers where startup takes longer.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(30);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

// ---------------------------------------------------------------------------
// Shared container setup (LazyLock)
// ---------------------------------------------------------------------------

/// Shared infrastructure handles. All tests reuse the same containers instead
/// of spawning their own, avoiding resource exhaustion on CI runners.
struct TestContainers {
    pool: PgPool,
    redis_client: Arc<RedisClient>,
}

/// Lazy, one-shot initialization of Postgres + SierraDB + audit projectors.
/// All 5 tests in this file share this setup.
static CONTAINERS: LazyLock<TestContainers> = LazyLock::new(|| {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("Failed to build tokio runtime for container setup");

    rt.block_on(async {
        let (pool, _pg) = fixtures::spawn_postgres()
            .await
            .expect("spawn_postgres failed");
        let (redis_client, _sierra_conn, _sierra) = fixtures::spawn_sierradb()
            .await
            .expect("spawn_sierradb failed");

        // Spawn ALL audit projectors (11 categories including non-membership).
        spawn_all_audit_projectors(pool.clone(), Arc::clone(&redis_client))
            .await
            .expect("spawn audit projectors failed");

        // Let subscriptions settle.
        tokio::time::sleep(Duration::from_millis(500)).await;

        TestContainers { pool, redis_client }
    })
});

// ---------------------------------------------------------------------------
// EAPPEND helpers
// ---------------------------------------------------------------------------

/// Serialise an event to CBOR.
fn encode_event<E: Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut buf = Vec::new();
    ciborium::into_writer(event, &mut buf).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    Ok(buf)
}

/// EAPPEND a single event to a SierraDB stream using direct RESP3 commands.
///
/// The `metadata` parameter must be CBOR-encoded `EventMetadata`.
async fn eappend_event(
    client: &Arc<RedisClient>,
    stream_id: &str,
    event_name: &str,
    expected_version: &str,
    payload: &[u8],
    metadata: &[u8],
) -> Result<()> {
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
        .map_err(|e| anyhow!("EAPPEND {event_name} failed: {e}"))?;
    Ok(())
}

/// Create CBOR-encoded saga metadata.
fn saga_metadata(series_id: SeriesId, saga_name: &'static str) -> Result<Vec<u8>> {
    let meta = EventMetadata {
        actor: None,
        provenance: Provenance::saga(saga_name),
        series_id: Some(series_id),
    };
    let mut buf = Vec::new();
    ciborium::into_writer(&meta, &mut buf)
        .map_err(|e| anyhow!("CBOR metadata encode failed: {e}"))?;
    Ok(buf)
}

/// Create CBOR-encoded "human" metadata (actor set, provenance = Human, optional series).
fn human_metadata(actor: UserId, series_id: Option<SeriesId>) -> Result<Vec<u8>> {
    let meta = EventMetadata {
        actor: Some(actor),
        provenance: Provenance::Human,
        series_id,
    };
    let mut buf = Vec::new();
    ciborium::into_writer(&meta, &mut buf)
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
async fn await_audit_rows(
    repo: &AuditRepositoryImpl,
    entity_type: &str,
    entity_id: Uuid,
    min: usize,
) -> Result<Vec<AuditEntry>> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let result = repo
            .list_by_entity(entity_type, &entity_id.to_string(), 100, 0)
            .await;
        match result {
            Ok(entries) if entries.len() >= min => return Ok(entries),
            Ok(_) => {}
            Err(ref e) => {
                let msg = e.to_string();
                if msg.contains("NotFound") && std::time::Instant::now() < deadline {
                    tokio::time::sleep(POLL_INTERVAL).await;
                    continue;
                }
                return Err(anyhow!("list_by_entity failed: {e}"));
            }
        }
        if std::time::Instant::now() < deadline {
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
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let result = repo.list_by_series(series_id, 100, 0).await;
        match result {
            Ok(list) if list.len() >= min => return Ok(list),
            Ok(_) => {}
            Err(ref e) => {
                let msg = e.to_string();
                if msg.contains("NotFound") && std::time::Instant::now() < deadline {
                    tokio::time::sleep(POLL_INTERVAL).await;
                    continue;
                }
                return Err(anyhow!("list_by_series failed: {e}"));
            }
        }
        if std::time::Instant::now() < deadline {
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
    let pool = &CONTAINERS.pool;
    let redis_client = &CONTAINERS.redis_client;
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

    // Wait for the season to be projected first.
    {
        let _season = SeasonRepositoryImpl::new(pool.clone())
            .find_by_id(season_id)
            .await?;
    }

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
    let pool = &CONTAINERS.pool;
    let redis_client = &CONTAINERS.redis_client;
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
    let pool = &CONTAINERS.pool;
    let redis_client = &CONTAINERS.redis_client;

    // Spawn the costume category projector AND the audit projector for
    // costume_category, so both projection and audit rows are produced.
    infra::projectors::spawn_costume_category_projector(pool.clone(), Arc::clone(redis_client))
        .await?;

    // Let subscriptions settle.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let cc_repo = infra::queries::CostumeCategoryRepositoryImpl::new(pool.clone());

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
        let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
        loop {
            if cc_repo.find_by_id(cc_id).await.is_ok() {
                break;
            }
            if std::time::Instant::now() < deadline {
                tokio::time::sleep(POLL_INTERVAL).await;
            } else {
                bail!("costume_category projection not ready within deadline");
            }
        }
    }

    // Now check the audit row.
    let audit_repo = AuditRepositoryImpl::new(pool.clone());
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
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
                if msg.contains("NotFound") && std::time::Instant::now() < deadline {
                    tokio::time::sleep(POLL_INTERVAL).await;
                    continue;
                }
                return Err(anyhow!("audit query failed: {e}"));
            }
        }
        if std::time::Instant::now() < deadline {
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
    let pool = &CONTAINERS.pool;
    let redis_client = &CONTAINERS.redis_client;
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
    let pool = &CONTAINERS.pool;
    let redis_client = &CONTAINERS.redis_client;

    // Let spawn_all_audit_projectors run during LazyLock init.
    // This test needs the costume_category projector that was spawned.
    tokio::time::sleep(Duration::from_millis(200)).await;

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

    // 1. First append (EXPECTED_VERSION EMPTY → version 0→1).
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

    // 2. Redelivery: same logical event, fresh SierraDB append (version 0→2,
    // but same payload → same event_key → deduped by audit projector).
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
        "0",
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

    // Count distinct payload names.
    let jacke_v1 = entries
        .iter()
        .filter(|e| {
            matches!(
                &e.payload.as_object(),
                Some(obj) if obj.get("name").and_then(|v| v.as_str()) == Some("Jacke")
            )
        })
        .count();
    let jacke_v2 = entries
        .iter()
        .filter(|e| {
            matches!(
                &e.payload.as_object(),
                Some(obj) if obj.get("name").and_then(|v| v.as_str()) == Some("Jacke v2")
            )
        })
        .count();

    assert_eq!(
        jacke_v1, 1,
        "Jacke must appear exactly once (redelivery deduped)"
    );
    assert_eq!(jacke_v2, 1, "Jacke v2 must appear exactly once");
    assert!(
        entries.iter().any(|e| {
            matches!(
                &e.payload.as_object(),
                Some(obj) if obj.get("name").and_then(|v| v.as_str()) == Some("Jacke v2")
            )
        }),
        "distinct event (Jacke v2) must be projected as its own row"
    );

    Ok(())
}
