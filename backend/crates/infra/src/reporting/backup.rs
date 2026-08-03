// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: grok-4.5 (opencode-go)

//! Idempotent staging-then-external report backup worker.
//!
//! Pipeline (ADR-022 D6):
//! 1. claim job
//! 2. authorized-by-service-scope read of report data
//! 3. render via shared `ReportRenderer` (shared semaphore budget)
//! 4. write PDF + content digest to durable Garage staging
//! 5. upload the **exact** staged object to the external provider
//! 6. persist provider object ID/ETag + success
//! 7. apply staging retention
//!
//! On external failure: reuse the staged object (no re-query, no re-render).
//! Bounded retries → dead-letter. Periodic reconciliation for stranded claims.

use std::sync::Arc;
use std::time::Duration;

use breakdown_core::reporting::{
    ContentDigest, RenderPresentationContext, ReportArchiveStorage, ReportArtifactKey,
    ReportJobStatus, ReportKind, ReportRenderError, ReportRenderRequest, ReportRenderer,
};
use breakdown_core::scene_shoot::ports::SceneShootReportRepository;
use breakdown_core::shared::ShootingDayId;
use serde_json::json;
use tracing::{info, warn};
use uuid::Uuid;

use super::jobs::{PgReportArchivalQueue, ReportJobRow};
use super::storage::{external_key, sha256_hex, staging_key};

/// Configuration for the backup worker + reconciliation.
#[derive(Debug, Clone)]
pub struct BackupWorkerConfig {
    /// Worker poll interval when the queue is empty.
    pub poll_interval: Duration,
    /// Base backoff for the first retry.
    pub backoff_base: Duration,
    /// Maximum backoff between retries.
    pub backoff_max: Duration,
    /// How long a `claimed` row may sit before recon releases it.
    pub claim_stale_after: Duration,
    /// How often the reconciliation pass runs.
    pub recon_interval: Duration,
    /// Whether to delete staged objects after successful external upload.
    pub retain_staging_after_success: bool,
    /// Default IANA timezone for renders.
    pub default_timezone: String,
    /// Worker identity written into `claimed_by`.
    pub worker_id: String,
}

impl Default for BackupWorkerConfig {
    fn default() -> Self {
        Self {
            poll_interval: Duration::from_secs(env_u64("REPORT_BACKUP_POLL_SECS", 5)),
            backoff_base: Duration::from_secs(env_u64("REPORT_BACKUP_BACKOFF_BASE_SECS", 30)),
            backoff_max: Duration::from_secs(env_u64("REPORT_BACKUP_BACKOFF_MAX_SECS", 900)),
            claim_stale_after: Duration::from_secs(env_u64("REPORT_BACKUP_CLAIM_STALE_SECS", 900)),
            recon_interval: Duration::from_secs(env_u64("REPORT_BACKUP_RECON_SECS", 300)),
            retain_staging_after_success: env_bool("REPORT_BACKUP_RETAIN_STAGING", false),
            default_timezone: std::env::var("REPORT_BACKUP_TIMEZONE")
                .unwrap_or_else(|_| "Europe/Berlin".into()),
            worker_id: std::env::var("REPORT_BACKUP_WORKER_ID")
                .unwrap_or_else(|_| format!("worker-{}", Uuid::now_v7())),
        }
    }
}

fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn env_bool(key: &str, default: bool) -> bool {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

/// Data-loading callback used by the worker (keeps sqlx out of the render path).
///
/// Returns a JSON value suitable for `ReportRenderRequest.data`.
pub trait ReportDataLoader: Send + Sync {
    fn load(
        &self,
        kind: ReportKind,
        shooting_day_id: ShootingDayId,
    ) -> impl std::future::Future<Output = Result<serde_json::Value, String>> + Send;
}

/// Default loader backed by the concrete sqlx report repository.
///
/// Uses the concrete type (not the RPITIT port) so the returned future is `Send`
/// and can be spawned on the worker runtime.
pub struct SceneShootReportDataLoader {
    repo: crate::queries::SceneShootReportRepositoryImpl,
}

impl SceneShootReportDataLoader {
    pub fn new(repo: crate::queries::SceneShootReportRepositoryImpl) -> Self {
        Self { repo }
    }
}

impl ReportDataLoader for SceneShootReportDataLoader {
    async fn load(
        &self,
        kind: ReportKind,
        shooting_day_id: ShootingDayId,
    ) -> Result<serde_json::Value, String> {
        // Call through the port trait on the concrete impl — the concrete
        // future from sqlx is Send.
        use SceneShootReportRepository as _;
        match kind {
            ReportKind::Dispo => {
                let rows = self
                    .repo
                    .dispo_report(shooting_day_id)
                    .await
                    .map_err(|e| e.to_string())?;
                serde_json::to_value(rows).map_err(|e| e.to_string())
            }
            ReportKind::ShootDay => {
                let rows = self
                    .repo
                    .shoot_day_report(shooting_day_id)
                    .await
                    .map_err(|e| e.to_string())?;
                serde_json::to_value(rows).map_err(|e| e.to_string())
            }
            ReportKind::PlannedVsActual => {
                let report = self
                    .repo
                    .soll_ist_report(shooting_day_id)
                    .await
                    .map_err(|e| e.to_string())?;
                serde_json::to_value(report).map_err(|e| e.to_string())
            }
        }
    }
}

/// A no-op loader that returns empty JSON (tests).
pub struct EmptyReportDataLoader;

impl ReportDataLoader for EmptyReportDataLoader {
    async fn load(
        &self,
        _kind: ReportKind,
        _shooting_day_id: ShootingDayId,
    ) -> Result<serde_json::Value, String> {
        Ok(json!({ "rows": [] }))
    }
}

/// Backup worker holding staging + external storage and the shared renderer.
pub struct ReportBackupWorker<L: ReportDataLoader> {
    queue: PgReportArchivalQueue,
    staging: Arc<dyn ReportArchiveStorage>,
    external: Arc<dyn ReportArchiveStorage>,
    renderer: Arc<dyn ReportRenderer>,
    loader: Arc<L>,
    config: BackupWorkerConfig,
}

impl<L: ReportDataLoader + 'static> ReportBackupWorker<L> {
    pub fn new(
        queue: PgReportArchivalQueue,
        staging: Arc<dyn ReportArchiveStorage>,
        external: Arc<dyn ReportArchiveStorage>,
        renderer: Arc<dyn ReportRenderer>,
        loader: Arc<L>,
        config: BackupWorkerConfig,
    ) -> Self {
        Self {
            queue,
            staging,
            external,
            renderer,
            loader,
            config,
        }
    }

    /// Run one claim → process cycle. Returns `true` if a job was processed.
    pub async fn tick(&self) -> bool {
        match self.queue.claim_next(&self.config.worker_id).await {
            Ok(Some(job)) => {
                if let Err(e) = self.process_job(job).await {
                    // process_job records failure itself; this is a last-resort log.
                    warn!(error = %e, "report backup job processing failed");
                }
                true
            }
            Ok(None) => false,
            Err(e) => {
                warn!(error = %e, "report backup claim failed");
                false
            }
        }
    }

    /// Process a single claimed job through the staging-then-external pipeline.
    pub async fn process_job(&self, job: ReportJobRow) -> Result<(), String> {
        info!(
            job_id = %job.id,
            kind = %job.kind,
            day = %job.shooting_day_id.0,
            status = job.status.as_str(),
            "processing report archival job"
        );

        // --- 1. Ensure we have staged bytes (render only if not already staged) ---
        let (staged_key, digest) = match (&job.staged_handle, &job.content_digest) {
            (Some(handle), Some(digest_hex)) => {
                // Reuse staged object — NO re-query, NO re-render.
                let key = ReportArtifactKey::new(handle.clone()).map_err(|e| e.to_string())?;
                let digest = ContentDigest::new(digest_hex.clone()).map_err(|e| e.to_string())?;
                // Verify digest still matches.
                let art = self.staging.fetch(&key).await.map_err(|e| e.to_string())?;
                let actual = sha256_hex(&art.bytes);
                if actual.as_str() != digest.as_str() {
                    if let Err(e) = self
                        .queue
                        .mark_terminal_failure(job.id, "staged digest mismatch")
                        .await
                    {
                        warn!(job_id = %job.id, error = %e, "failed to record terminal failure");
                    }
                    return Err("staged digest mismatch".into());
                }
                (key, digest)
            }
            _ => {
                // Fresh render path.
                let data = match self.loader.load(job.kind, job.shooting_day_id).await {
                    Ok(d) => d,
                    Err(e) => {
                        if let Err(err) = self
                            .queue
                            .mark_terminal_failure(job.id, &format!("data load failed: {e}"))
                            .await
                        {
                            warn!(job_id = %job.id, error = %err, "failed to record terminal failure");
                        }
                        return Err(format!("data load failed: {e}"));
                    }
                };

                let req = ReportRenderRequest {
                    kind: job.kind,
                    context: RenderPresentationContext {
                        locale: job.locale.clone(),
                        timezone: self.config.default_timezone.clone(),
                        template_version: job.template_version.clone(),
                    },
                    data,
                };

                let rendered = match self.renderer.render(req).await {
                    Ok(r) => r,
                    Err(e) => {
                        // Render failures (bounds, timeout, compiler) are terminal —
                        // do not stage partial bytes.
                        let summary = render_error_summary(&e);
                        if let Err(err) = self.queue.mark_terminal_failure(job.id, &summary).await {
                            warn!(job_id = %job.id, error = %err, "failed to record terminal failure");
                        }
                        return Err(summary);
                    }
                };

                let digest = sha256_hex(&rendered.pdf_bytes);
                let key = staging_key(
                    job.shooting_day_id.0,
                    &job.kind.to_string(),
                    job.locale.as_str(),
                    &job.template_version,
                    &digest,
                )
                .map_err(|e| e.to_string())?;

                self.staging
                    .put(&key, &rendered.pdf_bytes, rendered.content_type, &digest)
                    .await
                    .map_err(|e| {
                        // Staging failure is retryable.
                        e.to_string()
                    })?;

                if let Err(e) = self
                    .queue
                    .mark_staged(job.id, key.as_str(), digest.as_str())
                    .await
                {
                    return Err(e.to_string());
                }
                (key, digest)
            }
        };

        // --- 2. Upload exact staged object to external provider ---
        if let Err(e) = self.queue.mark_uploading(job.id).await {
            return Err(e.to_string());
        }

        let staged = match self.staging.fetch(&staged_key).await {
            Ok(a) => a,
            Err(e) => {
                self.fail_retryable(&job, &e.to_string()).await;
                return Err(e.to_string());
            }
        };

        // Digest verification before external upload.
        let actual = sha256_hex(&staged.bytes);
        if actual.as_str() != digest.as_str() {
            if let Err(e) = self
                .queue
                .mark_terminal_failure(job.id, "digest mismatch before external upload")
                .await
            {
                warn!(job_id = %job.id, error = %e, "failed to record terminal failure");
            }
            return Err("digest mismatch before external upload".into());
        }

        let dest = external_key(
            job.shooting_day_id.0,
            &job.kind.to_string(),
            job.locale.as_str(),
            &job.template_version,
        )
        .map_err(|e| e.to_string())?;

        if let Err(e) = self
            .external
            .put(&dest, &staged.bytes, &staged.content_type, &digest)
            .await
        {
            self.fail_retryable(&job, &e.to_string()).await;
            return Err(e.to_string());
        }

        // --- 3. Persist provider outcome BEFORE staging retention ---
        if let Err(e) = self
            .queue
            .mark_succeeded(job.id, dest.as_str(), Some(digest.as_str()))
            .await
        {
            return Err(e.to_string());
        }

        // --- 4. Staging retention ---
        if !self.config.retain_staging_after_success {
            if let Err(e) = self.staging.delete(&staged_key).await {
                // Non-fatal: recon will clean up later.
                warn!(job_id = %job.id, error = %e, "staging delete after success failed");
            } else if let Err(e) = self.queue.clear_staged_handle(job.id).await {
                warn!(job_id = %job.id, error = %e, "failed to clear staged handle");
            }
        }

        info!(job_id = %job.id, dest = %dest, "report archival succeeded");
        Ok(())
    }

    async fn fail_retryable(&self, job: &ReportJobRow, summary: &str) {
        let backoff = compute_backoff(
            job.retries,
            self.config.backoff_base,
            self.config.backoff_max,
        );
        match self.queue.mark_failure(job.id, summary, backoff).await {
            Ok(ReportJobStatus::DeadLetter) => {
                warn!(job_id = %job.id, "report archival dead-lettered");
            }
            Ok(_) => {
                info!(job_id = %job.id, ?backoff, "report archival scheduled for retry");
            }
            Err(e) => {
                warn!(job_id = %job.id, error = %e, "failed to record job failure");
            }
        }
    }

    /// Reconciliation: release stale claims; delete orphaned staging for succeeded jobs.
    pub async fn reconcile(&self) {
        match self
            .queue
            .list_stale_claims(self.config.claim_stale_after)
            .await
        {
            Ok(stale) => {
                for job in stale {
                    info!(job_id = %job.id, "releasing stale claim");
                    if let Err(e) = self.queue.release_stale_claim(job.id).await {
                        warn!(job_id = %job.id, error = %e, "failed to release stale claim");
                    }
                }
            }
            Err(e) => warn!(error = %e, "list_stale_claims failed"),
        }

        if !self.config.retain_staging_after_success {
            match self.queue.list_succeeded_with_staging().await {
                Ok(rows) => {
                    for job in rows {
                        if let Some(handle) = &job.staged_handle
                            && let Ok(key) = ReportArtifactKey::new(handle.clone())
                        {
                            if let Err(e) = self.staging.delete(&key).await {
                                // Keep the staged handle: the artifact may still
                                // exist in staging, and the handle is the only
                                // reference a later cleanup attempt can use.
                                warn!(
                                    job_id = %job.id,
                                    error = %e,
                                    "failed to delete staged artifact; keeping staged handle"
                                );
                            } else if let Err(e) = self.queue.clear_staged_handle(job.id).await {
                                warn!(job_id = %job.id, error = %e, "failed to clear staged handle");
                            }
                        }
                    }
                }
                Err(e) => warn!(error = %e, "list_succeeded_with_staging failed"),
            }
        }
    }
}

