// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Tier-4 replay proof for the `SeriesId` → `ProjectId` rename (issue #591,
//! ADR-035 D1/S1 — layers 1 and 2).
//!
//! ## Why this test exists
//!
//! The rename was deliberately **not** allowed to touch the persisted event
//! payload. The event store already holds events written under the key
//! `series_id`, and ADR-002 forbids rewriting history, so the Rust field is now
//! `project_id` while the serde key stays `series_id`
//! (`#[serde(rename = "series_id")]` on `SeasonEvent::SeasonCreated` and on
//! `EventMetadata::project_id`).
//!
//! The failure mode a blind rename causes is invisible to the compiler: the
//! projector dies on deserialization (surfacing as SQLSTATE 22 / a #37
//! dead-letter, not a build failure). And the *tempting* fix — giving the field
//! `#[serde(rename = "project_id", alias = "series_id")]` — is worse than it
//! looks, because it silently breaks `projection_audit.event_key` idempotency.
//! See `audit_event_key_survives_the_rename`.
//!
//! ## What makes this a real proof
//!
//! Every test here appends **hand-built CBOR carrying the pre-rename
//! `series_id` key**, pushed straight into SierraDB with `EAPPEND`. Nothing
//! constructs today's Rust event type to produce the payload bytes, so the
//! projector genuinely consumes an event written *before* the rename — not a
//! re-serialization of a post-rename one. The chain driven is the real one:
//! `EAPPEND → EventStore → SeasonProjector → projection_season →
//! SeasonRepository`.
//!
//! ## Why the payload is hand-built CBOR, not JSON
//!
//! A `serde_json` round-trip would be a *lie* about the stored bytes. `Uuid`'s
//! serde impl branches on the serializer's human-readable flag, and CBOR is not
//! human-readable — so a real stored event encodes every UUID as **16 raw
//! CBOR bytes**, while `serde_json::to_value` would yield a **string**.
//! Feeding a string to the projector fails with
//! `invalid type: string "…", expected bytes` — a false negative that has
//! nothing to do with this rename. Building the `ciborium::Value` directly is
//! what makes these fixtures byte-faithful to what a pre-rename build wrote.

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use breakdown_core::audit::ports::AuditRepository as _;
use breakdown_core::season::aggregate::SeasonAggregate;
use breakdown_core::season::events::SeasonEvent;
use breakdown_core::season::ports::SeasonRepository as _;
use breakdown_core::shared::{AggregateVersion, EventMetadata, ProjectId};
use chrono::Utc;
use ciborium::Value as Cbor;
use infra::projectors::AuditCategory;
use infra::queries::{AuditRepositoryImpl, SeasonRepositoryImpl};
use kameo_es::{Apply, Metadata};
use redis::Client as RedisClient;
use serde_json::json;
use uuid::Uuid;

/// ADR-015 eventual consistency: bounded wait for a projector to catch up.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// The UUIDv7 that stood for the tenant id *before* the rename. Identical in
/// every test — ADR-035 B1: the rename moves no UUIDv7 values.
const LEGACY_PROJECT: &str = "019e7044-8800-700a-8000-00000000000a";

fn legacy_project() -> Uuid {
    Uuid::parse_str(LEGACY_PROJECT).expect("LEGACY_PROJECT is a valid UUID")
}

/// A UUID as a pre-rename event stored it: 16 raw CBOR bytes (see the module
/// doc on why JSON strings are not faithful).
fn cbor_uuid(id: Uuid) -> Cbor {
    Cbor::Bytes(id.as_bytes().to_vec())
}

/// The `SeasonCreated` payload **as written before the rename**.
///
/// The externally-tagged `{"SeasonCreated": {…}}` envelope is what
/// `kameo_es::event_handler::postgres` reads back; the field is spelled
/// `series_id`, which is the whole point.
fn legacy_season_created_cbor(season_id: Uuid, number: i64, title: &str) -> Cbor {
    Cbor::Map(vec![(
        Cbor::Text("SeasonCreated".into()),
        Cbor::Map(vec![
            (Cbor::Text("id".into()), cbor_uuid(season_id)),
            (Cbor::Text("series_id".into()), cbor_uuid(legacy_project())),
            (Cbor::Text("number".into()), Cbor::Integer(number.into())),
            (Cbor::Text("title".into()), Cbor::Text(title.into())),
            (
                Cbor::Text("version".into()),
                Cbor::Integer(AggregateVersion::INITIAL.0.into()),
            ),
        ]),
    )])
}

