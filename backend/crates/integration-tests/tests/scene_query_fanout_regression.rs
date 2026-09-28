// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

//! Regression tests for issue #550 — `array_agg` fan-out over joined
//! one-to-many pivots.
//!
//! The scene read model joined `projection_scene_character` and
//! `projection_scene_shooting_day` side-by-side and aggregated each list with
//! a plain `array_agg`. Two independent one-to-many joins multiply the row
//! count (`c·d`, `c·c·d` in `scenes_by_character`), so `assigned_characters`
//! and `shooting_day_ids` came back with duplicated elements for every scene
//! where either side exceeded 1. These tests pin the corrected shape with a
//! fan-out-triggering fixture (2 characters × 2 shooting days — the 1×1 case
//! passes with or without the fix and is what let the bug through), cover all
//! four affected read entry points, and cross-check the aggregate state
//! against the query result for the same event stream.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

mod fixtures;

use anyhow::Result;
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::events::{SceneDetails, SceneEvent, SceneSource};
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::shared::{AggregateVersion, EpisodeId, ShootingDayId};
use breakdown_core::shooting_day::ports::ShootingDayRepository;
use chrono::{DateTime, Utc};
use infra::projectors::SceneProjector;
use infra::queries::{SceneRepositoryImpl, ShootingDayRepositoryImpl};
use kameo_es::event_handler::EntityEventHandler;
use kameo_es::{Apply, Entity, Event, EventType, Metadata, StreamId};
use uuid::Uuid;

/// Seed a `projection_shooting_day` parent row. The
/// `projection_scene_shooting_day.shooting_day_id` foreign key requires it
/// before a scene→day link can exist.
async fn insert_projection_shooting_day(
    pool: &sqlx::PgPool,
    id: ShootingDayId,
    episode_id: EpisodeId,
    order_key: &str,
    now: DateTime<Utc>,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO projection_shooting_day
            (id, episode_id, label, order_key, date, source, archived, version, updated_at)
        VALUES ($1, $2, $3, $4, $5, '{"Manual":null}'::jsonb, false, 1, $6)
        "#,
    )
    .bind(id.0)
    .bind(episode_id.0)
    .bind(format!("Day {order_key}"))
    .bind(order_key)
    .bind(now.date_naive())
    .bind(now)
    .execute(pool)
    .await?;
    Ok(())
}

/// Fan-out fixture: one scene with **2 assigned characters** and links to
/// **2 shooting days**, written directly into the projections (1 pivot row per
/// element — the pivots themselves were never the problem).
///
/// Under the buggy query shape `find_by_id` returned `c·d = 4` elements per
/// list; a correct read returns exactly 2 + 2.
async fn seed_fanout_scene(
    pool: &sqlx::PgPool,
    scene_id: Uuid,
    episode_id: EpisodeId,
    characters: &[Uuid],
    days: &[ShootingDayId],
    now: DateTime<Utc>,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO projection_scene
            (id, episode_id, scene_number, location, mood, is_schedule_set, version, updated_at)
        VALUES ($1, $2, $3, $4, $5, true, 1, $6)
        "#,
    )
    .bind(scene_id)
    .bind(episode_id.0)
    .bind(7_i32)
    .bind("Studio")
    .bind("Neutral")
    .bind(now)
    .execute(pool)
    .await?;

    for character_id in characters {
        sqlx::query(
            r#"
            INSERT INTO projection_scene_character (scene_id, character_id, version)
            VALUES ($1, $2, 1)
            "#,
        )
        .bind(scene_id)
        .bind(character_id)
        .execute(pool)
        .await?;
    }

    for day in days {
        insert_projection_shooting_day(pool, *day, episode_id, &day.0.simple().to_string(), now)
            .await?;
        sqlx::query(
            r#"
            INSERT INTO projection_scene_shooting_day (scene_id, shooting_day_id, version)
            VALUES ($1, $2, 1)
            "#,
        )
        .bind(scene_id)
        .bind(day.0)
        .execute(pool)
        .await?;
    }
    Ok(())
}

/// `find_by_id` and `list_by_episode` must return each pivot element exactly
/// once even though both one-to-many pivots are present (issue #550).
#[tokio::test]
async fn scene_find_by_id_and_list_by_episode_return_unduplicated_pivots() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let characters = [Uuid::now_v7(), Uuid::now_v7()];
    let days = [ShootingDayId::new(), ShootingDayId::new()];
    let now = Utc::now();

    seed_fanout_scene(&pool, scene_id, episode_id, &characters, &days, now).await?;

    let repo = SceneRepositoryImpl::new(pool.clone());

    let view = repo.find_by_id(scene_id).await?;
    assert_eq!(
        view.assigned_characters.len(),
        2,
        "assigned_characters fanned out: {:?}",
        view.assigned_characters
    );
    assert_eq!(
        view.shooting_day_ids.len(),
        2,
        "shooting_day_ids fanned out: {:?}",
        view.shooting_day_ids
    );
    for character_id in characters {
        assert!(view.assigned_characters.contains(&character_id));
    }
    for day in days {
        assert!(view.shooting_day_ids.contains(&day));
    }

    let listed = repo.list_by_episode(episode_id, 10, 0).await?;
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].assigned_characters.len(), 2);
    assert_eq!(listed[0].shooting_day_ids.len(), 2);

    Ok(())
}

