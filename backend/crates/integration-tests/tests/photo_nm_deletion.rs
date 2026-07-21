// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Tier-4 integration test: N:M photo deletion round-trip.
//!
//! Spawns Postgres + SierraDB + Garage with the photo projector, costume projector,
//! and all three photo sagas (thumbnail, deletion, bytes-cleanup).
//!
//! Scenario: Photo P is linked to two costumes (A and B).
//!   - Unlink from A → refcount drops to 1 → `PhotoDeletionSaga` does NOT
//!     dispatch `DeletePhoto` → bytes remain in Garage.
//!   - Unlink from B → refcount drops to 0 → saga dispatches `DeletePhoto` →
//!     `PhotoBytesCleanupSaga` removes bytes from Garage.

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use breakdown_core::costume::commands::{CreateCostume, LinkPhoto, UnlinkPhoto};
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::photo::commands::UploadPhoto;
use breakdown_core::photo::ports::{PhotoCommands, PhotoRepository, PhotoStorage};
use breakdown_core::shared::{PhotoId, PhotoVariant};
use fixtures::{await_photo, build_storage, spawn_garage, spawn_postgres, spawn_sierradb};
use infra::event_store::{CostumeCommandsImpl, PhotoCommandsImpl};
use infra::photo::repository::PhotoRepositoryImpl;
use infra::queries::CostumeRepositoryImpl;
use kameo_es::command_service::CommandService;
use uuid::Uuid;

