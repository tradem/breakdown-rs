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

use std::time::Duration;

use async_trait::async_trait;
use breakdown_core::ai::ports::{
    LlmProvider, OpenBreaker, ProbeLease, ProbeOutcome, ProviderBreakerSnapshot, ProviderHealth,
};
use breakdown_core::ai::provider_health::{
    BreakerCounters, BreakerDecision, on_probe_failure, on_probe_success, on_retryable_failure,
    on_success,
};
use breakdown_core::ai::views::ProviderBreakerState;
use breakdown_core::error::DomainError;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

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
    ) -> Result<(ProviderBreakerSnapshot, Option<DateTime<Utc>>), DomainError> {
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
    ) -> Result<(ProviderBreakerSnapshot, Option<DateTime<Utc>>), DomainError> {
        let row = sqlx::query(
            r#"
            SELECT state, consecutive_failures, flap_count, retry_at, closed_at
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
                retry_at: row.try_get("retry_at").map_err(map_sqlx_error)?,
            },
            row.try_get("closed_at").map_err(map_sqlx_error)?,
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
        .bind(decision.retry_at)
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
    ) -> Result<BreakerDecision, DomainError> {
        for _ in 0..CAS_ATTEMPTS {
            let (snapshot, closed_at) = self.read_or_create(provider, model).await?;
            let counters = BreakerCounters {
                state: snapshot.state,
                consecutive_failures: snapshot.consecutive_failures,
                flap_count: snapshot.flap_count,
                closed_at,
            };
            let decision = on_retryable_failure(counters, threshold, Utc::now());
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
        // * from `half_open`, the current lease must be **stale**. Without this
        //   branch a probe that hangs after its CAS would leave the pair in
        //   `half_open` for good: no claim is admitted in that state (D-A2) and
        //   nothing else can leave it, so one dead HTTP request would stop every
        //   job of that pair permanently.
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
            ProbeOutcome::Reachable => {
                // Fenced on the LEASE, not on the owner: the same task can
                // reacquire the lease, so an owner check would accept a stale
                // result.
                let result = sqlx::query(
                    r#"
                    UPDATE ai_import.provider_health
                    SET state = 'closed',
                        consecutive_failures = 0,
                        retry_at = NULL,
                        closed_at = now(),
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
                let decision = on_probe_success(BreakerCounters {
                    state: ProviderBreakerState::HalfOpen,
                    consecutive_failures: 0,
                    flap_count: 0,
                    closed_at: None,
                });
                Self::log_transition(lease.provider, &lease.model, &decision, "probe-reachable");
                Ok(decision)
            }
            ProbeOutcome::Unreachable => {
                // The decision's `retry_at` needs the current flap count, so read
                // it first — the write below is still fenced on the lease, which
                // is what makes the read harmless.
                let (snapshot, closed_at) = self.read(lease.provider, &lease.model).await?;
                let counters = BreakerCounters {
                    state: snapshot.state,
                    consecutive_failures: snapshot.consecutive_failures,
                    flap_count: snapshot.flap_count,
                    closed_at,
                };
                let decision = on_probe_failure(counters, Utc::now());
                let result = sqlx::query(
                    r#"
                    UPDATE ai_import.provider_health
                    SET state = 'open',
                        retry_at = $4,
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
                .bind(decision.retry_at)
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
                Self::log_transition(lease.provider, &lease.model, &decision, "probe-unreachable");
                Ok(decision)
            }
        }
    }

    async fn open_breakers(&self, limit: i64) -> Result<Vec<OpenBreaker>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT provider, model, state, retry_at
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
                retry_at: row.try_get("retry_at").map_err(map_sqlx_error)?,
            });
        }
        Ok(breakers)
    }
}

/// The probe lease window, exposed for the sweeper's own budgeting.
#[must_use]
pub const fn probe_lease_window() -> Duration {
    Duration::from_secs(PROBE_LEASE_SECS.unsigned_abs())
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
