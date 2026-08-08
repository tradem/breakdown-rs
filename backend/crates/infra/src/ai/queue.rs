// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)

use std::time::Duration;

use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId, AiImportQueue,
    DocumentKind, JobStatus, Telemetry,
};
use breakdown_core::error::DomainError;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// Default claim lease. A worker that dies holds its job for at most this long
/// before another worker may reclaim it. Matches the report-archival stale
/// claim window (`REPORT_BACKUP_CLAIM_STALE_SECS`) so operators reason about
/// one recovery horizon.
const DEFAULT_LEASE_SECS: u64 = 900;
const MIN_LEASE_SECS: u64 = 30;
const MAX_LEASE_SECS: u64 = 86_400;

// The lease must outlive a normal job by a wide margin, otherwise a healthy
// worker's job would be reclaimed mid-flight and processed twice. The default
// request timeout ceiling is 3600s per LLM call, but a job is retried rather
// than duplicated on timeout, so a 30s floor is the safety net against a
// misconfigured near-zero lease.
const _LEASE_BOUNDS_INVARIANT: () =
    assert!(MIN_LEASE_SECS > 0 && MIN_LEASE_SECS <= DEFAULT_LEASE_SECS);
const _LEASE_RANGE_INVARIANT: () = assert!(DEFAULT_LEASE_SECS <= MAX_LEASE_SECS);

#[derive(Clone, Debug)]
pub struct PgAiImportQueue {
    pool: PgPool,
    lease: Duration,
}

impl PgAiImportQueue {
    /// Build a queue with the lease window from `AI_IMPORT_LEASE_SECS`
    /// (default 900s, clamped to 30..=86400).
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            lease: lease_from_env(),
        }
    }

    /// Override the claim lease window. Used by deployments that want a
    /// different recovery horizon and by tests that need a deterministic
    /// already-expired lease (`Duration::ZERO`).
    #[must_use]
    pub fn with_lease(mut self, lease: Duration) -> Self {
        self.lease = lease;
        self
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    /// The active claim lease window.
    pub const fn lease(&self) -> Duration {
        self.lease
    }

    fn lease_secs(&self) -> f64 {
        self.lease.as_secs_f64()
    }
}

fn lease_from_env() -> Duration {
    parse_lease(std::env::var("AI_IMPORT_LEASE_SECS").ok().as_deref())
}

/// Pure parser for the lease override so the clamping contract is testable
/// without mutating process-global environment state.
fn parse_lease(raw: Option<&str>) -> Duration {
    let secs = raw
        .and_then(|value| value.trim().parse::<u64>().ok())
        .filter(|value| (*value >= MIN_LEASE_SECS) && (*value <= MAX_LEASE_SECS))
        .unwrap_or(DEFAULT_LEASE_SECS);
    Duration::from_secs(secs)
}

