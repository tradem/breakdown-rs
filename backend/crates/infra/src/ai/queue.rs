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

/// The one named unit the whole lease window is derived from.
///
/// It is the report-archival stale-claim window
/// (`REPORT_BACKUP_CLAIM_STALE_SECS`, 900s) so operators reason about a single
/// recovery horizon across both queues. Everything below is a multiple or
/// fraction of this unit, so the ordering invariant cannot drift when the
/// horizon is retuned.
const LEASE_UNIT_SECS: u64 = 900;

/// Default claim lease: one recovery horizon. A worker that dies holds its job
/// for at most this long before another worker may reclaim it.
const DEFAULT_LEASE_SECS: u64 = LEASE_UNIT_SECS;
/// Floor: 1/30th of the horizon (30s). Not a tuning knob — purely a guard
/// against a misconfigured near-zero lease that would reclaim a healthy
/// worker's job mid-flight. Workers renew the lease via `mark_running`, so the
/// floor only has to exceed one heartbeat interval.
const MIN_LEASE_SECS: u64 = LEASE_UNIT_SECS / 30;
/// Ceiling: 96 horizons (24h). Beyond this a crashed worker's job is stranded
/// so long that recovery is indistinguishable from a leak.
const MAX_LEASE_SECS: u64 = LEASE_UNIT_SECS * 96;

// Ordering invariant, enforced at compile time: the three bounds must stay
// strictly ordered no matter how `LEASE_UNIT_SECS` is retuned. A zero floor
// would defeat the fence; an inverted range would make every override fall
// back to the default silently.
const _LEASE_BOUNDS_INVARIANT: () = assert!(
    MIN_LEASE_SECS > 0
        && MIN_LEASE_SECS <= DEFAULT_LEASE_SECS
        && DEFAULT_LEASE_SECS <= MAX_LEASE_SECS
);

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
///
/// An out-of-range *number* is clamped to the nearest bound (the operator
/// clearly asked for "as short/long as possible"); only an absent or
/// unparsable value falls back to the default.
fn parse_lease(raw: Option<&str>) -> Duration {
    let secs = raw
        .and_then(|value| value.trim().parse::<u64>().ok())
        .map(|value| value.clamp(MIN_LEASE_SECS, MAX_LEASE_SECS))
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

    fn lease_window(&self) -> Option<Duration> {
        Some(self.lease)
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
    /// Callers use this as a heartbeat for long jobs. It is owner-fenced: a
    /// worker whose lease already expired and whose job was reclaimed cannot
    /// steal it back, because the predicate still requires its own
    /// `worker_id`.
    async fn mark_running(&self, id: AiImportJobId, worker_id: &str) -> Result<(), DomainError> {
        let result = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET status = 'running',
                lease_expires_at = now() + make_interval(secs => $3),
                updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(self.lease_secs())
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(result.rows_affected(), id, worker_id, "renew the lease of")
    }

    async fn mark_succeeded(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        preview_handle: &str,
    ) -> Result<(), DomainError> {
        let result = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET status = 'succeeded', preview_handle = $3,
                last_error = NULL, next_attempt_at = NULL,
                worker_id = NULL, lease_expires_at = NULL,
                updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(preview_handle)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(result.rows_affected(), id, worker_id, "complete")
    }

    async fn mark_failed(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        error_summary: &str,
        retryable: bool,
    ) -> Result<(), DomainError> {
        let result = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET retries = retries + 1,
                status = CASE
                    WHEN $4 AND retries + 1 < max_retries THEN 'failed'
                    ELSE 'dead_letter'
                END,
                last_error = LEFT($3, 1000),
                next_attempt_at = CASE
                    WHEN $4 AND retries + 1 < max_retries
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
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(error_summary)
        .bind(retryable)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(result.rows_affected(), id, worker_id, "fail")
    }

    /// Owner-fenced telemetry write for a worker that still holds the claim.
    ///
    /// Without the fence a displaced worker's telemetry would commit over the
    /// new owner's numbers even though its subsequent `mark_succeeded` is
    /// rejected — the metrics would describe work that was thrown away.
    async fn record_worker_telemetry(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        let values = TelemetryValues::try_from_telemetry(telemetry)?;
        let result = values
            .bind_all(
                sqlx::query(
                    r#"
            UPDATE ai_import.ai_import_job
            SET provider = $3, model = $4, chunk_count = $5,
                tokens_in = $6, tokens_out = $7, latency_total_ms = $8,
                accept_as_is = $9, edit_distance = $10, updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            "#,
                )
                .bind(id.as_uuid())
                .bind(worker_id),
            )
            .execute(&self.pool)
            .await
            .map_err(map_sqlx_error)?;
        ensure_claim_owned(
            result.rows_affected(),
            id,
            worker_id,
            "record telemetry for",
        )
    }

    async fn record_telemetry(
        &self,
        id: AiImportJobId,
        telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        let values = TelemetryValues::try_from_telemetry(telemetry)?;
        values
            .bind_all(
                sqlx::query(
                    r#"
            UPDATE ai_import.ai_import_job
            SET provider = $2, model = $3, chunk_count = $4,
                tokens_in = $5, tokens_out = $6, latency_total_ms = $7,
                accept_as_is = $8, edit_distance = $9, updated_at = now()
            WHERE id = $1
            "#,
                )
                .bind(id.as_uuid()),
            )
            .execute(&self.pool)
            .await
            .map_err(map_sqlx_error)?;
        Ok(())
    }
}

/// Telemetry values narrowed to their database types once, so the fenced and
/// unfenced writes cannot drift in their range checks.
struct TelemetryValues {
    provider: Option<&'static str>,
    model: Option<String>,
    chunk_count: i32,
    tokens_in: i64,
    tokens_out: i64,
    latency_total: i64,
    accept_as_is: Option<bool>,
    edit_distance: Option<i32>,
}

impl TelemetryValues {
    fn try_from_telemetry(telemetry: Telemetry) -> Result<Self, DomainError> {
        Ok(Self {
            provider: telemetry.provider.map(|provider| provider.as_str()),
            model: telemetry.model,
            chunk_count: i32::try_from(telemetry.chunk_count).map_err(|error| {
                DomainError::ValidationError(format!(
                    "AI chunk count exceeds database range: {error}"
                ))
            })?,
            tokens_in: i64::try_from(telemetry.tokens_in).map_err(|error| {
                DomainError::ValidationError(format!(
                    "AI input token count exceeds database range: {error}"
                ))
            })?,
            tokens_out: i64::try_from(telemetry.tokens_out).map_err(|error| {
                DomainError::ValidationError(format!(
                    "AI output token count exceeds database range: {error}"
                ))
            })?,
            latency_total: i64::try_from(telemetry.latency_total).map_err(|error| {
                DomainError::ValidationError(format!("AI latency exceeds database range: {error}"))
            })?,
            accept_as_is: telemetry.apply_state.accept_as_is(),
            edit_distance: telemetry
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
        })
    }

    /// Bind the eight telemetry columns in the order both statements declare.
    fn bind_all<'q>(
        self,
        query: sqlx::query::Query<'q, sqlx::Postgres, sqlx::postgres::PgArguments>,
    ) -> sqlx::query::Query<'q, sqlx::Postgres, sqlx::postgres::PgArguments> {
        query
            .bind(self.provider)
            .bind(self.model)
            .bind(self.chunk_count)
            .bind(self.tokens_in)
            .bind(self.tokens_out)
            .bind(self.latency_total)
            .bind(self.accept_as_is)
            .bind(self.edit_distance)
    }
}

