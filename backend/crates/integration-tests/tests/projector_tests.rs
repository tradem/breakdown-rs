// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Category C: Projector-handler integration tests.
//!
//! Directly exercise each projector's `EntityEventHandler::handle` method:
//! write an event via CBOR → EAPPEND into SierraDB → wait for projector to
//! catch up → assert the resulting projection row.
//!
//! This bypasses aggregate logic (kameo_es actors) to target the mutation
//! points in the projector SQL statements (e.g. `sqlx::query().execute()`
//! returning `Ok(())` vs `Err`).

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow};
use breakdown_core::calculation::ports::CalculationRepository;
use breakdown_core::character::ports::CharacterRepository;
use breakdown_core::costume::ports::CostumeRepository;
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use chrono::Utc;
use redis::Client as RedisClient;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// Wait until the projector has caught up by checking a predicate.
/// Retries for PROJECTION_DEADLINE.
async fn await_proj_row<
    F: Fn() -> std::pin::Pin<Box<dyn std::future::Future<Output = bool> + Send>>,
>(
    predicate: F,
    table: &str,
) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        tokio::time::sleep(POLL_INTERVAL).await;
        if std::time::Instant::now() > deadline {
            anyhow::bail!("{table} not projected within {:?}", PROJECTION_DEADLINE);
        }
        if predicate().await {
            return Ok(());
        }
    }
}

/// Wait until the projection row for `id` exists and its `version` column is
/// at least `min_version`.
///
/// Every projector handler bumps the parent's `version` (directly or via
/// `touch_parent`) **in the same transaction** as its mutation. Awaiting the
/// parent version is therefore a reliable eventual-consistency sync point —
/// unlike an existence check (e.g. `find_by_id().is_ok()`), which returns as
/// soon as the CREATE event is projected and can read stale state for any
/// subsequent UPDATE/DELETE event on the same stream.
async fn await_proj_version(
    pool: &sqlx::PgPool,
    table: &str,
    id: Uuid,
    min_version: i64,
) -> Result<()> {
    let query = format!(r#"SELECT version FROM "{table}" WHERE id = $1"#);
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        tokio::time::sleep(POLL_INTERVAL).await;
        if std::time::Instant::now() > deadline {
            anyhow::bail!(
                "{table}({id}) not projected to version >= {min_version} within {PROJECTION_DEADLINE:?}"
            );
        }
        let version: Option<i64> = sqlx::query_scalar(sqlx::AssertSqlSafe(query.as_str()))
            .bind(id)
            .fetch_optional(pool)
            .await
            .ok()
            .flatten();
        if version.is_some_and(|v| v >= min_version) {
            return Ok(());
        }
    }
}

/// EAPPEND an event stream in SierraDB and return the Redis client for
/// subsequent events. Uses ciborium to CBOR-encode the event as kameo_es expects.
async fn eappend_event<T: serde::Serialize>(
    client: Arc<RedisClient>,
    stream_id: &str,
    event_name: &str,
    expected_version: &str,
    payload: &T,
) -> Result<(redis::aio::MultiplexedConnection, u64)> {
    let mut conn = client.get_multiplexed_tokio_connection().await?;

    let mut encoded = Vec::new();
    ciborium::into_writer(payload, &mut encoded).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;

    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);

    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_name)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(&encoded)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {event_name} failed: {e}"))?;

    Ok((conn, now_ms))
}

// ---------------------------------------------------------------------------
// Scene projector tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn scene_created_projects_scene_details() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("scene-{}", scene_id);

    let event = breakdown_core::scene::events::SceneEvent::SceneCreated {
        id: scene_id,
        project_id,
        details: breakdown_core::scene::events::SceneDetails {
            scene_number: Some(42),
            location: Some("Berlin".into()),
            mood: Some("dark".into()),
            is_schedule_set: true,
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
    };

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "SceneCreated",
        "EMPTY",
        &event,
    )
    .await?;

    await_proj_row(
        || {
            let s_repo = scene_repo.clone();
            Box::pin(async move { s_repo.find_by_id(scene_id).await.is_ok() })
        },
        "scene",
    )
    .await?;

    let v = scene_repo.find_by_id(scene_id).await?;
    assert_eq!(v.scene_number, Some(42));
    assert_eq!(v.location, Some("Berlin".into()));
    assert_eq!(v.mood, Some("dark".into()));
    assert!(v.is_schedule_set);

    Ok(())
}

