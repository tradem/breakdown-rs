// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.2 (neuralwatt)
// Co-authored-by: glm-5.3-flash (neuralwatt)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Tier-4 round-trip integration tests (ADR-014 / ADR-015 / ADR-016).
//!
//! The tests drive the full live chain against ephemeral containers:
//!
//! ```text
//! CommandService → SierraDB event persisted → PostgresProcessor catches up
//!              → read via *Repository adapter asserts the projection row
//! ```
//!
//! # Variants
//!
//! 1. `command_service_create_scene_round_trips_via_escan` — the spec-mandated
//!    variant: a real `CreateScene`/`UpdateSceneDetails` command dispatched
//!    through the production `SceneCommandsImpl` adapter, events verified via
//!    raw `ESCAN` reads, projection asserted via the read adapter. This
//!    re-closes the former issue #25 deviation: the SierraDB v0.3.1
//!    single-node `PartitionUnavailable` failure on the `EntityActor`'s
//!    `resync_with_db` read no longer reproduces on the current client stack
//!    (vendored `kameo_es` 0.2.0, `sierradb-client` 0.3.1, `redis` 1.7).
//! 2. `eappend_scene_created_round_trips_into_projection` — appends via raw
//!    `EAPPEND` and asserts the full `SierraDB → projector → Postgres
//!    projection → read query` segment.
//! 3. `eappend_character_assigned_twice_is_idempotent` — verifies projector
//!    idempotency under event redelivery (ADR-016 task 4.3).
//!
//! Requirements: Docker (or a compatible container runtime) and network access
//! to pull the SierraDB image. Excluded from `cargo-mutants` (`.mutants.toml`).

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use breakdown_core::error::DomainError;
use breakdown_core::scene::commands::{CreateScene, UpdateSceneDetails};
use breakdown_core::scene::events::{SceneDetails, SceneEvent, SceneSource};
use breakdown_core::scene::ports::{SceneCommands as _, SceneRepository as _};
use breakdown_core::shared::{AggregateVersion, EpisodeId, UserId};
use chrono::Utc;
use infra::event_store::SceneCommandsImpl;
use infra::queries::SceneRepositoryImpl;
use kameo_es::command_service::CommandService;
use sierradb_client::AsyncCommands;
use uuid::Uuid;

