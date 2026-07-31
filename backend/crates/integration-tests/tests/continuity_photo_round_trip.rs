// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)

//! Tier-4 integration tests for continuity-photo lifecycle (9.2 + 9.3).
//!
//! 9.2: continuity photo upload → variant generation → bytes in Garage → projection rows
//! 9.3: continuity delete → refcount → `DeletePhoto` only at zero → bytes cleaned
//!
//! Drives the full chain: EAPPEND → SierraDB → projectors → Postgres projections
//! and Garage byte storage.

mod fixtures;

fn test_user() -> breakdown_core::shared::UserId {
    breakdown_core::shared::UserId("test-user".into())
}

use std::sync::Arc;
use std::time::Duration;
use tokio::time::Instant;

use anyhow::{Result, anyhow, bail};
use breakdown_core::photo::commands::UploadPhoto;
use breakdown_core::photo::ports::{PhotoCommands, PhotoStorage};
use breakdown_core::scene_shoot::events::SceneShootEvent;
use breakdown_core::scene_shoot::ports::SceneShootRepository as _;
use breakdown_core::shared::{
    AggregateVersion, LexicalSortKey, PhotoId, PhotoVariant, SceneShootId, SceneShootStatus,
    ShootingDayId,
};
use chrono::Utc;
use fixtures::{await_photo, build_storage, spawn_garage, spawn_postgres, spawn_sierradb};
use infra::event_store::PhotoCommandsImpl;
use infra::photo::repository::PhotoRepositoryImpl;
use infra::projectors::{
    spawn_photo_projector, spawn_scene_projector, spawn_scene_shoot_projector,
    spawn_shooting_day_projector,
};
use kameo_es::command_service::CommandService;
use uuid::Uuid;

const DEADLINE: Duration = Duration::from_secs(30);
const POLL: Duration = Duration::from_millis(200);

fn encode<E: serde::Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut buf = Vec::new();
    ciborium::into_writer(event, &mut buf).map_err(|e| anyhow!("CBOR: {e}"))?;
    Ok(buf)
}

async fn eappend(
    client: &Arc<redis::Client>,
    stream: &str,
    etype: &str,
    ver: &str,
    payload: &[u8],
) -> Result<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let _: redis::Value = redis::cmd("EAPPEND")
        .arg(stream)
        .arg(etype)
        .arg("EXPECTED_VERSION")
        .arg(ver)
        .arg("PAYLOAD")
        .arg(payload)
        .arg("TIMESTAMP")
        .arg(ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {etype}: {e}"))?;
    Ok(())
}

/// Seed FK-required parent rows.
async fn seed_parents(pool: &sqlx::PgPool, scene_id: Uuid, day_id: ShootingDayId) -> Result<()> {
    let ep = Uuid::now_v7();
    let char_id = Uuid::now_v7();
    let costume_id = Uuid::now_v7();

    // character (after 20250626000001: season_id, category instead of project_id/is_extra/is_main_character)
    sqlx::query(
        r#"INSERT INTO projection_character
            (id,name,season_id,category,measurements,contact,version,updated_at)
        VALUES ($1,'Char',$2,'"main_cast"'::jsonb,'{}'::jsonb,'{}'::jsonb,1,now())
        ON CONFLICT (id) DO NOTHING"#,
    )
    .bind(char_id)
    .bind(ep)
    .execute(pool)
    .await?;

    // costume (after 20250627000001: project_id dropped)
    sqlx::query(
        r#"INSERT INTO projection_costume
            (id,character_id,notes,version,updated_at)
        VALUES ($1,$2,'',1,now())
        ON CONFLICT (id) DO NOTHING"#,
    )
    .bind(costume_id)
    .bind(char_id)
    .execute(pool)
    .await?;

    // scene
    sqlx::query(
        r#"INSERT INTO projection_scene
            (id,episode_id,scene_number,location,mood,is_schedule_set,summary,script_day,version,updated_at)
        VALUES ($1,$2,1,'loc','mood',false,NULL,NULL,1,now())
        ON CONFLICT (id) DO NOTHING"#,
    )
    .bind(scene_id)
    .bind(ep)
    .execute(pool)
    .await?;

    // shooting_day
    sqlx::query(
        r#"INSERT INTO projection_shooting_day
            (id,episode_id,label,order_key,date,source,archived,wrapped_at,version,updated_at)
        VALUES ($1,$2,'Day 1','a',NULL,'{"Manual":null}'::jsonb,false,NULL,1,now())
        ON CONFLICT (id) DO NOTHING"#,
    )
    .bind(day_id.0)
    .bind(ep)
    .execute(pool)
    .await?;

    // episode (required so photo upload resolve_series_id finds it)
    sqlx::query(
        r#"INSERT INTO projection_episode
            (id,block_id,series_id,number,name,version,updated_at)
        VALUES ($1,$2,$3,1,'Test Ep',1,now())
        ON CONFLICT (id) DO NOTHING"#,
    )
    .bind(ep)
    .bind(ep) // block_id = same id re-used as opaque value
    .bind(ep) // series_id = same id re-used as opaque value
    .execute(pool)
    .await?;

    Ok(())
}

