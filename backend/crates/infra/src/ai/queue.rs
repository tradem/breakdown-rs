// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)

use std::pin::Pin;
use std::time::Duration;

use breakdown_core::ai::{
    AiImportAttempt, AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId,
    AiImportProgress, AiImportQueue, AppliedEpisode, CostBreakdown, DocumentKind, JobStatus,
    JobTelemetrySummary, LlmProvider, SourceFormat, Telemetry,
};
use breakdown_core::error::DomainError;
use breakdown_core::shared::UserId;
use chrono::{DateTime, Utc};
use futures::Stream;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use super::events::AiJobEventHub;

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

/// Upper bound on the per-job attempt history returned to a caller (issue
/// #637). A job can accumulate many attempts over its life; the read surface
/// only needs enough to explain the failure sequence.
const ATTEMPT_HISTORY_LIMIT: i64 = 20;

#[derive(Clone, Debug)]
pub struct PgAiImportQueue {
    pool: PgPool,
    lease: Duration,
    /// In-process fan-out for SSE wake-ups (issue #664). Every fenced
    /// lifecycle/progress write notifies it directly after commit; in
    /// PostgreSQL mode the shared `PgListener` task additionally forwards
    /// cross-instance `pg_notify` payloads into the same hub.
    hub: AiJobEventHub,
}

impl PgAiImportQueue {
    /// Build a queue with the lease window from `AI_IMPORT_LEASE_SECS`
    /// (default 900s, clamped to 30..=86400).
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            lease: lease_from_env(),
            hub: AiJobEventHub::new(),
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

