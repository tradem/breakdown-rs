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

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use breakdown_core::error::DomainError;
use breakdown_core::scene::events::{SceneDetails, SceneEvent};
use breakdown_core::scene::ports::SceneRepository as _;
use breakdown_core::shared::{AggregateVersion, ProjectId};
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
    let (pool, _pg) = infra::testing::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = infra::testing::spawn_sierradb().await?;

    // Start the scene projector so it subscribes to event notifications.
    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let repo = SceneRepositoryImpl::new(pool);

    let scene_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("scene-{scene_id}");

    let created_event = SceneEvent::SceneCreated {
        id: scene_id,
        project_id,
        details: SceneDetails {
            scene_number: Some(7),
            location: Some("Berlin".into()),
            mood: Some("dark".into()),
            is_schedule_set: true,
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
    let mut conn = redis_client.get_multiplexed_tokio_connection().await?;
    let _resp: String = redis::cmd("EAPPEND")
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
    assert_eq!(view.project_id, project_id);
    assert_eq!(view.scene_number, Some(7));
    assert_eq!(view.location.as_deref(), Some("Berlin"));
    assert_eq!(view.mood.as_deref(), Some("dark"));
    assert!(view.is_schedule_set);
    assert_eq!(view.version, AggregateVersion::INITIAL);
    assert!(view.assigned_characters.is_empty());

    Ok(())
}