/// Minimal JPEG header bytes for testing.
fn jpeg_bytes() -> Vec<u8> {
    vec![
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06,
        0x05, 0x08, 0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b,
        0x0c, 0x19, 0x12, 0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20,
        0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29, 0x2c, 0x30, 0x31,
        0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34, 0x32,
    ]
}

/// Poll `projection_costume_photo` until count matches `expected`.
async fn await_refcount(pool: &sqlx::PgPool, photo_id: PhotoId, expected: i64) -> Result<()> {
    let dl = Instant::now() + DEADLINE;
    loop {
        let count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM projection_costume_photo WHERE photo_id = $1")
                .bind(photo_id.0)
                .fetch_one(pool)
                .await?;
        if count == expected {
            return Ok(());
        }
        if Instant::now() > dl {
            bail!("refcount timeout: expected {expected}, got {count}");
        }
        tokio::time::sleep(POLL).await;
    }
}

// ---------------------------------------------------------------------------
// 9.2  continuity photo upload → projection rows
// ---------------------------------------------------------------------------

#[tokio::test]
async fn continuity_photo_upload_projection() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let (client, _conn, _sierra) = spawn_sierradb().await?;
    let (creds, _garage) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let cmd_service = CommandService::new(client.get_multiplexed_async_connection().await?);
    let photo_commands = PhotoCommandsImpl::new(
        cmd_service.clone(),
        PhotoRepositoryImpl::new(pool.clone()),
        infra::queries::CostumeRepositoryImpl::new(pool.clone()),
        infra::queries::CharacterRepositoryImpl::new(pool.clone()),
        infra::queries::SeasonRepositoryImpl::new(pool.clone()),
        infra::queries::SceneShootRepositoryImpl::new(pool.clone()),
        infra::queries::SceneRepositoryImpl::new(pool.clone()),
        infra::queries::EpisodeRepositoryImpl::new(pool.clone()),
    );
    let photo_repo = PhotoRepositoryImpl::new(pool.clone());

    let _scene_proj = spawn_scene_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _sd_proj = spawn_shooting_day_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _ss_proj = spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _photo_proj = spawn_photo_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    let shoot_id = SceneShootId::new();
    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();

    seed_parents(&pool, scene_id, day_id).await?;

    // Plan a SceneShoot via EAPPEND.
    let ss_stream = format!("scene_shoot-{}", shoot_id.0);
    let planned = SceneShootEvent::SceneShootPlanned {
        id: shoot_id,
        scene_id,
        shooting_day_id: day_id,
        planned_order: LexicalSortKey::new("001").unwrap(),
        status: SceneShootStatus::Planned,
        version: AggregateVersion(1),
    };
    eappend(
        &client,
        &ss_stream,
        "SceneShootPlanned",
        "EMPTY",
        &encode(&planned)?,
    )
    .await?;

    // Wait for scene_shoot projection.
    let ss_repo = infra::queries::SceneShootRepositoryImpl::new(pool.clone());
    let dl = Instant::now() + DEADLINE;
    loop {
        if ss_repo.find_by_id(shoot_id).await.is_ok() {
            break;
        }
        if Instant::now() > dl {
            bail!("scene_shoot not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    // Upload photo with Continuity binding.
    let photo_id = PhotoId::new();
    let bytes = jpeg_bytes();
    let ct = "image/jpeg".to_string();

    storage
        .store(photo_id, PhotoVariant::Original, bytes.clone(), ct.clone())
        .await?;

    let version = photo_commands
        .upload(
            test_user(),
            UploadPhoto {
                id: photo_id,
                content_type: ct.clone(),
                size_bytes: bytes.len() as u64,
                binding: breakdown_core::photo::binding::PhotoBinding::Continuity {
                    scene_shoot_id: shoot_id,
                    costume_id: None,
                },
            },
        )
        .await?;
    assert!(version.0 > 0);

    // Wait for projection_photo row.
    let photo_view = await_photo(&photo_repo, photo_id, Instant::now() + DEADLINE).await?;
    assert_eq!(photo_view.content_type, ct);
    assert_eq!(photo_view.size_bytes, bytes.len() as u64);

    // Wait for projection_continuity_photo row.
    let dl = Instant::now() + DEADLINE;
    loop {
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM projection_continuity_photo WHERE photo_id = $1)",
        )
        .bind(photo_id.0)
        .fetch_one(&pool)
        .await?;
        if exists {
            break;
        }
        if Instant::now() > dl {
            bail!("projection_continuity_photo not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    // Verify original bytes are fetchable.
    let fetched = storage.fetch(photo_id, PhotoVariant::Original).await?;
    assert_eq!(fetched.bytes, bytes);

    Ok(())
}

// ---------------------------------------------------------------------------
// 9.3  continuity delete → refcount → DeletePhoto only at zero → bytes cleaned
// ---------------------------------------------------------------------------

#[tokio::test]
async fn continuity_photo_delete_on_zero_refcount() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let (client, _conn, _sierra) = spawn_sierradb().await?;
    let (creds, _garage) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let cmd_service = CommandService::new(client.get_multiplexed_async_connection().await?);
    let photo_commands = PhotoCommandsImpl::new(
        cmd_service.clone(),
        PhotoRepositoryImpl::new(pool.clone()),
        infra::queries::CostumeRepositoryImpl::new(pool.clone()),
        infra::queries::CharacterRepositoryImpl::new(pool.clone()),
        infra::queries::SeasonRepositoryImpl::new(pool.clone()),
        infra::queries::SceneShootRepositoryImpl::new(pool.clone()),
        infra::queries::SceneRepositoryImpl::new(pool.clone()),
        infra::queries::EpisodeRepositoryImpl::new(pool.clone()),
    );
    let photo_repo = PhotoRepositoryImpl::new(pool.clone());

    let _scene_proj = spawn_scene_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _sd_proj = spawn_shooting_day_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _ss_proj = spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _photo_proj = spawn_photo_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    // Spawn ContinuityDeletionSaga (after projectors so replay picks up events).
    tokio::time::sleep(Duration::from_millis(500)).await;
    infra::photo::sagas::spawn_continuity_deletion_saga(
        cmd_service.clone(),
        photo_repo.clone(),
        infra::queries::CostumeRepositoryImpl::new(pool.clone()),
        infra::queries::CharacterRepositoryImpl::new(pool.clone()),
        infra::queries::SeasonRepositoryImpl::new(pool.clone()),
        infra::queries::SceneShootRepositoryImpl::new(pool.clone()),
        infra::queries::SceneRepositoryImpl::new(pool.clone()),
        infra::queries::EpisodeRepositoryImpl::new(pool.clone()),
        Arc::clone(&client),
    )
    .await?;
    infra::photo::sagas::spawn_photo_bytes_cleanup_saga(storage.clone(), Arc::clone(&client))
        .await?;

    let shoot_id = SceneShootId::new();
    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();

    seed_parents(&pool, scene_id, day_id).await?;

    // Plan SceneShoot.
    let ss_stream = format!("scene_shoot-{}", shoot_id.0);
    let planned = SceneShootEvent::SceneShootPlanned {
        id: shoot_id,
        scene_id,
        shooting_day_id: day_id,
        planned_order: LexicalSortKey::new("001").unwrap(),
        status: SceneShootStatus::Planned,
        version: AggregateVersion(1),
    };
    eappend(
        &client,
        &ss_stream,
        "SceneShootPlanned",
        "EMPTY",
        &encode(&planned)?,
    )
    .await?;

    let ss_repo = infra::queries::SceneShootRepositoryImpl::new(pool.clone());
    let dl = Instant::now() + DEADLINE;
    loop {
        if ss_repo.find_by_id(shoot_id).await.is_ok() {
            break;
        }
        if Instant::now() > dl {
            bail!("scene_shoot not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    // Upload photo with Continuity binding.
    let photo_id = PhotoId::new();
    let bytes = jpeg_bytes();
    let ct = "image/jpeg".to_string();

    storage
        .store(photo_id, PhotoVariant::Original, bytes.clone(), ct.clone())
        .await?;

    let _v = photo_commands
        .upload(
            test_user(),
            UploadPhoto {
                id: photo_id,
                content_type: ct,
                size_bytes: bytes.len() as u64,
                binding: breakdown_core::photo::binding::PhotoBinding::Continuity {
                    scene_shoot_id: shoot_id,
                    costume_id: None,
                },
            },
        )
        .await?;

    // Link photo to scene shoot.
    let link = SceneShootEvent::ContinuityPhotoLinked {
        id: shoot_id,
        photo_id,
        version: AggregateVersion(2),
    };
    eappend(
        &client,
        &ss_stream,
        "ContinuityPhotoLinked",
        "0",
        &encode(&link)?,
    )
    .await?;

    // Verify projection_scene_shoot has the photo linked.
    let dl = Instant::now() + DEADLINE;
    loop {
        if let Ok(view) = ss_repo.find_by_id(shoot_id).await
            && view.continuity_photo_ids.contains(&photo_id)
        {
            break;
        }
        if Instant::now() > dl {
            bail!("continuity photo not linked in projection");
        }
        tokio::time::sleep(POLL).await;
    }

    // Verify no costume-side refs.
    await_refcount(&pool, photo_id, 0).await?;

    // Unlink photo from scene shoot.
    let unlink = SceneShootEvent::ContinuityPhotoUnlinked {
        id: shoot_id,
        photo_id,
        version: AggregateVersion(3),
    };
    eappend(
        &client,
        &ss_stream,
        "ContinuityPhotoUnlinked",
        "1",
        &encode(&unlink)?,
    )
    .await?;

    // Wait for ContinuityDeletionSaga to dispatch DeletePhoto.
    // The saga sees refcount 0 (no costume-side links) and dispatches DeletePhoto.
    // Then PhotoBytesCleanupSaga removes bytes from Garage.
    let dl = Instant::now() + Duration::from_secs(20);
    loop {
        let fetch_result = storage.fetch(photo_id, PhotoVariant::Original).await;
        if fetch_result.is_err() {
            break; // Bytes cleaned up — DeletePhoto + cleanup saga ran.
        }
        if Instant::now() > dl {
            bail!("bytes not cleaned up within deadline");
        }
        tokio::time::sleep(POLL).await;
    }

    // Verify projection_photo row is gone (PhotoDeleted → projector deletes row).
    let dl = Instant::now() + DEADLINE;
    loop {
        let exists: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM projection_photo WHERE photo_id = $1)")
                .bind(photo_id.0)
                .fetch_one(&pool)
                .await?;
        if !exists {
            break;
        }
        if Instant::now() > dl {
            bail!("projection_photo row not deleted");
        }
        tokio::time::sleep(POLL).await;
    }

    Ok(())
}