/// Poll `SELECT COUNT(*) FROM projection_costume_photo WHERE photo_id = $1`
/// until it matches `expected` or the deadline expires.
async fn await_photo_refcount(
    pool: &sqlx::PgPool,
    photo_id: PhotoId,
    expected: i64,
    deadline: tokio::time::Instant,
) -> Result<()> {
    loop {
        let count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM projection_costume_photo WHERE photo_id = $1")
                .bind(photo_id.0)
                .fetch_one(pool)
                .await?;

        if count == expected {
            return Ok(());
        }
        if tokio::time::Instant::now() > deadline {
            anyhow::bail!("Timed out waiting for photo refcount {expected} (current: {count})");
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
    }
}

/// Poll the photo projection until `find_by_id` returns NotFound (row deleted).
/// Confirms that `PhotoDeleted` was emitted and the projector removed the row.
async fn await_photo_deleted(
    repo: &PhotoRepositoryImpl,
    photo_id: PhotoId,
    deadline: tokio::time::Instant,
) -> Result<()> {
    loop {
        match repo.find_by_id(photo_id).await {
            Err(_) => return Ok(()),
            Ok(_) if tokio::time::Instant::now() > deadline => {
                anyhow::bail!("Timed out waiting for photo projection to be deleted");
            }
            Ok(_) => {
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }
}

/// Poll `storage.fetch(photo_id, variant)` for existence check (retry on error).
async fn await_storage_fetch_ok(
    storage: &impl PhotoStorage,
    photo_id: PhotoId,
    variant: PhotoVariant,
    deadline: tokio::time::Instant,
) -> Result<()> {
    loop {
        match storage.fetch(photo_id, variant).await {
            Ok(_) => return Ok(()),
            Err(_) if tokio::time::Instant::now() > deadline => {
                anyhow::bail!("Timed out waiting for photo bytes to appear in storage");
            }
            Err(_) => {
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }
}

/// Poll `storage.fetch(photo_id, variant)` until it errors (bytes deleted).
async fn await_storage_fetch_err(
    storage: &impl PhotoStorage,
    photo_id: PhotoId,
    variant: PhotoVariant,
    deadline: tokio::time::Instant,
) -> Result<()> {
    loop {
        match storage.fetch(photo_id, variant).await {
            Ok(_) if tokio::time::Instant::now() > deadline => {
                anyhow::bail!("Timed out waiting for photo bytes to be deleted");
            }
            Ok(_) => {
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
            Err(_) => return Ok(()),
        }
    }
}

#[tokio::test]
async fn photo_nm_deletion_round_trip() -> Result<()> {
    // -----------------------------------------------------------------------
    // 1. Infrastructure: Postgres + SierraDB + Garage
    // -----------------------------------------------------------------------
    let (_pool, _pg_guard) = spawn_postgres().await?;
    let (sierra_client, _conn, _sierra_guard) = spawn_sierradb().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let cmd_service = {
        let conn = sierra_client.get_multiplexed_tokio_connection().await?;
        CommandService::new(conn)
    };

    // -----------------------------------------------------------------------
    // 2. Adapters
    // -----------------------------------------------------------------------
    let photo_commands = PhotoCommandsImpl::new(cmd_service.clone());
    let costume_commands = CostumeCommandsImpl::new(cmd_service.clone());
    let photo_repo = PhotoRepositoryImpl::new(_pool.clone());
    let _costume_repo = CostumeRepositoryImpl::new(_pool.clone());

    // -----------------------------------------------------------------------
    // 3. Projectors (photo + costume — both needed for FK refs)
    // -----------------------------------------------------------------------
    let redis_client = Arc::clone(&sierra_client);
    let _photo_projector =
        infra::projectors::spawn_photo_projector(_pool.clone(), Arc::clone(&redis_client)).await?;
    let _costume_projector =
        infra::projectors::spawn_costume_projector(_pool.clone(), Arc::clone(&redis_client))
            .await?;

    // -----------------------------------------------------------------------
    // 4. Sagas (thumbnail, deletion, bytes-cleanup)
    // -----------------------------------------------------------------------
    infra::photo::sagas::spawn_photo_thumbnail_saga(
        storage.clone(),
        photo_commands.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    infra::photo::sagas::spawn_photo_deletion_saga(
        photo_repo.clone(),
        photo_commands.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    infra::photo::sagas::spawn_photo_bytes_cleanup_saga(storage.clone(), Arc::clone(&redis_client))
        .await?;

    // -----------------------------------------------------------------------
    // 5. Create photo P (store bytes + UploadPhoto)
    // -----------------------------------------------------------------------
    let photo_id = PhotoId::new();
    let content_type = "image/jpeg".to_string();
    let image_bytes = vec![
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06,
        0x05, 0x08, 0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b,
        0x0c, 0x19, 0x12, 0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20,
        0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29, 0x2c, 0x30, 0x31,
        0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34, 0x32,
    ];

    // Store bytes first (thumbnail saga reads them on PhotoUploaded).
    storage
        .store(
            photo_id,
            PhotoVariant::Original,
            image_bytes.clone(),
            content_type.clone(),
        )
        .await?;

    // Dispatch UploadPhoto.
    let photo_version = photo_commands
        .upload(UploadPhoto {
            id: photo_id,
            content_type: content_type.clone(),
            size_bytes: image_bytes.len() as u64,
        })
        .await?;
    assert!(photo_version.0 > 0, "UploadPhoto should return version > 0");

    // Wait for photo projection.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
    let photo_view = await_photo(&photo_repo, photo_id, deadline).await?;
    assert_eq!(photo_view.id, photo_id);

    // -----------------------------------------------------------------------
    // 6. Create two costumes (A and B)
    // -----------------------------------------------------------------------
    let costume_a_id = Uuid::now_v7();
    let costume_b_id = Uuid::now_v7();

    let (_id_a, ver_a) = costume_commands
        .create(CreateCostume { id: costume_a_id })
        .await?;
    // Wait for costume A projection.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    loop {
        match _costume_repo.find_by_id(costume_a_id).await {
            Ok(_) => break,
            Err(_) if tokio::time::Instant::now() > deadline => {
                anyhow::bail!("Timed out waiting for costume A projection");
            }
            Err(_) => {
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }

    let (_id_b, ver_b) = costume_commands
        .create(CreateCostume { id: costume_b_id })
        .await?;
    // Wait for costume B projection.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    loop {
        match _costume_repo.find_by_id(costume_b_id).await {
            Ok(_) => break,
            Err(_) if tokio::time::Instant::now() > deadline => {
                anyhow::bail!("Timed out waiting for costume B projection");
            }
            Err(_) => {
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }

    // -----------------------------------------------------------------------
    // 7. Link photo P to both costumes
    // -----------------------------------------------------------------------
    let ver_a2 = costume_commands
        .link_photo(LinkPhoto {
            id: costume_a_id,
            photo_id: photo_id.0,
            version: ver_a,
        })
        .await?;
    assert!(ver_a2.0 > ver_a.0, "LinkPhoto should increase version");

    let ver_b2 = costume_commands
        .link_photo(LinkPhoto {
            id: costume_b_id,
            photo_id: photo_id.0,
            version: ver_b,
        })
        .await?;
    assert!(ver_b2.0 > ver_b.0, "LinkPhoto should increase version");

    // Wait for both links to appear in projection_costume_photo.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    await_photo_refcount(&_pool, photo_id, 2, deadline).await?;

    // -----------------------------------------------------------------------
    // 8. Unlink from costume A — refcount drops to 1, bytes should survive
    // -----------------------------------------------------------------------
    let ver_a3 = costume_commands
        .unlink_photo(UnlinkPhoto {
            id: costume_a_id,
            photo_id: photo_id.0,
            version: ver_a2,
        })
        .await?;
    assert!(ver_a3.0 > ver_a2.0, "UnlinkPhoto should increase version");

    // Wait for projection to reflect the unlink.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    await_photo_refcount(&_pool, photo_id, 1, deadline).await?;

    // Short grace period for saga to process (should NOT delete).
    tokio::time::sleep(Duration::from_secs(3)).await;

    // Assert bytes still exist in Garage.
    let fetched = storage.fetch(photo_id, PhotoVariant::Original).await?;
    assert_eq!(
        fetched.bytes, image_bytes,
        "Bytes must remain after unlinking from first costume"
    );

    // -----------------------------------------------------------------------
    // 9. Unlink from costume B — refcount drops to 0, bytes must be deleted
    // -----------------------------------------------------------------------
    let ver_b3 = costume_commands
        .unlink_photo(UnlinkPhoto {
            id: costume_b_id,
            photo_id: photo_id.0,
            version: ver_b2,
        })
        .await?;
    assert!(ver_b3.0 > ver_b2.0, "UnlinkPhoto should increase version");

    // Wait for the deletion saga chain to complete:
    //   refcount → 0  (CostumeProjector processes PhotoUnlinked)
    //   → PhotoDeleted projected  (PhotoProjector processes DeletePhoto)
    //   → Garage bytes deleted  (PhotoBytesCleanupSaga processes PhotoDeleted)
    //
    // Each hop uses its own deadline so a timeout pinpoints the slow link.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(60);
    await_photo_refcount(&_pool, photo_id, 0, deadline).await?;

    // Wait for the photo projection to be deleted (confirms DeletePhoto
    // was emitted and projected; the bytes saga runs on the same stream).
    let deadline = tokio::time::Instant::now() + Duration::from_secs(60);
    await_photo_deleted(&photo_repo, photo_id, deadline).await?;

    // Wait for bytes to be removed from Garage.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(60);
    await_storage_fetch_err(&storage, photo_id, PhotoVariant::Original, deadline).await?;

    // -----------------------------------------------------------------------
    // 10. Final assertions
    // -----------------------------------------------------------------------
    // projection_costume_photo should be empty for this photo.
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_costume_photo WHERE photo_id = $1")
            .bind(photo_id.0)
            .fetch_one(&_pool)
            .await?;
    assert_eq!(
        count, 0,
        "projection_costume_photo should have no rows for deleted photo"
    );

    // Photo projection should be gone (PhotoDeleted → PhotoProjector deletes row).
    let photo_result = photo_repo.find_by_id(photo_id).await;
    assert!(
        photo_result.is_err(),
        "Photo projection should be deleted after PhotoDeleted event"
    );

    Ok(())
}