    /// The event hub this queue publishes job wake-ups to (issue #664).
    /// The composition root forwards it to
    /// [`spawn_pg_job_event_listener`](super::events::spawn_pg_job_event_listener)
    /// so cross-instance `pg_notify` payloads land in the same fan-out.
    pub fn event_hub(&self) -> AiJobEventHub {
        self.hub.clone()
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
    /// Push wake-ups for this job through the in-process hub (issue #664).
    /// The hub is also fed by the shared `PgListener` task for
    /// cross-instance `pg_notify` payloads; duplicate local + echoed
    /// notifications are deduplicated by the SSE handler's watermark
    /// comparison.
    fn subscribe(&self, id: AiImportJobId) -> Pin<Box<dyn Stream<Item = AiImportJobId> + Send>> {
        self.hub.subscribe(id)
    }

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
                (id, user_id, document_kind, source_format, block_id, dedup_key, document_digest, source_handle, source_file_name)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            -- The conflict target only echoes the key it collided on: a
            -- duplicate re-upload must NOT overwrite the existing row's
            -- display name (issue #763). The row the user already knows keeps
            -- the name it was created with.
            ON CONFLICT (user_id, dedup_key) DO UPDATE
                SET dedup_key = EXCLUDED.dedup_key
            RETURNING id, (xmax = 0) AS inserted
            "#,
        )
        .bind(request.id.as_uuid())
        .bind(request.user_id.as_str())
        .bind(request.document_kind.as_str())
        .bind(request.source_format.as_str())
        .bind(request.block_id.map(|block_id| block_id.0))
        .bind(&request.dedup_key)
        .bind(&request.document_digest)
        .bind(&request.source_handle)
        .bind(request.source_file_name.as_deref())
        .fetch_one(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let id = AiImportJobId::from_uuid(row.try_get::<Uuid, _>("id").map_err(map_sqlx_error)?);
        let inserted = row.try_get::<bool, _>("inserted").map_err(map_sqlx_error)?;
        // A newly enqueued job may be claimed within milliseconds; an
        // existing (deduplicated) one may just have transitioned. Either way
        // a watcher benefits from a wake-up (issue #664).
        self.hub.notify(id);
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
                -- Every claim path must leave the same invariant: a fresh
                -- claim owns no permit yet. Carrying the previous owner's
                -- `permit_id` forward would let a later reconciling reclaim
                -- delete a permit this worker never attached.
                permit_id = NULL,
                -- Stale progress from a prior attempt must never flash
                -- before the new attempt's first `mark_progress` (issue #664).
                progress = NULL,
                lease_expires_at = now() + make_interval(secs => $2),
                updated_at = now()
            FROM next_job
            WHERE job.id = next_job.id
            RETURNING job.*,
                pg_notify('ai_import_job_events', job.id::text)
            "#,
        )
        .bind(worker_id)
        .bind(self.lease_secs())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let job = row.map(map_job_row).transpose()?;
        if let Some(job) = &job {
            self.hub.notify(job.id);
        }
        Ok(job)
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
                -- See `claim_next`: every claim path clears the permit link.
                permit_id = NULL,
                -- See `claim_next`: no stale progress across attempts.
                progress = NULL,
                lease_expires_at = now() + make_interval(secs => $3),
                updated_at = now()
            FROM next_job
            WHERE job.id = next_job.id
            RETURNING job.*,
                pg_notify('ai_import_job_events', job.id::text)
            "#,
        )
        .bind(kind.as_str())
        .bind(worker_id)
        .bind(self.lease_secs())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let job = row.map(map_job_row).transpose()?;
        if let Some(job) = &job {
            self.hub.notify(job.id);
        }
        Ok(job)
    }

    fn lease_window(&self) -> Option<Duration> {
        Some(self.lease)
    }

    /// Claim the next runnable job and release the permit orphaned by the
    /// worker that previously held it, in one statement (issue #180).
    ///
    /// The three writes — flip the job to this worker, clear the stale permit
    /// link, delete the stale permit row — are data-modifying CTEs of a single
    /// statement, so they share one snapshot and one implicit transaction.
    /// There is no instant at which the job is reclaimed while the orphan is
    /// still counted, or the reverse.
    ///
    /// `permit_id` is set to NULL, not to the new owner's permit: capacity is
    /// acquired *after* the claim, once the job's `user_id` is known, and
    /// linked with [`attach_permit`](AiImportQueue::attach_permit).
    async fn claim_next_reconciling(
        &self,
        worker_id: &str,
    ) -> Result<Option<(AiImportJob, Option<Uuid>)>, DomainError> {
        let row = sqlx::query(
            r#"
            WITH next_job AS (
                SELECT id, permit_id AS orphan_permit_id
                FROM ai_import.ai_import_job
                WHERE status = 'pending'
                   OR (status = 'failed' AND
                       (next_attempt_at IS NULL OR next_attempt_at <= now()))
                   OR (status = 'running' AND
                       lease_expires_at IS NOT NULL AND lease_expires_at <= now())
                ORDER BY created_at, id
                FOR UPDATE SKIP LOCKED
                LIMIT 1
            ),
            claim AS (
                UPDATE ai_import.ai_import_job AS job
                SET status = 'running',
                    worker_id = $1,
                    permit_id = NULL,
                    progress = NULL,
                    lease_expires_at = now() + make_interval(secs => $2),
                    updated_at = now()
                FROM next_job
                WHERE job.id = next_job.id
                RETURNING job.*, next_job.orphan_permit_id,
                    pg_notify('ai_import_job_events', job.id::text)
            ),
            released AS (
                DELETE FROM ai_import.concurrency_permit
                WHERE id = (SELECT orphan_permit_id FROM claim)
                RETURNING id
            )
            SELECT claim.*, (SELECT id FROM released) AS released_permit_id
            FROM claim
            "#,
        )
        .bind(worker_id)
        .bind(self.lease_secs())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let claimed = map_reconciling_claim(row, worker_id)?;
        if let Some((job, _)) = &claimed {
            self.hub.notify(job.id);
        }
        Ok(claimed)
    }

    /// Kind-filtered [`claim_next_reconciling`](AiImportQueue::claim_next_reconciling).
    async fn claim_next_kind_reconciling(
        &self,
        worker_id: &str,
        kind: DocumentKind,
    ) -> Result<Option<(AiImportJob, Option<Uuid>)>, DomainError> {
        let row = sqlx::query(
            r#"
            WITH next_job AS (
                SELECT id, permit_id AS orphan_permit_id
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
            ),
            claim AS (
                UPDATE ai_import.ai_import_job AS job
                SET status = 'running',
                    worker_id = $2,
                    permit_id = NULL,
                    progress = NULL,
                    lease_expires_at = now() + make_interval(secs => $3),
                    updated_at = now()
                FROM next_job
                WHERE job.id = next_job.id
                RETURNING job.*, next_job.orphan_permit_id,
                    pg_notify('ai_import_job_events', job.id::text)
            ),
            released AS (
                DELETE FROM ai_import.concurrency_permit
                WHERE id = (SELECT orphan_permit_id FROM claim)
                RETURNING id
            )
            SELECT claim.*, (SELECT id FROM released) AS released_permit_id
            FROM claim
            "#,
        )
        .bind(kind.as_str())
        .bind(worker_id)
        .bind(self.lease_secs())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let claimed = map_reconciling_claim(row, worker_id)?;
        if let Some((job, _)) = &claimed {
            self.hub.notify(job.id);
        }
        Ok(claimed)
    }

    /// Link the permit acquired for this job's own user to the claim.
    ///
    /// Owner-fenced: a worker that lost its claim must not overwrite the new
    /// owner's link, or a later reclaim would delete a *live* permit and
    /// under-count the ceiling.
    async fn attach_permit(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        permit_id: Uuid,
    ) -> Result<(), DomainError> {
        let result = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET permit_id = $3, updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            RETURNING pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(permit_id)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(result.rows_affected(), id, worker_id, "attach a permit to")?;
        self.hub.notify(id);
        Ok(())
    }

    /// Hand a claimed job back without charging it an attempt.
    ///
    /// `retries` is deliberately untouched: the job never ran, it was only
    /// held. Charging a retry here would let a saturated ceiling dead-letter
    /// a perfectly valid job.
    async fn release_claim(&self, id: AiImportJobId, worker_id: &str) -> Result<(), DomainError> {
        let result = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET status = 'pending',
                worker_id = NULL,
                permit_id = NULL,
                lease_expires_at = NULL,
                updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            RETURNING pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(
            result.rows_affected(),
            id,
            worker_id,
            "release the claim of",
        )?;
        self.hub.notify(id);
        Ok(())
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
        match row.map(map_job_row).transpose()? {
            Some(mut job) => {
                job.attempts = self.list_attempts(id, ATTEMPT_HISTORY_LIMIT).await?;
                Ok(Some(job))
            }
            None => Ok(None),
        }
    }

    /// List the caller's jobs, newest first (issue #337).
    ///
    /// `LIMIT`/`OFFSET` are clamped in Rust; the statement itself stays a
    /// static literal with `.bind()` values (AGENTS.md §3).
    async fn list_for_user(
        &self,
        user_id: &UserId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AiImportJob>, DomainError> {
        let limit = limit.clamp(1, 100);
        let offset = offset.max(0);
        let rows = sqlx::query(
            r#"
            SELECT *
            FROM ai_import.ai_import_job
            WHERE user_id = $1
            ORDER BY created_at DESC, id DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id.as_str())
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        rows.into_iter().map(map_job_row).collect()
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
            RETURNING pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(self.lease_secs())
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(result.rows_affected(), id, worker_id, "renew the lease of")?;
        self.hub.notify(id);
        Ok(())
    }

    /// Test-support storage seam (issue #748): one INSERT that lands the job
    /// directly in the terminal `succeeded` state, pointing at
    /// [preview_handle]. No claim, no lease and no permit are involved, so the
    /// row is unclaimable by construction and can never be picked up by a
    /// worker or occupy the runnable pool.
    ///
    /// The column list mirrors [`AiImportQueue::enqueue`]: the fixtures go
    /// through the same table defaults (`retries`, `max_retries`, timestamps)
    /// a production enqueue uses. A `(user_id, dedup_key)` collision is a
    /// genuine caller bug and surfaces as the mapped adapter error instead of
    /// being swallowed by an `ON CONFLICT DO NOTHING`.
    #[cfg(feature = "test-support")]
    async fn seed_succeeded(
        &self,
        request: AiImportEnqueueRequest,
        preview_handle: &str,
    ) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            INSERT INTO ai_import.ai_import_job
                (id, user_id, document_kind, source_format, block_id, dedup_key, document_digest, source_handle, source_file_name, status, preview_handle)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'succeeded', $10)
            "#,
        )
        .bind(request.id.as_uuid())
        .bind(request.user_id.as_str())
        .bind(request.document_kind.as_str())
        .bind(request.source_format.as_str())
        .bind(request.block_id.map(|block_id| block_id.0))
        .bind(&request.dedup_key)
        .bind(&request.document_digest)
        .bind(&request.source_handle)
        .bind(request.source_file_name.as_deref())
        .bind(preview_handle)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        self.hub.notify(request.id);
        Ok(())
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
                -- A finished job has no live stage (issue #763). The last frame
                -- a worker publishes is `storing_preview`, so leaving the
                -- column set made every succeeded job advertise that stage
                -- forever — to every consumer, across restarts.
                progress = NULL,
                last_error = NULL, next_attempt_at = NULL,
                worker_id = NULL, lease_expires_at = NULL,
                -- The permit is released by its holder around this write, so
                -- the link must not outlive the claim: a stale id would name a
                -- row that is already gone, and permit ids are not reserved
                -- after deletion.
                permit_id = NULL,
                updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            RETURNING pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(preview_handle)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(result.rows_affected(), id, worker_id, "complete")?;
        self.hub.notify(id);
        Ok(())
    }

    async fn mark_failed(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        error_summary: &str,
        error_code: Option<&str>,
        retryable: bool,
    ) -> Result<(), DomainError> {
        // The attempt row is appended in the same statement as the lifecycle
        // write, so a failed attempt can never exist without its history row
        // (or vice versa). `rows_affected` is the INSERT's count: a fenced-out
        // UPDATE returns nothing from the CTE, so no attempt is recorded and
        // `ensure_claim_owned` still sees zero.
        let result = sqlx::query(
            r#"
            WITH updated AS (
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
                    -- A terminal job also has no live stage (issue #763); a
                    -- job that merely backs off keeps its progress until the
                    -- next claim replaces it. `retries` is the pre-update
                    -- value inside this SET list, so this predicate mirrors
                    -- the status CASE above exactly.
                    progress = CASE
                        WHEN $4 AND retries + 1 < max_retries THEN progress
                        ELSE NULL
                    END,
                    -- A terminal or backing-off job holds no claim: releasing the
                    -- lease here keeps `running` the only leased state, so the
                    -- reclaim predicate can never resurrect a failed job early.
                    worker_id = NULL,
                    lease_expires_at = NULL,
                    -- Likewise the permit link. This matters most on the retryable
                    -- branch: the job stays claimable, so a stale id would be read
                    -- by the next reclaim and deleted — freeing a permit that this
                    -- worker already released, and whose id may since belong to
                    -- someone else.
                    permit_id = NULL,
                    updated_at = now()
                WHERE id = $1 AND status = 'running' AND worker_id = $2
                RETURNING id, retries, status, last_error,
                    pg_notify('ai_import_job_events', id::text)
            )
            INSERT INTO ai_import.ai_import_job_attempt
                (id, job_id, attempt_no, status, error_summary, error_code, retryable)
            SELECT $5, id, retries, status, last_error, $6, $4
            FROM updated
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(error_summary)
        .bind(retryable)
        .bind(Uuid::now_v7())
        .bind(error_code)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(result.rows_affected(), id, worker_id, "fail")?;
        self.hub.notify(id);
        Ok(())
    }

    /// Terminate a job whose durable payload is gone (issue #181).
    ///
    /// Unlike `mark_failed`, `retries` is left untouched and no
    /// `next_attempt_at` is set: this is not an attempt that failed, it is the
    /// discovery that there is nothing left to attempt. The claim, lease and
    /// permit link are cleared exactly as on the other terminal paths, so no
    /// reclaim can resurrect the job and no stale permit id survives the
    /// holder's release.
    ///
    /// Owner-fenced: a worker whose lease lapsed must not stamp this terminal
    /// state over the result of the worker that reclaimed the job.
    async fn mark_payload_unavailable(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        error_summary: &str,
        error_code: Option<&str>,
    ) -> Result<(), DomainError> {
        let result = sqlx::query(
            r#"
            WITH updated AS (
                UPDATE ai_import.ai_import_job
                SET status = 'payload_unavailable',
                    last_error = LEFT($3, 1000),
                    next_attempt_at = NULL,
                    -- Terminal, so no live stage survives it (issue #763).
                    progress = NULL,
                    worker_id = NULL,
                    lease_expires_at = NULL,
                    permit_id = NULL,
                    updated_at = now()
                WHERE id = $1 AND status = 'running' AND worker_id = $2
                RETURNING id, retries, status, last_error,
                    pg_notify('ai_import_job_events', id::text)
            )
            INSERT INTO ai_import.ai_import_job_attempt
                (id, job_id, attempt_no, status, error_summary, error_code, retryable)
            -- `retries` is unchanged on this path, so the attempt that made the
            -- discovery is `retries + 1` (matching `mark_failed`'s post-increment
            -- numbering).
            SELECT $4, id, retries + 1, status, last_error, $5, FALSE
            FROM updated
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(error_summary)
        .bind(Uuid::now_v7())
        .bind(error_code)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(result.rows_affected(), id, worker_id, "mark the payload of")?;
        self.hub.notify(id);
        Ok(())
    }

    /// Owner-fenced, throttled progress write (issue #664, ADR-038 D3).
    ///
    /// Same fence as every other worker transition: a worker whose lease
    /// lapsed gets `Conflict` here instead of overwriting the new owner's
    /// progress — and aborts before its next billable LLM call. Called only
    /// at stage boundaries and completed chunks, never per LLM token.
    async fn mark_progress(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        progress: &AiImportProgress,
    ) -> Result<(), DomainError> {
        let payload = serde_json::to_value(progress).map_err(|error| {
            DomainError::validation(format!("AI import progress is not serializable: {error}"))
        })?;
        let result = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET progress = $3, updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            RETURNING pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(payload)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(
            result.rows_affected(),
            id,
            worker_id,
            "publish progress for",
        )?;
        self.hub.notify(id);
        Ok(())
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
                cached_tokens_in = $9, energy_millijoules = $10, cost = $11,
                accept_as_is = $12, edit_distance = $13, updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            RETURNING pg_notify('ai_import_job_events', id::text)
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
        )?;
        self.hub.notify(id);
        Ok(())
    }

    async fn record_telemetry(
        &self,
        id: AiImportJobId,
        telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        // Apply-path telemetry ONLY: this unfenced update runs after a
        // successful apply on an already-terminal job whose completion-time
        // telemetry/cost snapshot is IMMUTABLE (design D4 — never recomputed).
        // The only fields observable at apply time are the accept signal and
        // the content-free edit count; rewriting the other columns (defaulted
        // `..Telemetry::default()` in the handler) would NULL out the
        // persisted cost snapshot.
        let values = TelemetryValues::try_from_telemetry(telemetry)?;
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET accept_as_is = $2, edit_distance = $3, updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .bind(values.accept_as_is)
        .bind(values.edit_distance)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }

    /// Record the target episodes of a successful apply (issue #763).
    ///
    /// Unfenced for the same reason as [`record_telemetry`]: the apply only
    /// runs on a `succeeded` job, so no worker holds a claim that could be
    /// displaced. `updated_at` is bumped deliberately — the jobs list orders by
    /// it, and a job the user just applied to is the most recently *used* row.
    /// Payload retention is measured from the same column, so an applied job's
    /// preview lives a full retention window longer, which is the intended
    /// direction: the user may still re-open it.
    /// Record the target episodes a successful apply dispatched rows into
    /// (issue #763).
    ///
    /// Unfenced for the same reason as [`record_telemetry`]: the apply only runs
    /// on a `succeeded` job, so no worker holds a claim that could be displaced.
    ///
    /// The write **merges** instead of replacing, and the row lock makes the
    /// read-merge-write atomic against a concurrent duplicate apply. Merging is
    /// what keeps a retry from destroying correct attribution (CodeRabbit
    /// review): a retry finds every row already applied and therefore reports no
    /// entries at all — replacing would wipe the first apply's summary, while a
    /// union keeps it and lets a partially applied job add the episodes it
    /// reached later. A known episode's `applied_count` is **accumulated** (a
    /// later apply reports only its own rows) and its position is kept; a new
    /// episode is appended.
    ///
    /// `updated_at` is bumped deliberately — the jobs list orders by it, and a
    /// job the user just applied to is the most recently *used* row. Payload
    /// retention is measured from the same column, so an applied job's preview
    /// lives a full retention window longer, which is the intended direction:
    /// the user may still re-open it.
    async fn record_applied_episodes(
        &self,
        id: AiImportJobId,
        episodes: &[AppliedEpisode],
    ) -> Result<(), DomainError> {
        if episodes.is_empty() {
            // Nothing dispatched: keep the existing summary untouched (a retry
            // of an applied preview must not blank it), and skip the row lock.
            return Ok(());
        }
        let mut transaction = self.pool.begin().await.map_err(map_sqlx_error)?;
        // `Option<Option<_>>`: the outer one is "no such job row", the inner one
        // is the nullable column — a job no apply has written a summary for yet.
        let existing: Option<Option<serde_json::Value>> = sqlx::query_scalar(
            r#"
            SELECT applied_episodes
            FROM ai_import.ai_import_job
            WHERE id = $1
            FOR UPDATE
            "#,
        )
        .bind(id.as_uuid())
        .fetch_optional(&mut *transaction)
        .await
        .map_err(map_sqlx_error)?;
        let Some(stored) = existing else {
            // The job vanished between the apply and this write (a concurrent
            // delete): nothing to annotate, and no error to raise for it.
            transaction.rollback().await.map_err(map_sqlx_error)?;
            return Ok(());
        };
        // An undecodable payload degrades to "nothing recorded yet", exactly
        // like the read path — a broken display field never blocks the merge.
        let mut merged: Vec<AppliedEpisode> = stored
            .and_then(|value| serde_json::from_value(value).ok())
            .unwrap_or_default();
        for entry in episodes {
            match merged.iter_mut().find(|known| known.id == entry.id) {
                // ACCUMULATE, do not replace (CodeRabbit review): a later apply
                // reports only the rows IT dispatched, so replacing would turn a
                // stored 57 rows + 3 new ones into 3. Rows are never dispatched
                // twice (a confirmed mapping short-circuits), so the sum is the
                // job's real total for that episode. The freshest non-empty label
                // wins, because a later apply may have resolved the episode's
                // title where the earlier one could not.
                Some(known) => {
                    known.applied_count = known.applied_count.saturating_add(entry.applied_count);
                    if entry.number.is_some() || entry.name.is_some() {
                        known.number = entry.number;
                        known.name = entry.name.clone();
                    }
                }
                None => merged.push(entry.clone()),
            }
        }
        let payload = serde_json::to_value(&merged).map_err(|error| {
            DomainError::validation(format!(
                "AI import applied-episode summary is not serializable: {error}"
            ))
        })?;
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET applied_episodes = $2, updated_at = now()
            WHERE id = $1
            RETURNING pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(id.as_uuid())
        .bind(payload)
        .execute(&mut *transaction)
        .await
        .map_err(map_sqlx_error)?;
        transaction.commit().await.map_err(map_sqlx_error)?;
        self.hub.notify(id);
        Ok(())
    }

    async fn list_attempts(
        &self,
        id: AiImportJobId,
        limit: i64,
    ) -> Result<Vec<AiImportAttempt>, DomainError> {
        let limit = limit.clamp(1, ATTEMPT_HISTORY_LIMIT);
        let rows = sqlx::query(
            r#"
            SELECT attempt_no, status, error_summary, error_code, retryable, created_at
            FROM ai_import.ai_import_job_attempt
            WHERE job_id = $1
            ORDER BY attempt_no DESC
            LIMIT $2
            "#,
        )
        .bind(id.as_uuid())
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        rows.into_iter().map(map_attempt_row).collect()
    }

    /// Delete a terminal job row (issue #671).
    ///
    /// The terminal predicate in the statement is the authoritative backstop
    /// behind the handler's `ai-import.job-not-deletable` 409 pre-check: a
    /// `pending`/`running`/`failed` row is leased, queued or backed off, and
    /// removing one would corrupt the claim/permit machinery.
    ///
    /// `ai_import.projection_ai_import_mapping` has **no** foreign key to the
    /// job row (the apply-idempotency mapping predates the delete affordance),
    /// so its rows are removed explicitly in the same transaction — a deleted
    /// `succeeded` job must not leave dangling mapping rows. The mapping
    /// delete is gated on the job DELETE having affected a row: a guarded
    /// zero-row delete (a direct non-terminal call, or a concurrent delete
    /// that won the race) must leave the mapping state untouched — losing
    /// the idempotency mappings of a job that still exists would let a
    /// re-apply duplicate its aggregates. Attempt-history and
    /// payload-cleanup rows go via their `ON DELETE CASCADE` FKs.
    async fn delete_terminal(&self, id: AiImportJobId) -> Result<bool, DomainError> {
        let mut tx = self.pool.begin().await.map_err(map_sqlx_error)?;
        let result = sqlx::query(
            r#"
            DELETE FROM ai_import.ai_import_job
            WHERE id = $1
              AND status IN ('succeeded', 'dead_letter', 'payload_unavailable')
            "#,
        )
        .bind(id.as_uuid())
        .execute(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;
        if result.rows_affected() == 1 {
            sqlx::query(
                r#"
                DELETE FROM ai_import.projection_ai_import_mapping
                WHERE preview_id = $1
                "#,
            )
            .bind(id.as_uuid())
            .execute(&mut *tx)
            .await
            .map_err(map_sqlx_error)?;
        }
        tx.commit().await.map_err(map_sqlx_error)?;
        Ok(result.rows_affected() == 1)
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
    cached_tokens_in: i64,
    energy_millijoules: Option<i64>,
    cost: Option<serde_json::Value>,
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
                DomainError::validation(format!("AI chunk count exceeds database range: {error}"))
            })?,
            tokens_in: i64::try_from(telemetry.tokens_in).map_err(|error| {
                DomainError::validation(format!(
                    "AI input token count exceeds database range: {error}"
                ))
            })?,
            tokens_out: i64::try_from(telemetry.tokens_out).map_err(|error| {
                DomainError::validation(format!(
                    "AI output token count exceeds database range: {error}"
                ))
            })?,
            cached_tokens_in: i64::try_from(telemetry.cached_tokens_in).map_err(|error| {
                DomainError::validation(format!(
                    "AI cached token count exceeds database range: {error}"
                ))
            })?,
            energy_millijoules: match telemetry.energy_millijoules {
                0 => None,
                millijoules => Some(i64::try_from(millijoules).map_err(|error| {
                    DomainError::validation(format!(
                        "AI energy telemetry exceeds database range: {error}"
                    ))
                })?),
            },
            cost: telemetry
                .cost
                .map(serde_json::to_value)
                .transpose()
                .map_err(|error| {
                    DomainError::validation(format!(
                        "AI cost snapshot cannot be serialized: {error}"
                    ))
                })?,
            latency_total: i64::try_from(telemetry.latency_total).map_err(|error| {
                DomainError::validation(format!("AI latency exceeds database range: {error}"))
            })?,
            accept_as_is: telemetry.apply_state.accept_as_is(),
            edit_distance: telemetry
                .apply_state
                .edit_distance()
                .map(|distance| {
                    i32::try_from(distance).map_err(|error| {
                        DomainError::validation(format!(
                            "AI edit distance exceeds database range: {error}"
                        ))
                    })
                })
                .transpose()?,
        })
    }

    /// Bind the eleven telemetry columns in the exact order both UPDATE
    /// statements declare their placeholders: `tokens_in`, `tokens_out`,
    /// `latency_total_ms`, then the #675 trio `cached_tokens_in`,
    /// `energy_millijoules`, `cost` — a wrong order would be silently
    /// type-compatible between the integer columns (the jsonb `cost` binding
    /// against `energy_millijoules` is the only mismatch Postgres rejects).
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
            .bind(self.cached_tokens_in)
            .bind(self.energy_millijoules)
            .bind(self.cost)
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
        return Err(DomainError::conflict(format!(
            "worker {worker_id} no longer holds the claim on AI import job {} and cannot {action} it",
            id.as_uuid()
        )));
    }
    Ok(())
}