/// Turn an owner-fenced UPDATE that matched no row into a typed conflict.
///
/// Zero rows means the caller no longer owns the claim: its lease expired and
/// another worker reclaimed the job, or the job already left `running`. This
/// must never be silently swallowed — the caller has just produced a result
/// for a job it no longer owns and needs to abandon it, not retry blindly.
fn ensure_claim_owned(
    rows_affected: u64,
    id: AiImportJobId,
    worker_id: &str,
    action: &str,
) -> Result<(), DomainError> {
    if rows_affected == 0 {
        tracing::warn!(
            job_id = %id.as_uuid(),
            worker_id,
            action,
            "AI import worker lost its claim; refusing a stale lifecycle write"
        );
        return Err(DomainError::Conflict(format!(
            "worker {worker_id} no longer holds the claim on AI import job {} and cannot {action} it",
            id.as_uuid()
        )));
    }
    Ok(())
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
        DEFAULT_LEASE_SECS, Duration, LEASE_UNIT_SECS, MAX_LEASE_SECS, MIN_LEASE_SECS,
        PgAiImportQueue, parse_lease,
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
    fn numeric_lease_override_outside_bounds_is_clamped() {
        // A near-zero lease would let a healthy worker's job be reclaimed
        // mid-flight; an absurd lease would make crash recovery useless. The
        // operator's intent is still honoured as far as the bounds allow.
        assert_eq!(
            parse_lease(Some(&(MIN_LEASE_SECS - 1).to_string())),
            Duration::from_secs(MIN_LEASE_SECS)
        );
        assert_eq!(parse_lease(Some("0")), Duration::from_secs(MIN_LEASE_SECS));
        assert_eq!(
            parse_lease(Some(&(MAX_LEASE_SECS + 1).to_string())),
            Duration::from_secs(MAX_LEASE_SECS)
        );
    }

    #[test]
    fn absent_or_unparsable_lease_override_falls_back_to_default() {
        let default = Duration::from_secs(DEFAULT_LEASE_SECS);
        // Unparsable input carries no intent to honour, so the safe default
        // applies — unlike an out-of-range number, which is clamped.
        assert_eq!(parse_lease(Some("not-a-number")), default);
        assert_eq!(parse_lease(Some("")), default);
        assert_eq!(parse_lease(Some("-5")), default);
        assert_eq!(parse_lease(None), default);
    }

    #[test]
    fn lease_bounds_are_derived_from_the_shared_unit() {
        // The ordering itself is guaranteed by `_LEASE_BOUNDS_INVARIANT` at
        // compile time; asserting it again at runtime would be a tautology
        // (clippy::assertions_on_constants). What is worth pinning here is the
        // *derivation*: all three bounds must stay tied to the one named unit,
        // so a future edit cannot reintroduce free-floating literals.
        assert_eq!(DEFAULT_LEASE_SECS, LEASE_UNIT_SECS);
        assert_eq!(MIN_LEASE_SECS, LEASE_UNIT_SECS / 30);
        assert_eq!(MAX_LEASE_SECS, LEASE_UNIT_SECS * 96);
        // Sanity-check the derived values against the documented contract.
        assert_eq!(MIN_LEASE_SECS, 30);
        assert_eq!(MAX_LEASE_SECS, 86_400);
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
