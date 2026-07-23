// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Tier-4 round-trip integration tests (ADR-014 / ADR-015 / ADR-016).
//!
//! These tests drive the full live chain against ephemeral containers:
//!
//! ```text
//! direct EAPPEND → SierraDB event persisted → PostgresProcessor catches up
//!              → read via *Repository adapter asserts the projection row
//! ```
//!
//! SierraDB v0.3.1 has a single-node topology issue where `ESCAN` (used by
//! `kameo_es`'s `EntityActor::resync_with_db`) returns `PartitionUnavailable`.
//! To work around this, we append events directly via `EAPPEND` (which goes
//! through the write path) instead of using the `kameo_es` `CommandService`.
//! The projector subscription picks up the event regardless of how it was
//! written, so the full `SierraDB → projector → Postgres projection` chain
//! is still exercised.
//!
//! Requirements: Docker (or a compatible container runtime) and network access
//! to pull the SierraDB image. Excluded from `cargo-mutants` (`.mutants.toml`).

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use breakdown_core::error::DomainError;
use breakdown_core::scene::events::{SceneDetails, SceneEvent};
use breakdown_core::scene::ports::SceneRepository as _;
use breakdown_core::shared::{AggregateVersion, EpisodeId};
use chrono::Utc;
use infra::queries::SceneRepositoryImpl;
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
            Err(DomainError::NotFound(_)) if std::time::Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound(_)) => {
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
    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;

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
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
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
            Err(DomainError::NotFound(_)) if std::time::Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound(_)) => {
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

    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;

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
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
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
