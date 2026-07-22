// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Periodic orphan GC for costume-photo storage.
//!
//! Reconciles the Garage object listing against `projection_photo` and
//! deletes orphans (photo_ids present in Garage but absent from the
//! projection) older than a configurable age gate. Acquires a Postgres
//! advisory lock at sweep start so at most one sweep runs per cycle.

use std::time::Duration;

use anyhow::Result;
use breakdown_core::photo::ports::{PhotoRepository, PhotoStorage};
use breakdown_core::photo::views::PhotoGcConfig;
use breakdown_core::shared::PhotoVariant;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::photo::repository::PhotoRepositoryImpl;
use crate::photo::storage::OpenDalPhotoStorage;

/// Build a `PhotoGcConfig` from environment variables.
pub fn gc_config_from_env() -> PhotoGcConfig {
    let enabled = std::env::var("PHOTO_GC_ENABLED")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(true);

    let interval_secs = std::env::var("PHOTO_GC_INTERVAL_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(3600);

    let max_age_secs = std::env::var("PHOTO_GC_MAX_AGE_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(86400);

    let batch_size = std::env::var("PHOTO_GC_BATCH_SIZE")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(1000);

    let dry_run = std::env::var("PHOTO_GC_DRY_RUN")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(false);

    PhotoGcConfig {
        enabled,
        interval_secs,
        max_age_secs,
        batch_size,
        dry_run,
    }
}

/// Run a single GC sweep cycle.
///
/// 1. Acquire Postgres advisory lock (id `0x50484F54_4F5F4743` = "PHOTO_GC").
/// 2. List Garage objects via `PhotoStorage::list`.
/// 3. List known photo_ids via `PhotoRepository::list_known_ids`.
/// 4. Compute orphans (Garage ids not in known ids).
/// 5. Filter by age gate (`max_age_secs`).
/// 6. Delete (unless dry_run).
/// 7. Write history row to `projection_photo_gc_run`.
pub async fn run_gc_sweep(
    pool: &PgPool,
    storage: &OpenDalPhotoStorage,
    repo: &PhotoRepositoryImpl,
    config: &PhotoGcConfig,
) -> Result<()> {
    if !config.enabled {
        info!("Photo GC is disabled — skipping sweep");
        return Ok(());
    }

    let started_at = Utc::now();

    // 1. Advisory lock.
    let lock_acquired: Option<bool> =
        sqlx::query_scalar("SELECT pg_try_advisory_lock(5784960944884893507)")
            .fetch_one(pool)
            .await?;

    if lock_acquired != Some(true) {
        info!("Photo GC advisory lock not acquired — another sweep in progress");
        return Ok(());
    }

    let result = try_run_sweep(pool, storage, repo, config, started_at).await;

    // Release the advisory lock.
    let _: () = sqlx::query_scalar("SELECT pg_advisory_unlock(5784960944884893507)")
        .fetch_one(pool)
        .await
        .unwrap_or_default();

    result
}

async fn try_run_sweep(
    pool: &PgPool,
    storage: &OpenDalPhotoStorage,
    repo: &PhotoRepositoryImpl,
    config: &PhotoGcConfig,
    started_at: DateTime<Utc>,
) -> Result<()> {
    // 2. List Garage objects.
    let garage_ids = storage.list().await?;
    let scanned = garage_ids.len() as i64;

    // 3. List known photo_ids from projection.
    let known_ids = repo.list_known_ids().await?;
    let known_set: std::collections::HashSet<_> = known_ids.into_iter().collect();

    // 4. Compute orphans.
    let orphans: Vec<_> = garage_ids
        .into_iter()
        .filter(|id| !known_set.contains(id))
        .collect();
    let orphans_found = orphans.len() as i64;

    info!(
        scanned = scanned,
        orphans_found = orphans_found,
        dry_run = config.dry_run,
        "Photo GC sweep completed listing phase"
    );

    // 5-6. Filter by age gate and batch size, then delete.
    let mut orphans_deleted: i64 = 0;
    let max_age = chrono::Duration::seconds(config.max_age_secs as i64);

    for photo_id in orphans.iter().take(config.batch_size as usize) {
        // Check the age of the original variant's `stored_at` metadata.
        match storage
            .fetch_stored_at(*photo_id, PhotoVariant::Original)
            .await?
        {
            Some(stored_at) => {
                let age = started_at - stored_at;
                if age < max_age {
                    // Too young — skip deletion.
                    info!(
                        photo_id = %photo_id.0,
                        age_secs = ?age.num_seconds(),
                        max_age_secs = config.max_age_secs,
                        "Orphan is too young for deletion"
                    );
                    continue;
                }
            }
            None => {
                // No stored_at metadata — treat as too young (pre-existing
                // objects stored before this feature was added).
                warn!(
                    photo_id = %photo_id.0,
                    "No stored_at metadata for orphan, treating as too young"
                );
                continue;
            }
        }

        if !config.dry_run {
            storage.delete_all(*photo_id).await?;
            orphans_deleted += 1;
        }
    }

    // 7. Write history row.
    let run_id = Uuid::now_v7();
    let finished_at = Utc::now();

    sqlx::query(
        r#"
        INSERT INTO projection_photo_gc_run
            (run_id, started_at, finished_at, scanned, orphans_found, orphans_deleted, dry_run)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        "#,
    )
    .bind(run_id)
    .bind(started_at)
    .bind(finished_at)
    .bind(scanned)
    .bind(orphans_found)
    .bind(orphans_deleted)
    .bind(config.dry_run)
    .execute(pool)
    .await?;

    info!(
        run_id = %run_id,
        scanned,
        orphans_found,
        orphans_deleted,
        dry_run = config.dry_run,
        "Photo GC sweep completed"
    );

    Ok(())
}

/// Spawn a background GC scheduler task.
///
/// Reads config from env at startup, loops on the configured interval,
/// and runs a single sweep per tick. The task exits if the interval is 0
/// or GC is disabled at startup (env changes mid-flight are ignored in v1).
pub fn spawn_gc_scheduler(pool: PgPool, storage: OpenDalPhotoStorage, repo: PhotoRepositoryImpl) {
    let config = gc_config_from_env();

    if !config.enabled {
        info!("Photo GC is disabled — not spawning scheduler");
        return;
    }

    let interval = Duration::from_secs(config.interval_secs);
    if interval.is_zero() {
        warn!("PHOTO_GC_INTERVAL_SECS is 0 — not spawning scheduler");
        return;
    }

    tokio::spawn(async move {
        loop {
            tokio::time::sleep(interval).await;

            if let Err(e) = run_gc_sweep(&pool, &storage, &repo, &config).await {
                error!(error = %e, "Photo GC sweep failed");
            }
        }
    });
}
