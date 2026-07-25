// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: moonshotai/kimi-k3 (openrouter)

//! Tier-3 (Postgres-only) repository tests for the SceneShoot read model.
//!
//! Seeds projection data directly into Postgres and exercises the four
//! `SceneShootRepository` query methods without SierraDB or projectors.

mod fixtures;

use std::time::Duration;

use anyhow::Result;
use breakdown_core::scene_shoot::ports::SceneShootRepository;
use breakdown_core::scene_shoot::views::SceneShootView;
use breakdown_core::shared::{AggregateVersion, LexicalSortKey, SceneShootId, ShootingDayId};
use chrono::Utc;
use infra::queries::SceneShootRepositoryImpl;
use serde_json::json;
use sqlx::PgPool;
use uuid::Uuid;

/// Spin up Postgres, apply migrations.
async fn init() -> Result<(
    PgPool,
    testcontainers::ContainerAsync<testcontainers_modules::postgres::Postgres>,
)> {
    let (pool, pg_guard) = fixtures::spawn_postgres().await?;
    sqlx::migrate!("../infra/migrations").run(&pool).await?;
    Ok((pool, pg_guard))
}

/// Seed the parent `projection_scene` and `projection_shooting_day` rows that
/// the `projection_scene_shoot` FK constraints require (see AGENTS.md gotcha).
async fn seed_parents(pool: &PgPool, scene_id: Uuid, day_id: ShootingDayId) -> Result<()> {
    let episode_id = Uuid::now_v7();
    sqlx::query(
        r#"
        INSERT INTO projection_scene
            (id, episode_id, scene_number, location, mood, is_schedule_set, summary, script_day, version, updated_at)
        VALUES ($1, $2, 1, 'loc', 'mood', false, NULL, NULL, 1, now())
        ON CONFLICT (id) DO NOTHING
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
        ON CONFLICT (id) DO NOTHING
        "#,
    )
    .bind(day_id.0)
    .bind(episode_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Seed a single row in `projection_scene_shoot` with the given fields.
async fn seed_scene_shoot(
    pool: &PgPool,
    id: SceneShootId,
    scene_id: Uuid,
    shooting_day_id: ShootingDayId,
    planned_order: &str,
    actual_order: Option<&str>,
    status: &str,
) -> Result<()> {
    seed_parents(pool, scene_id, shooting_day_id).await?;

    let notes = json!([{"id": Uuid::now_v7().to_string(), "body": "test note"}]);
    let continuity_ids: Vec<Uuid> = vec![];

    sqlx::query(
        r#"
        INSERT INTO projection_scene_shoot (id, scene_id, shooting_day_id, planned_order, actual_order, start_dt, end_dt, status, notes, continuity_photo_ids, version, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, now(), now())
        "#,
    )
    .bind(id.0)
    .bind(scene_id)
    .bind(shooting_day_id.0)
    .bind(planned_order)
    .bind(actual_order)
    .bind(None::<chrono::DateTime<Utc>>)
    .bind(None::<chrono::DateTime<Utc>>)
    .bind(status)
    .bind(notes)
    .bind(&continuity_ids)
    .bind(1i64)
    .execute(pool)
    .await?;

    Ok(())
}

/// Strip version and timestamp fields for comparison.
fn strip_volatile(mut v: SceneShootView) -> SceneShootView {
    v.version = AggregateVersion(0);
    v.updated_at = chrono::DateTime::UNIX_EPOCH;
    v
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn find_by_id_returns_row() -> Result<()> {
    let (pool, _pg_guard) = init().await?;

    let id = SceneShootId::new();
    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();

    seed_scene_shoot(&pool, id, scene_id, day_id, "001", None, "Planned").await?;

    let repo = SceneShootRepositoryImpl::new(pool.clone());
    let view = repo.find_by_id(id).await?;

    assert_eq!(view.id, id);
    assert_eq!(view.scene_id, scene_id);
    assert_eq!(view.shooting_day_id, day_id);
    assert_eq!(view.status.as_str(), "Planned");
    assert_eq!(view.planned_order, LexicalSortKey::new("001").unwrap());
    assert!(view.actual_order.is_none());
    assert_eq!(view.notes.len(), 1);
    assert_eq!(view.notes[0].body, "test note");

    Ok(())
}

#[tokio::test]
async fn find_by_id_returns_not_found() -> Result<()> {
    let (pool, _pg_guard) = init().await?;
    let repo = SceneShootRepositoryImpl::new(pool.clone());

    let result = repo.find_by_id(SceneShootId::new()).await;
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("not found"));

    Ok(())
}

#[tokio::test]
async fn list_by_shooting_day_returns_ordered() -> Result<()> {
    let (pool, _pg_guard) = init().await?;

    let day_id = ShootingDayId::new();
    let scene_a = Uuid::now_v7();
    let scene_b = Uuid::now_v7();

    // Create two scene-shoots on the same day with different orders.
    let id_b = SceneShootId::new();
    let id_a = SceneShootId::new();

    // Use actual_order to verify ordering.
    seed_scene_shoot(&pool, id_a, scene_a, day_id, "002", Some("001"), "Shot").await?;
    seed_scene_shoot(&pool, id_b, scene_b, day_id, "001", Some("002"), "Shot").await?;

    let repo = SceneShootRepositoryImpl::new(pool.clone());
    let views = repo.list_by_shooting_day(day_id).await?;

    assert_eq!(views.len(), 2);
    // First by actual_order (001 before 002).
    assert_eq!(views[0].id, id_a);
    assert_eq!(views[1].id, id_b);

    Ok(())
}

#[tokio::test]
async fn list_by_shooting_day_filters_by_day() -> Result<()> {
    let (pool, _pg_guard) = init().await?;

    let day_a = ShootingDayId::new();
    let day_b = ShootingDayId::new();
    let scene = Uuid::now_v7();

    seed_scene_shoot(
        &pool,
        SceneShootId::new(),
        scene,
        day_a,
        "001",
        None,
        "Planned",
    )
    .await?;
    seed_scene_shoot(
        &pool,
        SceneShootId::new(),
        scene,
        day_b,
        "001",
        None,
        "Planned",
    )
    .await?;

    let repo = SceneShootRepositoryImpl::new(pool.clone());
    let views = repo.list_by_shooting_day(day_a).await?;

    assert_eq!(views.len(), 1);

    Ok(())
}

#[tokio::test]
async fn find_by_scene_and_day_returns_correct() -> Result<()> {
    let (pool, _pg_guard) = init().await?;

    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();

    seed_scene_shoot(
        &pool,
        SceneShootId::new(),
        scene_id,
        day_id,
        "001",
        None,
        "Planned",
    )
    .await?;
    // Another shoot on a different day for the same scene.
    let other_day = ShootingDayId::new();
    seed_scene_shoot(
        &pool,
        SceneShootId::new(),
        scene_id,
        other_day,
        "001",
        None,
        "Planned",
    )
    .await?;

    let repo = SceneShootRepositoryImpl::new(pool.clone());
    let view = repo.find_by_scene_and_day(scene_id, day_id).await?;

    assert_eq!(view.scene_id, scene_id);
    assert_eq!(view.shooting_day_id, day_id);

    Ok(())
}

#[tokio::test]
async fn find_by_scene_and_day_not_found() -> Result<()> {
    let (pool, _pg_guard) = init().await?;
    let repo = SceneShootRepositoryImpl::new(pool.clone());

    let result = repo
        .find_by_scene_and_day(Uuid::now_v7(), ShootingDayId::new())
        .await;
    assert!(result.is_err());

    Ok(())
}

#[tokio::test]
async fn list_by_scene_returns_all() -> Result<()> {
    let (pool, _pg_guard) = init().await?;

    let scene_id = Uuid::now_v7();
    let day_a = ShootingDayId::new();
    let day_b = ShootingDayId::new();

    seed_scene_shoot(
        &pool,
        SceneShootId::new(),
        scene_id,
        day_a,
        "001",
        None,
        "Planned",
    )
    .await?;
    seed_scene_shoot(
        &pool,
        SceneShootId::new(),
        scene_id,
        day_b,
        "002",
        None,
        "Planned",
    )
    .await?;

    let repo = SceneShootRepositoryImpl::new(pool.clone());
    let views = repo.list_by_scene(scene_id).await?;

    assert_eq!(views.len(), 2);

    Ok(())
}

#[tokio::test]
async fn list_by_scene_empty_for_unknown_scene() -> Result<()> {
    let (pool, _pg_guard) = init().await?;

    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();
    seed_scene_shoot(
        &pool,
        SceneShootId::new(),
        Uuid::now_v7(),
        day_id,
        "001",
        None,
        "Planned",
    )
    .await?;

    let repo = SceneShootRepositoryImpl::new(pool.clone());
    let views = repo.list_by_scene(scene_id).await?;

    assert!(views.is_empty());

    Ok(())
}

#[tokio::test]
async fn all_status_variants_round_trip() -> Result<()> {
    let (pool, _pg_guard) = init().await?;

    let day_id = ShootingDayId::new();
    let statuses = ["Planned", "Scheduled", "InProgress", "Shot", "Skipped"];

    for (i, status) in statuses.iter().enumerate() {
        let id = SceneShootId::new();
        let key = format!("{:03}", i + 1);
        seed_scene_shoot(&pool, id, Uuid::now_v7(), day_id, &key, None, status).await?;
    }

    let repo = SceneShootRepositoryImpl::new(pool.clone());
    let views = repo.list_by_shooting_day(day_id).await?;

    assert_eq!(views.len(), 5);

    let db_statuses: Vec<&str> = views.iter().map(|v| v.status.as_str()).collect();
    for s in &statuses {
        assert!(db_statuses.contains(s), "missing status {s}");
    }

    Ok(())
}