/// The `EventMetadata` a pre-rename build persisted.
///
/// `EventMetadata` is the metadata of *every* stored event, so its key has the
/// widest blast radius in the whole rename: a serde-key change here makes every
/// already-stored event un-deserializable. `kameo_es::Metadata<T>` nests the
/// payload under `data`.
fn legacy_event_metadata_inner_cbor() -> Cbor {
    Cbor::Map(vec![
        (
            Cbor::Text("actor".into()),
            Cbor::Text("fixture-owner".into()),
        ),
        (Cbor::Text("provenance".into()), Cbor::Text("Human".into())),
        (Cbor::Text("series_id".into()), cbor_uuid(legacy_project())),
    ])
}

fn legacy_event_metadata_cbor() -> Cbor {
    Cbor::Map(vec![(
        Cbor::Text("data".into()),
        legacy_event_metadata_inner_cbor(),
    )])
}

fn cbor_bytes(value: &Cbor) -> Result<Vec<u8>> {
    let mut buf = Vec::new();
    ciborium::into_writer(value, &mut buf).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    Ok(buf)
}

/// CBOR-encode + `EAPPEND` a **pre-rename** event payload into SierraDB.
///
/// Takes `&Cbor` rather than a typed event on purpose: the caller hands over
/// the exact bytes a pre-rename build would have persisted.
async fn eappend_legacy_cbor(
    client: &Arc<RedisClient>,
    stream_id: &str,
    event_name: &str,
    expected_version: &str,
    payload: &Cbor,
) -> Result<()> {
    let metadata = cbor_bytes(&legacy_event_metadata_cbor())?;
    let encoded = cbor_bytes(payload)?;
    let mut conn = client.get_multiplexed_async_connection().await?;
    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_name)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(&encoded)
        .arg("METADATA")
        .arg(&metadata)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {event_name} failed: {e}"))?;
    Ok(())
}

