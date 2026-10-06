// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: glm-5.2 (neuralwatt)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
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

use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::ports::CharacterRepository;
use breakdown_core::costume::ports::CostumeRepository;
use breakdown_core::scene::events::SceneSource;
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::shared::{AggregateVersion, EpisodeId, SeasonId};
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
    let mut conn = client.get_multiplexed_async_connection().await?;

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

// ---------------------------------------------------------------------------

#[tokio::test]
async fn scene_created_projects_scene_details() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _scene_ref = infra::projectors::spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    let stream_id = format!("scene-{}", scene_id);

    let event = breakdown_core::scene::events::SceneEvent::SceneCreated {
        id: scene_id,
        episode_id,
        details: breakdown_core::scene::events::SceneDetails {
            scene_number: Some(42),
            location: Some("Berlin".into()),
            mood: Some("dark".into()),
            is_schedule_set: true,
            summary: None,
            script_day: None,
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
        source: SceneSource::Manual,
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

    let _scene_ref = infra::projectors::spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    let stream_id = format!("scene-{}", scene_id);

    // 1. SceneCreated
    let created = breakdown_core::scene::events::SceneEvent::SceneCreated {
        id: scene_id,
        episode_id,
        details: breakdown_core::scene::events::SceneDetails {
            scene_number: Some(1),
            location: Some("A".into()),
            mood: Some("A".into()),
            is_schedule_set: false,
            summary: None,
            script_day: None,
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
        source: SceneSource::Manual,
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
            summary: None,
            script_day: None,
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

    let _scene_ref = infra::projectors::spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    let stream_id = format!("scene-{}", scene_id);

    // SceneCreated
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "SceneCreated",
        "EMPTY",
        &breakdown_core::scene::events::SceneEvent::SceneCreated {
            id: scene_id,
            episode_id,
            details: breakdown_core::scene::events::SceneDetails {
                scene_number: Some(1),
                location: None,
                mood: None,
                is_schedule_set: false,
                summary: None,
                script_day: None,
            },
            assigned_characters: vec![],
            version: AggregateVersion::INITIAL,
            source: SceneSource::Manual,
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

    let _scene_ref = infra::projectors::spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let scene_repo = infra::queries::SceneRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    let stream_id = format!("scene-{}", scene_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "SceneCreated",
        "EMPTY",
        &breakdown_core::scene::events::SceneEvent::SceneCreated {
            id: scene_id,
            episode_id,
            details: breakdown_core::scene::events::SceneDetails {
                scene_number: Some(1),
                location: None,
                mood: None,
                is_schedule_set: false,
                summary: None,
                script_day: None,
            },
            assigned_characters: vec![character_id],
            version: AggregateVersion::INITIAL,
            source: SceneSource::Manual,
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

// ---------------------------------------------------------------------------

#[tokio::test]
async fn character_created_projects_basic_fields() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _char_ref = infra::projectors::spawn_character_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let char_repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();
    let season_id = SeasonId::new();
    let stream_id = format!("character-{}", char_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CharacterCreated",
        "EMPTY",
        &breakdown_core::character::events::CharacterEvent::CharacterCreated {
            id: char_id,
            season_id,
            name: "Hero".into(),
            category: CharacterCategory::MainCast,
            measurements: Default::default(),
            contact_info: Default::default(),
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    await_proj_version(&pool, "projection_character", char_id, 1).await?;

    let v = char_repo.find_by_id(char_id).await?;
    assert_eq!(v.name, "Hero");
    assert_eq!(v.category, CharacterCategory::MainCast);

    Ok(())
}

#[tokio::test]
async fn character_measurements_updated_projects_values() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _char_ref = infra::projectors::spawn_character_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let char_repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();
    let season_id = SeasonId::new();
    let stream_id = format!("character-{}", char_id);

    // Create
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CharacterCreated",
        "EMPTY",
        &breakdown_core::character::events::CharacterEvent::CharacterCreated {
            id: char_id,
            season_id,
            name: "Test".into(),
            category: CharacterCategory::Guest,
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

    let _char_ref = infra::projectors::spawn_character_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let char_repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();
    let season_id = SeasonId::new();
    let stream_id = format!("character-{}", char_id);

    // Create
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CharacterCreated",
        "EMPTY",
        &breakdown_core::character::events::CharacterEvent::CharacterCreated {
            id: char_id,
            season_id,
            name: "Test".into(),
            category: CharacterCategory::Guest,
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

// ---------------------------------------------------------------------------

#[tokio::test]
async fn costume_created_projects_basic_fields() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: None,
            season_id: None,
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

    let _costume_ref = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: None,
            season_id: None,
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

    let _costume_ref = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    // The costume projector's `CostumeAssignedToCharacter` handler writes
    // `character_id` into `projection_costume`, whose FK references
    // `projection_character(id)`. We therefore also run the character
    // projector and project the referenced character *before* appending the
    // assign event, so the projector does not hit a foreign-key violation
    // and stall the checkpoint.
    let _char_ref = infra::projectors::spawn_character_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let season_id = SeasonId::new();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: None,
            season_id: None,
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
            season_id,
            name: "Wearer".into(),
            category: CharacterCategory::Guest,
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

    let _costume_ref = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let detail_id = Uuid::now_v7();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: None,
            season_id: None,
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
                subject: None,
                category_id: None,
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

    // DetailUpdated (issue #544): the projector reuses the `DetailAdded`
    // upsert on `(costume_id, detail_id)`, so the row is overwritten IN PLACE
    // — no migration, and no second row. A cleared `subject` must land as
    // NULL, not survive from the previous value.
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "DetailUpdated",
        "1",
        &breakdown_core::costume::events::CostumeEvent::DetailUpdated {
            id: costume_id,
            detail: breakdown_core::costume::events::CostumeDetail {
                id: detail_id,
                subject: Some("Rote Lederjacke".into()),
                category_id: None,
                text: "Leder, rot gefüttert".into(),
            },
            version: AggregateVersion(3),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_costume", costume_id, 3).await?;

    let v = costume_repo.costume_with_details_photos(costume_id).await?;
    assert_eq!(v.details.len(), 1, "an edit must not insert a second row");
    assert_eq!(v.details[0].id, detail_id, "the row must be the same one");
    assert_eq!(v.details[0].text, "Leder, rot gefüttert");
    assert_eq!(v.details[0].subject.as_deref(), Some("Rote Lederjacke"));

    // DetailRemoved
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "DetailRemoved",
        "2",
        &breakdown_core::costume::events::CostumeEvent::DetailRemoved {
            id: costume_id,
            detail_id,
            version: AggregateVersion(4),
        },
    )
    .await?;

    await_proj_version(&pool, "projection_costume", costume_id, 4).await?;

    let v = costume_repo.costume_with_details_photos(costume_id).await?;
    assert!(v.details.is_empty());

    Ok(())
}

#[tokio::test]
async fn costume_photo_link_unlink() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let photo_id = Uuid::now_v7();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: None,
            season_id: None,
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

/// Issue #453: a costume created with a repertoire `season_id` appears in the
/// season's costume stream (`list_by_season`) even while unassigned
/// (`character_id IS NULL`). The pre-#453 INNER-JOIN-through-character query
/// returned 0 rows for this case — leaving no UI path to a first assignment.
#[tokio::test]
async fn costume_created_with_repertoire_season_is_visible_in_season_stream() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());
    let season_id = Uuid::now_v7();
    let costume_id = Uuid::now_v7();
    let stream_id = format!("costume-{}", costume_id);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: None,
            season_id: Some(season_id),
            notes: "Unassigned Repertoire Costume".into(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    await_proj_row(
        || {
            let c_repo = costume_repo.clone();
            let expected_season = season_id;
            Box::pin(async move {
                c_repo
                    .list_by_season(SeasonId(expected_season), 50, 0)
                    .await
                    .map(|rows| rows.iter().any(|v| v.id == costume_id))
                    .unwrap_or(false)
            })
        },
        "costume in season stream",
    )
    .await?;

    let listed = costume_repo
        .list_by_season(SeasonId(season_id), 50, 0)
        .await?;
    assert_eq!(listed.len(), 1, "unassigned repertoire costume is visible");
    assert_eq!(listed[0].id, costume_id);
    assert!(listed[0].character_id.is_none());

    // A different season must NOT list the costume (no cross-stream bleed).
    let other = costume_repo
        .list_by_season(SeasonId(Uuid::now_v7()), 50, 0)
        .await?;
    assert!(other.is_empty(), "costume must not leak into other seasons");

    Ok(())
}

/// Issue #453 backwards compatibility: a pre-#453 `CostumeCreated` event
/// (no `season_id` field — old CBOR payload) must still project; the
/// `#[serde(default)]` on the event field deserializes it as `None` and the
/// costume simply has no repertoire binding.
#[tokio::test]
async fn costume_created_without_season_still_projects() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());

    let costume_id = Uuid::now_v7();
    let stream_id = format!("costume-{}", costume_id);

    // Pre-#453 payload shape: externally tagged enum WITHOUT `season_id`,
    // UUID encoded as CBOR bytes (matching the real old events' encoder).
    let legacy_cbor = ciborium::value::Value::Map(vec![(
        ciborium::value::Value::Text("CostumeCreated".into()),
        ciborium::value::Value::Map(vec![
            (
                ciborium::value::Value::Text("id".into()),
                ciborium::value::Value::Bytes(costume_id.as_bytes().to_vec()),
            ),
            (
                ciborium::value::Value::Text("character_id".into()),
                ciborium::value::Value::Null,
            ),
            (
                ciborium::value::Value::Text("notes".into()),
                ciborium::value::Value::Text("Legacy costume".into()),
            ),
            (
                ciborium::value::Value::Text("details".into()),
                ciborium::value::Value::Array(vec![]),
            ),
            (
                ciborium::value::Value::Text("photos".into()),
                ciborium::value::Value::Array(vec![]),
            ),
            (
                ciborium::value::Value::Text("version".into()),
                ciborium::value::Value::Integer(1.into()),
            ),
        ]),
    )]);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &legacy_cbor,
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
    assert_eq!(v.notes, "Legacy costume");

    // No repertoire binding → not visible in any season stream.
    let listed = costume_repo
        .list_by_season(SeasonId(Uuid::now_v7()), 50, 0)
        .await?;
    assert!(listed.is_empty());

    Ok(())
}

// ---------------------------------------------------------------------------

/// Issue #534: the repertoire becomes real aggregate state and
/// `projection_costume_season` becomes truly m:n. A costume carried from
/// season 1 into season 2 is visible in BOTH season streams; removing it
/// from season 1 leaves it only in season 2. `CostumeView.season_ids`
/// mirrors the rows through the enrich path.
#[tokio::test]
async fn costume_repertoire_spans_two_seasons_and_removal_leaves_one() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());
    let season1 = Uuid::now_v7();
    let season2 = Uuid::now_v7();
    let costume_id = Uuid::now_v7();
    let stream_id = format!("costume-{}", costume_id);

    // Costume built for season 1.
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &breakdown_core::costume::events::CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: None,
            season_id: Some(season1),
            notes: "Repertoire Costume".into(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    // Carried over into season 2 (CostumeAddedToSeason, v1 -> v2).
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeAddedToSeason",
        "0",
        &breakdown_core::costume::events::CostumeEvent::CostumeAddedToSeason {
            id: costume_id,
            season_id: season2,
            version: AggregateVersion(2),
        },
    )
    .await?;

    // Visible in BOTH season streams; the view lists both seasons.
    await_proj_row(
        || {
            let c_repo = costume_repo.clone();
            let expected = (season1, season2, costume_id);
            Box::pin(async move {
                let Ok(v) = c_repo.costume_with_details_photos(expected.2).await else {
                    return false;
                };
                v.season_ids == vec![expected.0, expected.1]
            })
        },
        "costume in both season streams",
    )
    .await?;

    let in_s1 = costume_repo
        .list_by_season(SeasonId(season1), 50, 0)
        .await?;
    let in_s2 = costume_repo
        .list_by_season(SeasonId(season2), 50, 0)
        .await?;
    assert_eq!(in_s1.len(), 1, "costume visible in season 1");
    assert_eq!(in_s2.len(), 1, "costume visible in season 2");

    // Season 1 wrapped: the wardrobe carries the costume back (removal,
    // v2 -> v3) — it stays only in season 2.
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeRemovedFromSeason",
        "1",
        &breakdown_core::costume::events::CostumeEvent::CostumeRemovedFromSeason {
            id: costume_id,
            season_id: season1,
            version: AggregateVersion(3),
        },
    )
    .await?;

    await_proj_row(
        || {
            let c_repo = costume_repo.clone();
            let expected = (season2, costume_id);
            Box::pin(async move {
                let Ok(v) = c_repo.costume_with_details_photos(expected.1).await else {
                    return false;
                };
                v.season_ids == vec![expected.0]
            })
        },
        "costume only in season 2",
    )
    .await?;

    let in_s1 = costume_repo
        .list_by_season(SeasonId(season1), 50, 0)
        .await?;
    let in_s2 = costume_repo
        .list_by_season(SeasonId(season2), 50, 0)
        .await?;
    assert!(
        in_s1.iter().all(|v| v.id != costume_id),
        "season 1 must no longer list the costume"
    );
    assert_eq!(in_s2.len(), 1, "season 2 keeps the costume");

    Ok(())
}

/// Issue #534 replay compatibility, DELETE path: a legacy costume stream
/// (no `season_id` at all) that later gains repertoire events still
/// projects — the DELETE of a never-inserted row affects 0 rows and the
/// version guard still advances.
#[tokio::test]
async fn costume_repertoire_events_on_legacy_stream_project() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _costume_ref = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let costume_repo = infra::queries::CostumeRepositoryImpl::new(pool.clone());
    let season1 = Uuid::now_v7();
    let costume_id = Uuid::now_v7();
    let stream_id = format!("costume-{}", costume_id);

    // Pre-#453 `CostumeCreated` (no `season_id`) — CBOR bytes for UUIDs.
    let legacy_cbor = ciborium::value::Value::Map(vec![(
        ciborium::value::Value::Text("CostumeCreated".into()),
        ciborium::value::Value::Map(vec![
            (
                ciborium::value::Value::Text("id".into()),
                ciborium::value::Value::Bytes(costume_id.as_bytes().to_vec()),
            ),
            (
                ciborium::value::Value::Text("character_id".into()),
                ciborium::value::Value::Null,
            ),
            (
                ciborium::value::Value::Text("notes".into()),
                ciborium::value::Value::Text("Legacy costume".into()),
            ),
            (
                ciborium::value::Value::Text("details".into()),
                ciborium::value::Value::Array(vec![]),
            ),
            (
                ciborium::value::Value::Text("photos".into()),
                ciborium::value::Value::Array(vec![]),
            ),
            (
                ciborium::value::Value::Text("version".into()),
                ciborium::value::Value::Integer(1.into()),
            ),
        ]),
    )]);

    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeCreated",
        "EMPTY",
        &legacy_cbor,
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

    // Repertoire events on top of the legacy stream: add, then remove the
    // same season — final state: empty repertoire, version 3.
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeAddedToSeason",
        "0",
        &breakdown_core::costume::events::CostumeEvent::CostumeAddedToSeason {
            id: costume_id,
            season_id: season1,
            version: AggregateVersion(2),
        },
    )
    .await?;
    eappend_event(
        Arc::clone(&redis_client),
        &stream_id,
        "CostumeRemovedFromSeason",
        "1",
        &breakdown_core::costume::events::CostumeEvent::CostumeRemovedFromSeason {
            id: costume_id,
            season_id: season1,
            version: AggregateVersion(3),
        },
    )
    .await?;

    await_proj_row(
        || {
            let c_repo = costume_repo.clone();
            Box::pin(async move {
                let Ok(v) = c_repo.costume_with_details_photos(costume_id).await else {
                    return false;
                };
                v.version == AggregateVersion(3) && v.season_ids.is_empty()
            })
        },
        "legacy stream repertoire settled",
    )
    .await?;

    let listed = costume_repo
        .list_by_season(SeasonId(season1), 50, 0)
        .await?;
    assert!(
        listed.iter().all(|v| v.id != costume_id),
        "removed repertoire row must leave the season stream"
    );

    Ok(())
}
