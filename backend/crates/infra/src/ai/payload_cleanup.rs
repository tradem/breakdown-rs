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

use super::preview_store::{AiDocumentStore, AiPreviewStore};

fn is_not_found(err: &DomainError) -> bool {
    matches!(err, DomainError::NotFound(_))
}

/// Terminal jobs whose payloads may be swept, oldest first.
///
/// `failed` is deliberately **excluded** (issue #181). It is the *retryable*
/// state: a job sits there with a `next_attempt_at` backoff and is claimed
/// again once it is due. Sweeping `failed` rows — which the pre-#181 query did
/// — deleted the source document of a job that was still scheduled to run, so
/// the retry could only fail again, this time with the payload genuinely gone.
///
/// The exclusion is unconditional, **not** `retries >= max_retries`. That
/// refinement looks safe and is not: the claim predicates
/// (`claim_next`/`claim_next_kind` and their reconciling variants) match
/// `status = 'failed' AND (next_attempt_at IS NULL OR next_attempt_at <=
/// now())` and never consult `retries`. A `failed` row with an exhausted
/// budget is therefore still claimable, and sweeping it would reintroduce the
/// exact bug this predicate exists to fix.
///
/// Nothing leaks as a result. `mark_failed` resolves
/// `WHEN retryable AND retries + 1 < max_retries THEN 'failed' ELSE
/// 'dead_letter'`, so a job that runs out of budget is dead-lettered in the
/// same statement and *is* swept. A `failed` row is by construction one that
/// still has a future.
///
/// `payload_unavailable` jobs have no payload left to protect, so they are
/// swept like any other terminal job (the delete is a no-op for the missing
/// blob and still removes the sibling that survived).
///
/// # Why the anti-join (issue #206)
///
/// Retention alone is not a progress condition. Without the
/// `ai_payload_cleanup` marks this query returned the *same* oldest
/// `batch_size` rows on every run: their deletions are idempotent, so nothing
/// broke, but the sweep re-paid the S3 round-trips forever, re-counted the
/// same deletions into every history row, and never advanced past the `LIMIT`
/// — so a job behind that parked head could outlive its retention window
/// indefinitely. The anti-join makes each successful sweep shrink the
/// candidate set, which is what turns `LIMIT` into a rate limit rather than a
/// permanent horizon.
///
/// The two payloads are tracked independently: a sweep that deleted the source
/// but hit a 503 on the preview comes back for the preview only. A job whose
/// `preview_handle` is NULL never had one, so only the source is owed — and it
/// can never acquire one later, because `preview_handle` is written solely by
/// `mark_succeeded`, which requires a `running` claim that no terminal status
/// can return to.
///
/// The `pending` derived table exists only so the two `NOT EXISTS` probes are
/// written once instead of duplicated between the select list and the filter;
/// Postgres still walks `idx_ai_import_job_retention` in `updated_at` order
/// and stops at the first `$2` matches.
const TERMINAL_JOBS_SQL: &str = r#"
    SELECT id, source_handle, preview_handle, source_pending, preview_pending
    FROM (
        SELECT job.id,
               job.source_handle,
               job.preview_handle,
               job.updated_at,
               NOT EXISTS (
                   SELECT 1
                   FROM ai_import.ai_payload_cleanup done
                   WHERE done.job_id = job.id
                     AND done.payload_kind = 'source'
               ) AS source_pending,
               (job.preview_handle IS NOT NULL AND NOT EXISTS (
                   SELECT 1
                   FROM ai_import.ai_payload_cleanup done
                   WHERE done.job_id = job.id
                     AND done.payload_kind = 'preview'
               )) AS preview_pending
        FROM ai_import.ai_import_job job
        WHERE job.status IN ('succeeded', 'dead_letter', 'payload_unavailable')
          AND job.updated_at < $1
    ) pending
    WHERE source_pending OR preview_pending
    ORDER BY updated_at ASC
    LIMIT $2
"#;

/// Record the payloads this sweep finished with, so the next one skips them.
///
/// `ON CONFLICT DO NOTHING` rather than an upsert: the mark is a fact about
/// *that* handle being gone, and the first sweep to establish it is the one
/// worth keeping in the audit trail. The advisory lock already excludes a
/// concurrent sweep; this clause covers the residual case of a lock lost to a
/// connection reset mid-run.
///
/// Written with the *current* handle values, which is why the marks are keyed
/// per payload kind and not merely counted.
const MARK_CLEANED_SQL: &str = r#"
    INSERT INTO ai_import.ai_payload_cleanup (job_id, payload_kind, handle, run_id)
    SELECT job_id, payload_kind, handle, $4
    FROM UNNEST($1::uuid[], $2::text[], $3::text[])
        AS marks(job_id, payload_kind, handle)
    ON CONFLICT (job_id, payload_kind) DO NOTHING
