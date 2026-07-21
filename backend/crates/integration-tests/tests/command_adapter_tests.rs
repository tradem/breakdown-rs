// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Category A + B: Command-adapter integration tests.
//!
//! Full path: command → SierraDB → projector → Postgres projection.
//! Mutants killed = assert return value ≠ nil + projection row exists.

mod fixtures;

use std::time::Duration;

use anyhow::Result;
use breakdown_core::block::commands::CreateBlock;
use breakdown_core::block::ports::{BlockCommands, BlockRepository};
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use breakdown_core::character::events::{CharacterMeasurements, ContactInfo};
use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
use breakdown_core::costume::commands::{AssignCostumeToCharacter, CreateCostume};
use breakdown_core::costume::events::CostumeDetail;
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::episode::commands::CreateEpisode;
use breakdown_core::episode::ports::{EpisodeCommands, EpisodeRepository};
use breakdown_core::scene::commands::AssignCharacter;
use breakdown_core::scene::events::SceneDetails;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::season::commands::CreateSeason;
use breakdown_core::season::ports::{SeasonCommands, SeasonRepository};
use breakdown_core::shared::{BlockId, EpisodeId, SeasonId, SeriesId};
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

    // All projector spawners take PgPool by value and Arc<RedisClient> by value.
    // Clone the Arc (cheap refcount bump) for each projector, keeping the
    // original for CommandService construction.
    let r1 = sierra_client.clone();
    let r2 = sierra_client.clone();
    let r3 = sierra_client.clone();
    let r4 = sierra_client.clone();
    let r5 = sierra_client.clone();
    let r6 = sierra_client.clone();

    let _sp = infra::projectors::spawn_season_projector(pool.clone(), r1).await?;
    let _sp = infra::projectors::spawn_block_projector(pool.clone(), r2).await?;
    let _sp = infra::projectors::spawn_episode_projector(pool.clone(), r3).await?;
    let _sp = infra::projectors::spawn_scene_projector(pool.clone(), r4).await?;
    let _sp = infra::projectors::spawn_character_projector(pool.clone(), r5).await?;
    let _sp = infra::projectors::spawn_costume_projector(pool.clone(), r6).await?;

    // Give the supervisor background tasks a chance to enter their epoch loop
    // (tokio::spawn + first backoff + Redis subscription). In slow CI environments
    // the projector subscriptions may not be ready immediately.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let cmd_service = CommandService::new(sierra_client.get_multiplexed_tokio_connection().await?);
    Ok((pool, cmd_service, pg_guard, sierra_guard))
}

// ---------------------------------------------------------------------------
// Scene
// ---------------------------------------------------------------------------

#[tokio::test]
async fn scene_create() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let scene_cmd = infra::event_store::SceneCommandsImpl::new(cmd_svc);
    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();

    let cmd = breakdown_core::scene::commands::CreateScene {
        id: scene_id,
        episode_id,
        details: SceneDetails {
            scene_number: Some(42),
            location: Some("Berlin".into()),
            mood: Some("dark".into()),
            is_schedule_set: true,
            summary: None,
        },
    };

    let (rid, rv) = scene_cmd.create(cmd).await?;
    assert_ne!(rid, Uuid::nil());
    assert_eq!(rid, scene_id);
    assert!(rv.0 >= 1, "version {}", rv.0);

    await_proj(&pool, "projection_scene", scene_id).await;
    let v = scene_repo.find_by_id(scene_id).await?;
    assert_eq!(v.scene_number, Some(42));
    assert_eq!(v.location, Some("Berlin".into()));
    Ok(())
}

