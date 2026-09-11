// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Tier-4 regression test for the #404 invariant-skip path (ADR-016).
//!
//! Verifies the projector failure behavior for a permanent unique violation
//! of the `(scene_id, shooting_day_id)` pair invariant
//! (`uq_projection_scene_shoot_pair`, issue #404):
//!
//! - A second `SceneShootPlanned` for the *same* pair under a *different*
//!   stream id hits the authoritative constraint (23505), is classified, and
//!   is **skipped** via SAVEPOINT rollback — the projector must stay alive
//!   (pre-#404 it panic-killed the worker/coordinator).
//! - Follow-up events on the skipped duplicate stream are harmless: their
//!   handlers are `UPDATE ... WHERE id` statements that affect 0 rows and
//!   **cannot create a projection row** (CodeRabbit #406 review).
//! - A trailing event on the authoritative stream proves the projector
//!   processed *through* the poison event and its follow-ups.

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
            Ok(_) | Err(DomainError::NotFound { .. }) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Ok(view) => {
                bail!(
                    "projection lag: SceneShoot({id}) version {} < {min_version}",
                    view.version.0
                );
            }
            Err(DomainError::NotFound { .. }) => {
                bail!("projection lag: SceneShoot({id}) not projected within deadline");
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

/// A duplicate pair under a fresh stream id must be skipped (not panic-kill
/// the projector), its follow-up events must stay harmless, and the
/// authoritative row must survive.
#[tokio::test]
async fn duplicate_pair_is_skipped_and_follow_up_events_are_harmless() -> Result<()> {
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

    let shoot_a = SceneShootId::new();
    let shoot_b = SceneShootId::new(); // duplicate stream, same pair
    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();

    // Seed FK parents before any scene_shoot events are projected.
    seed_parents(&pool, scene_id, day_id).await?;

    // 1. Authoritative plan (stream A, EMPTY → version 0).
    let planned = SceneShootEvent::SceneShootPlanned {
        id: shoot_a,
        scene_id,
        shooting_day_id: day_id,
        planned_order: LexicalSortKey::new("001").unwrap(),
        status: SceneShootStatus::Planned,
        version: AggregateVersion(1),
    };
    eappend(
        &redis_client,
        &format!("scene_shoot-{}", shoot_a.0),
        "SceneShootPlanned",
        "EMPTY",
        &encode_event(&planned)?,
    )
    .await?;
    let view = await_scene_shoot_version(&repo, shoot_a, 1).await?;
    assert_eq!(view.version.0, 1, "authoritative plan projected");

    // 2. Duplicate pair under a DIFFERENT stream id (issue #404 write-path
    //    gap): the insert violates uq_projection_scene_shoot_pair (23505).
    //    The projector must skip it via SAVEPOINT and stay alive.
    let duplicate = SceneShootEvent::SceneShootPlanned {
        id: shoot_b,
        scene_id,
        shooting_day_id: day_id,
        planned_order: LexicalSortKey::new("002").unwrap(),
        status: SceneShootStatus::Planned,
        version: AggregateVersion(1),
    };
    eappend(
        &redis_client,
        &format!("scene_shoot-{}", shoot_b.0),
        "SceneShootPlanned",
        "EMPTY",
        &encode_event(&duplicate)?,
    )
    .await?;

    // 3. Follow-up event on the skipped duplicate stream: its handler is an
    //    `UPDATE ... WHERE id = $1` that affects 0 rows — it must neither
    //    error nor create a projection row.
    let started_b = SceneShootEvent::SceneShootStarted {
        id: shoot_b,
        start_dt: Utc::now(),
        version: AggregateVersion(2),
    };
    eappend(
        &redis_client,
        &format!("scene_shoot-{}", shoot_b.0),
        "SceneShootStarted",
        "0",
        &encode_event(&started_b)?,
    )
    .await?;

    // 4. Trailing event on the authoritative stream: proves the projector
    //    processed *through* the poison event and the duplicate follow-up.
    let note_a = SceneShootEvent::ShootDayNoteAdded {
        id: shoot_a,
        note_id: Uuid::now_v7(),
        body: "after the poison".into(),
        author: None,
        version: AggregateVersion(2),
    };
    eappend(
        &redis_client,
        &format!("scene_shoot-{}", shoot_a.0),
        "ShootDayNoteAdded",
        "0",
        &encode_event(&note_a)?,
    )
    .await?;
    let view = await_scene_shoot_version(&repo, shoot_a, 2).await?;
    assert_eq!(
        view.notes.len(),
        1,
        "projector alive after the poison event"
    );

    // 5. Exactly ONE projection row exists for the pair — the authoritative
    //    one. The duplicate row must never exist.
    let count: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*) FROM projection_scene_shoot
        WHERE scene_id = $1 AND shooting_day_id = $2
        "#,
    )
    .bind(scene_id)
    .bind(day_id.0)
    .fetch_one(&pool)
    .await?;
    assert_eq!(count, 1, "duplicate pair must not create a second row");

    let authoritative = repo.find_by_scene_and_day(scene_id, day_id).await?;
    assert_eq!(
        authoritative.id, shoot_a,
        "kept row is the authoritative one"
    );
    assert!(
        repo.find_by_id(shoot_b).await.is_err(),
        "skipped duplicate stream must not be projected"
    );

    Ok(())
}
