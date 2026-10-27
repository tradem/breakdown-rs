// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Tier-4 integration test: N:M photo deletion round-trip.
//!
//! Spawns Postgres + SierraDB + Garage with the photo projector, piece projector,
//! and all three photo sagas (thumbnail, deletion, bytes-cleanup).
//!
//! Scenario: Photo P is linked to two pieces (A and B).
//!   - Unlink from A → refcount drops to 1 → `PhotoDeletionSaga` does NOT
//!     dispatch `DeletePhoto` → bytes remain in Garage.
//!   - Unlink from B → refcount drops to 0 → saga dispatches `DeletePhoto` →
//!     `PhotoBytesCleanupSaga` removes bytes from Garage.

mod fixtures;

fn test_user() -> breakdown_core::shared::UserId {
    breakdown_core::shared::UserId("test-user".into())
}

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use breakdown_core::photo::commands::UploadPhoto;
use breakdown_core::photo::ports::{PhotoCommands, PhotoRepository, PhotoStorage};
use breakdown_core::piece::commands::{CreatePiece, LinkPiecePhoto, UnlinkPiecePhoto};
use breakdown_core::piece::ports::{PieceCommands, PieceRepository};
use breakdown_core::shared::{PhotoId, PhotoVariant};
use fixtures::{await_photo, build_storage, spawn_garage, spawn_postgres, spawn_sierradb};
use infra::event_store::{PhotoCommandsImpl, WardrobeCommandsImpl};
use infra::photo::repository::PhotoRepositoryImpl;
use infra::queries::PieceRepositoryImpl;
use kameo_es::command_service::CommandService;
use uuid::Uuid;

