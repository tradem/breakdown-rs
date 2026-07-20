// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Category D: Query-Repository integration tests.
//!
//! Exercise the read-model query implementations for Scene, Character, Costume,
//! Season, Block and Episode across an empty → populated projection cycle.

mod fixtures;

use std::time::Duration;

use anyhow::Result;
use breakdown_core::block::commands::CreateBlock;
use breakdown_core::block::ports::{BlockCommands, BlockRepository};
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::commands::{CreateCharacter, UpdateMeasurements};
use breakdown_core::character::events::CharacterMeasurements;
use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
use breakdown_core::costume::commands::{AddDetail, AssignCostumeToCharacter, CreateCostume};
use breakdown_core::costume::events::CostumeDetail;
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::episode::commands::CreateEpisode;
use breakdown_core::episode::ports::{EpisodeCommands, EpisodeRepository};
use breakdown_core::scene::commands::CreateScene;
use breakdown_core::scene::events::SceneDetails;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::season::commands::CreateSeason;
use breakdown_core::season::ports::{SeasonCommands, SeasonRepository};
use breakdown_core::shared::{BlockId, EpisodeId, SeasonId, SeriesId};
use infra::event_store::{
    BlockCommandsImpl, CharacterCommandsImpl, CostumeCommandsImpl, EpisodeCommandsImpl,
    SceneCommandsImpl, SeasonCommandsImpl,
};
use infra::projectors::{
    spawn_block_projector, spawn_character_projector, spawn_costume_projector,
    spawn_episode_projector, spawn_scene_projector, spawn_season_projector,
};
use infra::queries::{
    BlockRepositoryImpl, CharacterRepositoryImpl, CostumeRepositoryImpl, EpisodeRepositoryImpl,
    SceneRepositoryImpl, SeasonRepositoryImpl,
};
use kameo_es::command_service::CommandService;
use rust_decimal::Decimal;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Determine the primary-key column used in a projection table.
fn pk_column_for(table: &str) -> &str {
    match table {
        "projection_scene_character" => "scene_id",
        "projection_costume_detail" | "projection_costume_photo" => "costume_id",
        // All other major projection tables use `id` as primary key.
        _ => "id",
    }
}

/// Wait for a projection row (up to 15 s for eventual consistency),
/// verifying the `version` column is at least `min_version`.
async fn await_proj(pool: &sqlx::PgPool, table: &str, id: Uuid) {
    await_proj_version(pool, table, id, 1).await;
}