/// Decode a reconciling-claim row into `(job, released_orphan_permit_id)`.
///
/// Shared by the plain and kind-filtered variants so the two cannot drift on
/// the column name the release is read from.
fn map_reconciling_claim(
    row: Option<sqlx::postgres::PgRow>,
    worker_id: &str,
) -> Result<Option<(AiImportJob, Option<Uuid>)>, DomainError> {
    let Some(row) = row else { return Ok(None) };
    let released: Option<Uuid> = row.try_get("released_permit_id").map_err(map_sqlx_error)?;
    let job = map_job_row(row)?;
    if let Some(orphan) = released {
        // Warn, not info: reaching this means a worker died holding capacity.
        // It is recovered, but the rate of it is an operational signal.
        tracing::warn!(
            job_id = %job.id.as_uuid(),
            worker_id,
            released_permit_id = %orphan,
            "reclaimed an abandoned AI import job and released the permit its \
             dead worker still held"
        );
    }
    Ok(Some((job, released)))
}

/// Decode the nullable `progress` JSONB column into the core view type.
///
/// Progress is advisory visibility data: a `NULL` column or an undecodable
/// payload degrades to `None` instead of failing the whole job read.
fn decode_progress(row: &sqlx::postgres::PgRow) -> Option<AiImportProgress> {
    let value: Option<serde_json::Value> = row
        .try_get("progress")
        .map_err(|err| {
            tracing::warn!(error = %err, "failed to read ai_import progress column");
            err
        })
        .ok()
        .flatten()?;
    match serde_json::from_value::<AiImportProgress>(value?) {
        Ok(progress) => Some(progress),
        Err(err) => {
            tracing::warn!(error = %err, "failed to decode ai_import progress payload");
            None
        }
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
        source_format: parse_source_format(row.try_get("source_format").map_err(map_sqlx_error)?)?,
        block_id: row
            .try_get::<Option<Uuid>, _>("block_id")
            .map_err(map_sqlx_error)?
            .map(breakdown_core::shared::BlockId::from_uuid),
        dedup_key: row.try_get("dedup_key").map_err(map_sqlx_error)?,
        document_digest: row.try_get("document_digest").map_err(map_sqlx_error)?,
        source_handle: row.try_get("source_handle").map_err(map_sqlx_error)?,
        // Display metadata (issue #763). `NULL` for pre-#763 rows and for
        // uploads that carried no name — the wire field is `null`, and no
        // client invents a name from the opaque handle.
        source_file_name: row.try_get("source_file_name").map_err(map_sqlx_error)?,
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
        next_attempt_at: row.try_get("next_attempt_at").map_err(map_sqlx_error)?,
        // JSONB decoded through the core view type; `NULL`/undecodable
        // payloads degrade to `None` rather than failing the whole read —
        // progress is advisory visibility data, never correctness state.
        progress: decode_progress(&row),
        created_at,
        updated_at,
        // Populated by `get` (single-job read); list/claim contexts leave it
        // empty so they do not pay N+1 history queries.
        attempts: Vec::new(),
        telemetry: decode_job_telemetry(&row),
        cost: decode_job_cost(&row),
        applied_episodes: decode_applied_episodes(&row),
    })
}

