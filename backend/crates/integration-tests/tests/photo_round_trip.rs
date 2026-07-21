// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Tier-4 integration test: Postgres + SierraDB + Garage full round-trip.
//!
//! Spawns the Photo projector + thumbnail/deletion/bytes-cleanup sagas and
//! exercises the full command→event→projection→read chain for photo lifecycle.

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use breakdown_core::photo::commands::UploadPhoto;
use breakdown_core::photo::ports::{PhotoCommands, PhotoRepository, PhotoStorage};
use breakdown_core::shared::{PhotoId, PhotoVariant};
use fixtures::{GarageCredentials, spawn_garage, spawn_postgres, spawn_sierradb};
use infra::event_store::PhotoCommandsImpl;
use infra::photo::repository::PhotoRepositoryImpl;
use infra::photo::storage::OpenDalPhotoStorage;
use kameo_es::command_service::CommandService;

/// Build a storage adapter from test Garage credentials.
fn build_storage(creds: &GarageCredentials) -> OpenDalPhotoStorage {
    let builder = opendal::services::S3::default()
        .endpoint(&creds.endpoint)
        .access_key_id(&creds.access_key)
        .secret_access_key(&creds.secret_key)
        .bucket(&creds.bucket);

    let op = opendal::Operator::new(builder)
        .expect("Failed to build S3 operator")
        .finish();

    OpenDalPhotoStorage::new(op)
}

/// Await a photo view from the projection (retry on NotFound).
async fn await_photo(
    repo: &PhotoRepositoryImpl,
    photo_id: PhotoId,
    deadline: tokio::time::Instant,
) -> Result<breakdown_core::photo::views::PhotoView> {
    loop {
        match repo.find_by_id(photo_id).await {
            Ok(view) => return Ok(view),
            Err(_) if tokio::time::Instant::now() > deadline => {
                anyhow::bail!("Timed out waiting for photo projection");
            }
            Err(_) => {
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }
}

#[tokio::test]
async fn photo_upload_then_delete_round_trip() -> Result<()> {
    // Start all three tiers.
    let (_pool, _pg_guard) = spawn_postgres().await?;
    let (sierra_client, _conn, _sierra_guard) = spawn_sierradb().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let cmd_service = {
        let conn = sierra_client.get_multiplexed_tokio_connection().await?;
        CommandService::new(conn)
    };
    let photo_commands = PhotoCommandsImpl::new(cmd_service.clone());
    let photo_repo = PhotoRepositoryImpl::new(_pool.clone());

    // Spawn the photo projector.
    let redis_client = Arc::clone(&sierra_client);
    let _photo_projector =
        infra::projectors::spawn_photo_projector(_pool.clone(), Arc::clone(&redis_client)).await?;

    // Spawn photo sagas.
    infra::photo::sagas::spawn_photo_thumbnail_saga(
        storage.clone(),
        photo_commands.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    infra::photo::sagas::spawn_photo_bytes_cleanup_saga(storage.clone(), Arc::clone(&redis_client))
        .await?;

    // Generate a photo ID and store original bytes in Garage.
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

    // Store original bytes in Garage first (the saga needs them).
    storage
        .store(
            photo_id,
            PhotoVariant::Original,
            image_bytes.clone(),
            content_type.clone(),
        )
        .await?;

    // 1. Dispatch UploadPhoto command.
    let version = photo_commands
        .upload(UploadPhoto {
            id: photo_id,
            content_type: content_type.clone(),
            size_bytes: image_bytes.len() as u64,
        })
        .await?;
    assert!(version.0 > 0, "UploadPhoto should return version > 0");

    // 2. Wait for the projector to create the projection row.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
    let photo_view = await_photo(&photo_repo, photo_id, deadline).await?;
    assert_eq!(photo_view.id, photo_id);
    assert_eq!(photo_view.content_type, content_type);
    assert_eq!(photo_view.size_bytes, image_bytes.len() as u64);

    // 3. Verify bytes are still fetchable from Garage.
    let fetched = storage.fetch(photo_id, PhotoVariant::Original).await?;
    assert_eq!(fetched.bytes, image_bytes);

    // 4. Dispatch DeletePhoto.
    photo_commands
        .delete(breakdown_core::photo::commands::DeletePhoto {
            id: photo_id,
            version,
        })
        .await?;

    // 5. Wait for the bytes-cleanup saga to remove bytes from Garage.
    tokio::time::sleep(Duration::from_secs(5)).await;
    let fetch_result = storage.fetch(photo_id, PhotoVariant::Original).await;
    assert!(
        fetch_result.is_err(),
        "Original bytes should be deleted after PhotoDeleted"
    );

    Ok(())
}