/// Wait for a projection row whose `version` >= `min_version`.
/// If `min_version` is 0, this falls back to existence-only checking
/// (useful for child-table joins like projection_scene_character).
async fn await_proj_version(pool: &sqlx::PgPool, table: &str, id: Uuid, min_version: u64) {
    let deadline = std::time::Instant::now() + Duration::from_secs(15);
    let col = pk_column_for(table);
    let query = if min_version > 0 {
        format!(r#"SELECT version FROM "{}" WHERE {} = $1"#, table, col)
    } else {
        format!(
            r#"SELECT EXISTS(SELECT 1 FROM "{}" WHERE {} = $1)"#,
            table, col
        )
    };
    let mut interval = tokio::time::interval(Duration::from_millis(150));
    loop {
        interval.tick().await;
        if std::time::Instant::now() > deadline {
            panic!(
                "{table}({}) not projected{}",
                id,
                if min_version > 0 {
                    format!(" (expected version >= {min_version})")
                } else {
                    String::new()
                }
            );
        }
        let result = sqlx::query(sqlx::AssertSqlSafe(query.as_str()))
            .bind(id)
            .fetch_optional(pool)
            .await
            .unwrap();

        if min_version > 0 {
            // Check that the row exists AND version >= min_version
            if let Some(row) = result {
                let version: i64 = sqlx::Row::try_get(&row, 0).unwrap();
                if version >= min_version as i64 {
                    return;
                }
            }
        } else {
            // Existence-only check: EXISTS() always returns one row
            let exists: bool = sqlx::query_scalar::<_, bool>(sqlx::AssertSqlSafe(query.as_str()))
                .bind(id)
                .fetch_one(pool)
                .await
                .unwrap();
            if exists {
                return;
            }
        }
    }
}

/// Spin up: postgres + sierradb + all projectors.
async fn init() -> Result<(
    sqlx::PgPool,
    CommandService,
    testcontainers::ContainerAsync<testcontainers_modules::postgres::Postgres>,
    testcontainers::ContainerAsync<fixtures::SierraDbImage>,
)> {
    let (pool, pg_guard) = fixtures::spawn_postgres().await?;
    let (sierra_client, _sierra_conn, sierra_guard) = fixtures::spawn_sierradb().await?;

    let r1 = sierra_client.clone();
    let r2 = sierra_client.clone();
    let r3 = sierra_client.clone();
    let r4 = sierra_client.clone();
    let r5 = sierra_client.clone();
    let r6 = sierra_client.clone();

    let _sp = spawn_season_projector(pool.clone(), r1).await?;
    let _sp = spawn_block_projector(pool.clone(), r2).await?;
    let _sp = spawn_episode_projector(pool.clone(), r3).await?;
    let _sp = spawn_scene_projector(pool.clone(), r4).await?;
    let _sp = spawn_character_projector(pool.clone(), r5).await?;
    let _sp = spawn_costume_projector(pool.clone(), r6).await?;

    // Give the supervisor background tasks a chance to enter their epoch loop
    // (tokio::spawn + first backoff + Redis subscription). In slow CI environments
    // the projector subscriptions may not be ready immediately.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let cmd_service = CommandService::new(sierra_client.get_multiplexed_tokio_connection().await?);

    Ok((pool, cmd_service, pg_guard, sierra_guard))
}

// ---------------------------------------------------------------------------
// Query tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn scenes_by_episode_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let episode_id = EpisodeId::new();
    let scene_repo = SceneRepositoryImpl::new(pool.clone());
    let scene_cmd = SceneCommandsImpl::new(cmd_svc);

    let scene_id = Uuid::now_v7();

    let cmd = CreateScene {
        id: scene_id,
        episode_id,
        details: SceneDetails {
            scene_number: Some(1),
            location: Some("A".into()),
            mood: Some("A".into()),
            is_schedule_set: false,
summary: None,
        },
    };
    scene_cmd.create(cmd).await?;

    await_proj(&pool, "projection_scene", scene_id).await;

    let scenes = scene_repo.list_by_episode(episode_id, 100, 0).await?;

    assert!(
        !scenes.is_empty(),
        "expected at least 1 scene, got {}",
        scenes.len()
    );

    assert!(scenes.iter().any(|s| s.id == scene_id));

    Ok(())
}

#[tokio::test]
async fn characters_by_season_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let season_id = SeasonId::new();
    let char_repo = CharacterRepositoryImpl::new(pool.clone());
    let char_cmd = CharacterCommandsImpl::new(cmd_svc);

    let char_id = Uuid::now_v7();

    let cmd = CreateCharacter {
        id: char_id,
        season_id,
        name: "Heroin".into(),
        category: CharacterCategory::MainCast,
    };
    char_cmd.create(cmd).await?;

    await_proj(&pool, "projection_character", char_id).await;

    let chars = char_repo.list_by_season(season_id, 100, 0).await?;

    assert!(
        !chars.is_empty(),
        "expected at least 1 character, got {}",
        chars.len()
    );

    assert!(chars.iter().any(|c| c.id == char_id));

    Ok(())
}

#[tokio::test]
async fn costumes_by_season_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let season_id = SeasonId::new();
    let char_cmd = CharacterCommandsImpl::new(cmd_svc.clone());
    let costume_cmd = CostumeCommandsImpl::new(cmd_svc);
    let costume_repo = CostumeRepositoryImpl::new(pool.clone());

    // A costume is only visible via `list_by_season` once it is bound to a
    // character in that season (the query joins through `character_id`).
    let char_id = Uuid::now_v7();
    char_cmd
        .create(CreateCharacter {
            id: char_id,
            season_id,
            name: "Wearer".into(),
            category: CharacterCategory::MainCast,
        })
        .await?;
    await_proj(&pool, "projection_character", char_id).await;

    let costume_id = Uuid::now_v7();
    let (_id, ver) = costume_cmd.create(CreateCostume { id: costume_id }).await?;
    await_proj(&pool, "projection_costume", costume_id).await;

    costume_cmd
        .assign_to_character(AssignCostumeToCharacter {
            id: costume_id,
            character_id: char_id,
            version: ver,
        })
        .await?;
    await_proj_version(&pool, "projection_costume", costume_id, ver.0 + 1).await;

    let costumes = costume_repo.list_by_season(season_id, 100, 0).await?;

    assert!(
        !costumes.is_empty(),
        "expected at least 1 costume, got {}",
        costumes.len()
    );
    assert!(costumes.iter().any(|c| c.id == costume_id));

    Ok(())
}