/// Decode the persisted `applied_episodes` JSONB list (issue #763).
///
/// A display summary, exactly like [`decode_job_cost`]: an undecodable payload
/// degrades to "no recorded target" rather than failing the whole job read — a
/// broken display field must never make the job unreachable.
fn decode_applied_episodes(row: &sqlx::postgres::PgRow) -> Vec<AppliedEpisode> {
    let value: Option<serde_json::Value> = row.try_get("applied_episodes").ok().flatten();
    let Some(value) = value else {
        return Vec::new();
    };
    match serde_json::from_value::<Vec<AppliedEpisode>>(value) {
        Ok(episodes) => episodes,
        Err(err) => {
            tracing::warn!(error = %err, "failed to decode ai_import applied_episodes payload");
            Vec::new()
        }
    }
}

/// Decode the telemetry columns of one job row into the wire summary
/// (issue #675). `None` for rows no worker has recorded telemetry for yet
/// (provider NULL and all counters zero) — never a fabricated empty summary.
fn decode_job_telemetry(row: &sqlx::postgres::PgRow) -> Option<JobTelemetrySummary> {
    let provider: Option<String> = row.try_get("provider").ok().flatten();
    let model: Option<String> = row.try_get("model").ok().flatten();
    let chunk_count: i32 = row.try_get("chunk_count").unwrap_or(0);
    let tokens_in: i64 = row.try_get("tokens_in").unwrap_or(0);
    let tokens_out: i64 = row.try_get("tokens_out").unwrap_or(0);
    let cached_tokens_in: i64 = row.try_get("cached_tokens_in").unwrap_or(0);
    let energy_millijoules: Option<i64> = row.try_get("energy_millijoules").unwrap_or(None);
    let latency_total_ms: i64 = row.try_get("latency_total_ms").unwrap_or(0);
    let has_telemetry = provider.is_some()
        || chunk_count > 0
        || tokens_in > 0
        || tokens_out > 0
        || latency_total_ms > 0;
    if !has_telemetry {
        return None;
    }
    Some(JobTelemetrySummary {
        provider: provider.as_deref().and_then(parse_provider_key),
        model,
        doc_kind: parse_document_kind(row.try_get("document_kind").ok()?).ok(),
        chunk_count: chunk_count.max(0) as u32,
        tokens_in: tokens_in.max(0) as u64,
        tokens_out: tokens_out.max(0) as u64,
        cached_tokens_in: cached_tokens_in.max(0) as u64,
        energy_millijoules: energy_millijoules.unwrap_or(0).max(0) as u64,
        latency_total_ms: latency_total_ms.max(0) as u64,
    })
}

