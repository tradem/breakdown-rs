// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: pi-agent (pi-coding-agent)

use std::time::Duration;

use anyhow::Result;
use breakdown_core::error::DomainError;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use tracing::{error, info, trace, warn};
use uuid::Uuid;

use super::payload_storage::OpenDalAiPayloadStorage;
use super::preview_store::{AiDocumentStore, AiPreviewStore};

fn is_not_found(err: &DomainError) -> bool {
    matches!(err, DomainError::NotFound(_))
}

/// Configuration for the AI payload cleanup worker.
#[derive(Debug, Clone)]
pub struct AiPayloadGcConfig {
    /// Whether the cleanup sweep is enabled at all.
    pub enabled: bool,
    /// Interval between sweep runs (seconds).
    pub interval_secs: u64,
    /// Only delete payloads for jobs older than this (seconds).
    pub max_age_secs: u64,
    /// Maximum number of terminal-state jobs to process per run.
    pub batch_size: u64,
    /// When true, log payloads but do not delete.
    pub dry_run: bool,
}

/// Build an `AiPayloadGcConfig` from environment variables.
pub fn gc_config_from_env() -> AiPayloadGcConfig {
    let enabled = std::env::var("AI_PAYLOAD_GC_ENABLED")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(true);

    let interval_secs = std::env::var("AI_PAYLOAD_GC_INTERVAL_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(3600);

    let max_age_secs = std::env::var("AI_PAYLOAD_GC_MAX_AGE_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(604800);

    let batch_size = std::env::var("AI_PAYLOAD_GC_BATCH_SIZE")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(1000);

    let dry_run = std::env::var("AI_PAYLOAD_GC_DRY_RUN")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(false);

    AiPayloadGcConfig {
        enabled,
        interval_secs,
        max_age_secs,
        batch_size,
        dry_run,
    }
}

/// Run a single AI payload cleanup sweep cycle.
///
/// 1. Acquire Postgres advisory lock (id `0x41495F5041594C4F_41445F4743` = "AI_PAY_AD_GC").
/// 2. Query terminal-state jobs (succeeded/failed/dead_letter) older than grace period.
/// 3. Delete source and preview payloads from Garage.
/// 4. Log actions (respect dry_run).
/// 5. Write history row to `projection_ai_payload_gc_run`.
pub async fn run_gc_sweep(
    pool: &PgPool,
    storage: &OpenDalAiPayloadStorage,
    config: &AiPayloadGcConfig,
) -> Result<()> {
    if !config.enabled {
        info!("AI payload GC is disabled — skipping sweep");
        return Ok(());
    }

    let started_at = Utc::now();

    // Advisory lock ID: "AI_PAY_AD_GC" as i64
    let lock_id: i64 = 4706751127065399628;

    // Acquire a dedicated connection for the advisory lock lifecycle.
    // pg_try_advisory_lock is session-scoped, so we must use the same
    // connection for both lock and unlock.
    let mut conn = pool.acquire().await.map_err(|e| {
        DomainError::ServiceUnavailable(format!("Failed to acquire connection for lock: {}", e))
    })?;

    let lock_acquired: Option<bool> = sqlx::query_scalar("SELECT pg_try_advisory_lock($1)")
        .bind(lock_id)
        .fetch_one(&mut *conn)
        .await
        .map_err(|e| {
            DomainError::ServiceUnavailable(format!("Failed to acquire advisory lock: {}", e))
        })?;

    if lock_acquired != Some(true) {
        info!("AI payload GC advisory lock not acquired — another sweep in progress");
        return Ok(());
    }

    let result = try_run_sweep(pool, storage, config, started_at).await;

    // Best-effort unlock on the same connection.
    let unlock_result: Result<Option<bool>, _> =
        sqlx::query_scalar("SELECT pg_advisory_unlock($1)")
            .bind(lock_id)
            .fetch_one(&mut *conn)
            .await;
    match unlock_result {
        Ok(Some(true)) => {
            trace!("Advisory lock released successfully");
        }
        Ok(Some(false)) => {
            warn!("Advisory lock was not held by this session");
        }
        Ok(None) => {
            warn!("Advisory unlock returned NULL");
        }
        Err(e) => {
            warn!(error = %e, "Failed to release advisory lock");
        }
    }

    result
}

/// Internal implementation of the sweep.
async fn try_run_sweep(
    pool: &PgPool,
    storage: &OpenDalAiPayloadStorage,
    config: &AiPayloadGcConfig,
    started_at: DateTime<Utc>,
) -> Result<()> {
    // Find terminal-state jobs older than grace period
    let max_age_secs = i64::try_from(config.max_age_secs).map_err(|_| {
        DomainError::ValidationError("AI_PAYLOAD_GC_MAX_AGE_SECS exceeds i64::MAX".into())
    })?;
    let batch_size = i64::try_from(config.batch_size).map_err(|_| {
        DomainError::ValidationError("AI_PAYLOAD_GC_BATCH_SIZE exceeds i64::MAX".into())
    })?;
    let grace_period = chrono::TimeDelta::try_seconds(max_age_secs).ok_or_else(|| {
        DomainError::ValidationError(format!(
            "AI_PAYLOAD_GC_MAX_AGE_SECS ({}) exceeds Chrono TimeDelta range",
            config.max_age_secs
        ))
    })?;
    let cutoff = started_at.checked_sub_signed(grace_period).ok_or_else(|| {
        DomainError::ValidationError(
            "AI_PAYLOAD_GC_MAX_AGE_SECS produces cutoff outside DateTime range".into(),
        )
    })?;

    let rows: Vec<sqlx::postgres::PgRow> = sqlx::query(
        r#"
        SELECT id, source_handle, preview_handle, updated_at
        FROM ai_import.ai_import_job
        WHERE status IN ('succeeded', 'failed', 'dead_letter')
          AND updated_at < $1
        ORDER BY updated_at ASC
        LIMIT $2
        "#,
    )
    .bind(cutoff)
    .bind(batch_size)
    .fetch_all(pool)
    .await
    .map_err(|e| {
        DomainError::ServiceUnavailable(format!("Failed to query terminal jobs: {}", e))
    })?;

    let scanned = rows.len() as i64;

    info!(
        scanned = scanned,
        cutoff = %cutoff,
        dry_run = config.dry_run,
        "AI payload GC sweep completed listing phase"
    );

    let mut source_deleted: i64 = 0;
    let mut preview_deleted: i64 = 0;
    let mut errors: i64 = 0;
    let mut first_error: Option<DomainError> = None;

    for row in rows {
        let job_id: Uuid = row
            .try_get("id")
            .map_err(|e| DomainError::ServiceUnavailable(format!("Failed to get job id: {}", e)))?;
        let source_handle: String = row.try_get("source_handle").map_err(|e| {
            DomainError::ServiceUnavailable(format!("Failed to get source_handle: {}", e))
        })?;
        let preview_handle: Option<String> = row.try_get("preview_handle").map_err(|e| {
            DomainError::ServiceUnavailable(format!("Failed to get preview_handle: {}", e))
        })?;

        // Delete source payload
        if !config.dry_run {
            match storage.delete_source(&source_handle).await {
                Ok(()) => source_deleted += 1,
                Err(ref e) if is_not_found(e) => {
                    // Already deleted, treat as success
                    source_deleted += 1;
                }
                Err(e) => {
                    warn!(
                        job_id = %job_id,
                        source_handle = %source_handle,
                        error = %e,
                        "Failed to delete AI source payload"
                    );
                    if first_error.is_none() {
                        first_error = Some(e);
                    }
                    errors += 1;
                }
            }
        } else {
            info!(
                job_id = %job_id,
                source_handle = %source_handle,
                dry_run = true,
                "Would delete AI source payload"
            );
            source_deleted += 1;
        }

        // Delete preview payload if present
        if let Some(preview) = preview_handle {
            if !config.dry_run {
                match storage.delete(&preview).await {
                    Ok(()) => preview_deleted += 1,
                    Err(ref e) if is_not_found(e) => {
                        // Already deleted, treat as success
                        preview_deleted += 1;
                    }
                    Err(e) => {
                        warn!(
                            job_id = %job_id,
                            preview_handle = %preview,
                            error = %e,
                            "Failed to delete AI preview payload"
                        );
                        if first_error.is_none() {
                            first_error = Some(e);
                        }
                        errors += 1;
                    }
                }
            } else {
                info!(
                    job_id = %job_id,
                    preview_handle = %preview,
                    dry_run = true,
                    "Would delete AI preview payload"
                );
                preview_deleted += 1;
            }
        }
    }

    // Write history row
    let run_id = Uuid::now_v7();
    let finished_at = Utc::now();

    sqlx::query(
        r#"
        INSERT INTO ai_import.projection_ai_payload_gc_run
            (run_id, started_at, finished_at, scanned, source_deleted, preview_deleted, errors, dry_run)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        "#,
    )
    .bind(run_id)
    .bind(started_at)
    .bind(finished_at)
    .bind(scanned)
    .bind(source_deleted)
    .bind(preview_deleted)
    .bind(errors)
    .bind(config.dry_run)
    .execute(pool)
    .await
    .map_err(|e| {
        DomainError::ServiceUnavailable(format!("Failed to write GC history: {}", e))
    })?;

    info!(
        run_id = %run_id,
        scanned,
        source_deleted,
        preview_deleted,
        errors,
        dry_run = config.dry_run,
        "AI payload GC sweep completed"
    );

    // Return the first deletion error so the scheduler detects the failure
    if let Some(e) = first_error {
        return Err(e.into());
    }

    Ok(())
}

/// Spawn a background AI payload GC scheduler task.
///
/// Reads config from env at startup, loops on the configured interval,
/// and runs a single sweep per tick. The task exits if the interval is 0
/// or GC is disabled at startup (env changes mid-flight are ignored in v1).
pub fn spawn_gc_scheduler(pool: PgPool, storage: OpenDalAiPayloadStorage) {
    let config = gc_config_from_env();

    if !config.enabled {
        info!("AI payload GC is disabled — not spawning scheduler");
        return;
    }

    let interval = Duration::from_secs(config.interval_secs);
    if interval.is_zero() {
        warn!("AI_PAYLOAD_GC_INTERVAL_SECS is 0 — not spawning scheduler");
        return;
    }

    tokio::spawn(async move {
        loop {
            tokio::time::sleep(interval).await;

            if let Err(e) = run_gc_sweep(&pool, &storage, &config).await {
                error!(error = %e, "AI payload GC sweep failed");
            }
        }
    });
}

#[cfg(test)]
mod tests {
    #![allow(unsafe_code)] // env::remove_var is unsafe; test-only, no concurrent access

    use super::*;

    #[test]
    fn gc_config_defaults_are_sensible() {
        // Clear env vars for deterministic test
        let vars = [
            "AI_PAYLOAD_GC_ENABLED",
            "AI_PAYLOAD_GC_INTERVAL_SECS",
            "AI_PAYLOAD_GC_MAX_AGE_SECS",
            "AI_PAYLOAD_GC_BATCH_SIZE",
            "AI_PAYLOAD_GC_DRY_RUN",
        ];

        for key in &vars {
            // SAFETY: test-only, no concurrent env access
            unsafe {
                std::env::remove_var(key);
            }
        }

        let config = gc_config_from_env();
        assert!(config.enabled);
        assert_eq!(config.interval_secs, 3600);
        assert_eq!(config.max_age_secs, 604800);
        assert_eq!(config.batch_size, 1000);
        assert!(!config.dry_run);
    }
}
