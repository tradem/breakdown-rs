// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;

use breakdown_core::ai::ports::ProviderHealth as _;
use breakdown_core::ai::{
    AiImportAttempt, AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId,
    AiImportProgress, AiImportQueue, AiImportTarget, AppliedEpisode, ApplyProgress, ApplyRunId,
    ApplyRunState, BreakerCounters, BreakerDecision, CostBreakdown, DecisionTelemetry,
    DocumentKind, JobStatus, JobTelemetrySummary, LlmProvider, ProviderBreakerSnapshot,
    ProviderBreakerState, ProviderHold, ProviderOutcome, SourceFormat, TargetAttachOutcome,
    Telemetry, mapping_kind,
};
use breakdown_core::error::DomainError;
use breakdown_core::shared::{BlockId, UserId};
use chrono::{DateTime, Utc};
use futures::Stream;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use super::events::AiJobEventHub;

/// How many expired holds one sweeper tick dead-letters (issue #871).
///
/// A bound, not a horizon: the next tick continues where this one stopped. It also
/// sizes the pre-generated attempt-id vector the expiry statement joins against.
const EXPIRE_BATCH: i32 = 512;

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
///
/// **Both** reads use this one bound (issue #822): the single-job read and the
/// jobs list. That is a correctness requirement, not a tuning value — a client
/// aggregates the *consecutive newest* provider-attributed attempts into a
/// count, so a shorter window on one surface would make the compact list row
/// report fewer failures than the status card for the same job (observed at a
/// three-attempt window: four consecutive provider failures read as three on
/// the list). Two different bounds cannot both be honest about one history.
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
    /// `AI_IMPORT_BREAKER_ENABLED` (issue #871): when false the claim
    /// predicate admits every job, which is the pre-#871 behaviour.
    breaker_filter: bool,
}