"#;

/// Payload kinds, matching the `payload_kind` CHECK constraint.
const KIND_SOURCE: &str = "source";
const KIND_PREVIEW: &str = "preview";

/// Completion marks accumulated over one sweep, flushed in a single statement.
///
/// Struct-of-arrays because that is the shape `UNNEST` consumes; keeping the
/// three vectors behind one type is what guarantees they stay the same length
/// (every push goes through [`Self::push`]), since `UNNEST` would silently
/// pad a short column with NULLs and violate the NOT NULL constraints.
#[derive(Default)]
struct CleanupMarks {
    job_ids: Vec<Uuid>,
    kinds: Vec<String>,
    handles: Vec<String>,
}

impl CleanupMarks {
    fn push(&mut self, job_id: Uuid, kind: &str, handle: String) {
        self.job_ids.push(job_id);
        self.kinds.push(kind.to_owned());
        self.handles.push(handle);
    }

    fn is_empty(&self) -> bool {
        self.job_ids.is_empty()
    }

    fn len(&self) -> usize {
        self.job_ids.len()
    }

    /// Persist the marks. A failure here is fatal to the sweep's *progress*
    /// guarantee — the deletions already happened, so losing the marks means
    /// the next run repeats them — hence it is propagated rather than logged.
    async fn flush(&self, pool: &PgPool, run_id: Uuid) -> Result<(), DomainError> {
        if self.is_empty() {
            return Ok(());
        }
        sqlx::query(MARK_CLEANED_SQL)
            .bind(&self.job_ids)
            .bind(&self.kinds)
            .bind(&self.handles)
            .bind(run_id)
            .execute(pool)
            .await
            .map_err(|e| {
                DomainError::ServiceUnavailable(format!(
                    "Failed to persist AI payload cleanup marks: {e}"
                ))
            })?;
        Ok(())
    }
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
/// 2. Query terminal-state jobs older than the grace period whose payloads are
///    not already marked cleaned (see [`TERMINAL_JOBS_SQL`] for what "terminal"
///    excludes and why the marks exist).
/// 3. Delete the still-owed source and preview payloads from Garage.
/// 4. Log actions (respect dry_run).
/// 5. Record completion marks in `ai_payload_cleanup` so the next sweep
///    advances instead of re-selecting the same head of the queue.
/// 6. Write history row to `projection_ai_payload_gc_run`.
pub async fn run_gc_sweep<S>(pool: &PgPool, storage: &S, config: &AiPayloadGcConfig) -> Result<()>
where
    S: AiPreviewStore + AiDocumentStore + ?Sized,
{
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
async fn try_run_sweep<S>(
    pool: &PgPool,
    storage: &S,
    config: &AiPayloadGcConfig,
    started_at: DateTime<Utc>,
) -> Result<()>
where
    S: AiPreviewStore + AiDocumentStore + ?Sized,
{
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

    let rows: Vec<sqlx::postgres::PgRow> = sqlx::query(TERMINAL_JOBS_SQL)
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
    let mut marks = CleanupMarks::default();

    // Generated before the loop because the marks reference it: a completion
    // mark names the sweep that produced it, which is the whole audit value of
    // keeping the run history and the marks in the same schema.
    let run_id = Uuid::now_v7();

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
        let source_pending: bool = row.try_get("source_pending").map_err(|e| {
            DomainError::ServiceUnavailable(format!("Failed to get source_pending: {}", e))
        })?;
        let preview_pending: bool = row.try_get("preview_pending").map_err(|e| {
            DomainError::ServiceUnavailable(format!("Failed to get preview_pending: {}", e))
        })?;

        // A row can be selected because only *one* of its payloads is still
        // owed; re-deleting the other would be a harmless no-op but would
        // inflate the counters, which is half of what issue #206 is about.
        if source_pending {
            match delete_payload(
                storage,
                PayloadKind::Source,
                job_id,
                &source_handle,
                config.dry_run,
            )
            .await
            {
                PayloadOutcome::Removed => {
                    source_deleted += 1;
                    marks.push(job_id, KIND_SOURCE, source_handle.clone());
                }
                PayloadOutcome::WouldRemove => source_deleted += 1,
                PayloadOutcome::Failed(e) => {
                    if first_error.is_none() {
                        first_error = Some(e);
                    }
                    errors += 1;
                }
            }
        }

        // `preview_pending` is already false when the job never had a preview,
        // so the handle is present whenever the flag is set. Matching on the
        // Option rather than unwrapping keeps that an invariant the type
        // system enforces instead of a panic waiting for a schema change.
        if let (true, Some(preview)) = (preview_pending, preview_handle) {
            match delete_payload(
                storage,
                PayloadKind::Preview,
                job_id,
                &preview,
                config.dry_run,
            )
            .await
            {
                PayloadOutcome::Removed => {
                    preview_deleted += 1;
                    marks.push(job_id, KIND_PREVIEW, preview);
                }
                PayloadOutcome::WouldRemove => preview_deleted += 1,
                PayloadOutcome::Failed(e) => {
                    if first_error.is_none() {
                        first_error = Some(e);
                    }
                    errors += 1;
                }
            }
        }
    }

    // Flush before the history row, and before the early return on
    // `first_error`: the deletions have already happened, so a mark that is
    // not persisted is a payload this sweep will pay for again. A partial
    // batch (some payloads deleted, one 503) must still record what succeeded.
    let marked = marks.len();
    marks.flush(pool, run_id).await?;

    // Write history row
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
        marked,
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

/// Which of a job's two payloads a deletion targets.
#[derive(Clone, Copy)]
enum PayloadKind {
    Source,
    Preview,
}

impl PayloadKind {
    fn field(self) -> &'static str {
        match self {
            Self::Source => "source_handle",
            Self::Preview => "preview_handle",
        }
    }

    fn noun(self) -> &'static str {
        match self {
            Self::Source => "source document",
            Self::Preview => "preview payload",
        }
    }
}