#[tokio::test]
async fn scene_update_details() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let scene_cmd = infra::event_store::SceneCommandsImpl::new(cmd_svc);
    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();

    let cmd = breakdown_core::scene::commands::CreateScene {
        id: scene_id,
        episode_id: EpisodeId::new(),
        details: SceneDetails {
            scene_number: Some(1),
            location: Some("A".into()),
            mood: Some("A".into()),
            is_schedule_set: false,
            summary: None,
        },
    };
    let (_id, ver) = scene_cmd.create(cmd).await?;
    await_proj(&pool, "projection_scene", scene_id).await;

    let ver2 = scene_cmd
        .update_details(breakdown_core::scene::commands::UpdateSceneDetails {
            id: scene_id,
            details: SceneDetails {
                scene_number: Some(99),
                location: Some("Updated".into()),
                mood: Some("bright".into()),
                is_schedule_set: true,
                summary: None,
            },
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    // Wait for the *update* to be projected, not just the create (min_version 1
    // would return immediately on the stale create row).
    await_proj_version(&pool, "projection_scene", scene_id, ver2.0 as u64).await;
    assert_eq!(
        scene_repo.find_by_id(scene_id).await?.scene_number,
        Some(99)
    );
    Ok(())
}

#[tokio::test]
async fn scene_assign_remove_character() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let scene_cmd = infra::event_store::SceneCommandsImpl::new(cmd_svc);
    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let char_id = Uuid::now_v7();

    let cmd = breakdown_core::scene::commands::CreateScene {
        id: scene_id,
        episode_id: EpisodeId::new(),
        details: SceneDetails {
            scene_number: Some(1),
            location: None,
            mood: None,
            is_schedule_set: false,
            summary: None,
        },
    };
    let (_id, ver) = scene_cmd.create(cmd).await?;
    await_proj(&pool, "projection_scene", scene_id).await;

    let ver2 = scene_cmd
        .assign_character(AssignCharacter {
            id: scene_id,
            character_id: char_id,
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    await_proj_version(&pool, "projection_scene", scene_id, ver2.0 as u64).await;
    await_proj_version(&pool, "projection_scene_character", scene_id, 0).await;
    let v = scene_repo.find_by_id(scene_id).await?;
    assert_eq!(v.assigned_characters.len(), 1);

    let ver3 = scene_cmd
        .remove_character(breakdown_core::scene::commands::RemoveCharacter {
            id: scene_id,
            character_id: char_id,
            version: ver2,
        })
        .await?;
    assert!(ver3.0 > ver2.0);

    await_proj_version(&pool, "projection_scene", scene_id, ver3.0 as u64).await;
    let v = scene_repo.find_by_id(scene_id).await?;
    assert!(v.assigned_characters.is_empty());
    Ok(())
}

// ---------------------------------------------------------------------------
// Character
// ---------------------------------------------------------------------------

#[tokio::test]
async fn character_create() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let char_cmd = infra::event_store::CharacterCommandsImpl::new(cmd_svc);
    let char_repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();

    let cmd = CreateCharacter {
        id: char_id,
        season_id: SeasonId::new(),
        name: "Hero".into(),
        category: CharacterCategory::MainCast,
    };

    let (rid, rv) = char_cmd.create(cmd).await?;
    assert_ne!(rid, Uuid::nil());
    assert_eq!(rid, char_id);
    assert!(rv.0 >= 1);

    await_proj(&pool, "projection_character", char_id).await;
    let v = char_repo.find_by_id(char_id).await?;
    assert_eq!(v.name, "Hero");
    Ok(())
}

#[tokio::test]
async fn character_update_measurements() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let char_cmd = infra::event_store::CharacterCommandsImpl::new(cmd_svc);
    let char_repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();

    let cmd = CreateCharacter {
        id: char_id,
        season_id: SeasonId::new(),
        name: "Test".into(),
        category: CharacterCategory::Guest,
    };
    let (_id, ver) = char_cmd.create(cmd).await?;
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
    let v = char_repo.find_by_id(char_id).await?;
    assert_eq!(v.measurements.height, Some(Decimal::from(180)));
    Ok(())
}

#[tokio::test]
async fn character_update_contact_info() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let char_cmd = infra::event_store::CharacterCommandsImpl::new(cmd_svc);
    let char_repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();

    let cmd = CreateCharacter {
        id: char_id,
        season_id: SeasonId::new(),
        name: "Test".into(),
        category: CharacterCategory::Guest,
    };
    let (_id, ver) = char_cmd.create(cmd).await?;
    await_proj(&pool, "projection_character", char_id).await;

    let ver2 = char_cmd
        .update_contact_info(UpdateContactInfo {
            id: char_id,
            contact_info: ContactInfo {
                email: Some("test@example.com".into()),
                phone: Some("+49-123".into()),
            },
            version: ver,
        })
        .await?;

    await_proj_version(&pool, "projection_character", char_id, ver2.0 as u64).await;
    let v = char_repo.find_by_id(char_id).await?;
    assert_eq!(v.contact.email, Some("test@example.com".into()));
    Ok(())
}

