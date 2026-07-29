// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)

//! Tier-4 cross-cutting audit projector integration tests (tasks 6.1–6.4).
//!
//! These black-box tests drive the full `command → SierraDB → audit
//! projector → PostgreSQL projection_audit → read-back` chain (ADR-016)
//! against ephemeral Postgres and SierraDB containers, exercising the
//! generalized audit projector for **non-membership** aggregate categories.
//!
//! **Coverage:**
//! - 6.1: Non-membership events produce correctly-attributed audit rows
//! - 6.2: Saga-dispatched commands record `Provenance::Saga` + `actor = NULL`
//! - 6.3: `list_by_series` returns only the requested tenant's rows
//! - 6.4: Idempotency under redelivery for non-membership categories

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use breakdown_core::audit::ports::AuditRepository as _;
use breakdown_core::audit::views::AuditEntry;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::commands::CreateCharacter;
use breakdown_core::character::ports::CharacterCommands;
use breakdown_core::costume_category::commands::CreateCostumeCategory;
use breakdown_core::costume_category::ports::CostumeCategoryCommands;
use breakdown_core::season::commands::CreateSeason;
use breakdown_core::season::ports::SeasonCommands;
use breakdown_core::shared::{
    AggregateVersion, EventMetadata, LexicalSortKey, Provenance, SeasonId, SeriesId, UserId,
};
use infra::event_store::{
    CharacterCommandsImpl, CostumeCategoryCommandsImpl, SeasonCommandsImpl,
};
use infra::projectors::spawn_all_audit_projectors;
use infra::queries::{
    AuditRepositoryImpl, CharacterRepositoryImpl, CostumeCategoryRepositoryImpl,
    SeasonRepositoryImpl,
};
use kameo_es::command_service::CommandService;
use redis::Client as RedisClient;
use sqlx::PgPool;
use uuid::Uuid;

/// Bounded-retry window for the audit projector to catch up (ADR-015 eventual
/// consistency). Mirrors `audit_projector_tests.rs`.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

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

/// Spin up Postgres + SierraDB + the season projector + all audit projectors.
///
/// Returns the pool, command service, and repository handles needed for the
/// cross-cutting audit tests.
async fn init() -> Result<(
    PgPool,
    CommandService,
    AuditRepositoryImpl,
    Arc<RedisClient>,
)> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    // Spawn the season projector (needed for series_id resolution by other
    // command adapters).
    let _sp =
        infra::projectors::spawn_season_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    // Spawn ALL audit projectors (11 categories).
    let _ap = spawn_all_audit_projectors(pool.clone(), Arc::clone(&redis_client)).await?;

    // Give subscriptions time to settle.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let cmd_service = CommandService::new(
        redis_client
            .get_multiplexed_async_connection()
            .await?,
    );
    let audit_repo = AuditRepositoryImpl::new(pool.clone());

    Ok((pool, cmd_service, audit_repo, redis_client))
}

// ---------------------------------------------------------------------------
// 6.1 — Non-membership events produce correctly-attributed audit rows
// ---------------------------------------------------------------------------