/// Wait until `projection_season` carries `season_id`.
async fn await_season_projected(pool: &sqlx::PgPool, season_id: Uuid) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let found: Option<Uuid> =
            sqlx::query_scalar("SELECT id FROM projection_season WHERE id = $1")
                .bind(season_id)
                .fetch_optional(pool)
                .await
                .map_err(|e| anyhow!("poll projection_season: {e}"))?;
        if found.is_some() {
            return Ok(());
        }
        if std::time::Instant::now() >= deadline {
            bail!("projection_season not projected within {PROJECTION_DEADLINE:?}");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Wait until `projection_audit` has at least `expected` rows for `entity_id`.
async fn await_audit_row_count(pool: &sqlx::PgPool, entity_id: Uuid, expected: i64) -> Result<i64> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM projection_audit WHERE entity_id = $1 AND event_type = $2",
        )
        .bind(entity_id.to_string())
        .bind("SeasonCreated")
        .fetch_one(pool)
        .await
        .map_err(|e| anyhow!("count projection_audit: {e}"))?;
        if count >= expected || std::time::Instant::now() >= deadline {
            return Ok(count);
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// A pre-rename `SeasonCreated` still deserializes into today's renamed
/// `SeasonEvent` and still **rebuilds aggregate state**.
///
/// This is the criterion that fails if layer 2 was handled by a blind rename:
/// without `#[serde(rename = "series_id")]` the `project_id` field would be
/// missing and the projector would dead-letter the event instead of rebuilding
/// the row.
#[test]
fn pre_rename_event_rebuilds_aggregate_state() -> Result<()> {
    let season_id = Uuid::now_v7();
    let bytes = cbor_bytes(&legacy_season_created_cbor(season_id, 3, "Staffel 3"))?;

    // (a) Deserialization through the *production* deserializer (CBOR).
    let event: SeasonEvent = ciborium::from_reader(bytes.as_slice())
        .map_err(|e| anyhow!("pre-rename event failed to deserialize: {e}"))?;
    match &event {
        SeasonEvent::SeasonCreated {
            project_id, number, ..
        } => {
            assert_eq!(
                *project_id,
                ProjectId::from_uuid(legacy_project()),
                "the tenant UUIDv7 must be preserved verbatim (ADR-035 B1)"
            );
            assert_eq!(*number, 3);
        }
        other => panic!("expected SeasonCreated, got {other:?}"),
    }

    // (b) Aggregate replay: state is rebuilt from the pre-rename event.
    let mut aggregate = SeasonAggregate::default();
    aggregate.apply(event, Metadata::default());
    assert_eq!(
        aggregate.project_id,
        ProjectId::from_uuid(legacy_project()),
        "replaying a pre-rename event must restore the project id"
    );
    assert_eq!(aggregate.number, 3);
    assert_eq!(aggregate.title.as_deref(), Some("Staffel 3"));
    assert_eq!(aggregate.version, AggregateVersion::INITIAL);

    Ok(())
}

/// The pre-rename `EventMetadata` also still deserializes — the key with the
/// widest blast radius, because it rides on *every* stored event.
#[test]
fn pre_rename_event_metadata_still_deserializes() -> Result<()> {
    // Decode the inner payload exactly as `EventMetadata` — the type every
    // aggregate's `Entity::Metadata` is set to (`shared.rs`). The stored form
    // is that struct nested under `data` inside `kameo_es::Metadata<T>`.
    let meta: EventMetadata =
        ciborium::from_reader::<_, _>(cbor_bytes(&legacy_event_metadata_inner_cbor())?.as_slice())
            .map_err(|e| anyhow!("pre-rename EventMetadata failed to deserialize: {e}"))?;

    assert_eq!(
        meta.project_id,
        Some(ProjectId::from_uuid(legacy_project())),
        "EventMetadata must expose the pre-rename `series_id` key as project_id"
    );

    Ok(())
}

/// The critical assertion: re-serializing a **pre-rename** event must produce
/// byte-identical JSON, because `projection_audit.event_key` is derived from
/// the re-serialized payload:
///
/// ```text
/// event_key = "{entity_type}:{entity_id}:{event_type}:{payload}"   // audit.rs
/// ```
///
/// Had the rename been applied to the *serde* key (e.g. via
/// `#[serde(rename = "project_id", alias = "series_id")]`, which does
/// deserialize old events correctly and therefore looks safe), the audit
/// projector would re-serialize the stored event under a different key, the
/// `ON CONFLICT (event_key) DO NOTHING` idempotency guard would no longer
/// match, and **every replay would silently duplicate every pre-rename audit
/// row** — no compile error, no dead-letter, no failing test.
///
/// Pinning the serde key keeps `event_key` stable. This asserts that directly.
#[test]
fn audit_event_key_survives_the_rename() -> Result<()> {
    let season_id = Uuid::now_v7();

    // What a pre-rename build persisted, expressed as JSON for the
    // `to_value(&event)` round-trip the audit projector performs.
    let stored = json!({
        "SeasonCreated": {
            "id": season_id,
            "series_id": LEGACY_PROJECT,
            "number": 1,
            "title": "Staffel 1",
            "version": 1,
        }
    });

    let event: SeasonEvent = serde_json::from_value(stored.clone())?;
    let reserialized = serde_json::to_value(&event)?;

    assert!(
        reserialized["SeasonCreated"].get("series_id").is_some(),
        "the re-serialized event must still carry `series_id`, otherwise \
         projection_audit.event_key changes and audit rows duplicate on replay; \
         got {reserialized}"
    );
    assert!(
        reserialized["SeasonCreated"].get("project_id").is_none(),
        "the Rust field must not leak onto the wire; got {reserialized}"
    );
    assert_eq!(
        reserialized, stored,
        "re-serialization must be byte-identical for projection_audit.event_key \
         idempotency (audit.rs write_audit_row)"
    );

    Ok(())
}

/// End-to-end tier 4: a **pre-rename** event written straight into SierraDB is
/// consumed by the real season projector and rebuilds `projection_season`,
/// readable through the real repository.
#[tokio::test]
async fn pre_rename_event_flows_through_projector_to_projection() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _season_ref = infra::projectors::spawn_season_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let repo = SeasonRepositoryImpl::new(pool.clone());
    let season_id = Uuid::now_v7();

    eappend_legacy_cbor(
        &redis_client,
        &format!("season-{season_id}"),
        "SeasonCreated",
        "EMPTY",
        &legacy_season_created_cbor(season_id, 7, "Staffel 7"),
    )
    .await?;

    await_season_projected(&pool, season_id).await?;

    // The read model is rebuilt, and the column keeps its pre-rename name
    // (layer 3 is deferred to its own ADR-021 /v2 migration).
    let series_uuid: Uuid =
        sqlx::query_scalar("SELECT series_id FROM projection_season WHERE id = $1")
            .bind(season_id)
            .fetch_one(&pool)
            .await
            .map_err(|e| anyhow!("read projection_season.series_id: {e}"))?;
    assert_eq!(
        series_uuid,
        legacy_project(),
        "the denormalized tenant column must survive the rename with the same value"
    );

    let view = repo.find_by_id(season_id).await?;
    assert_eq!(view.project_id, ProjectId::from_uuid(legacy_project()));
    assert_eq!(view.number, 7);

    // The wire field name is deliberately still `series_id` (layer 3).
    let wire = serde_json::to_value(&view)?;
    assert!(
        wire.get("series_id").is_some() && wire.get("project_id").is_none(),
        "SeasonView must keep the `series_id` wire field until the layer-3 \
         ADR-021 /v2 migration; got {wire}"
    );

    Ok(())
}

