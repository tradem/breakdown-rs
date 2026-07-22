// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Tier-4 integration tests for the photo GC orphan-reconciliation sweep.
//!
//! Tests the full `storage → GC run → history` pipeline against real
//! Garage (S3), Postgres, and (optionally) SierraDB containers.
//! The GC age gate is verified by storing objects at different timestamps
//! and checking which ones get deleted.

mod fixtures;

use std::time::Duration;

use anyhow::Result;
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::photo::views::PhotoGcConfig;
use breakdown_core::shared::{PhotoId, PhotoVariant};
use fixtures::{build_storage, spawn_garage, spawn_postgres};
use infra::photo::gc::run_gc_sweep;
use infra::photo::repository::PhotoRepositoryImpl;
use sqlx::Row;

/// Tiny JPEG-like byte sequence for test storage (magic header only).
fn test_image_bytes() -> Vec<u8> {
    vec![
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
    ]
}

/// Assert that a `projection_photo_gc_run` row with the given properties
/// was written as the most recent sweep.
async fn assert_gc_history(
    pool: &sqlx::PgPool,
    expected_scanned: i64,
    expected_orphans_found: i64,
    expected_orphans_deleted: i64,
    expected_dry_run: bool,
) -> Result<()> {
    let row = sqlx::query(
        r#"
        SELECT scanned, orphans_found, orphans_deleted, dry_run
        FROM projection_photo_gc_run
        ORDER BY started_at DESC
        LIMIT 1
        "#,
    )
    .fetch_one(pool)
    .await?;

    let scanned: i64 = row.try_get("scanned")?;
    let orphans_found: i64 = row.try_get("orphans_found")?;
    let orphans_deleted: i64 = row.try_get("orphans_deleted")?;
    let dry_run: bool = row.try_get("dry_run")?;

    assert_eq!(scanned, expected_scanned, "scanned count mismatch");
    assert_eq!(
        orphans_found, expected_orphans_found,
        "orphans_found mismatch"
    );
    assert_eq!(
        orphans_deleted, expected_orphans_deleted,
        "orphans_deleted mismatch"
    );
    assert_eq!(dry_run, expected_dry_run, "dry_run mismatch");

    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn gc_deletes_old_orphans_preserves_young_ones() -> Result<()> {
    let (pool, _pg_guard) = spawn_postgres().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let repo = PhotoRepositoryImpl::new(pool.clone());

    let old_id = PhotoId::new();
    let young_id = PhotoId::new();
    let bytes = test_image_bytes();
    let content_type = "image/jpeg".to_string();

    // 1. Store the "old" orphan.
    storage
        .store(
            old_id,
            PhotoVariant::Original,
            bytes.clone(),
            content_type.clone(),
        )
        .await?;

    // 2. Wait 3 seconds so the old object's age exceeds max_age_secs=2.
    tokio::time::sleep(Duration::from_secs(3)).await;

    // 3. Store the "young" orphan (will be < max_age_secs old at GC time).
    storage
        .store(
            young_id,
            PhotoVariant::Original,
            bytes.clone(),
            content_type.clone(),
        )
        .await?;

    // 4. Run GC with max_age_secs=2.
    let config = PhotoGcConfig {
        enabled: true,
        interval_secs: 3600,
        max_age_secs: 2,
        batch_size: 100,
        dry_run: false,
    };
    run_gc_sweep(&pool, &storage, &repo, &config).await?;

    // 5. The old orphan should have been deleted.
    let old_result = storage.fetch(old_id, PhotoVariant::Original).await;
    assert!(
        old_result.is_err(),
        "Old orphan should have been deleted by GC"
    );

    // 6. The young orphan must still exist.
    let young_result = storage.fetch(young_id, PhotoVariant::Original).await;
    assert!(
        young_result.is_ok(),
        "Young orphan should NOT have been deleted by GC"
    );

    // 7. Verify the GC history row.
    assert_gc_history(&pool, 2, 2, 1, false).await?;

    Ok(())
}

#[tokio::test]
async fn gc_dry_run_does_not_delete() -> Result<()> {
    let (pool, _pg_guard) = spawn_postgres().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let repo = PhotoRepositoryImpl::new(pool.clone());

    let photo_id = PhotoId::new();
    let bytes = test_image_bytes();
    let content_type = "image/jpeg".to_string();

    // Store an orphan.
    storage
        .store(photo_id, PhotoVariant::Original, bytes, content_type)
        .await?;

    // Wait past max_age so the object would be eligible.
    tokio::time::sleep(Duration::from_secs(3)).await;

    // Run GC with dry_run = true.
    let config = PhotoGcConfig {
        enabled: true,
        interval_secs: 3600,
        max_age_secs: 2,
        batch_size: 100,
        dry_run: true,
    };
    run_gc_sweep(&pool, &storage, &repo, &config).await?;

    // The orphan must still exist (dry run — no deletion).
    let result = storage.fetch(photo_id, PhotoVariant::Original).await;
    assert!(result.is_ok(), "Orphan should still exist after dry-run GC");

    // History row must report dry_run = true and orphans_deleted = 0.
    assert_gc_history(&pool, 1, 1, 0, true).await?;

    Ok(())
}

#[tokio::test]
async fn gc_with_no_orphans_writes_history_row() -> Result<()> {
    let (pool, _pg_guard) = spawn_postgres().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let repo = PhotoRepositoryImpl::new(pool.clone());

    // No objects stored — Garage is empty.

    let config = PhotoGcConfig {
        enabled: true,
        interval_secs: 3600,
        max_age_secs: 2,
        batch_size: 100,
        dry_run: false,
    };
    run_gc_sweep(&pool, &storage, &repo, &config).await?;

    // History row with scanned = 0, orphans_found = 0, orphans_deleted = 0.
    assert_gc_history(&pool, 0, 0, 0, false).await?;

    Ok(())
}
