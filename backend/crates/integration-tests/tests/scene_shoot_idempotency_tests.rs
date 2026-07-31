// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: moonshotai/kimi-k3 (openrouter)

//! Tier-4 projector idempotency test for the SceneShoot aggregate (ADR-016).
//!
//! Verifies that event redelivery (a fresh SierraDB append of the same logical
//! event with a new `event.id`) does NOT corrupt the projection:
//!
//! - `SceneShootPlanned` redelivery: version guard on `ON CONFLICT` skips it.
//! - `ShootDayNoteAdded` redelivery: version guard prevents a duplicate note.
//!
//! A trailing distinct event proves the projector processed *through* the
//! redeliveries (i.e. they were handled, not lost).

mod fixtures;

use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow, bail};
use breakdown_core::error::DomainError;
use breakdown_core::scene_shoot::events::SceneShootEvent;
use breakdown_core::scene_shoot::ports::SceneShootRepository as _;
use breakdown_core::scene_shoot::views::SceneShootView;
use breakdown_core::shared::{
    AggregateVersion, LexicalSortKey, SceneShootId, SceneShootStatus, ShootingDayId,
};
use chrono::Utc;
use infra::projectors::spawn_scene_shoot_projector;
use infra::queries::SceneShootRepositoryImpl;
use uuid::Uuid;

const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

fn encode_event<E: serde::Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut payload = Vec::new();
    ciborium::into_writer(event, &mut payload).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    Ok(payload)
}

async fn eappend(
    redis_client: &Arc<redis::Client>,
    stream_id: &str,
    event_type: &str,
    expected_version: &str,
    payload: &[u8],
) -> Result<()> {
    let mut conn = redis_client.get_multiplexed_async_connection().await?;
    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let _: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_type)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {event_type} failed: {e}"))?;
    Ok(())
}