#[tokio::test]
async fn costumes_with_details_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let _costume_repo = CostumeRepositoryImpl::new(pool.clone());
    let costume_cmd = CostumeCommandsImpl::new(cmd_svc);

    let costume_id = Uuid::now_v7();

    let cmd = CreateCostume { id: costume_id };
    let (_id, ver) = costume_cmd.create(cmd).await?;

    await_proj(&pool, "projection_costume", costume_id).await;

    // Add a detail
    let detail_id = Uuid::now_v7();
    let ver2 = costume_cmd
        .add_detail(AddDetail {
            id: costume_id,
            detail: CostumeDetail {
                id: detail_id,
                text: "Sleeve".into(),
            },
            version: ver,
        })
        .await?;

    await_proj_version(&pool, "projection_costume", costume_id, ver2.0 as u64).await;
    await_proj_version(&pool, "projection_costume_detail", costume_id, 0).await;

    Ok(())
}

#[tokio::test]
async fn seasons_by_series_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let series_id = SeriesId::new();
    let season_repo = SeasonRepositoryImpl::new(pool.clone());
    let season_cmd = SeasonCommandsImpl::new(cmd_svc);

    let season_id = Uuid::now_v7();
    season_cmd
        .create(CreateSeason {
            id: season_id,
            series_id,
            number: 2,
            title: Some("S2".into()),
        })
        .await?;
    await_proj(&pool, "projection_season", season_id).await;

    let seasons = season_repo.list_by_series(series_id, 100, 0).await?;
    assert!(seasons.iter().any(|s| s.id == season_id));

    let found = season_repo.find_by_series_and_number(series_id, 2).await?;
    assert_eq!(found.map(|s| s.id), Some(season_id));
    Ok(())
}

#[tokio::test]
async fn blocks_by_season_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let season_id = SeasonId::new();
    let series_id = SeriesId::new();
    let block_repo = BlockRepositoryImpl::new(pool.clone());
    let block_cmd = BlockCommandsImpl::new(cmd_svc);

    let block_id = Uuid::now_v7();
    block_cmd
        .create(CreateBlock {
            id: block_id,
            season_id,
            series_id,
            number: 4,
            start_date: None,
            end_date: None,
        })
        .await?;
    await_proj(&pool, "projection_block", block_id).await;

    let blocks = block_repo.list_by_season(season_id, 100, 0).await?;
    assert!(blocks.iter().any(|b| b.id == block_id));
    Ok(())
}

#[tokio::test]
async fn episodes_by_series_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let block_id = BlockId::new();
    let series_id = SeriesId::new();
    let episode_repo = EpisodeRepositoryImpl::new(pool.clone());
    let episode_cmd = EpisodeCommandsImpl::new(cmd_svc);

    let episode_id = Uuid::now_v7();
    episode_cmd
        .create(CreateEpisode {
            id: episode_id,
            block_id,
            series_id,
            number: 9,
            name: Some("E9".into()),
        })
        .await?;
    await_proj(&pool, "projection_episode", episode_id).await;

    let episodes = episode_repo.list_by_series(series_id, 100, 0).await?;
    assert!(episodes.iter().any(|e| e.id == episode_id));

    let found = episode_repo.find_by_series_and_number(series_id, 9).await?;
    assert_eq!(found.map(|e| e.id), Some(episode_id));
    Ok(())
}

#[tokio::test]
async fn character_measurements_persist() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let season_id = SeasonId::new();
    let char_cmd = CharacterCommandsImpl::new(cmd_svc);
    let char_repo = CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();
    let (_id, ver) = char_cmd
        .create(CreateCharacter {
            id: char_id,
            season_id,
            name: "Measured".into(),
            category: CharacterCategory::Guest,
        })
        .await?;
    await_proj(&pool, "projection_character", char_id).await;

    let ver2 = char_cmd
        .update_measurements(UpdateMeasurements {
            id: char_id,
            measurements: CharacterMeasurements {
                height: Some(Decimal::from(180)),
                weight: Some(Decimal::from(75)),
                ..Default::default()
            },
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    await_proj_version(&pool, "projection_character", char_id, ver2.0 as u64).await;
    assert_eq!(
        char_repo.find_by_id(char_id).await?.measurements.height,
        Some(Decimal::from(180))
    );
    Ok(())
}