/// Create a season + character via command adapters and verify that the
/// `projection_audit` rows carry the correct actor, provenance = Human,
/// and series_id.
#[tokio::test]
async fn non_membership_events_produce_attributed_audit_rows() -> Result<()> {
    let (pool, cmd_svc, audit_repo, _redis) = init().await?;

    let actor = UserId::from_sub("test-actor-6.1");
    let series_id = SeriesId(Uuid::now_v7());

    // --- Create a season (carries series_id in its payload) ---
    let season_cmd = SeasonCommandsImpl::new(cmd_svc.clone(), SeasonRepositoryImpl::new(pool.clone()));
    let season_id = Uuid::now_v7();
    let season_cmd_create = CreateSeason {
        id: season_id,
        series_id,
        number: 1,
        title: Some("Test Season".into()),
    };
    let (rid, _rv) = season_cmd.create(actor.clone(), season_cmd_create).await?;
    assert_eq!(rid, season_id);
    let season_entries = await_audit_rows(&audit_repo, "season", season_id, 1).await?;
    assert_eq!(season_entries.len(), 1, "exactly one audit row for SeasonCreated");
    let season_row = &season_entries[0];
    assert_eq!(season_row.event_type, "SeasonCreated");
    assert_eq!(season_row.entity_type, "season");
    assert_eq!(
        season_row.actor.as_deref(),
        Some(&actor),
        "actor must come from command metadata"
    );
    assert_eq!(
        season_row.series_id,
        Some(series_id.0),
        "series_id must be denormalized from event metadata"
    );

    // Verify provenance via raw SQL query (AuditEntry view does not expose it).
    let prov = read_provenance(&pool, "season", season_id).await?;
    assert_eq!(
        prov.as_deref(),
        Some("Human"),
        "provenance must be Human for command-adapter-dispatched events"
    );

    // --- Create a character (resolves series_id via season projector) ---
    let char_cmd = CharacterCommandsImpl::new(
        cmd_svc.clone(),
        CharacterRepositoryImpl::new(pool.clone()),
        SeasonRepositoryImpl::new(pool.clone()),
    );
    let char_id = Uuid::now_v7();
    let char_cmd_create = CreateCharacter {
        id: char_id,
        season_id: SeasonId(season_id),
        name: "Hero".into(),
        category: CharacterCategory::MainCast,
    };
    let (rid, _rv) = char_cmd.create(actor.clone(), char_cmd_create).await?;
    assert_eq!(rid, char_id);
    let char_entries = await_audit_rows(&audit_repo, "character", char_id, 1).await?;
    assert_eq!(char_entries.len(), 1, "exactly one audit row for CharacterCreated");
    let char_row = &char_entries[0];
    assert_eq!(char_row.event_type, "CharacterCreated");
    assert_eq!(char_row.entity_type, "character");
    assert_eq!(
        char_row.actor.as_deref(),
        Some(&actor),
        "actor must come from command metadata"
    );
    assert_eq!(
        char_row.series_id,
        Some(series_id.0),
        "series_id must be denormalized in metadata, not resolved at projection time"
    );

    let prov = read_provenance(&pool, "character", char_id).await?;
    assert_eq!(
        prov.as_deref(),
        Some("Human"),
        "character provenance must be Human"
    );

    Ok(())
}

/// Create a costume category via the command adapter and verify audit row
/// attribution. (Requires a season to exist for series_id resolution.)
#[tokio::test]
async fn costume_category_create_produces_attributed_audit_row() -> Result<()> {
    let (pool, cmd_svc, audit_repo, _redis) = init().await?;

    let actor = UserId::from_sub("test-actor-cc");
    let series_id = SeriesId(Uuid::now_v7());

    // Create a season first (needed by costume_category adapter).
    let season_cmd = SeasonCommandsImpl::new(cmd_svc.clone(), SeasonRepositoryImpl::new(pool.clone()));
    let season_id = Uuid::now_v7();
    season_cmd
        .create(
            actor.clone(),
            CreateSeason {
                id: season_id,
                series_id,
                number: 2,
                title: Some("Costume Cat Season".into()),
            },
        )
        .await?;

    // Wait for season to be projected.
    await_audit_rows(&audit_repo, "season", season_id, 1).await?;

    // Create a costume category.
    let cc_cmd = CostumeCategoryCommandsImpl::new(
        cmd_svc.clone(),
        CostumeCategoryRepositoryImpl::new(pool.clone()),
        SeasonRepositoryImpl::new(pool.clone()),
    );
    let cc_id = Uuid::now_v7();
    cc_cmd
        .create(
            actor.clone(),
            CreateCostumeCategory {
                id: cc_id,
                season_id: SeasonId(season_id),
                name: "Oberteil".into(),
                order_key: LexicalSortKey("0".into()),
            },
        )
        .await?;

    let cc_entries = await_audit_rows(&audit_repo, "costume_category", cc_id, 1).await?;
    assert_eq!(cc_entries.len(), 1, "exactly one audit row for CostumeCategoryCreated");
    let row = &cc_entries[0];
    assert_eq!(row.event_type, "CostumeCategoryCreated");
    assert_eq!(row.entity_type, "costume_category");
    assert_eq!(row.actor.as_deref(), Some(&actor));
    assert_eq!(row.series_id, Some(series_id.0));

    let prov = read_provenance(&pool, "costume_category", cc_id).await?;
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

fn encode_event<E: serde::Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut buf = Vec::new();
    ciborium::into_writer(event, &mut buf).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    Ok(buf)
}