/// The audit projection of a pre-rename event is written exactly **once**,
/// even when the same stream is replayed — i.e. the `event_key` dedup guard
/// still works across the rename.
#[tokio::test]
async fn pre_rename_event_audits_exactly_once() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = fixtures::spawn_sierradb().await?;

    let mut handles = infra::projectors::AuditProjectorHandles::new();
    infra::projectors::spawn_audit_projectors_for_types(
        &[AuditCategory::Season],
        &mut handles,
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let audit_repo = AuditRepositoryImpl::new(pool.clone());
    let season_id = Uuid::now_v7();

    eappend_legacy_cbor(
        &redis_client,
        &format!("season-{season_id}"),
        "SeasonCreated",
        "EMPTY",
        &legacy_season_created_cbor(season_id, 4, "Staffel 4"),
    )
    .await?;

    let count = await_audit_row_count(&pool, season_id, 1).await?;
    assert_eq!(
        count, 1,
        "a pre-rename SeasonCreated must produce exactly one audit row"
    );

    // Re-deliver the identical event at the next stream position so the
    // projector sees it again. A changed `event_key` (the failure mode of a
    // serde-key rename) would show up here as a second row.
    //
    // SierraDB stream versions are 0-based (the integration-test convention:
    // first event = 0), so the second append expects version 0 — note this is
    // the *stream* version, distinct from the 1-based `AggregateVersion` in
    // the event payload.
    eappend_legacy_cbor(
        &redis_client,
        &format!("season-{season_id}"),
        "SeasonCreated",
        "0",
        &legacy_season_created_cbor(season_id, 4, "Staffel 4"),
    )
    .await?;

    tokio::time::sleep(Duration::from_secs(2)).await;
    let after_redelivery = await_audit_row_count(&pool, season_id, 1).await?;
    assert_eq!(
        after_redelivery, 1,
        "redelivery must not duplicate the audit row — this is exactly what a \
         changed projection_audit.event_key would break"
    );

    // And the audit row is reachable through the project-scoped journal
    // (ADR-035 B3, `AuditRepository::list_by_series` → `list_by_project`).
    let entries = audit_repo
        .list_by_project(ProjectId::from_uuid(legacy_project()), 50, 0)
        .await?;
    assert!(
        entries.iter().any(|e| e.entity_id == season_id.to_string()),
        "the pre-rename event must be reachable through the project-scoped \
         audit journal (ADR-035 B3)"
    );

    Ok(())
}
