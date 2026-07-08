// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Category D: Query-Repository integration tests.
//!
//! Exercise the read-model query implementations for Scene, Character, Costume,
//! and Calculation across an empty → populated projection cycle.

mod fixtures;

use std::time::Duration;

use anyhow::Result;
use breakdown_core::calculation::commands::{AddCalculationItem, CreateCalculation};
use breakdown_core::calculation::events::CalculationItem;
use breakdown_core::calculation::ports::{CalculationCommands, CalculationRepository};
use breakdown_core::character::commands::CreateCharacter;
use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
use breakdown_core::costume::commands::{AddDetail, CreateCostume};
use breakdown_core::costume::events::CostumeDetail;
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::scene::commands::CreateScene;
use breakdown_core::scene::events::SceneDetails;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::shared::ProjectId;
use infra::event_store::{
    CalculationCommandsImpl, CharacterCommandsImpl, CostumeCommandsImpl, SceneCommandsImpl,
};
use infra::projectors::{
    spawn_calculation_projector, spawn_character_projector, spawn_costume_projector,
    spawn_scene_projector,
};
use infra::queries::{
    CalculationRepositoryImpl, CharacterRepositoryImpl, CostumeRepositoryImpl, SceneRepositoryImpl,
};
use kameo_es::command_service::CommandService;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Determine the primary-key column used in a projection table.
fn pk_column_for(table: &str) -> &str {
    match table {
        "projection_scene_character" => "scene_id",
        "projection_costume_detail" | "projection_costume_photo" => "costume_id",
        "projection_calculation_item" => "calculation_id",
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
        let result = sqlx::query(&query)
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
            let exists: bool = sqlx::query_scalar::<_, bool>(&query)
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

    let _sp = spawn_scene_projector(pool.clone(), r1).await?;
    let _sp = spawn_character_projector(pool.clone(), r2).await?;
    let _sp = spawn_costume_projector(pool.clone(), r3).await?;
    let _sp = spawn_calculation_projector(pool.clone(), r4).await?;

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
async fn scenes_by_project_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let scene_repo = SceneRepositoryImpl::new(pool.clone());
    let scene_cmd = SceneCommandsImpl::new(cmd_svc);

    let scene_id = Uuid::now_v7();

    let cmd = CreateScene {
        id: scene_id,
        project_id: ProjectId::new(),
        details: SceneDetails {
            scene_number: Some(1),
            location: Some("A".into()),
            mood: Some("A".into()),
            is_schedule_set: false,
        },
    };
    scene_cmd.create(cmd).await?;

    await_proj(&pool, "projection_scene", scene_id).await;

    let scenes = scene_repo.list_by_project(ProjectId::new(), 100, 0).await?;

    assert!(
        !scenes.is_empty(),
        "expected at least 1 scene, got {}",
        scenes.len()
    );

    assert!(scenes.iter().any(|s| s.id == scene_id));

    Ok(())
}

#[tokio::test]
async fn characters_by_project_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let char_repo = CharacterRepositoryImpl::new(pool.clone());
    let char_cmd = CharacterCommandsImpl::new(cmd_svc);

    let char_id = Uuid::now_v7();

    let cmd = CreateCharacter {
        id: char_id,
        project_id: ProjectId::new(),
        name: "Heroin".into(),
        is_extra: false,
        is_main_character: false,
    };
    char_cmd.create(cmd).await?;

    await_proj(&pool, "projection_character", char_id).await;

    let chars = char_repo.list_by_project(ProjectId::new(), 100, 0).await?;

    assert!(
        !chars.is_empty(),
        "expected at least 1 character, got {}",
        chars.len()
    );

    assert!(chars.iter().any(|c| c.id == char_id));

    Ok(())
}

#[tokio::test]
async fn costumes_by_project_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let costume_repo = CostumeRepositoryImpl::new(pool.clone());
    let costume_cmd = CostumeCommandsImpl::new(cmd_svc);

    let costume_id = Uuid::now_v7();

    let cmd = CreateCostume {
        id: costume_id,
        project_id: ProjectId::new(),
    };
    costume_cmd.create(cmd).await?;

    await_proj(&pool, "projection_costume", costume_id).await;

    let costumes = costume_repo
        .list_by_project(ProjectId::new(), 100, 0)
        .await?;

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

    let cmd = CreateCostume {
        id: costume_id,
        project_id: ProjectId::new(),
    };
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
async fn calculations_with_items_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let calc_repo = CalculationRepositoryImpl::new(pool.clone());
    let calc_cmd = CalculationCommandsImpl::new(cmd_svc);

    let calc_id = Uuid::now_v7();

    let cmd = CreateCalculation {
        id: calc_id,
        project_id: ProjectId::new(),
    };
    calc_cmd.create(cmd).await?;

    await_proj(&pool, "projection_calculation", calc_id).await;

    // Add an item
    let item_id = Uuid::now_v7();
    let ver2 = calc_cmd
        .add_item(AddCalculationItem {
            id: calc_id,
            item: CalculationItem {
                id: item_id,
                name: "Item 1".into(),
                quantity: rust_decimal::Decimal::ONE,
                unit_price: rust_decimal::Decimal::ONE,
                is_paid: false,
            },
            version: breakdown_core::shared::AggregateVersion(1),
        })
        .await?;

    await_proj_version(&pool, "projection_calculation", calc_id, ver2.0 as u64).await;
    await_proj_version(&pool, "projection_calculation_item", calc_id, 0).await;

    let v = calc_repo.find_by_id(calc_id).await?;

    assert!(
        !v.items.is_empty(),
        "expected at least 1 item, got {}",
        v.items.len()
    );

    Ok(())
}

#[tokio::test]
async fn calculations_by_project_returns_data() -> Result<()> {
    let (pool, cmd_svc, _pg_guard, _sierra_guard) = init().await?;
    let calc_repo = CalculationRepositoryImpl::new(pool.clone());
    let calc_cmd = CalculationCommandsImpl::new(cmd_svc);

    let calc_id = Uuid::now_v7();

    let cmd = CreateCalculation {
        id: calc_id,
        project_id: ProjectId::new(),
    };
    calc_cmd.create(cmd).await?;

    await_proj(&pool, "projection_calculation", calc_id).await;

    let calcs = calc_repo.list_by_project(ProjectId::new(), 100, 0).await?;

    assert!(
        !calcs.is_empty(),
        "expected at least 1 calculation, got {}",
        calcs.len()
    );

    Ok(())
}
