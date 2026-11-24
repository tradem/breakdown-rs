// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Durable provider circuit breaker (issue #871, workstream A).
//!
//! One row per `(provider, model)` pair in `ai_import.provider_health`. The
//! **arithmetic** lives in `breakdown_core::ai::provider_health` as pure
//! functions; this module only moves it into Postgres, so the state machine has
//! exactly one source of truth and can be tested as a table (D-X4) instead of
//! through a database.
//!
//! Why durable at all (D-A2): the claim filter must run atomically with the
//! claim (a second in-process check is a TOCTOU), N replicas must not keep N
//! independent verdicts, and a restart must not forget an outage — which is
//! exactly when a cold-start fleet would re-pay the first failure.
//!
//! Every transition is a compare-and-set on the row it read. A racing worker
//! that lost the race re-reads and re-decides (bounded), which keeps the
//! transition atomic without duplicating the state machine in SQL.
//!
//! Every committed transition logs `#871 provider breaker` with the operator
//! fields from D-X2; the durable row is the runbook query. `GET /v1/health` is
//! deliberately **not** extended: it is unauthenticated with a 2 s per-check
//! timeout, and a provider probe needs a vaulted credential.

use async_trait::async_trait;
use breakdown_core::ai::ports::{
    LlmProvider, OpenBreaker, ProbeLease, ProbeOutcome, ProviderBreakerSnapshot, ProviderHealth,
};
use breakdown_core::ai::provider_health::{
    BreakerCounters, BreakerDecision, on_probe_failure, on_probe_success, on_retryable_failure,
    on_success,
};
use breakdown_core::ai::views::AiImportJobId;
use breakdown_core::ai::views::ProviderBreakerState;
use breakdown_core::error::DomainError;
use jiff::{SignedDuration, Timestamp};
use sqlx::{PgPool, Row};
use std::time::Duration;
use uuid::Uuid;

use crate::db_time::{PgRowTimeExt, sql_ts, sql_ts_opt};

/// How long one probe lease is valid.
///
/// A probe is one HTTP request (`GET {base}/models`, or `/api/tags` for
/// Ollama), so the lease is the request timeout: a prober that is still "in
/// flight" after it has hung, and the next tick must be able to take the lease
/// over — otherwise one hung probe would wedge `half_open` forever.
const PROBE_LEASE_SECS: i64 = 120;

/// How often a compare-and-set may lose to a concurrent worker before the write
/// gives up.
///
/// Losing is normal (several workers report failures of the same pair at once)
/// and cheap to retry: the loser re-reads the row it just lost and re-applies
/// the same pure decision to the fresh counters.
const CAS_ATTEMPTS: usize = 4;

/// Postgres-backed [`ProviderHealth`].
#[derive(Debug, Clone)]
pub struct PgProviderHealth {
    pool: PgPool,
}