#[tokio::test]
async fn scene_details_updated_projects_changes() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("scene-{}", scene_id);

    // 1. SceneCreated
    let created = breakdown_core::scene::events::SceneEvent::SceneCreated {
        id: scene_id,
        project_id,
        details: breakdown_core::scene::events::SceneDetails {
            scene_number: Some(1),
            location: Some("A".into()),
            mood: Some("A".into()),
            is_schedule_set: false,
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
    };
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "SceneCreated",
        "EMPTY",
        &created,
    )
    .await?;

    // 2. SceneDetailsUpdated
    let updated = breakdown_core::scene::events::SceneEvent::SceneDetailsUpdated {
        id: scene_id,
        details: breakdown_core::scene::events::SceneDetails {
            scene_number: Some(99),
            location: Some("Updated".into()),
            mood: Some("bright".into()),
            is_schedule_set: true,
        },
        version: AggregateVersion(2),
    };
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "SceneDetailsUpdated",
        "0",
        &updated,
    )
    .await?;

    await_proj_version(&pool, "projection_scene", scene_id, 2).await?;

    let v = scene_repo.find_by_id(scene_id).await?;
    assert_eq!(v.scene_number, Some(99));
    assert_eq!(v.location, Some("Updated".into()));
    assert_eq!(v.mood, Some("bright".into()));
    assert!(v.is_schedule_set);
    assert_eq!(v.version, AggregateVersion(2));

    Ok(())
}