/// Poll `SELECT COUNT(*) FROM projection_piece_photo WHERE photo_id = $1`
/// until it matches `expected` or the deadline expires.
async fn await_photo_refcount(
    pool: &sqlx::PgPool,
    photo_id: PhotoId,
    expected: i64,
    deadline: tokio::time::Instant,
) -> Result<()> {
    loop {
        let count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM projection_piece_photo WHERE photo_id = $1")
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
    let (pool, _pg_guard) = spawn_postgres().await?;
    let (sierra_client, _conn, _sierra_guard) = spawn_sierradb().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let cmd_service = {
        let conn = sierra_client.get_multiplexed_async_connection().await?;
        CommandService::new(conn)
    };

    // -----------------------------------------------------------------------
    // 2. Adapters
    // -----------------------------------------------------------------------
    let photo_commands = PhotoCommandsImpl::new(cmd_service.clone());
    let piece_commands = WardrobeCommandsImpl::new(cmd_service.clone());
    let photo_repo = PhotoRepositoryImpl::new(pool.clone());
    let _piece_repo = PieceRepositoryImpl::new(pool.clone());

    // -----------------------------------------------------------------------
    // 3. Projectors (photo + piece — both needed for FK refs)
    // -----------------------------------------------------------------------
    let redis_client = Arc::clone(&sierra_client);
    let _photo_projector = infra::projectors::spawn_photo_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _piece_projector = infra::projectors::spawn_piece_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    // -----------------------------------------------------------------------
    // 4. Sagas (thumbnail, deletion, bytes-cleanup)
    // -----------------------------------------------------------------------
    infra::photo::sagas::spawn_photo_thumbnail_saga(
        cmd_service.clone(),
        storage.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    infra::photo::sagas::spawn_photo_deletion_saga(
        cmd_service.clone(),
        photo_repo.clone(),
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
        .upload(
            test_user(),
            UploadPhoto {
                id: photo_id,
                content_type: content_type.clone(),
                size_bytes: image_bytes.len() as u64,
                binding: breakdown_core::photo::binding::PhotoBinding::Piece {
                    piece_id: Uuid::now_v7(),
                },
                project_id: Some(breakdown_core::shared::ProjectId::new()),
            },
        )
        .await?;
    assert!(photo_version.0 > 0, "UploadPhoto should return version > 0");

    // Wait for photo projection.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
    let photo_view = await_photo(&photo_repo, photo_id, deadline).await?;
    assert_eq!(photo_view.id, photo_id);

    // -----------------------------------------------------------------------
    // 6. Create two pieces (A and B)
    // -----------------------------------------------------------------------
    let piece_a_id = Uuid::now_v7();
    let piece_b_id = Uuid::now_v7();

    let (_id_a, ver_a) = piece_commands
        .create(
            test_user(),
            CreatePiece {
                id: piece_a_id,
                name: "Fundus-Piece".to_string(),
                category_id: None,
                season_id: None,
                project_id: None,
            },
        )
        .await?;
    // Wait for piece A projection.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    loop {
        match _piece_repo.find_by_id(piece_a_id).await {
            Ok(_) => break,
            Err(_) if tokio::time::Instant::now() > deadline => {
                anyhow::bail!("Timed out waiting for piece A projection");
            }
            Err(_) => {
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }

    let (_id_b, ver_b) = piece_commands
        .create(
            test_user(),
            CreatePiece {
                id: piece_b_id,
                name: "Fundus-Piece".to_string(),
                category_id: None,
                season_id: None,
                project_id: None,
            },
        )
        .await?;
    // Wait for piece B projection.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    loop {
        match _piece_repo.find_by_id(piece_b_id).await {
            Ok(_) => break,
            Err(_) if tokio::time::Instant::now() > deadline => {
                anyhow::bail!("Timed out waiting for piece B projection");
            }
            Err(_) => {
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }

    // -----------------------------------------------------------------------
    // 7. Link photo P to both pieces
    // -----------------------------------------------------------------------
    let ver_a2 = piece_commands
        .link_photo(
            test_user(),
            LinkPiecePhoto {
                id: piece_a_id,
                photo_id: photo_id.0,
                project_id: None,
                version: ver_a,
            },
        )
        .await?;
    assert!(ver_a2.0 > ver_a.0, "LinkPiecePhoto should increase version");

    let ver_b2 = piece_commands
        .link_photo(
            test_user(),
            LinkPiecePhoto {
                id: piece_b_id,
                photo_id: photo_id.0,
                project_id: None,
                version: ver_b,
            },
        )
        .await?;
    assert!(ver_b2.0 > ver_b.0, "LinkPiecePhoto should increase version");

    // Wait for both links to appear in projection_piece_photo.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    await_photo_refcount(&pool, photo_id, 2, deadline).await?;

    // -----------------------------------------------------------------------
    // 8. Unlink from piece A — refcount drops to 1, bytes should survive
    // -----------------------------------------------------------------------
    let ver_a3 = piece_commands
        .unlink_photo(
            test_user(),
            UnlinkPiecePhoto {
                id: piece_a_id,
                photo_id: photo_id.0,
                project_id: None,
                version: ver_a2,
            },
        )
        .await?;
    assert!(
        ver_a3.0 > ver_a2.0,
        "UnlinkPiecePhoto should increase version"
    );

    // Wait for projection to reflect the unlink.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    await_photo_refcount(&pool, photo_id, 1, deadline).await?;

    // Short grace period for saga to process (should NOT delete).
    tokio::time::sleep(Duration::from_secs(3)).await;

    // Assert bytes still exist in Garage.
    let fetched = storage.fetch(photo_id, PhotoVariant::Original).await?;
    assert_eq!(
        fetched.bytes, image_bytes,
        "Bytes must remain after unlinking from first piece"
    );

    // -----------------------------------------------------------------------
    // 9. Unlink from piece B — refcount drops to 0, bytes must be deleted
    // -----------------------------------------------------------------------
    let ver_b3 = piece_commands
        .unlink_photo(
            test_user(),
            UnlinkPiecePhoto {
                id: piece_b_id,
                photo_id: photo_id.0,
                project_id: None,
                version: ver_b2,
            },
        )
        .await?;
    assert!(
        ver_b3.0 > ver_b2.0,
        "UnlinkPiecePhoto should increase version"
    );

    // Wait for the deletion saga chain to complete:
    //   refcount → 0  (PieceProjector processes PhotoUnlinked)
    //   → PhotoDeleted projected  (PhotoProjector processes DeletePhoto)
    //   → Garage bytes deleted  (PhotoBytesCleanupSaga processes PhotoDeleted)
    //
    // Each hop uses its own deadline so a timeout pinpoints the slow link.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(60);
    await_photo_refcount(&pool, photo_id, 0, deadline).await?;

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
    // projection_piece_photo should be empty for this photo.
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_piece_photo WHERE photo_id = $1")
            .bind(photo_id.0)
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        count, 0,
        "projection_piece_photo should have no rows for deleted photo"
    );

    // Photo projection should be gone (PhotoDeleted → PhotoProjector deletes row).
    let photo_result = photo_repo.find_by_id(photo_id).await;
    assert!(
        photo_result.is_err(),
        "Photo projection should be deleted after PhotoDeleted event"
    );

    Ok(())
}