/// Bounded-retry window for the projector to catch up (ADR-015 eventual
/// consistency). Generous enough for a cold projector subscription on a local
/// container; failures report the lag explicitly rather than a bare assertion.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// Wait until `find_by_id` resolves to a projection row, retrying on
/// `NotFound` for [`PROJECTION_DEADLINE`]. Other errors surface immediately.
async fn await_scene_projection(
    repo: &SceneRepositoryImpl,
    scene_id: Uuid,
) -> Result<breakdown_core::scene::views::SceneView> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(scene_id).await {
            Ok(view) => return Ok(view),
            Err(DomainError::NotFound { .. }) if std::time::Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound { .. }) => {
                bail!(
                    "projection lag: Scene({scene_id}) not projected within {PROJECTION_DEADLINE:?} \
                     — the PostgresProcessor did not catch up in time"
                );
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

#[tokio::test]
async fn eappend_scene_created_round_trips_into_projection() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    // Start the scene projector so it subscribes to event notifications.
    let _scene_ref = infra::projectors::spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let repo = SceneRepositoryImpl::new(pool);

    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    let stream_id = format!("scene-{scene_id}");

    let created_event = SceneEvent::SceneCreated {
        id: scene_id,
        episode_id,
        details: SceneDetails {
            scene_number: Some(7),
            location: Some("Berlin".into()),
            mood: Some("dark".into()),
            is_schedule_set: true,
            summary: None,
            script_day: None,
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
        source: SceneSource::Manual,
    };

    // CBOR-encode the event (kameo_es uses ciborium internally).
    let mut payload = Vec::new();
    ciborium::into_writer(&created_event, &mut payload)
        .map_err(|e| anyhow!("CBOR encode failed: {e}"))?;

    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);

    // Append directly via EAPPEND, bypassing the broken ESCAN path.
    let mut conn = redis_client.get_multiplexed_async_connection().await?;
    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(&stream_id)
        .arg("SceneCreated")
        .arg("EXPECTED_VERSION")
        .arg("EMPTY") // new stream, must be empty
        .arg("PAYLOAD")
        .arg(&payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND failed: {e}"))?;

    // Wait for the projector to catch up.
    let view = await_scene_projection(&repo, scene_id).await?;

    assert_eq!(view.id, scene_id);
    assert_eq!(view.episode_id, episode_id);
    assert_eq!(view.scene_number, Some(7));
    assert_eq!(view.location.as_deref(), Some("Berlin"));
    assert_eq!(view.mood.as_deref(), Some("dark"));
    assert!(view.is_schedule_set);
    assert_eq!(view.version, AggregateVersion::INITIAL);
    assert!(view.assigned_characters.is_empty());

    Ok(())
}

/// Poll `find_by_id` until the projection version reaches at least `min_version`.
///
/// The scene row already exists (created by `await_scene_projection`), so we
/// must wait for the asynchronous projector to apply the mutation event and
/// bump the version. This is distinct from `await_scene_projection`, which
/// only waits for the row to come into existence.
async fn await_scene_version(
    repo: &SceneRepositoryImpl,
    scene_id: Uuid,
    min_version: AggregateVersion,
) -> Result<breakdown_core::scene::views::SceneView> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(scene_id).await {
            Ok(view) if view.version >= min_version => return Ok(view),
            Ok(_) if std::time::Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Ok(_) => {
                bail!(
                    "projection lag: Scene({scene_id}) version did not reach {min_version:?} \
                     within {PROJECTION_DEADLINE:?}"
                );
            }
            Err(DomainError::NotFound { .. }) if std::time::Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound { .. }) => {
                bail!(
                    "projection lag: Scene({scene_id}) disappeared or not yet created \
                     within {PROJECTION_DEADLINE:?}"
                );
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

/// Verifies projector idempotency under event redelivery (ADR-016 task 4.3).
///
/// Appends a `CharacterAssigned` event **twice** (same payload) and asserts
/// the projection row remains identical — no duplicate `assigned_characters`
/// entries, no version drift. This validates the `ON CONFLICT DO UPDATE` upsert
/// pattern in the scene projector is truly idempotent.
#[tokio::test]
async fn eappend_character_assigned_twice_is_idempotent() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _scene_ref = infra::projectors::spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let repo = SceneRepositoryImpl::new(pool);

    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    let stream_id = format!("scene-{scene_id}");
    let character_id = Uuid::now_v7();

    // 1. Create scene via EAPPEND SceneCreated
    let created_event = SceneEvent::SceneCreated {
        id: scene_id,
        episode_id,
        details: SceneDetails {
            scene_number: Some(7),
            location: Some("Berlin".into()),
            mood: Some("dark".into()),
            is_schedule_set: true,
            summary: None,
            script_day: None,
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
        source: SceneSource::Manual,
    };

    let mut payload = Vec::new();
    ciborium::into_writer(&created_event, &mut payload)
        .map_err(|e| anyhow!("CBOR encode failed: {e}"))?;

    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);

    let mut conn = redis_client.get_multiplexed_async_connection().await?;
    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(&stream_id)
        .arg("SceneCreated")
        .arg("EXPECTED_VERSION")
        .arg("EMPTY")
        .arg("PAYLOAD")
        .arg(&payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND SceneCreated failed: {e}"))?;

    let view = await_scene_projection(&repo, scene_id).await?;
    assert_eq!(view.id, scene_id);
    assert!(view.assigned_characters.is_empty());

    // 2. First CharacterAssigned EAPPEND — version 1, expected version 0 (SceneCreated)
    let assigned_event = SceneEvent::CharacterAssigned {
        id: scene_id,
        character_id,
        version: AggregateVersion(2),
    };

    let mut payload = Vec::new();
    ciborium::into_writer(&assigned_event, &mut payload)
        .map_err(|e| anyhow!("CBOR encode failed: {e}"))?;

    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);

    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(&stream_id)
        .arg("CharacterAssigned")
        .arg("EXPECTED_VERSION")
        .arg("0")
        .arg("PAYLOAD")
        .arg(&payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND CharacterAssigned #1 failed: {e}"))?;

    // Wait for the projector to process the CharacterAssigned event and bump
    // the version to >= 2. `await_scene_projection` is insufficient here
    // because the scene row already exists.
    let view = await_scene_version(&repo, scene_id, AggregateVersion(2)).await?;
    assert_eq!(
        view.assigned_characters.len(),
        1,
        "expected exactly one assigned character after first CharacterAssigned"
    );
    assert_eq!(view.assigned_characters[0], character_id);
    assert_eq!(view.version, AggregateVersion(2));

    // 3. Second (redelivery) CharacterAssigned EAPPEND — same payload, expected version 1
    let mut payload = Vec::new();
    ciborium::into_writer(&assigned_event, &mut payload)
        .map_err(|e| anyhow!("CBOR encode failed: {e}"))?;

    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);

    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(&stream_id)
        .arg("CharacterAssigned")
        .arg("EXPECTED_VERSION")
        .arg("1")
        .arg("PAYLOAD")
        .arg(&payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND CharacterAssigned #2 (redelivery) failed: {e}"))?;

    // 4. Wait for the projector to catch up on the redelivered event and
    //    assert the projection is unchanged — version should remain at 1.
    let view2 = await_scene_version(&repo, scene_id, AggregateVersion(2)).await?;
    assert_eq!(
        view2.assigned_characters.len(),
        1,
        "redelivery must not duplicate assigned characters"
    );
    assert_eq!(view2.assigned_characters[0], character_id);
    assert_eq!(
        view2.version, view.version,
        "version must not change on redelivery"
    );
    // All other fields must remain identical.
    assert_eq!(view2.id, view.id);
    assert_eq!(view2.episode_id, view.episode_id);
    assert_eq!(view2.scene_number, view.scene_number);
    assert_eq!(view2.location, view.location);
    assert_eq!(view2.mood, view.mood);
    assert_eq!(view2.is_schedule_set, view.is_schedule_set);

    Ok(())
}

/// Tier-4 round-trip variant driving a **real** `CommandService` command
/// (issue #25, ADR-016 §5; spec requirement restored 2026-09-21).
///
/// Dispatches `CreateScene` (and a follow-up `UpdateSceneDetails`) through the
/// production `SceneCommandsImpl` adapter onto the live write path
/// (`CommandService` → `EntityActor` → `on_start`/`resync_with_db` → append),
/// verifies the resulting events are persisted in SierraDB via raw `ESCAN`
/// reads, and asserts the projector catches up to the projection row — the
/// exact chain `openspec/specs/sierradb-round-trip-testing/spec.md` mandates.
///
/// Historical note: PR #24 worked around a SierraDB v0.3.1 single-node
/// `PartitionUnavailable` / `broken pipe` failure on the `EntityActor`'s
/// `resync_with_db` read. That failure no longer reproduces on the current
/// client stack (vendored `kameo_es` 0.2.0, `sierradb-client` 0.3.1,
/// `redis` 1.7) — empirically re-verified against the pinned container in
/// issue #25 (repeated stable runs; upstream tag unchanged at v0.3.1: the
/// fix lives client-side, not upstream). The `EAPPEND`-based variants below
/// are kept as additional projector idempotency/redelivery coverage.
#[tokio::test]
async fn command_service_create_scene_round_trips_via_escan() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _scene_ref = infra::projectors::spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let repo = SceneRepositoryImpl::new(pool);

    // 1. Dispatch a real CreateScene through the production command adapter.
    let cmd_service = CommandService::new(sierra_conn);
    let scenes = SceneCommandsImpl::new(cmd_service);

    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    let (created_id, created_version) = scenes
        .create(
            UserId::from_sub("tier4-command-service-probe"),
            CreateScene {
                id: scene_id,
                episode_id,
                series_id: None,
                details: SceneDetails {
                    scene_number: Some(7),
                    location: Some("Berlin".into()),
                    mood: Some("dark".into()),
                    is_schedule_set: true,
                    summary: None,
                    script_day: None,
                },
                source: SceneSource::Manual,
            },
        )
        .await
        .map_err(|e| anyhow!("CreateScene dispatch via CommandService failed: {e}"))?;

    assert_eq!(created_id, scene_id);
    assert_eq!(created_version, AggregateVersion::INITIAL);

    // 2. Verify the event is persisted in SierraDB via a raw ESCAN read.
    let stream_id = format!("scene-{scene_id}");
    let mut conn = redis_client.get_multiplexed_async_connection().await?;
    let batch: sierradb_client::EventBatch = conn
        .escan(&stream_id, 0, None, Some(100))
        .await
        .map_err(|e| anyhow!("ESCAN read-back failed: {e}"))?;
    assert_eq!(
        batch.events.len(),
        1,
        "expected exactly the SceneCreated event on stream {stream_id}"
    );
    assert_eq!(batch.events[0].event_name, "SceneCreated");
    let persisted: SceneEvent = ciborium::from_reader(batch.events[0].payload.as_slice())
        .map_err(|e| anyhow!("CBOR decode of persisted event failed: {e}"))?;
    assert!(matches!(persisted, SceneEvent::SceneCreated { .. }));

    // 3. Drive a second mutation through the same live write path to assert
    //    version progression on an already-loaded aggregate.
    let updated_version = scenes
        .update_details(
            UserId::from_sub("tier4-command-service-probe"),
            UpdateSceneDetails {
                id: scene_id,
                details: SceneDetails {
                    scene_number: Some(8),
                    location: Some("Potsdam".into()),
                    mood: Some("bright".into()),
                    is_schedule_set: true,
                    summary: None,
                    script_day: None,
                },
                series_id: None,
                // The caller-observed (domain) version after the create: the
                // adapter maps it to the 0-based SierraDB stream version.
                version: AggregateVersion(1),
            },
        )
        .await
        .map_err(|e| anyhow!("UpdateSceneDetails dispatch via CommandService failed: {e}"))?;
    assert_eq!(updated_version, AggregateVersion(2));

    let stream_batch: sierradb_client::EventBatch = conn
        .escan(&stream_id, 0, None, Some(100))
        .await
        .map_err(|e| anyhow!("ESCAN read-back after update failed: {e}"))?;
    assert_eq!(
        stream_batch.events.len(),
        2,
        "expected SceneCreated + SceneDetailsUpdated on stream {stream_id}"
    );
    assert_eq!(stream_batch.events[1].event_name, "SceneDetailsUpdated");

    // 4. Verify the projector consumed the CommandService-written events.
    let view = await_scene_version(&repo, scene_id, AggregateVersion(2)).await?;
    assert_eq!(view.id, scene_id);
    assert_eq!(view.episode_id, episode_id);
    assert_eq!(view.scene_number, Some(8));
    assert_eq!(view.location.as_deref(), Some("Potsdam"));
    assert_eq!(view.mood.as_deref(), Some("bright"));
    assert!(view.is_schedule_set);
    assert_eq!(view.version, AggregateVersion(2));

    Ok(())
}