/// What one payload deletion attempt established.
///
/// `Removed` and `WouldRemove` are separated because only the former may be
/// marked: a dry run deletes nothing, so persisting a mark for it would hide
/// the payload from every future *real* sweep — turning the observation mode
/// into a silent leak of exactly the objects it was meant to report.
enum PayloadOutcome {
    Removed,
    WouldRemove,
    Failed(DomainError),
}

/// Delete one payload, mapping the storage result onto the sweep's outcome.
///
/// A not-found result counts as `Removed`: the goal state (the object is gone)
/// holds, and marking it is what stops the sweep from re-checking an object
/// that will never come back — a terminal job cannot be re-claimed, so no
/// later write can recreate its payloads.
async fn delete_payload<S>(
    storage: &S,
    kind: PayloadKind,
    job_id: Uuid,
    handle: &str,
    dry_run: bool,
) -> PayloadOutcome
where
    S: AiPreviewStore + AiDocumentStore + ?Sized,
{
    if dry_run {
        info!(
            job_id = %job_id,
            handle = %handle,
            payload = kind.field(),
            dry_run = true,
            "Would delete AI {}",
            kind.noun()
        );
        return PayloadOutcome::WouldRemove;
    }

    let result = match kind {
        PayloadKind::Source => storage.delete_source(handle).await,
        PayloadKind::Preview => storage.delete(handle).await,
    };

    match result {
        Ok(()) => PayloadOutcome::Removed,
        Err(ref e) if is_not_found(e) => PayloadOutcome::Removed,
        Err(e) => {
            warn!(
                job_id = %job_id,
                handle = %handle,
                payload = kind.field(),
                error = %e,
                "Failed to delete AI {}",
                kind.noun()
            );
            PayloadOutcome::Failed(e)
        }
    }
}