/// Seed the parent `projection_scene` and `projection_shooting_day` rows that
/// the `projection_scene_shoot` FK constraints require (see AGENTS.md gotcha).
async fn seed_parents(pool: &sqlx::PgPool, scene_id: Uuid, day_id: ShootingDayId) -> Result<()> {
    let episode_id = Uuid::now_v7();
    sqlx::query(
        r#"
        INSERT INTO projection_scene
            (id, episode_id, scene_number, location, mood, is_schedule_set, summary, script_day, version, updated_at)
        VALUES ($1, $2, 1, 'loc', 'mood', false, NULL, NULL, 1, now())
        "#,
    )
    .bind(scene_id)
    .bind(episode_id)
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        INSERT INTO projection_shooting_day
            (id, episode_id, label, order_key, date, source, archived, wrapped_at, version, updated_at)
        VALUES ($1, $2, 'Day 1', 'a', NULL, '{"Manual":null}'::jsonb, false, NULL, 1, now())
        "#,
    )
    .bind(day_id.0)
    .bind(episode_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Wait until the scene-shoot row reaches at least `min_version`.
async fn await_scene_shoot_version(
    repo: &SceneShootRepositoryImpl,
    id: SceneShootId,
    min_version: u64,
) -> Result<SceneShootView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(id).await {
            Ok(view) if view.version.0 >= min_version => return Ok(view),
            Ok(_) | Err(DomainError::NotFound(_)) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Ok(view) => {
                bail!(
                    "projection lag: SceneShoot({id}) version {} < {min_version}",
                    view.version.0
                );
            }
            Err(DomainError::NotFound(_)) => {
                bail!("projection lag: SceneShoot({id}) not projected within deadline");
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

#[tokio::test]
async fn scene_shoot_projector_is_idempotent_under_redelivery() -> Result<()> {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,kameo_es=debug,sierradb=debug".into()),
        )
        .try_init();
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    sqlx::migrate!("../infra/migrations").run(&pool).await?;
    let (redis_client, _conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _projector = spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    // Give the subscription time to establish before appending.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let repo = SceneShootRepositoryImpl::new(pool.clone());

    let shoot_id = SceneShootId::new();
    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();
    let stream_id = format!("scene_shoot-{}", shoot_id.0);

    // Seed FK parents before any scene_shoot events are projected.
    seed_parents(&pool, scene_id, day_id).await?;

    let planned = SceneShootEvent::SceneShootPlanned {
        id: shoot_id,
        scene_id,
        shooting_day_id: day_id,
        planned_order: LexicalSortKey::new("001").unwrap(),
        status: SceneShootStatus::Planned,
        version: AggregateVersion(1),
    };

    // 1. First append (stream EMPTY → version 0).
    let payload = encode_event(&planned)?;
    eappend(
        &redis_client,
        &stream_id,
        "SceneShootPlanned",
        "EMPTY",
        &payload,
    )
    .await?;
    let view = await_scene_shoot_version(&repo, shoot_id, 1).await?;
    assert_eq!(view.version.0, 1, "first append projected at version 1");
    assert_eq!(view.status, SceneShootStatus::Planned);

    // 2. Redelivery: same logical event, fresh SierraDB append (stream 0 → 1).
    //    The payload still carries aggregate version 1; the version guard must
    //    skip the write.
    eappend(
        &redis_client,
        &stream_id,
        "SceneShootPlanned",
        "0",
        &payload,
    )
    .await?;

    // 3. Distinct event to prove the projector processed through the redelivery.
    let note_id = Uuid::now_v7();
    let note_added = SceneShootEvent::ShootDayNoteAdded {
        id: shoot_id,
        note_id,
        body: "first note".into(),
        author: None,
        version: AggregateVersion(2),
    };
    let note_payload = encode_event(&note_added)?;
    eappend(
        &redis_client,
        &stream_id,
        "ShootDayNoteAdded",
        "1",
        &note_payload,
    )
    .await?;
    let view = await_scene_shoot_version(&repo, shoot_id, 2).await?;
    assert_eq!(view.notes.len(), 1, "note projected");
    assert_eq!(view.notes[0].body, "first note");

    // 4. Redeliver the note event (stream 2 → 3, payload version still 2).
    //    Without the version guard this would append a duplicate note.
    eappend(
        &redis_client,
        &stream_id,
        "ShootDayNoteAdded",
        "2",
        &note_payload,
    )
    .await?;

    // 5. Distinct event to prove the projector processed through the note redelivery.
    let started = SceneShootEvent::SceneShootStarted {
        id: shoot_id,
        start_dt: Utc::now(),
        version: AggregateVersion(3),
    };
    let started_payload = encode_event(&started)?;
    eappend(
        &redis_client,
        &stream_id,
        "SceneShootStarted",
        "3",
        &started_payload,
    )
    .await?;

    let view = await_scene_shoot_version(&repo, shoot_id, 3).await?;
    assert_eq!(view.status, SceneShootStatus::InProgress);
    assert!(view.start_dt.is_some(), "start_dt projected");

    // The note redelivery must NOT have duplicated the note.
    assert_eq!(
        view.notes.len(),
        1,
        "note redelivery must not duplicate the note (got {})",
        view.notes.len()
    );

    Ok(())
}

/// Idempotency of the continuity-photo link operation under redelivery.
#[tokio::test]
async fn continuity_photo_link_is_idempotent_under_redelivery() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    sqlx::migrate!("../infra/migrations").run(&pool).await?;
    let (redis_client, _conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _projector = spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    let repo = SceneShootRepositoryImpl::new(pool.clone());

    let shoot_id = SceneShootId::new();
    let stream_id = format!("scene_shoot-{}", shoot_id.0);
    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();

    // Seed FK parents before any scene_shoot events are projected.
    seed_parents(&pool, scene_id, day_id).await?;

    let planned = SceneShootEvent::SceneShootPlanned {
        id: shoot_id,
        scene_id,
        shooting_day_id: day_id,
        planned_order: LexicalSortKey::new("001").unwrap(),
        status: SceneShootStatus::Planned,
        version: AggregateVersion(1),
    };
    let payload = encode_event(&planned)?;
    eappend(
        &redis_client,
        &stream_id,
        "SceneShootPlanned",
        "EMPTY",
        &payload,
    )
    .await?;
    await_scene_shoot_version(&repo, shoot_id, 1).await?;

    // Link a continuity photo (version 2).
    let photo_id = breakdown_core::shared::PhotoId::new();
    let link = SceneShootEvent::ContinuityPhotoLinked {
        id: shoot_id,
        photo_id,
        version: AggregateVersion(2),
    };
    let link_payload = encode_event(&link)?;
    eappend(
        &redis_client,
        &stream_id,
        "ContinuityPhotoLinked",
        "0",
        &link_payload,
    )
    .await?;
    let view = await_scene_shoot_version(&repo, shoot_id, 2).await?;
    assert_eq!(view.continuity_photo_ids.len(), 1);

    // Redeliver the link event (stream 1 → 2, payload version still 2).
    eappend(
        &redis_client,
        &stream_id,
        "ContinuityPhotoLinked",
        "1",
        &link_payload,
    )
    .await?;

    // Distinct event proves the projector processed through.
    let skipped = SceneShootEvent::SceneShootSkipped {
        id: shoot_id,
        version: AggregateVersion(3),
    };
    let skipped_payload = encode_event(&skipped)?;
    eappend(
        &redis_client,
        &stream_id,
        "SceneShootSkipped",
        "2",
        &skipped_payload,
    )
    .await?;

    let view = await_scene_shoot_version(&repo, shoot_id, 3).await?;
    assert_eq!(view.status, SceneShootStatus::Skipped);
    assert_eq!(
        view.continuity_photo_ids.len(),
        1,
        "continuity photo link redelivery must not duplicate the photo id"
    );

    Ok(())
}