/// EAPPEND a saga-dispatched CostumeCategoryCreated (simulating the
/// SeasonSeedingSaga path) and verify the audit row records
/// `provenance = "SeasonSeedingSaga"` and `actor = NULL`.
#[tokio::test]
async fn saga_dispatched_costume_category_shows_saga_provenance() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    // Spawn the costume category projector AND the audit projector for
    // costume_category, so both projection and audit rows are produced.
    let _cc_proj = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    let _ap = spawn_all_audit_projectors(pool.clone(), Arc::clone(&redis_client)).await?;

    // Let subscriptions settle.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let cc_repo = CostumeCategoryRepositoryImpl::new(pool.clone());

    // Build a saga-like metadata payload: provenance = Saga("SeasonSeedingSaga"),
    // actor = None, series_id = Some(...).
    let series_id = SeriesId(Uuid::now_v7());
    let saga_metadata = EventMetadata {
        actor: None,
        provenance: Provenance::saga("SeasonSeedingSaga"),
        series_id: Some(series_id),
    };
    let mut metadata_buf = Vec::new();
    ciborium::into_writer(&saga_metadata, &mut metadata_buf)
        .map_err(|e| anyhow!("CBOR metadata encode failed: {e}"))?;

    let season_id = SeasonId::new();
    let cc_id = Uuid::now_v7();
    let stream_id = format!("costume_category-{cc_id}");

    let event = breakdown_core::costume_category::events::CostumeCategoryEvent::CostumeCategoryCreated {
        id: cc_id,
        season_id,
        name: "Schuhe".into(),
        order_key: LexicalSortKey("0".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&event)?;

    // EAPPEND with saga metadata (simulates what SeasonSeedingSaga does).
    let now_ms = chrono::Utc::now()
        .timestamp_millis()
        .try_into()
        .unwrap_or(0u64);
    {
        let mut conn = redis_client.get_multiplexed_async_connection().await?;
        let _resp: redis::Value = redis::cmd("EAPPEND")
            .arg(&stream_id)
            .arg("CostumeCategoryCreated")
            .arg("EXPECTED_VERSION")
            .arg("EMPTY")
            .arg("PAYLOAD")
            .arg(&payload)
            .arg("METADATA")
            .arg(&metadata_buf)
            .arg("TIMESTAMP")
            .arg(now_ms.to_string().as_bytes())
            .query_async(&mut conn)
            .await
            .map_err(|e| anyhow!("EAPPEND with saga metadata failed: {e}"))?;
    }

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
            Ok(entries) if entries.len() >= 1 => {
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
                .fetch_optional(&pool)
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

/// Create seasons in two different series via command adapters, then verify
/// that `list_by_series` returns only rows for the requested series_id.
#[tokio::test]
async fn list_by_series_returns_tenant_scoped_rows() -> Result<()> {
    let (pool, cmd_svc, audit_repo, _redis) = init().await?;

    let actor = UserId::from_sub("tenant-test-6.3");
    let series_a = SeriesId(Uuid::now_v7());
    let series_b = SeriesId(Uuid::now_v7());
    let season_cmd = SeasonCommandsImpl::new(cmd_svc.clone(), SeasonRepositoryImpl::new(pool.clone()));

    // Create season in series A.
    let season_a_id = Uuid::now_v7();
    season_cmd
        .create(
            actor.clone(),
            CreateSeason {
                id: season_a_id,
                series_id: series_a,
                number: 1,
                title: Some("Series A Season".into()),
            },
        )
        .await?;

    // Create season in series B.
    let season_b_id = Uuid::now_v7();
    season_cmd
        .create(
            actor.clone(),
            CreateSeason {
                id: season_b_id,
                series_id: series_b,
                number: 1,
                title: Some("Series B Season".into()),
            },
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
    let a_ids: std::collections::HashSet<Uuid> =
        series_a_rows.iter().map(|r| r.id).collect();
    let b_ids: std::collections::HashSet<Uuid> =
        series_b_rows.iter().map(|r| r.id).collect();
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
/// redeliver the same logical event (fresh EAPPEND with EXPECTED_VERSION = 1),
/// and verify that only one projection_audit row exists.
///
/// This tests the non-membership idempotency path: the `event_key`
/// deterministically depends on (entity_type, entity_id, event_type, payload),
/// so even a fresh SierraDB append (new event.id) gets deduped.
#[tokio::test]
async fn non_membership_audit_projector_is_idempotent_under_redelivery() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    // Spawn: costume_category projector + all audit projectors.
    let _cc_proj = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    let _ap = spawn_all_audit_projectors(pool.clone(), Arc::clone(&redis_client)).await?;

    tokio::time::sleep(Duration::from_millis(500)).await;

    let audit_repo = AuditRepositoryImpl::new(pool.clone());

    // Build saga metadata.
    let saga_metadata = EventMetadata {
        actor: None,
        provenance: Provenance::saga("SeasonSeedingSaga"),
        series_id: Some(SeriesId(Uuid::now_v7())),
    };
    let mut metadata_buf = Vec::new();
    ciborium::into_writer(&saga_metadata, &mut metadata_buf)
        .map_err(|e| anyhow!("CBOR metadata encode failed: {e}"))?;

    let season_id = SeasonId::new();
    let cc_id = Uuid::now_v7();
    let stream_id = format!("costume_category-{cc_id}");

    let event = breakdown_core::costume_category::events::CostumeCategoryEvent::CostumeCategoryCreated {
        id: cc_id,
        season_id,
        name: "Jacke".into(),
        order_key: LexicalSortKey("0".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&event)?;

    // Helper: EAPPEND with metadata.
    async fn eappend_with_meta(
        client: &Arc<RedisClient>,
        stream_id: &str,
        event_name: &str,
        expected_version: &str,
        payload: &[u8],
        metadata: &[u8],
    ) -> Result<()> {
        let now_ms = chrono::Utc::now()
            .timestamp_millis()
            .try_into()
            .unwrap_or(0u64);
        let mut conn = client.get_multiplexed_async_connection().await?;
        let _resp: redis::Value = redis::cmd("EAPPEND")
            .arg(stream_id)
            .arg(event_name)
            .arg("EXPECTED_VERSION")
            .arg(expected_version)
            .arg("PAYLOAD")
            .arg(payload)
            .arg("METADATA")
            .arg(metadata)
            .arg("TIMESTAMP")
            .arg(now_ms.to_string().as_bytes())
            .query_async(&mut conn)
            .await
            .map_err(|e| anyhow!("EAPPEND {event_name} failed: {e}"))?;
        Ok(())
    }

    // 1. First append (EXPECTED_VERSION EMPTY → version 0→1).
    eappend_with_meta(
        &redis_client,
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

    // 2. Redelivery: same logical event, fresh SierraDB append (version 1→2).
    eappend_with_meta(
        &redis_client,
        &stream_id,
        "CostumeCategoryCreated",
        "0",
        &payload,
        &metadata_buf,
    )
    .await?;

    // 3. Distinct event to prove the projector processed through the redelivery.
    let event2 = breakdown_core::costume_category::events::CostumeCategoryEvent::CostumeCategoryCreated {
        id: cc_id,
        season_id,
        name: "Jacke v2".into(), // Different name → different payload → different event_key
        order_key: LexicalSortKey("1".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload2 = encode_event(&event2)?;
    eappend_with_meta(
        &redis_client,
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

    // Count distinct payload names.
    let jacke_v1 = entries
        .iter()
        .filter(|e| {
            matches!(&e.payload.as_object(), Some(obj) if obj.get("name").and_then(|v| v.as_str()) == Some("Jacke"))
        })
        .count();
    let jacke_v2 = entries
        .iter()
        .filter(|e| {
            matches!(&e.payload.as_object(), Some(obj) if obj.get("name").and_then(|v| v.as_str()) == Some("Jacke v2"))
        })
        .count();

    assert_eq!(jacke_v1, 1, "Jacke must appear exactly once (redelivery deduped)");
    assert_eq!(jacke_v2, 1, "Jacke v2 must appear exactly once");
    assert!(
        entries.iter().any(|e| {
            matches!(&e.payload.as_object(), Some(obj) if obj.get("name").and_then(|v| v.as_str()) == Some("Jacke v2"))
        }),
        "distinct event (Jacke v2) must be projected as its own row"
    );

    Ok(())
}