/// Exponential backoff with full jitter, capped at `max`.
pub fn compute_backoff(retries: i32, base: Duration, max: Duration) -> Duration {
    let exp = base
        .checked_mul(2u32.saturating_pow(retries.clamp(0, 16) as u32))
        .unwrap_or(max);
    let capped = exp.min(max);
    // Full jitter in [0, capped].
    let nanos = capped.as_nanos().max(1) as u64;
    let jitter = fastrand::u64(0..=nanos);
    Duration::from_nanos(jitter)
}

fn render_error_summary(err: &ReportRenderError) -> String {
    // Typed display is already free of PDF bytes.
    let s = err.to_string();
    s.chars().take(256).collect()
}

/// Spawn the backup worker loop + reconciliation loop.
pub fn spawn_backup_worker<L>(worker: Arc<ReportBackupWorker<L>>)
where
    L: ReportDataLoader + 'static,
{
    let poll = worker.clone();
    tokio::spawn(async move {
        loop {
            let worked = poll.tick().await;
            if !worked {
                tokio::time::sleep(poll.config.poll_interval).await;
            }
        }
    });

    let recon = worker;
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(recon.config.recon_interval).await;
            recon.reconcile().await;
        }
    });
}

/// Helper used by tests: process without needing a live claim.
#[cfg(test)]
pub mod test_support {
    use super::*;