/// Spawn a background AI payload GC scheduler task.
///
/// Reads config from env at startup, loops on the configured interval,
/// and runs a single sweep per tick. The task exits if the interval is 0
/// or GC is disabled at startup (env changes mid-flight are ignored in v1).
pub fn spawn_gc_scheduler<S>(pool: PgPool, storage: S)
where
    S: AiPreviewStore + AiDocumentStore + 'static,
{
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
    use super::*;

    /// Verify the GC config defaults by reading env vars in a known state.
    ///
    /// `std::env::remove_var` is `unsafe` (it can trigger a data race with
    /// concurrent reads), so each key is cleared inside an `unsafe` block.
    /// The loop is single-threaded and runs before any other test logic, so
    /// no concurrent access is possible.
    #[test]
    #[allow(unsafe_code)] // std::env::remove_var is unsafe; test-only, single-threaded
    fn gc_config_defaults_are_sensible() {
        let vars = [
            "AI_PAYLOAD_GC_ENABLED",
            "AI_PAYLOAD_GC_INTERVAL_SECS",
            "AI_PAYLOAD_GC_MAX_AGE_SECS",
            "AI_PAYLOAD_GC_BATCH_SIZE",
            "AI_PAYLOAD_GC_DRY_RUN",
        ];

        for key in &vars {
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

    /// `UNNEST` pads a short column with NULLs rather than erroring, which
    /// would hit the NOT NULL constraints at INSERT time with an opaque
    /// message. The three vectors must therefore advance together — which is
    /// the only reason `push` exists instead of three public fields.
    #[test]
    fn cleanup_marks_columns_stay_aligned() {
        let mut marks = CleanupMarks::default();
        assert!(marks.is_empty());

        marks.push(Uuid::now_v7(), KIND_SOURCE, "ai-import/a/source".to_owned());
        marks.push(
            Uuid::now_v7(),
            KIND_PREVIEW,
            "ai-import/b/preview".to_owned(),
        );

        assert!(!marks.is_empty());
        assert_eq!(marks.len(), 2);
        assert_eq!(marks.kinds.len(), marks.job_ids.len());
        assert_eq!(marks.handles.len(), marks.job_ids.len());
        assert_eq!(marks.kinds, vec![KIND_SOURCE, KIND_PREVIEW]);
    }

    /// The two kinds must stay distinguishable in the log record. This is the
    /// only signal an operator triaging a partial sweep has for *which* of a
    /// job's two payloads failed — and since the sweep deliberately does not
    /// mark a failed deletion, that is also the only way to tell a retry from
    /// a genuinely stuck object.
    #[test]
    fn payload_kinds_are_distinguishable_in_logs() {
        for kind in [PayloadKind::Source, PayloadKind::Preview] {
            assert!(!kind.field().is_empty());
            assert!(!kind.noun().is_empty());
        }
        assert_ne!(PayloadKind::Source.field(), PayloadKind::Preview.field());
        assert_ne!(PayloadKind::Source.noun(), PayloadKind::Preview.noun());
        // The field name must be the column the handle came from, so a log
        // line can be traced back to the row that produced it.
        assert_eq!(PayloadKind::Source.field(), "source_handle");
        assert_eq!(PayloadKind::Preview.field(), "preview_handle");
    }

    /// The kind strings are bound into `payload_kind`, which carries a CHECK
    /// constraint. A drift between the two would not fail to compile — it
    /// would fail at runtime, mid-sweep, after the deletions already happened
    /// and with the marks then lost.
    #[test]
    fn payload_kind_constants_match_the_check_constraint() {
        assert_eq!(KIND_SOURCE, "source");
        assert_eq!(KIND_PREVIEW, "preview");

        let migration =
            include_str!("../../migrations/20260813000001_ai_payload_cleanup_state.up.sql");
        assert!(
            migration.contains(&format!("'{KIND_SOURCE}', '{KIND_PREVIEW}'")),
            "payload_kind CHECK constraint must enumerate exactly the kinds the adapter writes"
        );
    }

    /// The anti-join is the entire fix for issue #206; a refactor that drops
    /// it restores the re-processing bug while every existing test still
    /// passes (deletions are idempotent, so nothing observably breaks until
    /// production starves a job behind the `LIMIT`).
    #[test]
    fn terminal_jobs_query_excludes_already_cleaned_payloads() {
        assert!(
            TERMINAL_JOBS_SQL.contains("ai_import.ai_payload_cleanup"),
            "the sweep must anti-join the completion marks"
        );
        assert!(
            TERMINAL_JOBS_SQL.contains("WHERE source_pending OR preview_pending"),
            "a job with both payloads already cleaned must not be selected"
        );
        assert!(
            !TERMINAL_JOBS_SQL.contains("'failed'"),
            "`failed` is the retryable state and must never be swept (issue #181)"
        );
    }

    /// A dry run must leave no trace in the marks table. Persisting one would
    /// convert the observation mode into a permanent leak: the payload is
    /// still in Garage, but every future real sweep skips it.
    #[tokio::test]
    async fn dry_run_outcome_is_not_markable() {
        // The in-memory store stands in for any backend: the dry-run branch
        // returns before reaching it at all, which is the property asserted.
        let storage = super::super::preview_store::MemoryAiPreviewStore::default();

        let outcome = delete_payload(
            &storage,
            PayloadKind::Source,
            Uuid::now_v7(),
            "ai-import/x/source",
            true,
        )
        .await;

        assert!(
            matches!(outcome, PayloadOutcome::WouldRemove),
            "a dry run must report a distinct outcome that the caller never marks"
        );
    }
}
