// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

//! Read-model round trip for the per-character appearances query (issue #621,
//! `GET /v1/characters/{id}/appearances`).
//!
//! Pins the two data properties the route promises: script order
//! (`scene_number`, unnumbered scenes last) and the **character's own** ordered
//! costume beats per scene (costume binding), enriched best-effort with the
//! costume category by join. The HTTP surface (authz denial, 404, 200) is
//! covered separately in `crates/api/tests/handler_character_appearances.rs`;
//! here we exercise the real SQL against Postgres.

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
use breakdown_core::character::ports::CharacterRepository;
use breakdown_core::shared::EpisodeId;
use chrono::{DateTime, Utc};
use infra::queries::CharacterRepositoryImpl;
use uuid::Uuid;

/// Insert one scene projection row. `scene_number` is `Option` so the
/// unnumbered case can be exercised.
async fn insert_scene(
    pool: &sqlx::PgPool,
    scene_id: Uuid,
    episode_id: EpisodeId,
    scene_number: Option<i32>,
    summary: &str,
    now: DateTime<Utc>,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO projection_scene
            (id, episode_id, scene_number, location, mood, is_schedule_set,
             summary, version, updated_at)
        VALUES ($1, $2, $3, $4, $5, true, $6, 1, $7)
        "#,
    )
    .bind(scene_id)
    .bind(episode_id.0)
    .bind(scene_number)
    .bind("Studio")
    .bind("Neutral")
    .bind(summary)
    .bind(now)
    .execute(pool)
    .await?;
    Ok(())
}

/// Insert an episode projection row (`projection_episode.number` is NOT NULL);
/// the query orders by it first because `scene_number` is episode-local.
async fn insert_episode(
    pool: &sqlx::PgPool,
    episode_id: EpisodeId,
    number: i32,
    now: DateTime<Utc>,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO projection_episode
            (id, block_id, project_id, number, name, version, updated_at)
        VALUES ($1, $2, $3, $4, $5, 1, $6)
        "#,
    )
    .bind(episode_id.0)
    .bind(Uuid::now_v7())
    .bind(Uuid::now_v7())
    .bind(number)
    .bind(format!("Episode {number}"))
    .bind(now)
    .execute(pool)
    .await?;
    Ok(())
}

async fn assign_character(pool: &sqlx::PgPool, scene_id: Uuid, character_id: Uuid) -> Result<()> {
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
    Ok(())
}

/// Insert a costume with an optional category and return its id.
async fn insert_costume(
    pool: &sqlx::PgPool,
    category_id: Option<Uuid>,
    category_name: Option<&str>,
    now: DateTime<Utc>,
) -> Result<Uuid> {
    let costume_id = Uuid::now_v7();
    sqlx::query(
        r#"
        INSERT INTO projection_costume
            (id, character_id, notes, category_id, category_name,
             version, updated_at)
        VALUES ($1, NULL, '', $2, $3, 1, $4)
        "#,
    )
    .bind(costume_id)
    .bind(category_id)
    .bind(category_name)
    .bind(now)
    .execute(pool)
    .await?;
    Ok(costume_id)
}

async fn add_beat(
    pool: &sqlx::PgPool,
    scene_id: Uuid,
    character_id: Uuid,
    order: i32,
    costume_id: Uuid,
    note: Option<&str>,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO projection_scene_costume_assignment
            (scene_id, character_id, "order", costume_id, note, version)
        VALUES ($1, $2, $3, $4, $5, 1)
        "#,
    )
    .bind(scene_id)
    .bind(character_id)
    .bind(order)
    .bind(costume_id)
    .bind(note)
    .execute(pool)
    .await?;
    Ok(())
}