#[tokio::test]
async fn scene_assign_character_creates_sub_row() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("scene-{}", scene_id);

    // SceneCreated
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "SceneCreated",
        "EMPTY",
        &breakdown_core::scene::events::SceneEvent::SceneCreated {
            id: scene_id,
            project_id,
            details: breakdown_core::scene::events::SceneDetails {
                scene_number: Some(1),
                location: None,
                mood: None,
                is_schedule_set: false,
            },
            assigned_characters: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    // CharacterAssigned
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CharacterAssigned",
        "0",
        &breakdown_core::scene::events::SceneEvent::CharacterAssigned {
            id: scene_id,
            character_id,
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_scene", scene_id, 2).await?;

    let v = scene_repo.find_by_id(scene_id).await?;
    assert_eq!(v.assigned_characters.len(), 1);
    assert_eq!(v.assigned_characters[0], character_id);

    Ok(())
}

#[tokio::test]
async fn scene_remove_character_clears_sub_row() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("scene-{}", scene_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "SceneCreated",
        "EMPTY",
        &breakdown_core::scene::events::SceneEvent::SceneCreated {
            id: scene_id,
            project_id,
            details: breakdown_core::scene::events::SceneDetails {
                scene_number: Some(1),
                location: None,
                mood: None,
                is_schedule_set: false,
            },
            assigned_characters: vec![character_id],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    // CharacterRemoved
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CharacterRemoved",
        "0",
        &breakdown_core::scene::events::SceneEvent::CharacterRemoved {
            id: scene_id,
            character_id,
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_scene", scene_id, 2).await?;

    let v = scene_repo.find_by_id(scene_id).await?;
    assert!(v.assigned_characters.is_empty());

    Ok(())
}

// ---------------------------------------------------------------------------
// Character projector tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn character_created_projects_basic_fields() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _char_ref =
        infra::projectors::spawn_character_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let char_repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("character-{}", char_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CharacterCreated",
        "EMPTY",
        &breakdown_core::character::events::CharacterEvent::CharacterCreated {
            id: char_id,
            project_id,
            name: "Hero".into(),
            is_extra: false,
            is_main_character: true,
            measurements: Default::default(),
            contact_info: Default::default(),
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    await_proj_version(&pool, "projection_character", char_id, 1).await?;

    let v = char_repo.find_by_id(char_id).await?;
    assert_eq!(v.name, "Hero");
    assert!(!v.is_extra);
    assert!(v.is_main_character);

    Ok(())
}

#[tokio::test]
async fn character_measurements_updated_projects_values() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _char_ref =
        infra::projectors::spawn_character_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let char_repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("character-{}", char_id);

    // Create
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CharacterCreated",
        "EMPTY",
        &breakdown_core::character::events::CharacterEvent::CharacterCreated {
            id: char_id,
            project_id,
            name: "Test".into(),
            is_extra: false,
            is_main_character: false,
            measurements: Default::default(),
            contact_info: Default::default(),
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    // Update measurements
    let meas = breakdown_core::character::events::CharacterMeasurements {
        height: Some(rust_decimal::Decimal::from(180)),
        weight: Some(rust_decimal::Decimal::from(75)),
        ..Default::default()
    };
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "MeasurementsUpdated",
        "0",
        &breakdown_core::character::events::CharacterEvent::MeasurementsUpdated {
            id: char_id,
            measurements: meas.clone(),
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_character", char_id, 2).await?;

    let v = char_repo.find_by_id(char_id).await?;
    assert_eq!(
        v.measurements.height,
        Some(rust_decimal::Decimal::from(180))
    );
    assert_eq!(v.measurements.weight, Some(rust_decimal::Decimal::from(75)));

    Ok(())
}

#[tokio::test]
async fn character_contact_info_updated_projects_values() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _char_ref =
        infra::projectors::spawn_character_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let char_repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("character-{}", char_id);

    // Create
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CharacterCreated",
        "EMPTY",
        &breakdown_core::character::events::CharacterEvent::CharacterCreated {
            id: char_id,
            project_id,
            name: "Test".into(),
            is_extra: false,
            is_main_character: false,
            measurements: Default::default(),
            contact_info: Default::default(),
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    // Update contact info
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "ContactInfoUpdated",
        "0",
        &breakdown_core::character::events::CharacterEvent::ContactInfoUpdated {
            id: char_id,
            contact_info: breakdown_core::character::events::ContactInfo {
                email: Some("test@example.com".into()),
                phone: Some("+49-123".into()),
            },
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_character", char_id, 2).await?;

    let v = char_repo.find_by_id(char_id).await?;
    assert_eq!(v.contact.email, Some("test@example.com".into()));
    assert_eq!(v.contact.phone, Some("+49-123".into()));

    Ok(())
}

// ---------------------------------------------------------------------------
// Costume projector tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn costume_created_projects_basic_fields() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            project_id,
            character_id: None,
            notes: "Blue dress".into(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    await_proj_row(
        || {
            let c_repo = costume_repo.clone();
            Box::pin(async move { c_repo.find_by_id(costume_id).await.is_ok() })
        },
        "costume",
    )
    .await?;

    let v = costume_repo.find_by_id(costume_id).await?;
    assert_eq!(v.notes, "Blue dress");
    assert!(v.character_id.is_none());
    Ok(())
}

#[tokio::test]
async fn costume_notes_updated_projects_changes() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            project_id,
            character_id: None,
            notes: "Initial".into(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeNotesUpdated",
        "0",
        &breakdown_core::costume::events::CostumeEvent::CostumeNotesUpdated {
            id: costume_id,
            notes: "Updated notes".into(),
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_costume", costume_id, 2).await?;

    let v = costume_repo.find_by_id(costume_id).await?;
    assert_eq!(v.notes, "Updated notes");

    Ok(())
}

#[tokio::test]
async fn costume_assign_unassign_characters() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    // The costume projector's `CostumeAssignedToCharacter` handler writes
    // `character_id` into `projection_costume`, whose FK references
    // `projection_character(id)`. We therefore also run the character
    // projector and project the referenced character *before* appending the
    // assign event, so the projector does not hit a foreign-key violation
    // and stall the checkpoint.
    let _char_ref =
        infra::projectors::spawn_character_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            project_id,
            character_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    // Create the referenced character so the `projection_costume.character_id`
    // foreign key (-> projection_character.id) is satisfied when the assign
    // event is projected.
    let char_stream_id = format!("character-{}", character_id);
    eappend_event(
        Arc::clone(&redis_client),
        &char_stream_id,
        "CharacterCreated",
        "EMPTY",
        &breakdown_core::character::events::CharacterEvent::CharacterCreated {
            id: character_id,
            project_id,
            name: "Wearer".into(),
            is_extra: false,
            is_main_character: false,
            measurements: Default::default(),
            contact_info: Default::default(),
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;
    await_proj_version(&pool, "projection_character", character_id, 1).await?;

    // Assign
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeAssignedToCharacter",
        "0",
        &breakdown_core::costume::events::CostumeEvent::CostumeAssignedToCharacter {
            id: costume_id,
            character_id,
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_costume", costume_id, 2).await?;

    let v = costume_repo.find_by_id(costume_id).await?;
    assert_eq!(v.character_id, Some(character_id));

    // Unassign
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeUnassigned",
        "1",
        &breakdown_core::costume::events::CostumeEvent::CostumeUnassigned {
            id: costume_id,
            version: AggregateVersion(3),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_costume", costume_id, 3).await?;

    let v = costume_repo.find_by_id(costume_id).await?;
    assert!(v.character_id.is_none());

    Ok(())
}

#[tokio::test]
async fn costume_detail_add_remove() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let detail_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            project_id,
            character_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    // DetailAdded
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "DetailAdded",
        "0",
        &breakdown_core::costume::events::CostumeEvent::DetailAdded {
            id: costume_id,
            detail: breakdown_core::costume::events::CostumeDetail {
                id: detail_id,
                text: "Red lining".into(),
            },
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_costume", costume_id, 2).await?;

    let v = costume_repo.costume_with_details_photos(costume_id).await?;
    assert_eq!(v.details.len(), 1);
    assert_eq!(v.details[0].text, "Red lining");

    // DetailRemoved
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "DetailRemoved",
        "1",
        &breakdown_core::costume::events::CostumeEvent::DetailRemoved {
            id: costume_id,
            detail_id,
            version: AggregateVersion(3),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_costume", costume_id, 3).await?;

    let v = costume_repo.costume_with_details_photos(costume_id).await?;
    assert!(v.details.is_empty());

    Ok(())
}

#[tokio::test]
async fn costume_photo_link_unlink() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let photo_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            project_id,
            character_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    // PhotoLinked
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "PhotoLinked",
        "0",
        &breakdown_core::costume::events::CostumeEvent::PhotoLinked {
            id: costume_id,
            photo_id,
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_costume", costume_id, 2).await?;

    let v = costume_repo.costume_with_details_photos(costume_id).await?;
    assert_eq!(v.photos.len(), 1);
    assert_eq!(v.photos[0].id, photo_id);

    // PhotoUnlinked
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "PhotoUnlinked",
        "1",
        &breakdown_core::costume::events::CostumeEvent::PhotoUnlinked {
            id: costume_id,
            photo_id,
            version: AggregateVersion(3),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_costume", costume_id, 3).await?;

    let v = costume_repo.costume_with_details_photos(costume_id).await?;
    assert!(v.photos.is_empty());

    Ok(())
}

// ---------------------------------------------------------------------------
// Calculation projector tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn calculation_created_projects_header_and_items() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _calc_ref =
        infra::projectors::spawn_calculation_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let item_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("calculation-{}", calc_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CalculationCreated",
        "EMPTY",
        &breakdown_core::calculation::events::CalculationEvent::CalculationCreated {
            id: calc_id,
            project_id,
            header: breakdown_core::calculation::events::CalculationHeader {
                subjects: Some("Math".into()),
                sender_name: Some("Alice".into()),
                date: Some("2025-01-01".into()),
            },
            items: vec![breakdown_core::calculation::events::CalculationItem {
                id: item_id,
                name: "Makeup".into(),
                quantity: rust_decimal::Decimal::from(50),
                unit_price: rust_decimal::Decimal::from(10),
                is_paid: false,
            }],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    await_proj_row(
        || {
            let c_repo = calc_repo.clone();
            Box::pin(async move { c_repo.find_by_id(calc_id).await.is_ok() })
        },
        "calculation",
    )
    .await?;

    let v = calc_repo.find_by_id(calc_id).await?;
    assert_eq!(v.header.subjects, Some("Math".into()));
    assert_eq!(v.header.sender_name, Some("Alice".into()));
    assert_eq!(v.items.len(), 1);
    assert_eq!(v.items[0].name, "Makeup");

    Ok(())
}

#[tokio::test]
async fn calculation_calculation_item_added_projects_item() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _calc_ref =
        infra::projectors::spawn_calculation_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let item_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("calculation-{}", calc_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CalculationCreated",
        "EMPTY",
        &breakdown_core::calculation::events::CalculationEvent::CalculationCreated {
            id: calc_id,
            project_id,
            header: Default::default(),
            items: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CalculationItemAdded",
        "0",
        &breakdown_core::calculation::events::CalculationEvent::CalculationItemAdded {
            id: calc_id,
            item: breakdown_core::calculation::events::CalculationItem {
                id: item_id,
                name: "Props".into(),
                quantity: rust_decimal::Decimal::from(2),
                unit_price: rust_decimal::Decimal::from(10),
                is_paid: false,
            },
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_calculation", calc_id, 2).await?;

    let v = calc_repo.find_by_id(calc_id).await?;
    assert_eq!(v.items.len(), 1);
    assert_eq!(v.items[0].name, "Props");

    Ok(())
}

#[tokio::test]
async fn calculation_item_updated_projects_new_values() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _calc_ref =
        infra::projectors::spawn_calculation_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let item_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("calculation-{}", calc_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CalculationCreated",
        "EMPTY",
        &breakdown_core::calculation::events::CalculationEvent::CalculationCreated {
            id: calc_id,
            project_id,
            header: Default::default(),
            items: vec![breakdown_core::calculation::events::CalculationItem {
                id: item_id,
                name: "Original".into(),
                quantity: rust_decimal::Decimal::ONE,
                unit_price: rust_decimal::Decimal::ONE,
                is_paid: false,
            }],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CalculationItemUpdated",
        "0",
        &breakdown_core::calculation::events::CalculationEvent::CalculationItemUpdated {
            id: calc_id,
            item: breakdown_core::calculation::events::CalculationItem {
                id: item_id,
                name: "Updated".into(),
                quantity: rust_decimal::Decimal::from(3),
                unit_price: rust_decimal::Decimal::from(20),
                is_paid: true,
            },
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_calculation", calc_id, 2).await?;

    let v = calc_repo.find_by_id(calc_id).await?;
    assert_eq!(v.items[0].name, "Updated");
    assert_eq!(v.items[0].quantity, rust_decimal::Decimal::from(3));
    assert!(v.items[0].is_paid);

    Ok(())
}

#[tokio::test]
async fn calculation_item_removed_cleared_from_projection() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _calc_ref =
        infra::projectors::spawn_calculation_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let item_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("calculation-{}", calc_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CalculationCreated",
        "EMPTY",
        &breakdown_core::calculation::events::CalculationEvent::CalculationCreated {
            id: calc_id,
            project_id,
            header: Default::default(),
            items: vec![breakdown_core::calculation::events::CalculationItem {
                id: item_id,
                name: "ToBeRemoved".into(),
                quantity: rust_decimal::Decimal::ONE,
                unit_price: rust_decimal::Decimal::ONE,
                is_paid: false,
            }],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CalculationItemRemoved",
        "0",
        &breakdown_core::calculation::events::CalculationEvent::CalculationItemRemoved {
            id: calc_id,
            item_id,
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_calculation", calc_id, 2).await?;

    let v = calc_repo.find_by_id(calc_id).await?;
    assert!(v.items.is_empty());

    Ok(())
}

#[tokio::test]
async fn calculation_item_marked_paid_unpaid() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _calc_ref =
        infra::projectors::spawn_calculation_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let item_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("calculation-{}", calc_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CalculationCreated",
        "EMPTY",
        &breakdown_core::calculation::events::CalculationEvent::CalculationCreated {
            id: calc_id,
            project_id,
            header: Default::default(),
            items: vec![breakdown_core::calculation::events::CalculationItem {
                id: item_id,
                name: "Item".into(),
                quantity: rust_decimal::Decimal::ONE,
                unit_price: rust_decimal::Decimal::ONE,
                is_paid: false,
            }],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    // Mark paid
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "ItemMarkedAsPaid",
        "0",
        &breakdown_core::calculation::events::CalculationEvent::ItemMarkedAsPaid {
            id: calc_id,
            item_id,
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_calculation", calc_id, 2).await?;

    let v = calc_repo.find_by_id(calc_id).await?;
    assert!(v.items[0].is_paid);

    // Mark unpaid
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "ItemMarkedAsUnpaid",
        "1",
        &breakdown_core::calculation::events::CalculationEvent::ItemMarkedAsUnpaid {
            id: calc_id,
            item_id,
            version: AggregateVersion(3),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_calculation", calc_id, 3).await?;

    let v = calc_repo.find_by_id(calc_id).await?;
    assert!(!v.items[0].is_paid);

    Ok(())
}

#[tokio::test]
async fn calculation_header_info_updated_projects_values() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _calc_ref =
        infra::projectors::spawn_calculation_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let calc_repo = infra::queries::CalculationRepositoryImpl::new(pool.clone());

    let calc_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let stream_id = format!("calculation-{}", calc_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CalculationCreated",
        "EMPTY",
        &breakdown_core::calculation::events::CalculationEvent::CalculationCreated {
            id: calc_id,
            project_id,
            header: Default::default(),
            items: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "HeaderInfoUpdated",
        "0",
        &breakdown_core::calculation::events::CalculationEvent::HeaderInfoUpdated {
            id: calc_id,
            header: breakdown_core::calculation::events::CalculationHeader {
                subjects: Some("Updated Subject".into()),
                sender_name: Some("Bob".into()),
                date: Some("2025-06-15".into()),
            },
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_calculation", calc_id, 2).await?;

    let v = calc_repo.find_by_id(calc_id).await?;
    assert_eq!(v.header.subjects, Some("Updated Subject".into()));
    assert_eq!(v.header.sender_name, Some("Bob".into()));
    assert_eq!(v.header.date, Some("2025-06-15".into()));

    Ok(())
}
