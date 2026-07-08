// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Category A + B: Command-adapter integration tests.
//!
//! Full path: command → SierraDB → projector → Postgres projection.
//! Mutants killed = assert return value ≠ nil + projection row exists.

mod fixtures;

use std::time::Duration;

use anyhow::Result;
use breakdown_core::calculation::commands::CreateCalculation;
use breakdown_core::calculation::events::{CalculationHeader, CalculationItem};
use breakdown_core::calculation::ports::{CalculationCommands, CalculationRepository};
use breakdown_core::character::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use breakdown_core::character::events::{CharacterMeasurements, ContactInfo};
use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
use breakdown_core::costume::commands::{AssignCostumeToCharacter, CreateCostume};
use breakdown_core::costume::events::CostumeDetail;
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::scene::commands::AssignCharacter;
use breakdown_core::scene::events::SceneDetails;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::shared::ProjectId;
use kameo_es::command_service::CommandService;
use rust_decimal::Decimal;
use std::str::FromStr;
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

/// Wait for a projection row (up to 15 s for eventual consistency).
async fn await_proj(pool: &sqlx::PgPool, table: &str, id: Uuid) {
    let deadline = std::time::Instant::now() + Duration::from_secs(15);
    let col = pk_column_for(table);
    let query = format!(
        r#"SELECT EXISTS(SELECT 1 FROM "{}" WHERE {} = $1)"#,
        table, col
    );
    let mut interval = tokio::time::interval(Duration::from_millis(150));
    loop {
        interval.tick().await;
        if std::time::Instant::now() > deadline {
            panic!("{table}({}) not projected", id);
        }
        let exists: Option<bool> = sqlx::query_scalar::<_, bool>(query.as_str())
            .bind(id)
            .fetch_optional(pool)
            .await
            .unwrap();
        if exists == Some(true) {
            return;
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

    let _sp = infra::projectors::spawn_scene_projector(pool.clone(), r1).await?;
    let _sp = infra::projectors::spawn_character_projector(pool.clone(), r2).await?;
    let _sp = infra::projectors::spawn_costume_projector(pool.clone(), r3).await?;
    let _sp = infra::projectors::spawn_calculation_projector(pool.clone(), r4).await?;

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
    let pid = ProjectId::new();

    let cmd = breakdown_core::scene::commands::CreateScene {
        id: scene_id,
        project_id: pid,
        details: SceneDetails {
            scene_number: Some(42),
            location: Some("Berlin".into()),
            mood: Some("dark".into()),
            is_schedule_set: true,
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
        project_id: ProjectId::new(),
        details: SceneDetails {
            scene_number: Some(1),
            location: Some("A".into()),
            mood: Some("A".into()),
            is_schedule_set: false,
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
            },
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    await_proj(&pool, "projection_scene", scene_id).await;
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
        project_id: ProjectId::new(),
        details: SceneDetails {
            scene_number: Some(1),
            location: None,
            mood: None,
            is_schedule_set: false,
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

    await_proj(&pool, "projection_scene_character", scene_id).await;
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
        project_id: ProjectId::new(),
        name: "Hero".into(),
        is_extra: false,
        is_main_character: true,
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
        project_id: ProjectId::new(),
        name: "Test".into(),
        is_extra: false,
        is_main_character: false,
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

    await_proj(&pool, "projection_character", char_id).await;
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
        project_id: ProjectId::new(),
        name: "Test".into(),
        is_extra: false,
        is_main_character: false,
    };
    let (_id, ver) = char_cmd.create(cmd).await?;
    await_proj(&pool, "projection_character", char_id).await;

    char_cmd
        .update_contact_info(UpdateContactInfo {
            id: char_id,
            contact_info: ContactInfo {
                email: Some("test@example.com".into()),
                phone: Some("+49-123".into()),
            },
            version: ver,
        })
        .await?;

    await_proj(&pool, "projection_character", char_id).await;
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

    let cmd = CreateCostume {
        id: costume_id,
        project_id: ProjectId::new(),
    };

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

    let cmd = CreateCostume {
        id: costume_id,
        project_id: ProjectId::new(),
    };
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

    await_proj(&pool, "projection_costume", costume_id).await;
    assert_eq!(
        costume_repo.find_by_id(costume_id).await?.notes,
        "Blue dress"
    );
    Ok(())
}

#[tokio::test]
async fn costume_assign_unassign() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let costume_cmd = infra::event_store::CostumeCommandsImpl::new(cmd_svc);
    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let char_id = Uuid::now_v7();

    let cmd = CreateCostume {
        id: costume_id,
        project_id: ProjectId::new(),
    };
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

    await_proj(&pool, "projection_costume", costume_id).await;
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

    let cmd = CreateCostume {
        id: costume_id,
        project_id: ProjectId::new(),
    };
    let (_id, ver) = costume_cmd.create(cmd).await?;
    await_proj(&pool, "projection_costume", costume_id).await;

    let ver2 = costume_cmd
        .add_detail(breakdown_core::costume::commands::AddDetail {
            id: costume_id,
            detail: CostumeDetail {
                id: detail_id,
                text: "Red lining".into(),
            },
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    await_proj(&pool, "projection_costume_detail", costume_id).await;
    assert_eq!(costume_repo.find_by_id(costume_id).await?.details.len(), 1);

    let ver3 = costume_cmd
        .remove_detail(breakdown_core::costume::commands::RemoveDetail {
            id: costume_id,
            detail_id,
            version: ver2,
        })
        .await?;
    assert!(ver3.0 > ver2.0);
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

    let cmd = CreateCostume {
        id: costume_id,
        project_id: ProjectId::new(),
    };
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

    await_proj(&pool, "projection_costume_photo", costume_id).await;
    assert_eq!(costume_repo.find_by_id(costume_id).await?.photos.len(), 1);

    let ver3 = costume_cmd
        .unlink_photo(breakdown_core::costume::commands::UnlinkPhoto {
            id: costume_id,
            photo_id,
            version: ver2,
        })
        .await?;
    assert!(ver3.0 > ver2.0);

    assert!(costume_repo.find_by_id(costume_id).await?.photos.is_empty());
    Ok(())
}

// ---------------------------------------------------------------------------
// Calculation
// ---------------------------------------------------------------------------

#[tokio::test]
async fn calculation_create() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let calc_cmd = infra::event_store::CalculationCommandsImpl::new(cmd_svc);
    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();

    let cmd = CreateCalculation {
        id: calc_id,
        project_id: ProjectId::new(),
    };

    let (rid, rv) = calc_cmd.create(cmd).await?;
    assert_ne!(rid, Uuid::nil());
    assert_eq!(rid, calc_id);
    assert!(rv.0 >= 1);

    await_proj(&pool, "projection_calculation", calc_id).await;
    let v = calc_repo.find_by_id(calc_id).await?;
    assert_eq!(v.id, calc_id);
    Ok(())
}

#[tokio::test]
async fn calculation_add_item() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let calc_cmd = infra::event_store::CalculationCommandsImpl::new(cmd_svc);
    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let item_id = Uuid::now_v7();

    let cmd = CreateCalculation {
        id: calc_id,
        project_id: ProjectId::new(),
    };
    let (_id, ver) = calc_cmd.create(cmd).await?;
    await_proj(&pool, "projection_calculation", calc_id).await;

    let ver2 = calc_cmd
        .add_item(breakdown_core::calculation::commands::AddCalculationItem {
            id: calc_id,
            item: CalculationItem {
                id: item_id,
                name: "Makeup".into(),
                quantity: Decimal::from_str("50").unwrap(),
                unit_price: Decimal::from_str("10").unwrap(),
                is_paid: false,
            },
            version: ver,
        })
        .await?;
    assert!(ver2.0 > ver.0);

    await_proj(&pool, "projection_calculation_item", calc_id).await;
    let v = calc_repo.find_by_id(calc_id).await?;
    assert_eq!(v.items.len(), 1);
    assert_eq!(v.items[0].name, "Makeup");
    Ok(())
}

#[tokio::test]
async fn calculation_remove_item() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let calc_cmd = infra::event_store::CalculationCommandsImpl::new(cmd_svc);
    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let item_id = Uuid::now_v7();

    let cmd = CreateCalculation {
        id: calc_id,
        project_id: ProjectId::new(),
    };
    let (_id, ver) = calc_cmd.create(cmd).await?;

    let ver2 = calc_cmd
        .add_item(breakdown_core::calculation::commands::AddCalculationItem {
            id: calc_id,
            item: CalculationItem {
                id: item_id,
                name: "Props".into(),
                quantity: Decimal::ONE,
                unit_price: Decimal::ONE,
                is_paid: false,
            },
            version: ver,
        })
        .await?;

    let ver3 = calc_cmd
        .remove_item(
            breakdown_core::calculation::commands::RemoveCalculationItem {
                id: calc_id,
                item_id,
                version: ver2,
            },
        )
        .await?;
    assert!(ver3.0 > ver2.0);

    assert!(calc_repo.find_by_id(calc_id).await?.items.is_empty());
    Ok(())
}

#[tokio::test]
async fn calculation_update_item() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let calc_cmd = infra::event_store::CalculationCommandsImpl::new(cmd_svc);
    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let item_id = Uuid::now_v7();

    let cmd = CreateCalculation {
        id: calc_id,
        project_id: ProjectId::new(),
    };
    let (_id, ver) = calc_cmd.create(cmd).await?;

    let ver2 = calc_cmd
        .add_item(breakdown_core::calculation::commands::AddCalculationItem {
            id: calc_id,
            item: CalculationItem {
                id: item_id,
                name: "Props".into(),
                quantity: Decimal::ONE,
                unit_price: Decimal::ONE,
                is_paid: false,
            },
            version: ver,
        })
        .await?;

    let ver3 = calc_cmd
        .update_item(
            breakdown_core::calculation::commands::UpdateCalculationItem {
                id: calc_id,
                item: CalculationItem {
                    id: item_id,
                    name: "Updated Props".into(),
                    quantity: Decimal::from(2),
                    unit_price: Decimal::from(10),
                    is_paid: false,
                },
                version: ver2,
            },
        )
        .await?;
    assert!(ver3.0 > ver2.0);

    let v = calc_repo.find_by_id(calc_id).await?;
    assert_eq!(v.items[0].name, "Updated Props");
    Ok(())
}

#[tokio::test]
async fn calculation_mark_paid_unpaid() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let calc_cmd = infra::event_store::CalculationCommandsImpl::new(cmd_svc);
    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let item_id = Uuid::now_v7();

    let cmd = CreateCalculation {
        id: calc_id,
        project_id: ProjectId::new(),
    };
    let (_id, ver) = calc_cmd.create(cmd).await?;

    let ver2 = calc_cmd
        .add_item(breakdown_core::calculation::commands::AddCalculationItem {
            id: calc_id,
            item: CalculationItem {
                id: item_id,
                name: "Props".into(),
                quantity: Decimal::ONE,
                unit_price: Decimal::ONE,
                is_paid: false,
            },
            version: ver,
        })
        .await?;

    let ver3 = calc_cmd
        .mark_item_paid(breakdown_core::calculation::commands::MarkItemAsPaid {
            id: calc_id,
            item_id,
            version: ver2,
        })
        .await?;
    assert!(ver3.0 > ver2.0);

    assert!(calc_repo.find_by_id(calc_id).await?.items[0].is_paid);

    let ver4 = calc_cmd
        .mark_item_unpaid(breakdown_core::calculation::commands::MarkItemAsUnpaid {
            id: calc_id,
            item_id,
            version: ver3,
        })
        .await?;
    assert!(ver4.0 > ver3.0);

    assert!(!calc_repo.find_by_id(calc_id).await?.items[0].is_paid);
    Ok(())
}

#[tokio::test]
async fn calculation_update_header() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init().await?;
    let calc_cmd = infra::event_store::CalculationCommandsImpl::new(cmd_svc);
    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();

    let cmd = CreateCalculation {
        id: calc_id,
        project_id: ProjectId::new(),
    };
    let (_id, ver) = calc_cmd.create(cmd).await?;
    await_proj(&pool, "projection_calculation", calc_id).await;

    calc_cmd
        .update_header(breakdown_core::calculation::commands::UpdateHeaderInfo {
            id: calc_id,
            header: CalculationHeader {
                subjects: Some("Math".into()),
                sender_name: Some("Alice".into()),
                date: Some("2025-01-01".into()),
            },
            version: ver,
        })
        .await?;

    let v = calc_repo.find_by_id(calc_id).await?;
    assert_eq!(v.header.subjects, Some("Math".into()));
    Ok(())
}