impl PgAiImportQueue {
    /// Build a queue with the lease window from `AI_IMPORT_LEASE_SECS`
    /// (default 900s, clamped to 30..=86400).
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            lease: lease_from_env(),
            hub: AiJobEventHub::new(),
            breaker_filter: true,
        }
    }

    /// Override the claim lease window. Used by deployments that want a
    /// different recovery horizon and by tests that need a deterministic
    /// already-expired lease (`Duration::ZERO`).
    /// Enable or disable the breaker's claim filter (issue #871,
    /// `AI_IMPORT_BREAKER_ENABLED`).
    ///
    /// With the switch off the predicate admits everything — the pre-#871
    /// behaviour — while the durable rows are left untouched, so re-enabling
    /// resumes with the verdicts as they were.
    #[must_use]
    pub fn with_breaker_filter(mut self, enabled: bool) -> Self {
        self.breaker_filter = enabled;
        self
    }

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

    /// Derive the applied-episode summary from the **durable** apply mappings
    /// (issue #864), one batch query for every job the caller is about to
    /// return.
    ///
    /// Why the read edge instead of the apply path: the summary used to be
    /// written by `apply_ai_import` *after* `ApplyWorker::apply_script`
    /// returned. A client that dropped or retried the request cancelled that
    /// handler future — the scene rows were already committed, the summary write
    /// never ran, and nothing retried it, so a completed apply could read back
    /// as "never applied". Denormalizing the summary from what actually
    /// committed removes the write entirely, so no cancellation point can lose
    /// it.
    ///
    /// The durable source is `projection_ai_import_mapping`: every applied scene
    /// row owns a `scene` mapping whose `aggregate_id` is the scene (a *new* one
    /// or the existing scene a reconciliation row updated), and
    /// `projection_scene.episode_id` says where that scene lives — the row's real
    /// home, not the episode the request happened to name. The episode's own
    /// number/title label the entry, which is the same authority a client would
    /// read.
    ///
    /// Two deliberate properties:
    ///
    /// * a still-**reserved** mapping (a crashed attempt that claimed an id) has
    ///   no scene projection row, so the join drops it: a reservation is not
    ///   applied work;
    /// * a schedule apply writes only `scene_shoot`/`shooting_day` mappings, so
    ///   it derives an empty list — the #763 decision (a schedule merge names no
    ///   target episode) falls out of the derivation instead of being a special
    ///   case.
    ///
    /// A failed derivation is display-metadata loss, never a failed read: the
    /// caller degrades to an empty list, exactly like an undecodable JSONB
    /// column did before.
    async fn derived_applied_episodes(
        &self,
        ids: &[AiImportJobId],
    ) -> HashMap<Uuid, Vec<AppliedEpisode>> {
        if ids.is_empty() {
            return HashMap::new();
        }
        let jobs: Vec<Uuid> = ids.iter().map(|id| id.as_uuid()).collect();
        let rows = sqlx::query(
            r#"
            SELECT mapping.preview_id                AS job_id,
                   scene.episode_id                  AS episode_id,
                   episode.number                    AS episode_number,
                   episode.name                      AS episode_name,
                   count(*)                          AS applied_count
            FROM ai_import.projection_ai_import_mapping AS mapping
            JOIN projection_scene AS scene ON scene.id = mapping.aggregate_id
            LEFT JOIN projection_episode AS episode ON episode.id = scene.episode_id
            WHERE mapping.aggregate_kind = $1
              AND mapping.preview_id = ANY($2)
            GROUP BY mapping.preview_id, scene.episode_id, episode.number, episode.name
            ORDER BY mapping.preview_id, episode.number NULLS LAST, scene.episode_id
            "#,
        )
        .bind(mapping_kind::SCENE)
        .bind(&jobs)
        .fetch_all(&self.pool)
        .await;
        let rows = match rows {
            Ok(rows) => rows,
            Err(error) => {
                tracing::warn!(
                    %error,
                    "failed to derive the AI import applied-episode summary; serving no recorded target"
                );
                return HashMap::new();
            }
        };
        let mut derived: HashMap<Uuid, Vec<AppliedEpisode>> = HashMap::new();
        for row in rows {
            let Ok(job_id) = row.try_get::<Uuid, _>("job_id") else {
                continue;
            };
            let (Ok(episode_id), Ok(applied_count)) = (
                row.try_get::<Uuid, _>("episode_id"),
                row.try_get::<i64, _>("applied_count"),
            ) else {
                continue;
            };
            derived.entry(job_id).or_default().push(AppliedEpisode {
                id: episode_id,
                number: row.try_get("episode_number").ok().flatten(),
                name: row.try_get("episode_name").ok().flatten(),
                applied_count: u32::try_from(applied_count).unwrap_or(u32::MAX),
            });
        }
        derived
    }

    fn lease_secs(&self) -> f64 {
        self.lease.as_secs_f64()
    }

    /// Newest attempts of a page of jobs, in ONE query (issue #822).
    ///
    /// The list read carries [`ATTEMPT_HISTORY_LIMIT`] attempts per job — the
    /// SAME bound the single-job read uses — so a client derives an identical
    /// provider-degraded aggregate from either read: the consecutive run of
    /// provider-attributed attempt codes is the only honest attribution signal
    /// (the free-form `error_summary`/`last_error` is never parsed). A shorter
    /// list window would make the compact row undercount what the status card
    /// shows for the same job.
    ///
    /// A read failure serves an empty attempt list per job and logs — history
    /// is explanatory metadata, exactly like the #864 applied-episode summary:
    /// a degraded provider must never be able to fail the whole jobs list, and
    /// an empty list is reported as "no history read", never as "no failures".
    async fn newest_attempts(&self, ids: &[AiImportJobId]) -> HashMap<Uuid, Vec<AiImportAttempt>> {
        if ids.is_empty() {
            return HashMap::new();
        }
        let jobs: Vec<Uuid> = ids.iter().map(|id| id.as_uuid()).collect();
        let rows = sqlx::query(
            r#"
            SELECT job_id, attempt_no, status, error_summary, error_code,
                   retryable, created_at
            FROM (
                SELECT attempt.*,
                       row_number() OVER (
                           PARTITION BY attempt.job_id
                           ORDER BY attempt.attempt_no DESC
                       ) AS rank_in_job
                FROM ai_import.ai_import_job_attempt AS attempt
                WHERE attempt.job_id = ANY($1)
            ) AS ranked
            WHERE ranked.rank_in_job <= $2
            ORDER BY ranked.job_id, ranked.attempt_no DESC
            "#,
        )
        .bind(&jobs)
        .bind(ATTEMPT_HISTORY_LIMIT)
        .fetch_all(&self.pool)
        .await;
        let rows = match rows {
            Ok(rows) => rows,
            Err(error) => {
                tracing::warn!(
                    %error,
                    "failed to read the AI import attempt history for the jobs list;                      serving no history"
                );
                return HashMap::new();
            }
        };
        let mut history: HashMap<Uuid, Vec<AiImportAttempt>> = HashMap::new();
        for row in rows {
            let Ok(job_id) = row.try_get::<Uuid, _>("job_id") else {
                continue;
            };
            match map_attempt_row(row) {
                Ok(attempt) => history.entry(job_id).or_default().push(attempt),
                Err(error) => tracing::warn!(
                    %error,
                    "failed to decode an AI import attempt row for the jobs list; skipping it"
                ),
            }
        }
        history
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
                (id, user_id, document_kind, source_format, block_id, dedup_key, document_digest, source_handle, source_file_name,
                 target_season_id, target_season_number, target_block_number,
                 breaker_provider, breaker_model)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
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
        // Import-target snapshot (issue #771, widened by #829):
        // display/attribution metadata resolved at the API edge. The season pair
        // stays NULL together when the snapshot could not be resolved, while the
        // block number is written only when a block is known — a block-less
        // upload (#829) carries its season from the first frame and gains the
        // block number when the target is attached.
        .bind(request.target.as_ref().map(|t| t.season_id.0))
        .bind(request.target.as_ref().map(|t| t.season_number))
        .bind(request.target.as_ref().map(|t| t.block_number))
        // The breaker key snapshot (issue #871, D-A2b): resolved at the API
        // edge, written here so the claim predicate can filter in SQL.
        .bind(request.provider.map(|provider| provider.as_str().to_string()))
        .bind(request.model.as_deref())
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
                WHERE (status = 'pending'
                   OR (status = 'failed' AND
                       (next_attempt_at IS NULL OR next_attempt_at <= now()))
                   OR (status = 'running' AND
                       lease_expires_at IS NOT NULL AND lease_expires_at <= now()))
                  -- Issue #871 (D-A2): only a CLOSED breaker admits a claim.
                  -- `retry_at` is deliberately absent: it is the probe
                  -- schedule, not a claim gate, and lifting the filter when the
                  -- probe became due would drain the queue instead of running
                  -- one probe.
                  -- The bound parameter is AI_IMPORT_BREAKER_ENABLED, so it is
                  -- NEGATED here: enabled ⇒ `false OR NOT EXISTS` ⇒ the filter
                  -- applies; disabled ⇒ `true OR …` ⇒ every job is admitted (the
                  -- pre-#871 behaviour). The durable rows stay untouched, so
                  -- re-enabling resumes with the verdicts as they were.
                  AND (NOT $3 OR NOT EXISTS (
                      SELECT 1 FROM ai_import.provider_health ph
                      WHERE ph.provider = ai_import.ai_import_job.breaker_provider
                        AND ph.model    = ai_import.ai_import_job.breaker_model
                        AND ph.state <> 'closed'
                  ))
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
                -- Issue #871: a claim ends the hold series. The job is about to
                -- run for real, so the next hold (if any) is a new episode and
                -- gets a fresh 6h budget (D-C4).
                provider_hold = NULL,
                provider_hold_series_started_at = NULL,
                -- Stale decision telemetry from a prior attempt must not be
                -- read as THIS attempt's outcome (issue #767). The column is
                -- written in the same completion write as the extraction
                -- telemetry, so a crash between that write and
                -- `mark_succeeded` leaves it set on a job that gets reclaimed.
                decision_telemetry = NULL,
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
        .bind(self.breaker_filter)
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
                  -- Issue #871 (D-A2): only a CLOSED breaker admits a claim.
                  -- `retry_at` is deliberately absent: it is the probe
                  -- schedule, not a claim gate, and lifting the filter when the
                  -- probe became due would drain the queue instead of running
                  -- one probe.
                  -- The bound parameter is AI_IMPORT_BREAKER_ENABLED, so it is
                  -- NEGATED here: enabled ⇒ `false OR NOT EXISTS` ⇒ the filter
                  -- applies; disabled ⇒ `true OR …` ⇒ every job is admitted (the
                  -- pre-#871 behaviour). The durable rows stay untouched, so
                  -- re-enabling resumes with the verdicts as they were.
                  AND (NOT $4 OR NOT EXISTS (
                      SELECT 1 FROM ai_import.provider_health ph
                      WHERE ph.provider = ai_import.ai_import_job.breaker_provider
                        AND ph.model    = ai_import.ai_import_job.breaker_model
                        AND ph.state <> 'closed'
                  ))
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
                -- See `claim_next`: a claim ends the hold series (issue #871).
                provider_hold = NULL,
                provider_hold_series_started_at = NULL,
                -- See `claim_next`: no stale decision telemetry across
                -- attempts (issue #767).
                decision_telemetry = NULL,
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
        .bind(self.breaker_filter)
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
                WHERE (status = 'pending'
                   OR (status = 'failed' AND
                       (next_attempt_at IS NULL OR next_attempt_at <= now()))
                   OR (status = 'running' AND
                       lease_expires_at IS NOT NULL AND lease_expires_at <= now()))
                  -- Issue #871 (D-A2): only a CLOSED breaker admits a claim.
                  -- `retry_at` is deliberately absent: it is the probe
                  -- schedule, not a claim gate, and lifting the filter when the
                  -- probe became due would drain the queue instead of running
                  -- one probe.
                  -- The bound parameter is AI_IMPORT_BREAKER_ENABLED, so it is
                  -- NEGATED here: enabled ⇒ `false OR NOT EXISTS` ⇒ the filter
                  -- applies; disabled ⇒ `true OR …` ⇒ every job is admitted (the
                  -- pre-#871 behaviour). The durable rows stay untouched, so
                  -- re-enabling resumes with the verdicts as they were.
                  AND (NOT $3 OR NOT EXISTS (
                      SELECT 1 FROM ai_import.provider_health ph
                      WHERE ph.provider = ai_import.ai_import_job.breaker_provider
                        AND ph.model    = ai_import.ai_import_job.breaker_model
                        AND ph.state <> 'closed'
                  ))
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
                    -- A claim ends the hold series (issue #871, D-C4) — same
                    -- rule as `claim_next`.
                    provider_hold = NULL,
                    provider_hold_series_started_at = NULL,
                    -- Stale decision telemetry never outlives its attempt
                    -- (issue #767) — same rule as `claim_next`.
                    decision_telemetry = NULL,
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
        .bind(self.breaker_filter)
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
                  -- Issue #871 (D-A2): only a CLOSED breaker admits a claim.
                  -- `retry_at` is deliberately absent: it is the probe
                  -- schedule, not a claim gate, and lifting the filter when the
                  -- probe became due would drain the queue instead of running
                  -- one probe.
                  -- The bound parameter is AI_IMPORT_BREAKER_ENABLED, so it is
                  -- NEGATED here: enabled ⇒ `false OR NOT EXISTS` ⇒ the filter
                  -- applies; disabled ⇒ `true OR …` ⇒ every job is admitted (the
                  -- pre-#871 behaviour). The durable rows stay untouched, so
                  -- re-enabling resumes with the verdicts as they were.
                  AND (NOT $4 OR NOT EXISTS (
                      SELECT 1 FROM ai_import.provider_health ph
                      WHERE ph.provider = ai_import.ai_import_job.breaker_provider
                        AND ph.model    = ai_import.ai_import_job.breaker_model
                        AND ph.state <> 'closed'
                  ))
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
                    -- A claim ends the hold series (issue #871, D-C4) — same
                    -- rule as `claim_next`.
                    provider_hold = NULL,
                    provider_hold_series_started_at = NULL,
                    -- Stale decision telemetry never outlives its attempt
                    -- (issue #767) — same rule as `claim_next`.
                    decision_telemetry = NULL,
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
        .bind(self.breaker_filter)
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
                job.applied_episodes = self
                    .derived_applied_episodes(std::slice::from_ref(&id))
                    .await
                    .remove(&id.as_uuid())
                    .unwrap_or_default();
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
        let mut jobs: Vec<AiImportJob> = rows
            .into_iter()
            .map(map_job_row)
            .collect::<Result<_, _>>()?;
        // One batch query for the whole page (issue #864): a per-job derivation
        // would turn the list into N+1 queries, and the summary is display
        // metadata every row on the page wants.
        let ids: Vec<AiImportJobId> = jobs.iter().map(|job| job.id).collect();
        let mut derived = self.derived_applied_episodes(&ids).await;
        // Same reasoning for the attempt history (issue #822): a client
        // deriving a degraded-provider state from the list must read the same
        // stable codes the single-job read carries, so the page is filled from
        // ONE windowed query instead of one read per row.
        let mut attempts = self.newest_attempts(&ids).await;
        for job in &mut jobs {
            job.applied_episodes = derived.remove(&job.id.as_uuid()).unwrap_or_default();
            job.attempts = attempts.remove(&job.id.as_uuid()).unwrap_or_default();
        }
        Ok(jobs)
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
                (id, user_id, document_kind, source_format, block_id, dedup_key, document_digest, source_handle, source_file_name,
                 target_season_id, target_season_number, target_block_number, status, preview_handle)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'succeeded', $13)
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
        // Import-target snapshot (issue #771): display/attribution metadata
        // resolved at the API edge from the block's owning season. All three
        // columns stay NULL together when the snapshot could not be resolved.
        .bind(request.target.as_ref().map(|t| t.season_id.0))
        .bind(request.target.as_ref().map(|t| t.season_number))
        .bind(request.target.as_ref().map(|t| t.block_number))
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
        let row = sqlx::query(
            r#"
            WITH updated AS (
            UPDATE ai_import.ai_import_job
            SET status = 'succeeded', preview_handle = $3,
                -- A finished job has no live stage (issue #763). The last frame
                -- a worker publishes is `storing_preview`, so leaving the
                -- column set made every succeeded job advertise that stage
                -- forever — to every consumer, across restarts.
                progress = NULL,
                last_error = NULL, next_attempt_at = NULL,
                -- Issue #871: a succeeded job holds nothing, and its hold
                -- series is over.
                provider_hold = NULL,
                provider_hold_series_started_at = NULL,
                worker_id = NULL, lease_expires_at = NULL,
                -- The permit is released by its holder around this write, so
                -- the link must not outlive the claim: a stale id would name a
                -- row that is already gone, and permit ids are not reserved
                -- after deletion.
                permit_id = NULL,
                updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            RETURNING id, pg_notify('ai_import_job_events', id::text)
            ),
            -- Issue #871 (D-B1): a terminal job's chunk rows are derived work for
            -- an attempt that will never happen again. Deleted in the SAME
            -- statement as the transition, so no crash can leave them behind.
            cleared AS (
                DELETE FROM ai_import.ai_import_job_chunk
                WHERE job_id IN (SELECT id FROM updated)
            )
            SELECT count(*) AS affected FROM updated
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(preview_handle)
        .fetch_one(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let affected: i64 = row.try_get("affected").map_err(map_sqlx_error)?;
        ensure_claim_owned(affected as u64, id, worker_id, "complete")?;
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
                    -- The decision outcome describes THIS attempt's scoring
                    -- pass, and a failed attempt recorded none: a value left
                    -- over from an earlier attempt (whose completion write
                    -- landed but whose `mark_succeeded` never did) would
                    -- describe a run this row is not in (issue #767). Cleared
                    -- on the retryable branch too — the job is backing off
                    -- until it is re-claimed, and a reader must not see the
                    -- old attempt's outcome in the meantime.
                    decision_telemetry = NULL,
                    -- Issue #871: the ordinary failure path is not a hold, so
                    -- the marker must not survive it. The ONE exception is the
                    -- hold-expiry write, which keeps it with state=expired —
                    -- that marker is what separates an expiry from a spent
                    -- retry budget.
                    provider_hold = NULL,
                    provider_hold_series_started_at = NULL,
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
            ),
            -- Issue #871 (D-B1): only the TERMINAL branch drops the chunk rows. A
            -- job that merely backs off keeps them — that is the whole point of
            -- the resume.
            cleared AS (
                DELETE FROM ai_import.ai_import_job_chunk
                WHERE job_id IN (SELECT id FROM updated WHERE status = 'dead_letter')
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
                    -- Terminal, and no scoring pass ran for THIS attempt: an
                    -- earlier attempt's outcome must not survive it (issue
                    -- #767).
                    decision_telemetry = NULL,
                    -- Issue #871: terminal, so the hold marker and its series
                    -- clock go too.
                    provider_hold = NULL,
                    provider_hold_series_started_at = NULL,
                    worker_id = NULL,
                    lease_expires_at = NULL,
                    permit_id = NULL,
                    updated_at = now()
                WHERE id = $1 AND status = 'running' AND worker_id = $2
                RETURNING id, retries, status, last_error,
                    pg_notify('ai_import_job_events', id::text)
            ),
            -- Issue #871 (D-B1): terminal, so the chunk rows go with it.
            cleared AS (
                DELETE FROM ai_import.ai_import_job_chunk
                WHERE job_id IN (SELECT id FROM updated)
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

    /// Park a claimed job on its provider's breaker without spending a retry
    /// (issue #871, D-A4).
    ///
    /// Three things make this deliberately *not* `mark_failed`:
    ///
    /// * `retries` is untouched — the budget must not be consumed by an attempt
    ///   that never reached the provider;
    /// * no `ai_import_job_attempt` row is appended — the history must not fill
    ///   with identical rows;
    /// * `next_attempt_at` is the breaker's probe time, not the per-job backoff,
    ///   so the whole fleet re-probes at one instant (D-C3).
    ///
    /// The **hold series clock** and the derived `hold_deadline` are written
    /// here rather than passed in: both expressions read the pre-update row, so
    /// the clock and the deadline can never disagree, and a re-hold refreshes
    /// `until` while the deadline stays where the series started (D-C4). A
    /// passed-in deadline could restart the 6h budget on every short recovery,
    /// which is exactly the unbounded hold the expiry exists to prevent.
    ///
    /// The claim, lease and permit link are cleared: a held job occupies no
    /// capacity (D-C2 — the permit is released with the attempt).
    async fn mark_held(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        hold: ProviderHold,
        hold_window_secs: u64,
    ) -> Result<(), DomainError> {
        let result = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET status = 'failed',
                next_attempt_at = $4,
                last_error = LEFT($3, 1000),
                -- The hold series clock (D-C4): set once per series, never
                -- restarted by a re-hold.
                provider_hold_series_started_at =
                    COALESCE(provider_hold_series_started_at, now()),
                -- The deadline is DERIVED here from that clock. Both
                -- expressions read the OLD row value, so they agree by
                -- construction.
                provider_hold = jsonb_set(
                    $5::jsonb,
                    '{hold_deadline}',
                    to_jsonb(
                        COALESCE(provider_hold_series_started_at, now())
                        + make_interval(secs => $6)
                    )
                ),
                -- A held job holds no claim (D-C2).
                worker_id = NULL,
                lease_expires_at = NULL,
                permit_id = NULL,
                updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
            RETURNING pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(&hold.reason_code)
        .bind(hold.until)
        .bind(serde_json::to_value(&hold).map_err(|error| {
            DomainError::validation(format!("provider hold is not serializable: {error}"))
        })?)
        .bind(i64::try_from(hold_window_secs).unwrap_or(i64::MAX))
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        ensure_claim_owned(result.rows_affected(), id, worker_id, "hold")?;
        self.hub.notify(id);
        Ok(())
    }

    /// Materialize a hold on every runnable job of a pair (issue #871, D-A4).
    ///
    /// Serves **both** materialization writers, because they are one statement
    /// with one semantics:
    ///
    /// * the `closed → open` transition calls it for the fast path, so an
    ///   outage becomes visible in the instant it is detected;
    /// * the sweeper calls it for every non-`closed` pair, which is the
    ///   guarantee — the open-time write cannot reach a job **enqueued while the
    ///   breaker is already open** (the claim predicate excludes it but writes
    ///   nothing) nor a `failed` job whose `next_attempt_at` became due
    ///   *afterwards*. Both would otherwise be invisible **and** unexpirable,
    ///   because the expiry precondition is the hold.
    ///
    /// Idempotent by the `provider_hold IS NULL` guard, so the two callers
    /// cannot double-apply.
    async fn hold_runnable_jobs(
        &self,
        provider: LlmProvider,
        model: &str,
        hold: ProviderHold,
        hold_window_secs: u64,
    ) -> Result<Vec<AiImportJobId>, DomainError> {
        let rows = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET status = 'failed',
                next_attempt_at = $3,
                last_error = LEFT($4, 1000),
                provider_hold_series_started_at =
                    COALESCE(provider_hold_series_started_at, now()),
                provider_hold = jsonb_set(
                    $5::jsonb,
                    '{hold_deadline}',
                    to_jsonb(
                        COALESCE(provider_hold_series_started_at, now())
                        + make_interval(secs => $6)
                    )
                ),
                updated_at = now()
            WHERE breaker_provider = $1 AND breaker_model = $2
              -- Only jobs that have not been held yet: the guard is what makes
              -- the two writers idempotent.
              AND provider_hold IS NULL
              -- "Runnable": a fresh job, or a failed one whose backoff is due.
              -- A `running` job is NOT touched — it has an owner, and its own
              -- attempt takes the held path through `mark_held`.
              AND (status = 'pending'
                   OR (status = 'failed' AND
                       (next_attempt_at IS NULL OR next_attempt_at <= now())))
            RETURNING id, pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(provider.as_str())
        .bind(model)
        .bind(hold.until)
        .bind(&hold.reason_code)
        .bind(serde_json::to_value(&hold).map_err(|error| {
            DomainError::validation(format!("provider hold is not serializable: {error}"))
        })?)
        .bind(i64::try_from(hold_window_secs).unwrap_or(i64::MAX))
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let mut ids = Vec::with_capacity(rows.len());
        for row in rows {
            let id =
                AiImportJobId::from_uuid(row.try_get::<Uuid, _>("id").map_err(map_sqlx_error)?);
            self.hub.notify(id);
            ids.push(id);
        }
        Ok(ids)
    }

    /// Re-point every held job of a pair at a new probe time (issue #871,
    /// D-A6 `half_open → open`).
    ///
    /// A held row follows the breaker: without this its `until` would show a
    /// resume time that has already passed while the claim predicate — which
    /// reads the breaker, not the job — keeps it unclaimable.
    async fn refresh_held_jobs(
        &self,
        provider: LlmProvider,
        model: &str,
        until: chrono::DateTime<Utc>,
    ) -> Result<Vec<AiImportJobId>, DomainError> {
        let rows = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET next_attempt_at = $3,
                provider_hold = jsonb_set(
                    provider_hold,
                    '{until}',
                    to_jsonb($3::timestamptz)
                ),
                updated_at = now()
            WHERE breaker_provider = $1 AND breaker_model = $2
              AND status = 'failed'
              AND provider_hold IS NOT NULL
              -- An EXPIRED marker is terminal: it must never be revived by a
              -- later probe failure (D-C4).
              AND COALESCE(provider_hold ->> 'state', '') <> 'expired'
            RETURNING id, pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(provider.as_str())
        .bind(model)
        .bind(until)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let mut ids = Vec::with_capacity(rows.len());
        for row in rows {
            let id =
                AiImportJobId::from_uuid(row.try_get::<Uuid, _>("id").map_err(map_sqlx_error)?);
            self.hub.notify(id);
            ids.push(id);
        }
        Ok(ids)
    }

    /// Owner-fenced rewrite of one job's breaker-key snapshot (issue #871).
    async fn stamp_breaker_pair(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        provider: LlmProvider,
        model: &str,
    ) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET breaker_provider = $3,
                breaker_model = $4,
                updated_at = now()
            WHERE id = $1 AND status = 'running' AND worker_id = $2
              AND (breaker_provider IS DISTINCT FROM $3
                   OR breaker_model IS DISTINCT FROM $4)
            "#,
        )
        .bind(id.as_uuid())
        .bind(worker_id)
        .bind(provider.as_str())
        .bind(model)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        // The row count is deliberately not inspected: zero rows is the NORMAL
        // case (the WHERE clause skips an unchanged pair, and an unchanged pair
        // is what most attempts see). A changed pair on a reclaimed job is
        // rejected by the same owner fence every other worker write uses, and
        // that attempt then fails on its next lifecycle write — turning a
        // snapshot refresh into a hard error here would fail jobs for a
        // bookkeeping write.
        Ok(())
    }

    /// Rewrite the snapshot of every runnable job of one user (issue #871,
    /// D-A2b layer 1 — the config-change edge).
    async fn restamp_user_breaker_pair(
        &self,
        user_id: &UserId,
        provider: LlmProvider,
        model: &str,
    ) -> Result<u64, DomainError> {
        let result = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET breaker_provider = $2,
                breaker_model = $3,
                updated_at = now()
            WHERE user_id = $1
              -- Only rows that can still be claimed: a running job has an owner
              -- and refreshes its own snapshot, and a terminal one never runs.
              AND status IN ('pending', 'failed')
              AND (breaker_provider IS DISTINCT FROM $2
                   OR breaker_model IS DISTINCT FROM $3)
            "#,
        )
        .bind(user_id.as_str())
        .bind(provider.as_str())
        .bind(model)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(result.rows_affected())
    }

    /// Release every held job of a pair after the breaker closed (issue #871,
    /// D-A6).
    ///
    /// `provider_hold_series_started_at` is deliberately **not** cleared: the
    /// series clock is what stops a flapping provider from resetting its 6 h
    /// budget on every short recovery (D-C4). It ends on claim, or by the
    /// sweeper's stable-window hygiene.
    async fn release_held_jobs(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<Vec<AiImportJobId>, DomainError> {
        let rows = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET provider_hold = NULL,
                updated_at = now()
            WHERE breaker_provider = $1 AND breaker_model = $2
              AND status = 'failed'
              AND provider_hold IS NOT NULL
              -- An EXPIRED marker is terminal: a close must never revive a job
              -- that already dead-lettered for the hold.
              AND COALESCE(provider_hold ->> 'state', '') <> 'expired'
            RETURNING id, pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(provider.as_str())
        .bind(model)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let mut ids = Vec::with_capacity(rows.len());
        for row in rows {
            let id =
                AiImportJobId::from_uuid(row.try_get::<Uuid, _>("id").map_err(map_sqlx_error)?);
            self.hub.notify(id);
            ids.push(id);
        }
        Ok(ids)
    }

    /// Dead-letter the held jobs whose own deadline passed (issue #871, D-C4).
    ///
    /// The only path that can reach such a job: it is `failed` while its pair is
    /// open, so the claim predicate keeps it unclaimable, and `mark_held`'s
    /// owner fence needs a `running` row that no longer exists. Keyed on the
    /// **job's own** `hold_deadline`, never on a claim.
    ///
    /// `retries` stays untouched and exactly one attempt row is written: the
    /// document did not fail, the provider did. `provider_hold` is **kept** with
    /// `state = expired` — the durable marker that lets a client tell "the
    /// provider never came back" from "your retries are used up" (the two must
    /// never share copy).
    async fn expire_provider_holds(
        &self,
        error_summary: &str,
        error_code: Option<&str>,
    ) -> Result<Vec<AiImportJobId>, DomainError> {
        // One attempt id PER expired job (issue #871 review): a single bound id
        // would be inserted for every row of the CTE and violate the attempt
        // primary key as soon as two holds expire in one tick — rolling the whole
        // statement back and leaving the D-C4 budget unenforced forever, because
        // the next tick would fail the same way.
        //
        // The ids are generated here (UUIDv7, per the repo rule) and joined to the
        // candidate rows by ordinality, which also bounds the batch: at most
        // `EXPIRE_BATCH` holds are examined per tick.
        let attempt_ids: Vec<Uuid> = (0..EXPIRE_BATCH).map(|_| Uuid::now_v7()).collect();
        let rows = sqlx::query(
            r#"
            WITH due AS (
                SELECT id
                FROM ai_import.ai_import_job
                WHERE status = 'failed'
                  AND provider_hold IS NOT NULL
                  AND (provider_hold ->> 'hold_deadline')::timestamptz <= now()
                ORDER BY (provider_hold ->> 'hold_deadline')::timestamptz
                LIMIT $4
                FOR UPDATE SKIP LOCKED
            ),
            numbered AS (
                SELECT id, row_number() OVER (ORDER BY id) AS rn FROM due
            ),
            expired AS (
                UPDATE ai_import.ai_import_job AS job
                SET status = 'dead_letter',
                    last_error = LEFT($1, 1000),
                    next_attempt_at = NULL,
                    progress = NULL,
                    decision_telemetry = NULL,
                    -- KEPT, not nulled: the marker the client branches on.
                    provider_hold = jsonb_set(
                        provider_hold,
                        '{state}',
                        '"expired"'
                    ),
                    provider_hold_series_started_at = NULL,
                    worker_id = NULL,
                    lease_expires_at = NULL,
                    permit_id = NULL,
                    updated_at = now()
                FROM numbered
                WHERE job.id = numbered.id
                RETURNING job.id, job.retries, job.last_error, numbered.rn,
                    pg_notify('ai_import_job_events', job.id::text)
            ),
            -- Issue #871 (D-B1): hold expiry is terminal (`dead_letter`), so any
            -- chunks stored before the hold are deleted in the same statement.
            cleared AS (
                DELETE FROM ai_import.ai_import_job_chunk
                WHERE job_id IN (SELECT id FROM expired)
            )
            INSERT INTO ai_import.ai_import_job_attempt
                (id, job_id, attempt_no, status, error_summary, error_code, retryable)
            -- Exactly ONE attempt row per expired job, each with its own id.
            SELECT lease.attempt_id, expired.id, expired.retries + 1, 'dead_letter',
                   expired.last_error, $3, FALSE
            FROM expired
            JOIN unnest($2::uuid[]) WITH ORDINALITY AS lease(attempt_id, rn)
              ON lease.rn = expired.rn
            RETURNING job_id
            "#,
        )
        .bind(error_summary)
        .bind(&attempt_ids)
        .bind(error_code)
        .bind(EXPIRE_BATCH)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let mut ids = Vec::with_capacity(rows.len());
        for row in rows {
            let id =
                AiImportJobId::from_uuid(row.try_get::<Uuid, _>("job_id").map_err(map_sqlx_error)?);
            self.hub.notify(id);
            ids.push(id);
        }
        Ok(ids)
    }

    /// Record one paid-call outcome in the durable breaker (issue #871).
    ///
    /// Delegates to the breaker repository over the same pool, so the state
    /// machine has exactly one implementation and the queue needs no second
    /// wiring handle. Constructing the repository per call is a `PgPool` clone —
    /// it holds no state of its own.
    async fn record_provider_outcome(
        &self,
        provider: LlmProvider,
        model: &str,
        outcome: ProviderOutcome,
        threshold: u32,
    ) -> Result<BreakerDecision, DomainError> {
        let health = super::provider_health::PgProviderHealth::new(self.pool.clone());
        match outcome {
            ProviderOutcome::Success => health.record_success(provider, model).await,
            // A PERMANENT failure must never open the breaker: it would convert
            // one user's misconfiguration into an outage for everyone on the
            // endpoint (D-A1). It is therefore not reported to the counter at all.
            ProviderOutcome::PermanentFailure => Ok(BreakerDecision::unchanged(BreakerCounters {
                state: ProviderBreakerState::Closed,
                consecutive_failures: 0,
                flap_count: 0,
                closed_at: None,
            })),
            ProviderOutcome::RetryableFailure => {
                health.record_failure(provider, model, threshold).await
            }
        }
    }

    /// The provider breaker's verdict for one pair (issue #871).
    ///
    /// A single primary-key read, and `closed` when the pair has no row (never
    /// seen a failure, so nothing to hold for). The claim predicate is the
    /// authority; this is the cheap consult the worker uses mid-run.
    async fn provider_breaker(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<ProviderBreakerSnapshot, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT state, consecutive_failures, flap_count, retry_at
            FROM ai_import.provider_health
            WHERE provider = $1 AND model = $2
            "#,
        )
        .bind(provider.as_str())
        .bind(model)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let Some(row) = row else {
            return Ok(ProviderBreakerSnapshot::closed());
        };
        let raw: String = row.try_get("state").map_err(map_sqlx_error)?;
        let state = match raw.as_str() {
            "open" => ProviderBreakerState::Open,
            "half_open" => ProviderBreakerState::HalfOpen,
            _ => ProviderBreakerState::Closed,
        };
        Ok(ProviderBreakerSnapshot {
            state,
            consecutive_failures: u32::try_from(
                row.try_get::<i32, _>("consecutive_failures")
                    .map_err(map_sqlx_error)?,
            )
            .unwrap_or(0),
            flap_count: u32::try_from(
                row.try_get::<i32, _>("flap_count")
                    .map_err(map_sqlx_error)?,
            )
            .unwrap_or(0),
            retry_at: row.try_get("retry_at").map_err(map_sqlx_error)?,
        })
    }

    /// Owner-fenced, throttled progress write (issue #664, ADR-038 D3).
    ///
    /// Same fence as every other worker transition: a worker whose lease
    /// lapsed gets `Conflict` here instead of overwriting the new owner's
    /// progress — and aborts before its next billable LLM call. Called only
    /// at stage boundaries and completed chunks, never per LLM token.
    /// Claim (or steal) the apply-run slot of one job (issue #800).
    ///
    /// Single-flight, one statement: the claim wins when the slot is free
    /// (`apply_run_id IS NULL`) **or** when the current owner is demonstrably
    /// dead — its payload has not been written for longer than
    /// [`ApplyProgress::STALE_AFTER`]. The cutoff is computed in Rust from that
    /// constant (never a second interval literal in SQL), so the window has
    /// exactly one definition.
    ///
    /// The steal is what makes the crash/release path need no separate reaper: a
    /// run whose process died blocks later applies for at most one staleness
    /// window, and the next apply takes the slot over in the same statement.
    ///
    /// Two details keep that honest (issue #800 review):
    ///
    /// * a claim **clears** `apply_progress`: a stolen slot must not leave the
    ///   previous run's payload behind, or the stream would read the new owner
    ///   with a stale (or already full) payload and close on the first frame
    ///   instead of waiting for the new run's;
    /// * an owner that has **not published yet** (`apply_progress IS NULL`) is
    ///   judged by the claim's own stamp `apply_claim_at` — never by "no payload
    ///   means free". Otherwise a second apply could take the slot from a run
    ///   that simply had not written its first frame.
    ///
    /// `apply_claim_at` is deliberately a column of its own instead of the row's
    /// `updated_at` (issue #863 review): `updated_at` is bumped by every
    /// run-scoped write, including a PREVIOUS apply's post-apply summary, so a
    /// late write could advance the stamp of the current owner and understate a
    /// dead run's silence by that gap. Only the claim writes `apply_claim_at`,
    /// so the silence the refusal reports and the steal decided on is one
    /// owner-scoped instant. A claim made before that column existed has NULL
    /// there and is judged by the row stamp it used before (`COALESCE`), which
    /// is exactly the pre-#863 behaviour — never worse.
    ///
    /// `false` means a live run owns the slot — the request answers
    /// `409 ai-import.apply-in-flight` instead of interleaving two runs.
    async fn claim_apply_run(
        &self,
        id: AiImportJobId,
        run_id: ApplyRunId,
    ) -> Result<bool, DomainError> {
        // A payload older than this belongs to a run whose process is gone.
        // Bound as a timestamptz, compared against the payload's own
        // `updated_at` — the same field the stream classifies staleness by.
        let stale_before = Utc::now() - ApplyProgress::STALE_AFTER;
        let result = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET apply_run_id = $2,
                -- The slot starts empty for the new owner: a stolen payload
                -- describes a run that is over (issue #800 review).
                apply_progress = NULL,
                apply_run_seq = apply_run_seq + 1,
                -- The owner-scoped instant this claim starts (issue #863):
                -- nothing else writes it, so no other run's late write can
                -- shift the silence window below.
                apply_claim_at = now(),
                updated_at = now()
            WHERE id = $1
              AND status = 'succeeded'
              AND (
                  apply_run_id IS NULL
                  -- Claimed but nothing published yet: the CLAIM's own stamp
                  -- decides whether that owner is still alive. The fallback
                  -- covers a claim made before the column existed.
                  OR (apply_progress IS NULL
                      AND COALESCE(apply_claim_at, updated_at) < $3)
                  OR (apply_progress->>'updated_at')::timestamptz < $3
              )
            RETURNING pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(id.as_uuid())
        .bind(run_id.as_uuid())
        .bind(stale_before)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        if result.is_some() {
            self.hub.notify(id);
        }
        Ok(result.is_some())
    }

    /// Read the apply-run slot: owner, run counter, published payload and the
    /// instant the owner took the slot (issues #800, #863).
    ///
    /// `Ok(None)` when the job does not exist (the stream closes). A row that
    /// predates the migration decodes as an empty slot (`owner: None`, `seq: 0`),
    /// which the stream reads exactly like a job no apply ran for.
    ///
    /// `apply_claim_at` is selected for one reason: the claim above judges an
    /// owner that has published **nothing** by that column
    /// (`OR (apply_progress IS NULL AND COALESCE(apply_claim_at, updated_at) <
    /// $3)`), and before #863 the refusal could not report the stamp that
    /// decision was made on — a run that died before its first frame therefore
    /// had no age on the wire. Reporting the same column here keeps the steal
    /// and the reported verdict on ONE owner-scoped instant; the row's
    /// `updated_at` would not do, because another run's late summary write can
    /// advance it (issue #863 review).
    async fn apply_run_state(
        &self,
        id: AiImportJobId,
    ) -> Result<Option<ApplyRunState>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT apply_progress, apply_run_id, apply_run_seq, apply_claim_at
            FROM ai_import.ai_import_job
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let Some(row) = row else {
            return Ok(None);
        };
        let owner: Option<Uuid> = row.try_get("apply_run_id").map_err(map_sqlx_error)?;
        let seq: i64 = row.try_get("apply_run_seq").map_err(map_sqlx_error)?;
        Ok(Some(ApplyRunState {
            owner: owner.map(ApplyRunId::from_uuid),
            seq,
            progress: decode_apply_progress(&row),
            // NULL for a claim made before the column existed: no age, rather
            // than a stamp another run's write could have moved.
            owner_claimed_at: row.try_get("apply_claim_at").map_err(map_sqlx_error)?,
        }))
    }

    /// Run-scoped (not job-scoped) apply-progress write (issues #762, #800).
    ///
    /// Fenced by the run identity instead of a worker lease: the job is already
    /// terminal (`succeeded`) while its apply runs, so there is no claim to
    /// fence on — the same shape as [`AiImportQueue::record_telemetry`], the
    /// other write the API edge performs. The status predicate stays as the
    /// outer guard: an apply can only ever run against a `succeeded` job.
    ///
    /// A write from a run that no longer owns the slot affects 0 rows and is a
    /// no-op — that is what keeps a superseded run (its claim went stale and was
    /// stolen) from overwriting or clearing the current run's progress.
    ///
    /// `None` clears the payload **and** releases the claim (`apply_run_id`),
    /// leaving `apply_run_seq` untouched so the ended run stays provable. Every
    /// write bumps `updated_at` and notifies the wake-up hub, so the dedicated
    /// apply stream pushes a frame per write without polling.
    async fn mark_apply_progress(
        &self,
        id: AiImportJobId,
        run_id: ApplyRunId,
        progress: Option<&ApplyProgress>,
    ) -> Result<(), DomainError> {
        let payload = match progress {
            Some(progress) => Some(serde_json::to_value(progress).map_err(|error| {
                DomainError::validation(format!(
                    "AI import apply progress is not serializable: {error}"
                ))
            })?),
            None => None,
        };
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET apply_progress = $3,
                apply_run_id = CASE WHEN $3::jsonb IS NULL THEN NULL ELSE apply_run_id END,
                updated_at = now()
            WHERE id = $1 AND status = 'succeeded' AND apply_run_id = $2
            RETURNING pg_notify('ai_import_job_events', id::text)
            "#,
        )
        .bind(id.as_uuid())
        .bind(run_id.as_uuid())
        .bind(payload)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        self.hub.notify(id);
        Ok(())
    }

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
                accept_as_is = $12, edit_distance = $13,
                scenes_detected = $14, scenes_extracted = $15,
                scenes_synthesized = $16, decision_telemetry = $17,
                updated_at = now()
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

    /// Attach the write target of a block-less job, set-once (issue #829).
    ///
    /// One statement carries the set-once contract so no read-then-write window
    /// exists: `block_id IS NULL` makes it attach-only, and
    /// `accept_as_is IS NULL` refuses a job whose apply already recorded rows
    /// (`AiImportJob::applied` is derived from that column). The block id and the
    /// number the visible snapshot renders move together, and
    /// `updated_at` is touched so the jobs list re-orders like any other write.
    ///
    /// A zero-row result is then diagnosed with ONE follow-up read, which is
    /// only ever reached by a refusal path or an idempotent repeat — never by a
    /// successful attach.
    async fn set_target_once(
        &self,
        id: AiImportJobId,
        block_id: BlockId,
        block_number: i32,
    ) -> Result<TargetAttachOutcome, DomainError> {
        let attached = sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET block_id = $2,
                target_block_number = $3,
                updated_at = now()
            WHERE id = $1
              AND block_id IS NULL
              AND accept_as_is IS NULL
              -- A job without a target SEASON cannot receive a block: the
              -- season is the attach's authorization scope and the snapshot's
              -- other half, so storing the number alone would leave a target
              -- that no longer decodes (review of #829).
              AND target_season_id IS NOT NULL
            "#,
        )
        .bind(id.as_uuid())
        .bind(block_id.0)
        .bind(block_number)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        if attached.rows_affected() == 1 {
            // Same wake-up the other writes emit: a watching client must see the
            // attached target without reconnecting (issue #664).
            self.hub.notify(id);
            return Ok(TargetAttachOutcome::Attached);
        }
        // Diagnose the refusal. `try_get` on a missing row degrades to NotFound
        // below; a decode fault on `accept_as_is` is mapped, never defaulted, so
        // an "applied" job can never be mistaken for a free slot.
        let row = sqlx::query(
            r#"
            SELECT block_id, accept_as_is, target_season_id
            FROM ai_import.ai_import_job
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let Some(row) = row else {
            return Ok(TargetAttachOutcome::NotFound);
        };
        let applied = row
            .try_get::<Option<bool>, _>("accept_as_is")
            .map_err(map_sqlx_error)?
            .is_some();
        let existing: Option<Uuid> = row
            .try_get::<Option<Uuid>, _>("block_id")
            .map_err(map_sqlx_error)?;
        // The SAME block is an idempotent success, checked BEFORE the applied
        // state (review of #829): a retry after the rows landed asks for nothing
        // that is not already true, and answering 409 there would report a
        // frozen target for a request that is satisfied.
        if existing == Some(block_id.0) {
            return Ok(TargetAttachOutcome::Unchanged);
        }
        if applied {
            return Ok(TargetAttachOutcome::AlreadyApplied);
        }

        let has_target_season = row
            .try_get::<Option<Uuid>, _>("target_season_id")
            .map_err(map_sqlx_error)?
            .is_some();
        if !has_target_season {
            return Ok(TargetAttachOutcome::NoTargetSeason);
        }
        Ok(match existing {
            Some(existing) => TargetAttachOutcome::AlreadySet {
                existing_block_id: BlockId::from_uuid(existing),
            },
            // No block and no apply: the UPDATE above matched, so this is a race
            // with a concurrent attach/apply. Reporting `AlreadyApplied` is the
            // safe direction — it never claims a slot the caller did not get.
            None => TargetAttachOutcome::AlreadyApplied,
        })
    }
}

/// Narrow one script scene reconciliation counter (issue #758) to its database
/// type.
///
/// Extracted so the three counters cannot drift into three hand-written range
/// checks, and so a `u32` above `i32::MAX` fails loudly instead of wrapping into
/// a negative count.
fn scene_count(value: u32, label: &str) -> Result<i32, DomainError> {
    i32::try_from(value).map_err(|error| {
        DomainError::validation(format!(
            "AI {label} scene counter exceeds database range: {error}"
        ))
    })
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
    scenes_detected: i32,
    scenes_extracted: i32,
    scenes_synthesized: i32,
    /// The Decision Model outcome as JSONB (issue #767). `None` for the apply
    /// path's unfenced write, which must never rewrite the completion-time
    /// snapshot.
    decision: Option<serde_json::Value>,
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
            scenes_detected: scene_count(telemetry.scenes_detected, "detected")?,
            scenes_extracted: scene_count(telemetry.scenes_extracted, "extracted")?,
            scenes_synthesized: scene_count(telemetry.scenes_synthesized, "synthesized")?,
            decision: telemetry
                .decision
                .map(serde_json::to_value)
                .transpose()
                .map_err(|error| {
                    DomainError::validation(format!(
                        "AI decision telemetry cannot be serialized: {error}"
                    ))
                })?,
        })
    }

    /// Bind the fifteen telemetry columns in the exact order both UPDATE
    /// statements declare their placeholders: `tokens_in`, `tokens_out`,
    /// `latency_total_ms`, then the #675 trio `cached_tokens_in`,
    /// `energy_millijoules`, `cost` — a wrong order would be silently
    /// type-compatible between the integer columns (the jsonb `cost` binding
    /// against `energy_millijoules` is the only mismatch Postgres rejects) —
    /// and, last, the #767 decision `jsonb`.
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
            .bind(self.scenes_detected)
            .bind(self.scenes_extracted)
            .bind(self.scenes_synthesized)
            .bind(self.decision)
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
        // The declared import target (issue #771). Resolved at the API edge,
        // stored purely for attribution: `block_id` stays the authoritative
        // write target. Absent for pre-#771 rows.
        target: decode_import_target(&row),
        // The breaker key snapshot (issue #871, D-A2b). `NULL` for every
        // pre-#871 row and for an upload whose config could not be resolved:
        // such a job is never breaker-filtered, which is the honest
        // degradation.
        provider: decode_job_provider(&row),
        model: row.try_get("breaker_model").map_err(map_sqlx_error)?,
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
        // The provider hold (issue #871). Advisory visibility data like
        // `progress`: an undecodable payload degrades to `None` rather than
        // failing the whole job read.
        provider_hold: decode_provider_hold(&row),
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
        // Derived at the read edge (issue #864): `get`/`list_for_user` fill
        // this from the durable apply mappings. Claim contexts leave it empty
        // because no client reads a claimed job.
        applied_episodes: Vec::new(),
        // Job-level Decision Model outcome (issue #767). Advisory: a NULL
        // column (pre-#767 row, or a job no worker completed) renders as the
        // honest "not recorded" rather than a guessed class.
        decision_telemetry: decode_job_decision_telemetry(&row),
        // Apply-run progress (issue #762). Advisory like `progress`: a NULL
        // column (no apply in flight) or an undecodable payload degrades to
        // `None`, which the stream reads as "run finished".
        apply_progress: decode_apply_progress(&row),
        // Whether an apply ever landed for this preview (issue #800). The
        // telemetry write records `Applied` (`accept_as_is` set) on the first
        // successful apply and never resets it, so this is the persisted
        // "already imported" fact — independent of `applied_episodes`, which is
        // empty for a schedule apply by design.
        applied: row
            .try_get::<Option<bool>, _>("accept_as_is")
            .map_err(map_sqlx_error)?
            .is_some(),
    })
}

/// Decode the nullable `apply_progress` JSONB column (issue #762).
///
/// Advisory visibility data: a `NULL` column (no apply running), an
/// undecodable payload or a missing column degrades to `None` instead of
/// failing the whole job read.
fn decode_apply_progress(row: &sqlx::postgres::PgRow) -> Option<ApplyProgress> {
    let value: Option<serde_json::Value> = row.try_get("apply_progress").ok().flatten()?;
    match serde_json::from_value::<ApplyProgress>(value?) {
        Ok(progress) => Some(progress),
        Err(err) => {
            tracing::warn!(error = %err, "failed to decode ai_import apply progress payload");
            None
        }
    }
}

/// Decode the import-target snapshot columns (issue #771, widened by #829).
///
/// The SEASON pair is written together, so a partial season means an
/// inconsistent row (or a column added mid-flight): the snapshot degrades to
/// `None` rather than rendering a half-invented target. The block number is
/// optional since issue #829 — a block-less job carries its target season from
/// the first frame and gains the block number only when the target is attached.
fn decode_import_target(row: &sqlx::postgres::PgRow) -> Option<AiImportTarget> {
    let season_id: Option<Uuid> = row.try_get("target_season_id").ok().flatten();
    let season_number: Option<i32> = row.try_get("target_season_number").ok().flatten();
    let block_number: Option<i32> = row.try_get("target_block_number").ok().flatten();
    match (season_id, season_number) {
        (Some(season_id), Some(season_number)) => Some(AiImportTarget {
            season_id: breakdown_core::shared::SeasonId::from_uuid(season_id),
            season_number,
            block_number,
        }),
        _ => None,
    }
}

/// Decode the `provider` snapshot column into the core enum (issue #871).
///
/// An unknown or missing value degrades to `None` — the job is then never
/// breaker-filtered, which is the same honest degradation a pre-#871 row gets.
fn decode_job_provider(row: &sqlx::postgres::PgRow) -> Option<LlmProvider> {
    let raw = row
        .try_get::<Option<String>, _>("provider")
        .ok()
        .flatten()?;
    match serde_json::from_value::<LlmProvider>(serde_json::Value::String(raw)) {
        Ok(provider) => Some(provider),
        Err(err) => {
            tracing::warn!(error = %err, "failed to decode ai_import provider snapshot");
            None
        }
    }
}

/// Decode the nullable `provider_hold` JSONB column (issue #871).
///
/// Advisory visibility data: `NULL` (no hold), an undecodable payload or a
/// missing column degrades to `None` instead of failing the whole job read —
/// the same contract as `progress` and `apply_progress`.
fn decode_provider_hold(row: &sqlx::postgres::PgRow) -> Option<ProviderHold> {
    let value = row
        .try_get::<Option<serde_json::Value>, _>("provider_hold")
        .ok()
        .flatten()?;
    match serde_json::from_value::<ProviderHold>(value) {
        Ok(hold) => Some(hold),
        Err(err) => {
            tracing::warn!(error = %err, "failed to decode ai_import provider hold payload");
            None
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
    // Scene reconciliation counters (issue #758). `NOT NULL DEFAULT 0`, so an
    // absent value only happens for a row selected from a pre-migration view;
    // it degrades to 0 ("not recorded") rather than failing the read.
    let scenes_detected: i32 = row.try_get("scenes_detected").unwrap_or(0);
    let scenes_extracted: i32 = row.try_get("scenes_extracted").unwrap_or(0);
    let scenes_synthesized: i32 = row.try_get("scenes_synthesized").unwrap_or(0);
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
        scenes_detected: scenes_detected.max(0) as u32,
        scenes_extracted: scenes_extracted.max(0) as u32,
        scenes_synthesized: scenes_synthesized.max(0) as u32,
    })
}

/// Decode the persisted `cost` JSONB snapshot (issue #675). Advisory
/// transparency data: an undecodable payload degrades to `None` rather than
/// failing the whole read.
fn decode_job_cost(row: &sqlx::postgres::PgRow) -> Option<CostBreakdown> {
    let value: Option<serde_json::Value> = row.try_get("cost").ok().flatten()?;
    serde_json::from_value(value?).ok()
}

/// Decode the persisted `decision_telemetry` JSONB column (issue #767).
///
/// Same contract as [`decode_job_cost`]: transparency data, never correctness
/// state, so an undecodable payload degrades to `None` ("not recorded") instead
/// of failing the job read.
fn decode_job_decision_telemetry(row: &sqlx::postgres::PgRow) -> Option<DecisionTelemetry> {
    let value: Option<serde_json::Value> = row.try_get("decision_telemetry").ok().flatten()?;
    match serde_json::from_value::<DecisionTelemetry>(value?) {
        Ok(telemetry) => Some(telemetry),
        Err(err) => {
            tracing::warn!(
                error = %err,
                "failed to decode ai_import decision_telemetry payload"
            );
            None
        }
    }
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