    /// A fake renderer that returns fixed PDF bytes and counts calls.
    #[derive(Debug)]
    pub struct CountingRenderer {
        pub pdf: Vec<u8>,
        pub calls: std::sync::atomic::AtomicU64,
        pub fail: std::sync::atomic::AtomicBool,
    }

    impl CountingRenderer {
        pub fn new(pdf: Vec<u8>) -> Self {
            Self {
                pdf,
                calls: std::sync::atomic::AtomicU64::new(0),
                fail: std::sync::atomic::AtomicBool::new(false),
            }
        }

        pub fn call_count(&self) -> u64 {
            self.calls.load(std::sync::atomic::Ordering::SeqCst)
        }
    }

    #[async_trait::async_trait]
    impl ReportRenderer for CountingRenderer {
        async fn render(
            &self,
            req: ReportRenderRequest,
        ) -> Result<breakdown_core::reporting::ReportBytes, ReportRenderError> {
            self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            if self.fail.load(std::sync::atomic::Ordering::SeqCst) {
                return Err(ReportRenderError::CompilerFailure {
                    detail: "injected".into(),
                });
            }
            Ok(breakdown_core::reporting::ReportBytes {
                kind: req.kind,
                locale: req.context.locale,
                pdf_bytes: self.pdf.clone(),
                page_count: 1,
                content_type: "application/pdf",
                filename: "test.pdf".into(),
            })
        }
    }
}
