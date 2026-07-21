// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Tier-3 integration test: Postgres + Garage for `OpenDalPhotoStorage`.
//!
//! This test starts a PostgreSQL container and a Garage (S3-compatible)
//! container, provisions Garage (layout + bucket + access key), and
//! exercises the `PhotoStorage` port (store / fetch / delete_all / list)
//! against real S3 semantics.

mod fixtures;

use anyhow::Result;
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::shared::{PhotoId, PhotoVariant};
use fixtures::{GarageCredentials, spawn_garage, spawn_postgres};
use infra::photo::storage::OpenDalPhotoStorage;

/// Helper to build an `OpenDalPhotoStorage` from test Garage credentials.
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

/// Generate a deterministic JPEG-like byte sequence for testing.
fn test_image_bytes() -> Vec<u8> {
    // Minimal valid JPEG (1x1 pixel, white).
    vec![
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06,
        0x05, 0x08, 0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b,
        0x0c, 0x19, 0x12, 0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20,
        0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29, 0x2c, 0x30, 0x31,
        0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff,
        0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00,
        0x1f, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0xff,
        0xc4, 0x00, 0xb5, 0x10, 0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04,
        0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x11, 0x05, 0x12,
        0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1,
        0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09,
        0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x34, 0x35, 0x36,
        0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55,
        0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74,
        0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92,
        0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8,
        0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
        0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1,
        0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6,
        0xf7, 0xf8, 0xf9, 0xfa, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00, 0x7b,
        0x94, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xd9,
    ]
}

#[tokio::test]
async fn photo_storage_store_fetch_delete_round_trip() -> Result<()> {
    let (_pg_pool, _pg_guard) = spawn_postgres().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let photo_id = PhotoId::new();
    let bytes = test_image_bytes();
    let content_type = "image/jpeg".to_string();

    // Store original variant.
    storage
        .store(
            photo_id,
            PhotoVariant::Original,
            bytes.clone(),
            content_type.clone(),
        )
        .await?;

    // Fetch it back and verify.
    let fetched = storage.fetch(photo_id, PhotoVariant::Original).await?;
    assert_eq!(fetched.bytes, bytes);
    assert_eq!(fetched.content_type, content_type);
    assert!(fetched.etag.is_some());

    Ok(())
}

#[tokio::test]
async fn photo_storage_store_multiple_variants() -> Result<()> {
    let (_pg_pool, _pg_guard) = spawn_postgres().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let photo_id = PhotoId::new();
    let original = test_image_bytes();
    let thumb = vec![0x00, 0x01, 0x02]; // fake thumb bytes
    let medium = vec![0x03, 0x04, 0x05]; // fake medium bytes

    // Store all three variants.
    storage
        .store(
            photo_id,
            PhotoVariant::Original,
            original.clone(),
            "image/jpeg".into(),
        )
        .await?;
    storage
        .store(
            photo_id,
            PhotoVariant::Thumb,
            thumb.clone(),
            "image/jpeg".into(),
        )
        .await?;
    storage
        .store(
            photo_id,
            PhotoVariant::Medium,
            medium.clone(),
            "image/jpeg".into(),
        )
        .await?;

    // Verify each variant independently.
    let orig_fetched = storage.fetch(photo_id, PhotoVariant::Original).await?;
    assert_eq!(orig_fetched.bytes, original);

    let thumb_fetched = storage.fetch(photo_id, PhotoVariant::Thumb).await?;
    assert_eq!(thumb_fetched.bytes, thumb);

    let med_fetched = storage.fetch(photo_id, PhotoVariant::Medium).await?;
    assert_eq!(med_fetched.bytes, medium);

    Ok(())
}

#[tokio::test]
async fn photo_storage_delete_all_removes_all_variants() -> Result<()> {
    let (_pg_pool, _pg_guard) = spawn_postgres().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let photo_id = PhotoId::new();
    let bytes = test_image_bytes();

    // Store two variants.
    storage
        .store(
            photo_id,
            PhotoVariant::Original,
            bytes.clone(),
            "image/jpeg".into(),
        )
        .await?;
    storage
        .store(
            photo_id,
            PhotoVariant::Thumb,
            bytes.clone(),
            "image/jpeg".into(),
        )
        .await?;

    // Delete all.
    storage.delete_all(photo_id).await?;

    // Verify both variants are gone (fetch should return NotFound).
    let orig_result = storage.fetch(photo_id, PhotoVariant::Original).await;
    assert!(orig_result.is_err(), "Original should be deleted");

    let thumb_result = storage.fetch(photo_id, PhotoVariant::Thumb).await;
    assert!(thumb_result.is_err(), "Thumb should be deleted");

    Ok(())
}

#[tokio::test]
async fn photo_storage_overwrite_by_default() -> Result<()> {
    let (_pg_pool, _pg_guard) = spawn_postgres().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let photo_id = PhotoId::new();
    let original = b"original_bytes".to_vec();
    let updated = b"updated_bytes".to_vec();

    // Store original.
    storage
        .store(
            photo_id,
            PhotoVariant::Original,
            original.clone(),
            "image/jpeg".into(),
        )
        .await?;

    // Overwrite with new bytes.
    storage
        .store(
            photo_id,
            PhotoVariant::Original,
            updated.clone(),
            "image/jpeg".into(),
        )
        .await?;

    // Verify the new bytes are returned.
    let fetched = storage.fetch(photo_id, PhotoVariant::Original).await?;
    assert_eq!(fetched.bytes, updated, "S3 overwrite should replace bytes");

    Ok(())
}

#[tokio::test]
async fn photo_storage_list_returns_known_ids() -> Result<()> {
    let (_pg_pool, _pg_guard) = spawn_postgres().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let id_a = PhotoId::new();
    let id_b = PhotoId::new();
    let bytes = test_image_bytes();

    // Store two photos (original variant for each).
    storage
        .store(
            id_a,
            PhotoVariant::Original,
            bytes.clone(),
            "image/jpeg".into(),
        )
        .await?;
    storage
        .store(
            id_b,
            PhotoVariant::Original,
            bytes.clone(),
            "image/jpeg".into(),
        )
        .await?;

    // List should contain both IDs.
    let ids = storage.list().await?;
    assert!(ids.contains(&id_a), "list should contain id_a");
    assert!(ids.contains(&id_b), "list should contain id_b");

    // After delete_one, list should reflect absence.
    storage.delete_all(id_a).await?;
    let ids = storage.list().await?;
    assert!(
        !ids.contains(&id_a),
        "list should NOT contain id_a after delete"
    );
    assert!(ids.contains(&id_b), "list should still contain id_b");

    Ok(())
}

#[tokio::test]
async fn photo_storage_delete_all_is_idempotent() -> Result<()> {
    let (_pg_pool, _pg_guard) = spawn_postgres().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let photo_id = PhotoId::new();

    // Deleting a non-existent photo should succeed (idempotent).
    storage.delete_all(photo_id).await?;

    // Store and delete twice.
    let bytes = test_image_bytes();
    storage
        .store(photo_id, PhotoVariant::Original, bytes, "image/jpeg".into())
        .await?;
    storage.delete_all(photo_id).await?;
    storage.delete_all(photo_id).await?; // second delete should be a no-op

    Ok(())
}