/// Decode the persisted `cost` JSONB snapshot (issue #675). Advisory
/// transparency data: an undecodable payload degrades to `None` rather than
/// failing the whole read.
fn decode_job_cost(row: &sqlx::postgres::PgRow) -> Option<CostBreakdown> {
    let value: Option<serde_json::Value> = row.try_get("cost").ok().flatten()?;
    serde_json::from_value(value?).ok()
}

/// Parse a persisted provider key (canonical key or accepted alias) —
/// delegates to the shared provider registry so a new provider needs exactly
/// one edit (the registry), not a fourth hand-written key table.
fn parse_provider_key(value: &str) -> Option<LlmProvider> {
    crate::ai::provider_registry::resolve_provider(value)
}

/// Decode one `ai_import.ai_import_job_attempt` row (issue #637).
fn map_attempt_row(row: sqlx::postgres::PgRow) -> Result<AiImportAttempt, DomainError> {
    Ok(AiImportAttempt {
        attempt_no: row
            .try_get::<i32, _>("attempt_no")
            .map_err(map_sqlx_error)?
            .max(0) as u32,
        status: parse_status(row.try_get("status").map_err(map_sqlx_error)?)?,
        error_summary: row.try_get("error_summary").map_err(map_sqlx_error)?,
        code: row.try_get("error_code").map_err(map_sqlx_error)?,
        retryable: row.try_get("retryable").map_err(map_sqlx_error)?,
        created_at: row.try_get("created_at").map_err(map_sqlx_error)?,
    })
}

fn parse_document_kind(value: String) -> Result<DocumentKind, DomainError> {
    match value.as_str() {
        "script" => Ok(DocumentKind::Script),
        "schedule" => Ok(DocumentKind::Schedule),
        other => Err(DomainError::validation(format!(
            "unknown AI document kind {other}"
        ))),
    }
}

fn parse_source_format(value: String) -> Result<SourceFormat, DomainError> {
    match value.as_str() {
        "csv" => Ok(SourceFormat::Csv),
        "pdf" => Ok(SourceFormat::Pdf),
        "plain_text" => Ok(SourceFormat::PlainText),
        other => Err(DomainError::validation(format!(
            "unknown AI source format {other}"
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
        "payload_unavailable" => Ok(JobStatus::PayloadUnavailable),
        other => Err(DomainError::validation(format!(
            "unknown AI job status {other}"
        ))),
    }
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    // Log the raw error (with bound values) internally; the HTTP-facing message
    // must not leak SQL details or bound values (CWE-209).
    tracing::error!(%error, "AI import database error");
    DomainError::service_unavailable("AI import database error")
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