/// `scenes_by_character` used to join the character pivot twice plus the day
/// pivot (`c·c·d` rows). With one filter-character and one *additional*
/// character on the scene the buggy shape inflated `assigned_characters` to
/// `c·d` entries; the fix must report 2 characters and 2 days.
#[tokio::test]
async fn scenes_by_character_returns_unduplicated_pivots() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let characters = [Uuid::now_v7(), Uuid::now_v7()];
    let days = [ShootingDayId::new(), ShootingDayId::new()];
    let now = Utc::now();

    seed_fanout_scene(&pool, scene_id, episode_id, &characters, &days, now).await?;

    let repo = SceneRepositoryImpl::new(pool.clone());
    let views = repo.scenes_by_character(characters[0]).await?;

    assert_eq!(views.len(), 1);
    assert_eq!(
        views[0].assigned_characters.len(),
        2,
        "assigned_characters fanned out through the double character join: {:?}",
        views[0].assigned_characters
    );
    assert_eq!(
        views[0].shooting_day_ids.len(),
        2,
        "shooting_day_ids fanned out: {:?}",
        views[0].shooting_day_ids
    );
    assert!(views[0].assigned_characters.contains(&characters[1]));

    Ok(())
}

/// `ShootingDayRepositoryImpl::scenes_by_shooting_day` joined the day filter
/// against the character pivot, so each character re-reported the already
/// single-linked day. A scene with 2 characters must still report its 2 days
/// once each (issue #550).
#[tokio::test]
async fn scenes_by_shooting_day_returns_unduplicated_pivots() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let characters = [Uuid::now_v7(), Uuid::now_v7()];
    let days = [ShootingDayId::new(), ShootingDayId::new()];
    let now = Utc::now();

    seed_fanout_scene(&pool, scene_id, episode_id, &characters, &days, now).await?;

    let repo = ShootingDayRepositoryImpl::new(pool.clone());
    let views = repo.scenes_by_shooting_day(days[0]).await?;

    assert_eq!(views.len(), 1);
    assert_eq!(
        views[0].assigned_characters.len(),
        2,
        "assigned_characters fanned out: {:?}",
        views[0].assigned_characters
    );
    assert_eq!(
        views[0].shooting_day_ids.len(),
        2,
        "shooting_day_ids duplicated for every character row: {:?}",
        views[0].shooting_day_ids
    );

    Ok(())
}

/// Cross-check test (issue #550): the write and read side must agree on the
/// same event stream. The `SceneAggregate` dedupes schedule/assign links by
/// construction, while the read model *disagreed* with it by duplicating the
/// ids through a join fan-out. Asserting *aggregate state == query result*
/// pins that class of bug mechanically: both sides replay the same events —
/// the aggregate through `Apply`, the projections through the production
/// `SceneProjector`.
#[tokio::test]
async fn aggregate_state_matches_query_result_for_same_event_stream() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let characters = [Uuid::now_v7(), Uuid::now_v7()];
    let days = [ShootingDayId::new(), ShootingDayId::new()];
    let now = Utc::now();

    // Parent rows for the day-link foreign key.
    for day in days {
        insert_projection_shooting_day(&pool, day, episode_id, &day.0.simple().to_string(), now)
            .await?;
    }

    let details = SceneDetails {
        scene_number: Some(7),
        location: Some("Studio".into()),
        mood: Some("Neutral".into()),
        is_schedule_set: true,
        summary: None,
        script_day: None,
    };

    let events = vec![
        SceneEvent::SceneCreated {
            id: scene_id,
            episode_id,
            details,
            assigned_characters: characters.to_vec(),
            version: AggregateVersion::INITIAL,
            source: SceneSource::Manual,
        },
        SceneEvent::ShootingDayScheduled {
            id: scene_id,
            shooting_day_id: days[0],
            version: AggregateVersion(2),
        },
        SceneEvent::ShootingDayScheduled {
            id: scene_id,
            shooting_day_id: days[1],
            version: AggregateVersion(3),
        },
    ];

    // Read side: project every event through the production projector.
    let mut expected_state = SceneAggregate::default();
    for event in events.clone() {
        let kameo_event = Event {
            id: Uuid::now_v7(),
            partition_key: Uuid::now_v7(),
            partition_id: 0,
            transaction_id: Uuid::now_v7(),
            partition_sequence: 1,
            stream_version: 1,
            stream_id: StreamId::new_from_parts(SceneAggregate::category(), scene_id),
            name: event.event_type().to_string(),
            data: event.clone(),
            metadata: Metadata::default(),
            timestamp: now,
        };
        let mut tx = pool.begin().await?;
        SceneProjector
            .handle(&mut tx, scene_id, kameo_event)
            .await?;
        tx.commit().await?;

        // Write side: fold the same event into the aggregate state.
        Apply::apply(&mut expected_state, event, Metadata::default());
    }

    let repo = SceneRepositoryImpl::new(pool.clone());
    let view = repo.find_by_id(scene_id).await?;

    let mut agg_characters = expected_state.assigned_characters.clone();
    agg_characters.sort();
    let mut view_characters = view.assigned_characters.clone();
    view_characters.sort();
    assert_eq!(
        agg_characters, view_characters,
        "aggregate and read model disagree on assigned_characters"
    );

    let mut agg_days = expected_state.shooting_day_ids.clone();
    agg_days.sort();
    let mut view_days = view.shooting_day_ids.clone();
    view_days.sort();
    assert_eq!(
        agg_days, view_days,
        "aggregate and read model disagree on shooting_day_ids"
    );

    // Sanity: the agreed state is the *distinct* 2×2 shape, not a fan-out.
    assert_eq!(view_characters.len(), 2);
    assert_eq!(view_days.len(), 2);

    Ok(())
}