// ---------------------------------------------------------------------------
// Costume
// ---------------------------------------------------------------------------

#[tokio::test]
async fn costume_create() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let costume_cmd = infra::event_store::CostumeCommandsImpl::new(cmd_svc);
    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();

    let cmd = CreateCostume { id: costume_id };

    let (rid, rv) = costume_cmd.create(cmd).await?;
    assert_ne!(rid, Uuid::nil());
    assert_eq!(rid, costume_id);
    assert!(rv.0 >= 1);

    await_proj(&pool, "projection_costume", costume_id).await;
    let v = costume_repo.find_by_id(costume_id).await?;
    assert!(v.details.is_empty());
    assert!(v.photos.is_empty());
    Ok(())
}

#[tokio::test]
async fn costume_notes() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let costume_cmd = infra::event_store::CostumeCommandsImpl::new(cmd_svc);
    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();

    let cmd = CreateCostume { id: costume_id };
    let (_id, ver) = costume_cmd.create(cmd).await?;
    await_proj(&pool, "projection_costume", costume_id).await;

    let ver2 = costume_cmd
        .update_notes(breakdown_core::costume::commands::UpdateCostumeNotes {
            id: costume_id,
            notes: "Blue dress".into(),
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    await_proj_version(&pool, "projection_costume", costume_id, ver2.0 as u64).await;
    assert_eq!(
        costume_repo.find_by_id(costume_id).await?.notes,
        "Blue dress"
    );
    Ok(())
}

#[tokio::test]
async fn costume_assign_unassign() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let costume_cmd = infra::event_store::CostumeCommandsImpl::new(cmd_svc.clone());
    let char_cmd = infra::event_store::CharacterCommandsImpl::new(cmd_svc);
    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let char_id = Uuid::now_v7();

    // `projection_costume.character_id` has a FOREIGN KEY to
    // `projection_character(id)` (see migration 20250623000001). Assigning a
    // costume to a non-existent character makes the projector's UPDATE fail
    // with an FK violation, which kills the projector epoch and restarts it
    // in a loop — the projection never advances past the create. Create the
    // character first and wait for its projection so the FK is satisfied.
    char_cmd
        .create(CreateCharacter {
            id: char_id,
            season_id: SeasonId::new(),
            name: "Wearer".into(),
            category: CharacterCategory::Guest,
        })
        .await?;
    await_proj(&pool, "projection_character", char_id).await;

    let cmd = CreateCostume { id: costume_id };
    let (_id, ver) = costume_cmd.create(cmd).await?;
    await_proj(&pool, "projection_costume", costume_id).await;

    let ver2 = costume_cmd
        .assign_to_character(AssignCostumeToCharacter {
            id: costume_id,
            character_id: char_id,
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    await_proj_version(&pool, "projection_costume", costume_id, ver2.0 as u64).await;
    assert_eq!(
        costume_repo.find_by_id(costume_id).await?.character_id,
        Some(char_id)
    );

    let ver3 = costume_cmd
        .unassign(breakdown_core::costume::commands::UnassignCostume {
            id: costume_id,
            version: ver2,
        })
        .await?;
    assert!(ver3.0 > ver2.0);

    await_proj_version(&pool, "projection_costume", costume_id, ver3.0 as u64).await;
    assert!(
        costume_repo
            .find_by_id(costume_id)
            .await?
            .character_id
            .is_none()
    );
    Ok(())
}

#[tokio::test]
async fn costume_detail_add_remove() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let costume_cmd = infra::event_store::CostumeCommandsImpl::new(cmd_svc);
    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let detail_id = Uuid::now_v7();

    let cmd = CreateCostume { id: costume_id };
    let (_id, ver) = costume_cmd.create(cmd).await?;
    await_proj(&pool, "projection_costume", costume_id).await;

    let ver2 = costume_cmd
        .add_detail(breakdown_core::costume::commands::AddDetail {
            id: costume_id,
            detail: CostumeDetail {
                id: detail_id,
                subject: None,
                category_id: None,
                text: "Red lining".into(),
            },
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    await_proj_version(&pool, "projection_costume", costume_id, ver2.0 as u64).await;
    await_proj_version(&pool, "projection_costume_detail", costume_id, 0).await;
    assert_eq!(costume_repo.find_by_id(costume_id).await?.details.len(), 1);

    let ver3 = costume_cmd
        .remove_detail(breakdown_core::costume::commands::RemoveDetail {
            id: costume_id,
            detail_id,
            version: ver2,
        })
        .await?;
    assert!(ver3.0 > ver2.0);

    await_proj_version(&pool, "projection_costume", costume_id, ver3.0 as u64).await;
    assert!(
        costume_repo
            .find_by_id(costume_id)
            .await?
            .details
            .is_empty()
    );
    Ok(())
}

#[tokio::test]
async fn costume_photo_link_unlink() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let costume_cmd = infra::event_store::CostumeCommandsImpl::new(cmd_svc);
    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let photo_id = Uuid::now_v7();

    let cmd = CreateCostume { id: costume_id };
    let (_id, ver) = costume_cmd.create(cmd).await?;
    await_proj(&pool, "projection_costume", costume_id).await;

    let ver2 = costume_cmd
        .link_photo(breakdown_core::costume::commands::LinkPhoto {
            id: costume_id,
            photo_id,
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    await_proj_version(&pool, "projection_costume", costume_id, ver2.0 as u64).await;
    await_proj_version(&pool, "projection_costume_photo", costume_id, 0).await;
    assert_eq!(costume_repo.find_by_id(costume_id).await?.photos.len(), 1);

    let ver3 = costume_cmd
        .unlink_photo(breakdown_core::costume::commands::UnlinkPhoto {
            id: costume_id,
            photo_id,
            version: ver2,
        })
        .await?;
    assert!(ver3.0 > ver2.0);

    await_proj_version(&pool, "projection_costume", costume_id, ver3.0 as u64).await;
    assert!(costume_repo.find_by_id(costume_id).await?.photos.is_empty());
    Ok(())
}

// ---------------------------------------------------------------------------
// Production hierarchy (Series > Season > Block > Episode)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn season_create() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let season_cmd = infra::event_store::SeasonCommandsImpl::new(cmd_svc);
    let season_repo = infra::queries::SeasonRepositoryImpl::new(pool.clone());

    let season_id = Uuid::now_v7();
    let series_id = SeriesId::new();
    let cmd = CreateSeason {
        id: season_id,
        series_id,
        number: 1,
        title: Some("Season One".into()),
    };

    let (rid, rv) = season_cmd.create(cmd).await?;
    assert_ne!(rid, Uuid::nil());
    assert_eq!(rid, season_id);
    assert!(rv.0 >= 1);

    await_proj(&pool, "projection_season", season_id).await;
    let v = season_repo.find_by_id(season_id).await?;
    assert_eq!(v.number, 1);
    assert_eq!(v.title, Some("Season One".into()));
    Ok(())
}

#[tokio::test]
async fn block_create() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let block_cmd = infra::event_store::BlockCommandsImpl::new(cmd_svc);
    let block_repo = infra::queries::BlockRepositoryImpl::new(pool.clone());

    let block_id = Uuid::now_v7();
    let season_id = SeasonId::new();
    let series_id = SeriesId::new();
    let cmd = CreateBlock {
        id: block_id,
        season_id,
        series_id,
        number: 3,
        start_date: None,
        end_date: None,
    };

    let (rid, rv) = block_cmd.create(cmd).await?;
    assert_eq!(rid, block_id);
    assert!(rv.0 >= 1);

    await_proj(&pool, "projection_block", block_id).await;
    let v = block_repo.find_by_id(block_id).await?;
    assert_eq!(v.number, 3);
    Ok(())
}

#[tokio::test]
async fn episode_create() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let episode_cmd = infra::event_store::EpisodeCommandsImpl::new(cmd_svc);
    let episode_repo = infra::queries::EpisodeRepositoryImpl::new(pool.clone());

    let episode_id = Uuid::now_v7();
    let block_id = BlockId::new();
    let series_id = SeriesId::new();
    let cmd = CreateEpisode {
        id: episode_id,
        block_id,
        series_id,
        number: 7,
        name: Some("Pilot".into()),
    };

    let (rid, rv) = episode_cmd.create(cmd).await?;
    assert_eq!(rid, episode_id);
    assert!(rv.0 >= 1);

    await_proj(&pool, "projection_episode", episode_id).await;
    let v = episode_repo.find_by_id(episode_id).await?;
    assert_eq!(v.number, 7);
    assert_eq!(v.name, Some("Pilot".into()));
    Ok(())
}