impl PgProviderHealth {
    #[must_use]
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Read the row, creating the default `closed` row when the pair has never
    /// failed.
    async fn read_or_create(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<(ProviderBreakerSnapshot, Option<Timestamp>), DomainError> {
        // An upsert rather than an INSERT after a failed SELECT: the pair may be
        // created by two replicas at the same instant, and `DO NOTHING` makes
        // the loser harmless.
        sqlx::query(
            r#"
            INSERT INTO ai_import.provider_health (provider, model)
            VALUES ($1, $2)
            ON CONFLICT (provider, model) DO NOTHING
            "#,
        )
        .bind(provider.as_str())
        .bind(model)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        self.read(provider, model).await
    }

    async fn read(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<(ProviderBreakerSnapshot, Option<Timestamp>), DomainError> {
        let row = sqlx::query(
            r#"
            SELECT state, consecutive_failures, flap_count, retry_at, closed_at, trial_job_id
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
            return Ok((ProviderBreakerSnapshot::closed(), None));
        };
        let state = parse_state(row.try_get("state").map_err(map_sqlx_error)?);
        Ok((
            ProviderBreakerSnapshot {
                state,
                consecutive_failures: clamp_u32(
                    row.try_get::<i32, _>("consecutive_failures")
                        .map_err(map_sqlx_error)?,
                ),
                flap_count: clamp_u32(
                    row.try_get::<i32, _>("flap_count")
                        .map_err(map_sqlx_error)?,
                ),
                retry_at: row.get_ts_opt("retry_at").map_err(map_sqlx_error)?,
                trial_job: row
                    .try_get::<Option<Uuid>, _>("trial_job_id")
                    .map_err(map_sqlx_error)?,
            },
            row.get_ts_opt("closed_at").map_err(map_sqlx_error)?,
        ))
    }

    /// Apply `decision` as a compare-and-set against the counters it was
    /// computed from.
    ///
    /// `opened_at` is stamped only when this write is the one that opens the
    /// breaker, so the operator query can answer "since when".
    async fn cas(
        &self,
        provider: LlmProvider,
        model: &str,
        observed: BreakerCounters,
        decision: BreakerDecision,
    ) -> Result<bool, DomainError> {
        let result = sqlx::query(
            r#"
            UPDATE ai_import.provider_health
            SET state = $3,
                consecutive_failures = $4,
                flap_count = $5,
                retry_at = $6,
                opened_at = CASE WHEN $7 THEN now() ELSE opened_at END,
                closed_at = CASE WHEN $8 THEN now() ELSE closed_at END,
                last_failure_at = CASE WHEN $9 THEN now() ELSE last_failure_at END,
                -- Issue #942 W1: the trial token lives only in `half_open`.
                -- Opening or closing must clear it, or a later window would
                -- silently inherit a stale holder and admit the wrong job.
                trial_job_id = CASE WHEN $3 = 'half_open' THEN trial_job_id ELSE NULL END,
                -- A close ends the probe: no owner, no lease, no started stamp.
                probe_owner = CASE WHEN $8 THEN NULL ELSE probe_owner END,
                probe_lease_id = CASE WHEN $8 THEN NULL ELSE probe_lease_id END,
                probe_started_at = CASE WHEN $8 THEN NULL ELSE probe_started_at END,
                updated_at = now()
            WHERE provider = $1 AND model = $2
              AND state = $10
              AND consecutive_failures = $11
            "#,
        )
        .bind(provider.as_str())
        .bind(model)
        .bind(decision.state.as_str())
        .bind(decision.consecutive_failures as i32)
        .bind(decision.flap_count as i32)
        .bind(sql_ts_opt(decision.retry_at))
        .bind(decision.opened)
        .bind(decision.closed)
        .bind(decision.state != ProviderBreakerState::Closed)
        .bind(observed.state.as_str())
        .bind(observed.consecutive_failures as i32)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(result.rows_affected() == 1)
    }

    /// Emit the operator log line for one committed transition (D-X2).
    fn log_transition(
        provider: LlmProvider,
        model: &str,
        decision: &BreakerDecision,
        trigger: &'static str,
    ) {
        tracing::warn!(
            provider = provider.as_str(),
            model = model,
            state = decision.state.as_str(),
            consecutive_failures = decision.consecutive_failures,
            retry_at = ?decision.retry_at,
            flap_count = decision.flap_count,
            trigger,
            "#871 provider breaker"
        );
    }
}

#[async_trait]
impl ProviderHealth for PgProviderHealth {
    async fn state(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<ProviderBreakerSnapshot, DomainError> {
        let (snapshot, _) = self.read(provider, model).await?;
        Ok(snapshot)
    }

    async fn record_failure(
        &self,
        provider: LlmProvider,
        model: &str,
        threshold: u32,
        retry_after: Option<std::time::Duration>,
    ) -> Result<BreakerDecision, DomainError> {
        for _ in 0..CAS_ATTEMPTS {
            let (snapshot, closed_at) = self.read_or_create(provider, model).await?;
            let counters = BreakerCounters {
                state: snapshot.state,
                consecutive_failures: snapshot.consecutive_failures,
                flap_count: snapshot.flap_count,
                closed_at,
                retry_at: snapshot.retry_at,
            };
            // Issue #926: the provider's own wait hint becomes the floor of the
            // probe schedule, so `retry_at` (and therefore every hold's `until`)
            // already respects it when the next watch tick looks for work.
            let decision = on_retryable_failure(counters, threshold, Timestamp::now(), retry_after);
            if self.cas(provider, model, counters, decision).await? {
                // Log every committed change, including the plain counter bump:
                // an operator watching a provider degrade wants the ramp, not
                // only the opening instant.
                Self::log_transition(provider, model, &decision, "failure");
                return Ok(decision);
            }
            // Lost the race: another worker updated the row between our read and
            // our write. Re-read and re-decide against the fresh counters.
        }
        Err(DomainError::conflict(
            "provider breaker write lost every compare-and-set attempt",
        ))
    }

    async fn record_success(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<BreakerDecision, DomainError> {
        for _ in 0..CAS_ATTEMPTS {
            let (snapshot, closed_at) = self.read_or_create(provider, model).await?;
            let counters = BreakerCounters {
                state: snapshot.state,
                consecutive_failures: snapshot.consecutive_failures,
                flap_count: snapshot.flap_count,
                closed_at,
                retry_at: snapshot.retry_at,
            };
            let decision = on_success(counters);
            if self.cas(provider, model, counters, decision).await? {
                Self::log_transition(provider, model, &decision, "paid-call-success");
                return Ok(decision);
            }
        }
        Err(DomainError::conflict(
            "provider breaker write lost every compare-and-set attempt",
        ))
    }

    async fn try_begin_probe(
        &self,
        provider: LlmProvider,
        model: &str,
        owner: &str,
    ) -> Result<Option<ProbeLease>, DomainError> {
        // One statement does the CAS *and* the lease fencing. `retry_at` is read
        // here and nowhere else — it is the probe schedule, never a claim gate
        // (D-A2).
        //
        // Two admissions, and the second is what keeps a hung probe from
        // wedging `half_open` forever (D-A6):
        //
        // * from `open`, the probe must be due and no live lease may hold the
        //   row — the ordinary window;
        // * from `half_open`, the current lease must be **stale** (or absent)
        //   AND no trial may be **live**. Without the first test a probe that
        //   hangs after its CAS would leave the pair in `half_open` for good: no
        //   claim is admitted in that state (D-A2) and nothing else can leave it,
        //   so one dead HTTP request would stop every job of that pair
        //   permanently. Without the second, a **delayed sweeper** — one that read
        //   the pair while it was still `open` and calls this after another
        //   sweeper granted the trial — acquires a lease over a paid call that is
        //   still running; `finish_probe(Usable)` then clears that live
        //   `trial_job_id` and grants a second trial inside the same window.
        //
        // `retry_at` carries the trial deadline: a grant arms it to
        // `now() + TRIAL_WINDOW_SECS`, so "no holder, or its window elapsed" is
        // exactly the fence that still lets an EXPIRED trial be recovered here.
        let lease_id = Uuid::now_v7();
        let result = sqlx::query(
            r#"
            UPDATE ai_import.provider_health
            SET state = 'half_open',
                probe_owner = $3,
                probe_lease_id = $4,
                probe_started_at = now(),
                updated_at = now()
            WHERE provider = $1 AND model = $2
              AND (
                  (
                      state = 'open'
                      AND (retry_at IS NULL OR retry_at <= now())
                      AND (
                          probe_lease_id IS NULL
                          OR probe_started_at IS NULL
                          OR probe_started_at <= now() - make_interval(secs => $5)
                      )
                  )
                  OR (
                      state = 'half_open'
                      AND (
                          probe_started_at IS NULL
                          OR probe_started_at <= now() - make_interval(secs => $5)
                      )
                      -- Issue #942 W1 follow-up: never probe over a LIVE trial.
                      AND (trial_job_id IS NULL OR retry_at IS NULL OR retry_at <= now())
                  )
              )
            "#,
        )
        .bind(provider.as_str())
        .bind(model)
        .bind(owner)
        .bind(lease_id)
        .bind(PROBE_LEASE_SECS)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        if result.rows_affected() != 1 {
            return Ok(None);
        }
        tracing::warn!(
            provider = provider.as_str(),
            model = model,
            state = "half_open",
            probe_owner = owner,
            probe_lease_id = %lease_id,
            "#871 provider breaker"
        );
        Ok(Some(ProbeLease {
            provider,
            model: model.to_string(),
            owner: owner.to_string(),
            lease_id,
        }))
    }

    async fn finish_probe(
        &self,
        lease: &ProbeLease,
        outcome: ProbeOutcome,
    ) -> Result<BreakerDecision, DomainError> {
        match outcome {
            ProbeOutcome::Usable => {
                // Issue #942 W1: a passing preflight releases the LEASE and
                // leaves the breaker `half_open` with no trial holder — the
                // caller then grants exactly one trial. It deliberately does not
                // close: `GET /key` answers 200 in 0.2 s while the model's chat
                // path stalls at 120 s, so closing here is the flap loop of
                // issue #942 F2.
                //
                // Fenced on the LEASE, not on the owner: the same task can
                // reacquire the lease, so an owner check would accept a stale
                // result.
                let result = sqlx::query(
                    r#"
                    UPDATE ai_import.provider_health
                    SET state = 'half_open',
                        consecutive_failures = 0,
                        retry_at = $4,
                        trial_job_id = NULL,
                        probe_owner = NULL,
                        probe_lease_id = NULL,
                        probe_started_at = NULL,
                        updated_at = now()
                    WHERE provider = $1 AND model = $2
                      AND state = 'half_open'
                      AND probe_lease_id = $3
                    "#,
                )
                .bind(lease.provider.as_str())
                .bind(&lease.model)
                .bind(lease.lease_id)
                .bind(sql_ts(Timestamp::now()))
                .execute(&self.pool)
                .await
                .map_err(map_sqlx_error)?;
                if result.rows_affected() != 1 {
                    // Stale lease: another task owns the state now. Discard —
                    // the same discipline as `ensure_claim_owned`.
                    tracing::debug!(
                        provider = lease.provider.as_str(),
                        model = lease.model,
                        probe_lease_id = %lease.lease_id,
                        "#871 provider breaker: stale probe result discarded"
                    );
                    return Err(DomainError::conflict(
                        "provider breaker write lost every compare-and-set attempt",
                    ));
                }
                let decision = on_probe_success(
                    BreakerCounters {
                        state: ProviderBreakerState::HalfOpen,
                        consecutive_failures: 0,
                        // Read, not assumed: the trial window and the escalation
                        // inherit the pair's flap history.
                        flap_count: self
                            .read(lease.provider, &lease.model)
                            .await
                            .map(|(snapshot, _)| snapshot.flap_count)
                            .unwrap_or(0),
                        closed_at: None,
                        retry_at: None,
                    },
                    Timestamp::now(),
                );
                Self::log_transition(lease.provider, &lease.model, &decision, "probe-usable");
                Ok(decision)
            }
            ProbeOutcome::NotUsable => {
                // The decision's `retry_at` needs the current flap count, so read
                // it first — the write below is still fenced on the lease, which
                // is what makes the read harmless.
                let (snapshot, closed_at) = self.read(lease.provider, &lease.model).await?;
                let counters = BreakerCounters {
                    state: snapshot.state,
                    consecutive_failures: snapshot.consecutive_failures,
                    flap_count: snapshot.flap_count,
                    closed_at,
                    retry_at: snapshot.retry_at,
                };
                let decision = on_probe_failure(counters, Timestamp::now());
                let result = sqlx::query(
                    r#"
                    UPDATE ai_import.provider_health
                    SET state = 'open',
                        retry_at = $4,
                        trial_job_id = NULL,
                        probe_owner = NULL,
                        probe_lease_id = NULL,
                        probe_started_at = NULL,
                        updated_at = now()
                    WHERE provider = $1 AND model = $2
                      AND state = 'half_open'
                      AND probe_lease_id = $3
                    "#,
                )
                .bind(lease.provider.as_str())
                .bind(&lease.model)
                .bind(lease.lease_id)
                .bind(sql_ts_opt(decision.retry_at))
                .execute(&self.pool)
                .await
                .map_err(map_sqlx_error)?;
                if result.rows_affected() != 1 {
                    tracing::debug!(
                        provider = lease.provider.as_str(),
                        model = lease.model,
                        probe_lease_id = %lease.lease_id,
                        "#871 provider breaker: stale probe result discarded"
                    );
                    return Err(DomainError::conflict(
                        "provider breaker write lost every compare-and-set attempt",
                    ));
                }
                Self::log_transition(lease.provider, &lease.model, &decision, "probe-not-usable");
                Ok(decision)
            }
        }
    }

    /// Grant the single half-open trial (issue #942 W1).
    ///
    /// One statement, because the three effects must not be observable apart:
    /// the breaker token is minted, the chosen job becomes claimable again
    /// (`next_attempt_at = now()`), and the pair's window is re-armed so a
    /// permanently broken model costs one paid call per window instead of a
    /// storm. The `state = 'half_open' AND trial_job_id IS NULL` guard makes it
    /// idempotent against a second sweeper: the loser stamps nothing.
    ///
    /// The `probe_lease_id IS NULL` guard is the second half of that fence
    /// (issue #942 W1 follow-up). A `half_open` pair with no holder has two
    /// meanings, and only one of them may be granted here: a **finished probe**
    /// (lease released) is grantable, a **probe in flight** is not. Stamping a
    /// holder while a probe lease is outstanding put two paid trials in one
    /// window — the in-flight probe's own fenced `finish_probe` clears
    /// `trial_job_id` on success and grants a *second* trial behind it. A
    /// **stale** lease is not grantable either: the recovery for a hung prober
    /// is the takeover branch of `try_begin_probe`, which re-dates the lease so
    /// the hung prober's result is fenced out.
    ///
    /// The candidate is the pair's longest-waiting held job — the same ordering
    /// the probe uses for its credential donor, so a fresh upload does not
    /// starve an older job.
    async fn begin_provider_trial(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<Option<AiImportJobId>, DomainError> {
        let rows = sqlx::query(
            r#"
            WITH candidate AS (
                SELECT id, flap_count
                FROM ai_import.ai_import_job
                JOIN ai_import.provider_health
                  ON provider_health.provider = ai_import.ai_import_job.breaker_provider
                 AND provider_health.model = ai_import.ai_import_job.breaker_model
                WHERE ai_import.ai_import_job.breaker_provider = $1
                  AND ai_import.ai_import_job.breaker_model = $2
                  AND ai_import.ai_import_job.status = 'failed'
                  AND ai_import.ai_import_job.provider_hold IS NOT NULL
                  AND COALESCE(ai_import.ai_import_job.provider_hold ->> 'state', '') <> 'expired'
                  AND provider_health.state = 'half_open'
                  AND provider_health.trial_job_id IS NULL
                  -- Issue #942 W1 follow-up: no outstanding probe lease. A live
                  -- lease belongs to an in-flight probe, and a stale one to a
                  -- hung prober that `try_begin_probe` must recover instead.
                  AND provider_health.probe_lease_id IS NULL
                ORDER BY ai_import.ai_import_job.created_at
                LIMIT 1
                -- Postgres accepts only UNQUALIFIED relation names here, so this is
                -- `ai_import_job`, not `ai_import.ai_import_job` (the qualified form
                -- is a runtime error the SQL cannot report at compile time).
                FOR UPDATE OF ai_import_job SKIP LOCKED
            ),
            stamped AS (
                UPDATE ai_import.provider_health
                SET trial_job_id = (SELECT id FROM candidate),
                    retry_at = now() + make_interval(secs => $3),
                    updated_at = now()
                WHERE provider = $1 AND model = $2
                  AND state = 'half_open'
                  AND trial_job_id IS NULL
                  AND probe_lease_id IS NULL
                  AND EXISTS (SELECT 1 FROM candidate)
                RETURNING trial_job_id
            ),
            released AS (
                UPDATE ai_import.ai_import_job
                SET next_attempt_at = now(),
                    updated_at = now()
                WHERE id IN (SELECT trial_job_id FROM stamped)
                RETURNING id
            )
            SELECT id, pg_notify('ai_import_job_events', id::text) FROM released
            "#,
        )
        .bind(provider.as_str())
        .bind(model)
        .bind(TRIAL_WINDOW_SECS)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let Some(row) = rows.first() else {
            return Ok(None);
        };
        let id = AiImportJobId::from_uuid(row.try_get::<Uuid, _>("id").map_err(map_sqlx_error)?);
        Ok(Some(id))
    }

    async fn open_breakers(&self, limit: i64) -> Result<Vec<OpenBreaker>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT provider, model, state, retry_at, trial_job_id, probe_started_at
            FROM ai_import.provider_health
            WHERE state <> 'closed'
            ORDER BY retry_at NULLS FIRST, provider, model
            LIMIT $1
            "#,
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let mut breakers = Vec::with_capacity(rows.len());
        for row in rows {
            let raw: String = row.try_get("provider").map_err(map_sqlx_error)?;
            let Some(provider) = parse_provider(&raw) else {
                tracing::warn!(
                    provider = raw,
                    "#871 provider breaker: unknown provider row"
                );
                continue;
            };
            breakers.push(OpenBreaker {
                provider,
                model: row.try_get("model").map_err(map_sqlx_error)?,
                state: parse_state(row.try_get("state").map_err(map_sqlx_error)?),
                retry_at: row.get_ts_opt("retry_at").map_err(map_sqlx_error)?,
                trial_job: row
                    .try_get::<Option<Uuid>, _>("trial_job_id")
                    .map_err(map_sqlx_error)?,
                probe_started_at: row.get_ts_opt("probe_started_at").map_err(map_sqlx_error)?,
            });
        }
        Ok(breakers)
    }
}

/// The internal, never-serialized sentinel for "the provider breaker is open"
/// (issue #871, D-C2/2.9b).
///
/// Deliberately **not** a retryable `ServiceUnavailable` — that is exactly the
/// shape `is_transient` retries, which is the bug the breaker removes — and
/// deliberately **not** a new problem code (D-X1: a hold is not an error, it has
/// no HTTP surface of its own). `Conflict` is this codebase's established
/// internal-terminal channel for worker-only states (`ensure_claim_owned` uses
/// it for a lost claim), and the AI worker path never maps it to a handler
/// response. [`is_breaker_open`] is the one place that recognises it, so no
/// caller has to match on the string.
pub const BREAKER_OPEN_REASON: &str = "ai-import provider breaker is open";

/// The sentinel a gated call returns when the breaker refuses it.
pub fn breaker_open_error() -> DomainError {
    breaker_open_error_with_usage(Vec::new())
}

/// The breaker sentinel carrying the usage the attempt ALREADY billed
/// (issue #970, CodeRabbit review PR #967): completed responses of the same
/// attempt whose answers were discarded by the refusal must reach the
/// caller's accounting, so the sentinel transports them instead of dropping
/// them at the client boundary.
///
/// `calls` is the **per-request ledger** of those responses, one entry per
/// paid request (CodeRabbit review, PR #967 round 13): the caller persists
/// them so the #794 energy cap can be applied per request.
pub fn breaker_open_error_with_usage(calls: Vec<breakdown_core::ai::LlmCallUsage>) -> DomainError {
    DomainError::BreakerOpen {
        code: &breakdown_core::error_registry::DOMAIN_CONFLICT,
        reason: BREAKER_OPEN_REASON.to_owned(),
        usage: std::sync::Arc::new(calls),
    }
}

/// Whether an error is the breaker sentinel rather than a real failure.
pub fn is_breaker_open(error: &DomainError) -> bool {
    match error {
        DomainError::BreakerOpen { .. } => true,
        DomainError::Conflict { reason, .. } => reason == BREAKER_OPEN_REASON,
        _ => false,
    }
}

/// The already-billed requests a breaker sentinel carries (issue #970), one
/// entry per paid request; empty for any other error.
pub(crate) fn orphaned_usage(error: &DomainError) -> Option<Vec<breakdown_core::ai::LlmCallUsage>> {
    match error {
        DomainError::BreakerOpen { usage, .. } => Some(usage.as_ref().clone()),
        _ => None,
    }
}

/// How long one granted trial may take before the next one is considered
/// (issue #942 W1).
///
/// One request (`AI_IMPORT_REQUEST_TIMEOUT_SECS`, 120 s default) plus a small
/// margin, so a hung trial cannot wedge `half_open` for longer than a single
/// request: the lease window is the same order of magnitude for the same reason.
pub const TRIAL_WINDOW_SECS: i64 = 300;

/// The probe lease window, exposed for the sweeper's own budgeting.
#[must_use]
pub const fn probe_lease_window() -> Duration {
    Duration::from_secs(PROBE_LEASE_SECS.unsigned_abs())
}

/// Whether an outstanding probe lease is still **live** at `now` (issue #942 W1
/// follow-up).
///
/// The sweeper needs this to tell the two meanings of "`half_open` with no trial
/// holder" apart, and they demand opposite actions:
///
/// * a **live** lease means a probe is in flight. Granting a trial then is the
///   double-trial bug: the in-flight probe's own fenced `finish_probe` clears
///   `trial_job_id` on success and grants a *second* trial in the same window;
/// * a **stale** lease means the prober hung. The recovery is the takeover
///   branch of [`ProviderHealth::try_begin_probe`], which is fenced on exactly
///   this timestamp, never a grant.
///
/// Only "no lease at all" is grantable, which is why the grant SQL additionally
/// requires `probe_lease_id IS NULL`.
#[must_use]
pub fn probe_lease_is_live(started_at: Option<Timestamp>, now: Timestamp) -> bool {
    let Some(started_at) = started_at else {
        return false;
    };
    // The window is a small positive constant, so this conversion cannot fail;
    // the `unwrap_or` keeps the "no panics" rule absolute. A degenerate window
    // only widens the direction that is safe here (treat the lease as stale and
    // recover it through the takeover instead of granting).
    let window = SignedDuration::try_from(probe_lease_window())
        .unwrap_or(SignedDuration::from_secs(PROBE_LEASE_SECS));
    started_at > now - window
}

/// Parse the durable `state` column.
///
/// The CHECK accepts three values and never `expired` (that is a *job-hold*
/// state, D-C4). An unknown value degrades to `closed` — the honest direction:
/// it admits claims rather than silently halting an endpoint nobody proved
/// degraded.
fn parse_state(raw: String) -> ProviderBreakerState {
    match raw.as_str() {
        "open" => ProviderBreakerState::Open,
        "half_open" => ProviderBreakerState::HalfOpen,
        "closed" => ProviderBreakerState::Closed,
        other => {
            tracing::warn!(
                state = other,
                "#871 provider breaker: unknown state, treating as closed"
            );
            ProviderBreakerState::Closed
        }
    }
}

fn parse_provider(raw: &str) -> Option<LlmProvider> {
    serde_json::from_value::<LlmProvider>(serde_json::Value::String(raw.to_string())).ok()
}

fn clamp_u32(value: i32) -> u32 {
    u32::try_from(value).unwrap_or(0)
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    match error {
        sqlx::Error::RowNotFound => DomainError::not_found("row not found"),
        sqlx::Error::PoolTimedOut => DomainError::service_unavailable("database pool timed out"),
        other => DomainError::service_unavailable(format!("database error: {other}")),
    }
}

#[cfg(test)]
mod breaker_sentinel_tests {
    use super::*;
    use breakdown_core::ai::LlmCallUsage;

    /// Issue #970 (CodeRabbit review, PR #967): the breaker sentinel carries
    /// the requests the attempt already billed — one entry per request, so the
    /// #794 energy cap survives the hold (round 13) — and stays the sentinel.
    #[test]
    fn the_breaker_sentinel_carries_orphaned_usage_and_stays_the_sentinel() {
        let calls = vec![
            LlmCallUsage {
                tokens_in: 500,
                tokens_out: 120,
                cached_tokens_in: 30,
                energy_millijoules: 7,
            },
            LlmCallUsage {
                tokens_in: 90,
                tokens_out: 0,
                cached_tokens_in: 0,
                energy_millijoules: 0,
            },
        ];
        let error = breaker_open_error_with_usage(calls.clone());
        assert!(
            is_breaker_open(&error),
            "the usage-carrying sentinel IS the breaker sentinel"
        );
        assert_eq!(
            orphaned_usage(&error),
            Some(calls),
            "every billed request travels on the sentinel, unmerged"
        );
        // The empty-ledger constructor stays the sentinel too.
        assert!(is_breaker_open(&breaker_open_error()));
        assert_eq!(orphaned_usage(&breaker_open_error()), Some(Vec::new()));
        // A real failure carries nothing and is not the sentinel.
        assert_eq!(orphaned_usage(&DomainError::conflict("lost claim")), None);
        assert!(!is_breaker_open(&DomainError::conflict("lost claim")));
        // The legacy Conflict-reason sentinel shape stays recognized.
        assert!(is_breaker_open(&DomainError::conflict(BREAKER_OPEN_REASON)));
    }
}