/// Appearances come back in script order — episode number first, then the
/// episode-local `scene_number` (unnumbered last) — carry only the queried
/// character's beats, and order those beats by `order`. A scene without a beat
/// for the character yields an empty costume list, and a scene that features
/// another character only is not returned.
#[tokio::test]
async fn appearances_are_script_ordered_with_the_characters_own_costumes() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;

    // Two episodes: `scene_number` is episode-local, so episode 2's scene 1 must
    // sort *after* episode 1's scene 30.
    let episode_1 = EpisodeId::new();
    let episode_2 = EpisodeId::new();
    let hero = Uuid::now_v7();
    let extra = Uuid::now_v7();
    let now = Utc::now();

    insert_episode(&pool, episode_1, 1, now).await?;
    insert_episode(&pool, episode_2, 2, now).await?;

    // Scenes inserted out of script order on purpose (30, 10, 20, unnumbered)
    // plus one scene in the second episode.
    let scene_30 = Uuid::now_v7();
    let scene_10 = Uuid::now_v7();
    let scene_20 = Uuid::now_v7();
    let scene_unnumbered = Uuid::now_v7();
    let scene_ep2_1 = Uuid::now_v7();
    // A scene featuring only the other character must not leak in.
    let scene_other = Uuid::now_v7();

    insert_scene(&pool, scene_30, episode_1, Some(30), "Third", now).await?;
    insert_scene(&pool, scene_10, episode_1, Some(10), "First", now).await?;
    insert_scene(&pool, scene_20, episode_1, Some(20), "Second", now).await?;
    insert_scene(&pool, scene_unnumbered, episode_1, None, "Unnumbered", now).await?;
    insert_scene(&pool, scene_ep2_1, episode_2, Some(1), "Next episode", now).await?;
    insert_scene(&pool, scene_other, episode_2, Some(5), "Other cast", now).await?;

    for scene in [scene_30, scene_10, scene_20, scene_unnumbered, scene_ep2_1] {
        assign_character(&pool, scene, hero).await?;
    }
    assign_character(&pool, scene_other, extra).await?;

    // Two costumes on scene 20 (order 0 = coat, order 1 = shirt), one on
    // scene 10; scenes 30 / unnumbered / ep2-1 intentionally have no beat.
    let category_id = Uuid::now_v7();
    let coat = insert_costume(&pool, Some(category_id), Some("Oberteil"), now).await?;
    let shirt = insert_costume(&pool, None, None, now).await?;
    let boots = insert_costume(&pool, Some(category_id), Some("Oberteil"), now).await?;
    add_beat(&pool, scene_10, hero, 0, boots, Some("Regen")).await?;
    add_beat(&pool, scene_20, hero, 0, coat, None).await?;
    add_beat(&pool, scene_20, hero, 1, shirt, Some("drunter")).await?;
    // A beat of the OTHER character must not appear in the hero's extract.
    add_beat(&pool, scene_other, extra, 0, coat, None).await?;

    let repo = CharacterRepositoryImpl::new(pool.clone());
    let appearances = repo.character_appearances(hero).await?;

    let numbers: Vec<Option<u32>> = appearances.iter().map(|a| a.scene_number).collect();
    assert_eq!(
        numbers,
        vec![Some(10), Some(20), Some(30), None, Some(1)],
        "episode 1 (10, 20, 30, unnumbered) must precede episode 2's scene 1"
    );
    assert_eq!(appearances[0].synopsis.as_deref(), Some("First"));

    // Scene 10: exactly the one boot beat, with its category resolved.
    assert_eq!(appearances[0].costumes.len(), 1);
    assert_eq!(appearances[0].costumes[0].costume_id, boots);
    assert_eq!(appearances[0].costumes[0].order, 0);
    assert_eq!(appearances[0].costumes[0].note.as_deref(), Some("Regen"));
    assert_eq!(
        appearances[0].costumes[0].costume_category_name.as_deref(),
        Some("Oberteil")
    );

    // Scene 20: both beats, ordered, and none of the other character's.
    let scene_20_row = &appearances[1];
    let ids: Vec<Uuid> = scene_20_row.costumes.iter().map(|c| c.costume_id).collect();
    assert_eq!(ids, vec![coat, shirt]);
    assert_eq!(scene_20_row.costumes[0].order, 0);
    assert_eq!(scene_20_row.costumes[1].order, 1);
    assert_eq!(scene_20_row.costumes[1].note.as_deref(), Some("drunter"));

    // Scenes without a beat for the character resolve to an empty list.
    assert!(appearances[2].costumes.is_empty());
    assert!(appearances[3].costumes.is_empty());
    assert!(appearances[4].costumes.is_empty());

    // The other character's scene is not part of the hero's extract.
    assert!(appearances.iter().all(|a| a.scene_id != scene_other));

    Ok(())
}

/// A character with no scene assignment resolves to an empty list — not an
/// error (the caller's `find_by_id` handles the 404, the query is a plain
/// projection read).
#[tokio::test]
async fn unknown_character_yields_an_empty_list() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;

    let repo = CharacterRepositoryImpl::new(pool.clone());
    let appearances = repo.character_appearances(Uuid::now_v7()).await?;

    assert!(appearances.is_empty());
    Ok(())
}