#[async_trait::async_trait]
impl AiImportQueue for PgAiImportQueue {
    async fn enqueue(
        &self,
        request: AiImportEnqueueRequest,
    ) -> Result<AiImportEnqueueResult, DomainError> {
        // One statement does the insert-or-conflict and returns the row with an
        // `inserted` flag (`xmax = 0` is true only for a freshly inserted
        // tuple). A separate SELECT after the INSERT could miss a concurrently
        // committed row (RowNotFound -> spurious ServiceUnavailable) — see
        // review comment on the previous two-statement enqueue.
        let row = sqlx::query(
            r#"
            INSERT INTO ai_import.ai_import_job
                (id, user_id, document_kind, block_id, dedup_key, document_digest, source_handle)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (user_id, dedup_key) DO UPDATE
                SET dedup_key = EXCLUDED.dedup_key
            RETURNING id, (xmax = 0) AS inserted
            "#,
        )
        .bind(request.id.as_uuid())
        .bind(request.user_id.as_str())
        .bind(request.document_kind.as_str())
        .bind(request.block_id.map(|block_id| block_id.0))
        .bind(&request.dedup_key)
        .bind(&request.document_digest)
        .bind(&request.source_handle)
        .fetch_one(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let id = AiImportJobId::from_uuid(row.try_get::<Uuid, _>("id").map_err(map_sqlx_error)?);
        let inserted = row.try_get::<bool, _>("inserted").map_err(map_sqlx_error)?;
        if inserted {
            Ok(AiImportEnqueueResult::Enqueued(id))
        } else {
            Ok(AiImportEnqueueResult::Existing(id))
        }
    }

    /// Claim the next runnable job of any kind.
    ///
    /// Runnable means `pending`, a retryable `failed` job whose backoff is due,
    /// or a `running` job whose worker lease has expired (crash recovery,
    /// issue #177). The claim records the owning `worker_id` and a fresh lease
    /// deadline in the same statement as the status flip, so two workers can
    /// never both believe they own the job (`FOR UPDATE SKIP LOCKED` plus the
    /// unexpired-lease predicate).
    async fn claim_next(&self, worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
        let row = sqlx::query(
            r#"
            WITH next_job AS (
                SELECT id
                FROM ai_import.ai_import_job
                WHERE status = 'pending'
                   OR (status = 'failed' AND
                       (next_attempt_at IS NULL OR next_attempt_at <= now()))
                   OR (status = 'running' AND
                       lease_expires_at IS NOT NULL AND lease_expires_at <= now())
                ORDER BY created_at, id
                FOR UPDATE SKIP LOCKED
                LIMIT 1
            )
            UPDATE ai_import.ai_import_job AS job
            SET status = 'running',
                worker_id = $1,
                lease_expires_at = now() + make_interval(secs => $2),
                updated_at = now()
            FROM next_job
            WHERE job.id = next_job.id
            RETURNING job.*
            "#,
        )
        .bind(worker_id)
        .bind(self.lease_secs())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        row.map(map_job_row).transpose()
    }

    /// Kind-filtered variant of [`claim_next`](Self::claim_next) with identical
    /// lease semantics.
    async fn claim_next_kind(
        &self,
        worker_id: &str,
        kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError> {
        let row = sqlx::query(
            r#"
            WITH next_job AS (
                SELECT id
                FROM ai_import.ai_import_job
                WHERE document_kind = $1
                  AND (status = 'pending'
                   OR (status = 'failed' AND
                       (next_attempt_at IS NULL OR next_attempt_at <= now()))
                   OR (status = 'running' AND
                       lease_expires_at IS NOT NULL AND lease_expires_at <= now()))
                ORDER BY created_at, id
                FOR UPDATE SKIP LOCKED
                LIMIT 1
            )
            UPDATE ai_import.ai_import_job AS job
            SET status = 'running',
                worker_id = $2,
                lease_expires_at = now() + make_interval(secs => $3),
                updated_at = now()
            FROM next_job
            WHERE job.id = next_job.id
            RETURNING job.*
            "#,
        )
        .bind(kind.as_str())
        .bind(worker_id)
        .bind(self.lease_secs())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        row.map(map_job_row).transpose()
    }

    async fn get(&self, id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT *
            FROM ai_import.ai_import_job
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        row.map(map_job_row).transpose()
    }

    /// Re-affirm the `running` status and extend the current lease.
    ///
    /// Callers use this as a heartbeat for long jobs; it never changes
    /// ownership, so a worker that lost its lease does not silently steal the
    /// job back — the reclaiming worker's `worker_id` stays untouched.
    async fn mark_running(&self, id: AiImportJobId) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET status = 'running',
                lease_expires_at = now() + make_interval(secs => $2),
                updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .bind(self.lease_secs())
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn mark_succeeded(
        &self,
        id: AiImportJobId,
        preview_handle: &str,
    ) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET status = 'succeeded', preview_handle = $2,
                last_error = NULL, next_attempt_at = NULL,
                worker_id = NULL, lease_expires_at = NULL,
                updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .bind(preview_handle)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn mark_failed(
        &self,
        id: AiImportJobId,
        error_summary: &str,
        retryable: bool,
    ) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET retries = retries + 1,
                status = CASE
                    WHEN $3 AND retries + 1 < max_retries THEN 'failed'
                    ELSE 'dead_letter'
                END,
                last_error = LEFT($2, 1000),
                next_attempt_at = CASE
                    WHEN $3 AND retries + 1 < max_retries
                        -- Exponential backoff: 1min * 2^retries, capped at
                        -- ~5.3h after 8 retries, so a failing dependency is not
                        -- hammered at a fixed one-minute cadence.
                        THEN now() + LEAST(
                            interval '1 minute' * power(2, retries)::int,
                            interval '6 hours'
                        )
                    ELSE NULL
                END,
                -- A terminal or backing-off job holds no claim: releasing the
                -- lease here keeps `running` the only leased state, so the
                -- reclaim predicate can never resurrect a failed job early.
                worker_id = NULL,
                lease_expires_at = NULL,
                updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .bind(error_summary)
        .bind(retryable)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn record_telemetry(
        &self,
        id: AiImportJobId,
        telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET provider = $2, model = $3, chunk_count = $4,
                tokens_in = $5, tokens_out = $6, latency_total_ms = $7,
                accept_as_is = $8, edit_distance = $9, updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .bind(telemetry.provider.map(|provider| provider.as_str()))
        .bind(telemetry.model)
        .bind(i32::try_from(telemetry.chunk_count).map_err(|error| {
            DomainError::ValidationError(format!("AI chunk count exceeds database range: {error}"))
        })?)
        .bind(i64::try_from(telemetry.tokens_in).map_err(|error| {
            DomainError::ValidationError(format!(
                "AI input token count exceeds database range: {error}"
            ))
        })?)
        .bind(i64::try_from(telemetry.tokens_out).map_err(|error| {
            DomainError::ValidationError(format!(
                "AI output token count exceeds database range: {error}"
            ))
        })?)
        .bind(i64::try_from(telemetry.latency_total).map_err(|error| {
            DomainError::ValidationError(format!("AI latency exceeds database range: {error}"))
        })?)
        .bind(telemetry.apply_state.accept_as_is())
        .bind(
            telemetry
                .apply_state
                .edit_distance()
                .map(|distance| {
                    i32::try_from(distance).map_err(|error| {
                        DomainError::ValidationError(format!(
                            "AI edit distance exceeds database range: {error}"
                        ))
                    })
                })
                .transpose()?,
        )
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }
}

fn map_job_row(row: sqlx::postgres::PgRow) -> Result<AiImportJob, DomainError> {
    let kind = parse_document_kind(row.try_get("document_kind").map_err(map_sqlx_error)?)?;
    let status = parse_status(row.try_get("status").map_err(map_sqlx_error)?)?;
    let id: Uuid = row.try_get("id").map_err(map_sqlx_error)?;
    let user_id = row
        .try_get::<String, _>("user_id")
        .map_err(map_sqlx_error)?;
    let created_at: DateTime<Utc> = row.try_get("created_at").map_err(map_sqlx_error)?;
    let updated_at: DateTime<Utc> = row.try_get("updated_at").map_err(map_sqlx_error)?;
    Ok(AiImportJob {
        id: AiImportJobId::from_uuid(id),
        user_id: breakdown_core::shared::UserId::from_sub(user_id),
        document_kind: kind,
        block_id: row
            .try_get::<Option<Uuid>, _>("block_id")
            .map_err(map_sqlx_error)?
            .map(breakdown_core::shared::BlockId::from_uuid),
        dedup_key: row.try_get("dedup_key").map_err(map_sqlx_error)?,
        document_digest: row.try_get("document_digest").map_err(map_sqlx_error)?,
        source_handle: row.try_get("source_handle").map_err(map_sqlx_error)?,
        status,
        preview_handle: row.try_get("preview_handle").map_err(map_sqlx_error)?,
        last_error: row.try_get("last_error").map_err(map_sqlx_error)?,
        retries: row
            .try_get::<i32, _>("retries")
            .map_err(map_sqlx_error)?
            .max(0) as u32,
        max_retries: row
            .try_get::<i32, _>("max_retries")
            .map_err(map_sqlx_error)?
            .max(0) as u32,
        created_at,
        updated_at,
    })
}

fn parse_document_kind(value: String) -> Result<DocumentKind, DomainError> {
    match value.as_str() {
        "script" => Ok(DocumentKind::Script),
        "schedule" => Ok(DocumentKind::Schedule),
        other => Err(DomainError::ValidationError(format!(
            "unknown AI document kind {other}"
        ))),
    }
}

fn parse_status(value: String) -> Result<JobStatus, DomainError> {
    match value.as_str() {
        "pending" => Ok(JobStatus::Pending),
        "running" => Ok(JobStatus::Running),
        "succeeded" => Ok(JobStatus::Succeeded),
        "failed" => Ok(JobStatus::Failed),
        "dead_letter" => Ok(JobStatus::DeadLetter),
        other => Err(DomainError::ValidationError(format!(
            "unknown AI job status {other}"
        ))),
    }
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    // Log the raw error (with bound values) internally; the HTTP-facing message
    // must not leak SQL details or bound values (CWE-209).
    tracing::error!(%error, "AI import database error");
    DomainError::ServiceUnavailable("AI import database error".to_owned())
}

#[cfg(test)]
mod tests {
    use super::{
        DEFAULT_LEASE_SECS, Duration, MAX_LEASE_SECS, MIN_LEASE_SECS, PgAiImportQueue, parse_lease,
    };

    #[test]
    fn lease_override_is_accepted_within_bounds() {
        assert_eq!(parse_lease(Some("60")), Duration::from_secs(60));
        assert_eq!(
            parse_lease(Some(" 120 ")),
            Duration::from_secs(120),
            "surrounding whitespace must not defeat the override"
        );
    }

    #[test]
    fn lease_override_outside_bounds_falls_back_to_default() {
        let default = Duration::from_secs(DEFAULT_LEASE_SECS);
        // A near-zero lease would let a healthy worker's job be reclaimed
        // mid-flight; an absurd lease would make crash recovery useless.
        assert_eq!(
            parse_lease(Some(&(MIN_LEASE_SECS - 1).to_string())),
            default
        );
        assert_eq!(
            parse_lease(Some(&(MAX_LEASE_SECS + 1).to_string())),
            default
        );
        assert_eq!(parse_lease(Some("not-a-number")), default);
        assert_eq!(parse_lease(Some("")), default);
        assert_eq!(parse_lease(None), default);
    }

    // `connect_lazy` registers a pool worker and therefore needs a runtime,
    // even though no connection is established.
    #[tokio::test]
    async fn with_lease_overrides_the_configured_window() {
        // `PgAiImportQueue::new` needs a pool, so exercise the builder on a
        // lazily-connected pool: no I/O happens until a query is issued.
        let pool = sqlx::postgres::PgPoolOptions::new()
            .connect_lazy("postgres://user:pass@127.0.0.1:1/none");
        let Ok(pool) = pool else {
            // A malformed URL would be a test bug, not a queue bug; skip
            // rather than panic (no-panic rule applies to tests we author).
            return;
        };
        let queue = PgAiImportQueue::new(pool).with_lease(Duration::from_secs(5));
        assert_eq!(queue.lease(), Duration::from_secs(5));
    }
}
