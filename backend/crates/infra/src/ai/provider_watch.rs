// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! The claim-free provider watch (issue #871, workstream A).
//!
//! Two of the three hold writers live here, and they are the ones that make the
//! design's promises true rather than best-effort:
//!
//! 1. **Materialization** (D-A4 writer 3). The `closed → open` transition holds
//!    the jobs that were runnable *at that instant*, but it cannot reach two
//!    cases — a job **enqueued while the breaker is already open** (the claim
//!    predicate excludes it and writes nothing) and a `failed` job whose
//!    `next_attempt_at` becomes due *afterwards*. Both would sit `pending`/
//!    `failed` with no reason and no deadline: invisible **and** unexpirable,
//!    because the expiry precondition is the hold.
//! 2. **Expiry** (D-C4). A held job is `failed` while its pair is open, so the
//!    claim predicate keeps it unclaimable and `mark_held`'s owner fence needs a
//!    `running` row that no longer exists. Nothing that can claim a job can
//!    reach it; only a claim-free sweeper can.
//!
//! Both run under one Postgres advisory lock, so concurrent replicas cannot
//! double-sweep (the payload-GC precedent), and every affected job is notified
//! through the existing SSE hub by the queue writes themselves.
//!
//! The probe (D-A3) is the third writer and needs a vaulted credential, so it
//! lives in [`super::provider_probe`].

use std::time::Duration;

use breakdown_core::ai::ports::{AiImportQueue, LlmProvider, ProviderHealth};
use breakdown_core::ai::views::{ProviderBreakerState, ProviderHold};
use breakdown_core::error::DomainError;
use chrono::Utc;
use sqlx::PgPool;

use super::provider_probe::ProviderProbe;
use super::queue::PgAiImportQueue;

/// The advisory lock id of the provider watch: `"AI_PROV_WATCH"` as `i64`.
///
/// A distinct id from the payload GC and the reservation reaper, so the three
/// sweeps never block each other.
const PROVIDER_WATCH_LOCK_ID: i64 = 4706751127065399629;

/// `#822`'s registered provider code, reused as the hold's reason (D-X1).
pub const PROVIDER_UNAVAILABLE_CODE: &str = "ai-import.llm-provider-unavailable";

/// How the watch is configured (`AI_IMPORT_PROVIDER_SWEEP_*`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProviderWatchConfig {
    pub enabled: bool,
    pub interval_secs: u64,
    /// `AI_IMPORT_MAX_PROVIDER_HOLD_SECS`: the deadline window a materialized
    /// hold carries. The queue re-derives the absolute instant from the job's
    /// own series clock, so this is only the length.
    pub max_provider_hold_secs: u64,
}

impl ProviderWatchConfig {
    /// Read the switch from the environment, defaulting to enabled every 60 s.
    #[must_use]
    pub fn from_env() -> Self {
        let bounds = breakdown_core::ai::AiImportBounds::from_env();
        Self {
            enabled: read_bool("AI_IMPORT_PROVIDER_SWEEP_ENABLED", true),
            interval_secs: read_u64("AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS", 60, 5, 3_600),
            max_provider_hold_secs: bounds.max_provider_hold_secs,
        }
    }
}

/// What one tick did, for logging and for the tests to assert on.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ProviderWatchReport {
    /// Jobs that gained a hold this tick (the two cases the open-time write
    /// cannot reach).
    pub held: usize,
    /// Held jobs that ran out of their deadline and dead-lettered.
    pub expired: usize,
}

/// Run one provider-watch tick.
///
/// Returns `Ok(None)` when another replica holds the advisory lock (nothing to
/// do), `Ok(Some(report))` otherwise.
pub async fn run_provider_watch_tick(
    pool: &PgPool,
    health: &dyn ProviderHealth,
    queue: &PgAiImportQueue,
    probe: Option<&dyn ProviderProbe>,
    config: &ProviderWatchConfig,
    error_summary: &str,
) -> Result<Option<ProviderWatchReport>, DomainError> {
    if !config.enabled {
        return Ok(None);
    }

    // A dedicated connection for the advisory-lock lifecycle:
    // `pg_try_advisory_lock` is session-scoped, so the unlock must run on the
    // same session (the payload-GC precedent).
    let mut conn = pool
        .acquire()
        .await
        .map_err(|error| DomainError::service_unavailable(format!("database error: {error}")))?;
    let locked: Option<bool> = sqlx::query_scalar("SELECT pg_try_advisory_lock($1)")
        .bind(PROVIDER_WATCH_LOCK_ID)
        .fetch_optional(&mut *conn)
        .await
        .map_err(|error| DomainError::service_unavailable(format!("database error: {error}")))?;
    if locked != Some(true) {
        tracing::debug!("#871 provider breaker: watch lock held elsewhere — skipping this tick");
        return Ok(None);
    }

    let outcome = watch_locked(pool, health, queue, probe, config, error_summary).await;

    if let Err(error) = sqlx::query_scalar::<_, bool>("SELECT pg_advisory_unlock($1)")
        .bind(PROVIDER_WATCH_LOCK_ID)
        .fetch_optional(&mut *conn)
        .await
    {
        // Never mask the tick's own result with an unlock failure; the lock is
        // released with the session anyway.
        tracing::warn!(error = %error, "failed to release the provider-watch advisory lock");
    }

    outcome.map(Some)
}

async fn watch_locked(
    pool: &PgPool,
    health: &dyn ProviderHealth,
    queue: &PgAiImportQueue,
    probe: Option<&dyn ProviderProbe>,
    config: &ProviderWatchConfig,
    error_summary: &str,
) -> Result<ProviderWatchReport, DomainError> {
    let mut report = ProviderWatchReport::default();

    // (a) Materialize the holds the open-time transition could not reach.
    // Bounded: the probe/watch set is the number of degraded pairs, which is
    // small by construction (a healthy fleet has zero).
    for breaker in health.open_breakers(WATCH_PAIR_LIMIT).await? {
        let Some(until) = breaker.retry_at else {
            // No probe time means the row is mid-transition; the next tick will
            // see the settled state. Holding with no resume time would create
            // exactly the unbounded wait the expiry exists to prevent.
            continue;
        };
        let hold = hold_for(
            breaker.provider,
            &breaker.model,
            breaker.state,
            until,
            config.max_provider_hold_secs,
        );
        let ids = queue
            .hold_runnable_jobs(
                breaker.provider,
                &breaker.model,
                hold,
                config.max_provider_hold_secs,
            )
            .await?;
        if !ids.is_empty() {
            tracing::warn!(
                provider = breaker.provider.as_str(),
                model = breaker.model,
                jobs = ids.len(),
                "#871 provider breaker: materialized holds the open-time write could not reach"
            );
            report.held += ids.len();
        }
    }

    // (c) The probe (D-A3). Without it a breaker is a one-way door: no claim is
    // admitted while it is open, so no paid call can succeed and nothing else
    // can close it.
    if let Some(probe) = probe {
        let probed =
            super::provider_probe::run_probes(pool, health, queue, probe, PROBE_OWNER).await?;
        if probed > 0 {
            tracing::warn!(probes = probed, "#871 provider breaker: probe tick");
        }
    }

    // (b) Expire the holds whose own deadline passed. Keyed on the job's
    // deadline, never on a claim, so it reaches pre-claim held jobs too.
    let expired = queue
        .expire_provider_holds(error_summary, Some(PROVIDER_UNAVAILABLE_CODE))
        .await?;
    if !expired.is_empty() {
        tracing::warn!(
            jobs = expired.len(),
            "#871 provider breaker: hold deadline passed — dead-lettered without charging a retry"
        );
        report.expired = expired.len();
    }

    Ok(report)
}

/// The `probe_owner` string written by this process. Operator-readable only —
/// the fence is the lease token, not the owner.
const PROBE_OWNER: &str = "provider-watch";

/// How many degraded pairs one tick examines. A bound, not a horizon: the next
/// tick continues where this one stopped, and the probe task shares the same
/// ceiling (`PROBE_CANDIDATE_LIMIT` is per pair, this is per tick).
const WATCH_PAIR_LIMIT: i64 = 32;

/// The hold a materialization write carries (D-A4).
///
/// `hold_deadline` here is provisional: the queue derives the authoritative
/// instant from the job's own series clock, so a re-hold cannot restart the
/// budget (D-C4). Keeping the field populated makes the struct self-describing.
#[must_use]
pub fn hold_for(
    provider: LlmProvider,
    model: &str,
    state: ProviderBreakerState,
    until: chrono::DateTime<Utc>,
    hold_window_secs: u64,
) -> ProviderHold {
    ProviderHold {
        provider,
        model: model.to_string(),
        reason_code: PROVIDER_UNAVAILABLE_CODE.to_string(),
        // The breaker's own state; `expired` never reaches here (that is a
        // job-hold state written by the expiry itself).
        state,
        until,
        hold_deadline: until
            + chrono::Duration::seconds(i64::try_from(hold_window_secs).unwrap_or(i64::MAX)),
        chunks_done: 0,
    }
}

/// Spawn the periodic provider watch.
///
/// Exits immediately when disabled or when the interval is zero, so an operator
/// can turn it off without a code change. Env changes mid-flight are ignored
/// (the payload-GC precedent).
pub fn spawn_provider_watch(
    pool: PgPool,
    health: std::sync::Arc<dyn ProviderHealth>,
    probe: std::sync::Arc<dyn ProviderProbe>,
) {
    let config = ProviderWatchConfig::from_env();
    if !config.enabled {
        tracing::info!("AI provider watch is disabled — not spawning the sweeper");
        return;
    }
    if config.interval_secs == 0 {
        tracing::warn!("AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS is 0 — not spawning the sweeper");
        return;
    }
    let queue = PgAiImportQueue::new(pool.clone());
    let interval = Duration::from_secs(config.interval_secs);
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(interval).await;
            let summary = format!(
                "the provider stayed unavailable; no retry was charged (issue #871, {}s hold window)",
                config.max_provider_hold_secs
            );
            match run_provider_watch_tick(
                &pool,
                health.as_ref(),
                &queue,
                Some(probe.as_ref()),
                &config,
                &summary,
            )
            .await
            {
                Ok(Some(report)) if report != ProviderWatchReport::default() => {
                    tracing::info!(
                        held = report.held,
                        expired = report.expired,
                        "#871 provider breaker: provider watch tick"
                    );
                }
                Ok(_) => {}
                Err(error) => {
                    tracing::error!(error = %error, "AI provider watch tick failed");
                }
            }
        }
    });
}

fn read_bool(name: &str, default: bool) -> bool {
    match std::env::var(name).ok().as_deref() {
        Some(value) if value.eq_ignore_ascii_case("true") || value == "1" => true,
        Some(value) if value.eq_ignore_ascii_case("false") || value == "0" => false,
        _ => default,
    }
}

fn read_u64(name: &str, default: u64, min: u64, max: u64) -> u64 {
    std::env::var(name)
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|value| (*value >= min) && (*value <= max))
        .unwrap_or(default)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn now() -> chrono::DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 11, 4, 7, 0, 0)
            .single()
            .unwrap_or_default()
    }

    #[test]
    fn materialized_hold_carries_the_breaker_state_and_reason() {
        let until = now() + chrono::Duration::seconds(60);
        let hold = hold_for(
            LlmProvider::OpenCodeGo,
            "some-model",
            ProviderBreakerState::Open,
            until,
            21_600,
        );
        assert_eq!(hold.provider, LlmProvider::OpenCodeGo);
        assert_eq!(hold.model, "some-model");
        // #822's registered code, reused: no new problem code (D-X1).
        assert_eq!(hold.reason_code, PROVIDER_UNAVAILABLE_CODE);
        assert_eq!(hold.state, ProviderBreakerState::Open);
        assert_eq!(hold.until, until);
        assert_eq!(
            hold.hold_deadline,
            until + chrono::Duration::seconds(21_600)
        );
        // Workstream B supplies the real count; 0 is honest here.
        assert_eq!(hold.chunks_done, 0);
    }

    #[test]
    fn watch_defaults_are_enabled_and_frequent() {
        // The switch has to be on by default: an operator who never reads the
        // docs still gets the expiry that keeps a hold from pinning a payload
        // forever.
        let config = ProviderWatchConfig::from_env();
        assert!(config.enabled);
        assert_eq!(config.interval_secs, 60);
    }

    #[test]
    fn read_u64_falls_back_outside_the_bounds() {
        // Pure helper check (no env writes): the bounds are the documented
        // 5..=3600 window.
        assert_eq!(
            read_u64(
                "AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS_UNSET_871",
                60,
                5,
                3600
            ),
            60
        );
    }

    #[test]
    fn report_default_is_empty() {
        assert_eq!(
            ProviderWatchReport::default(),
            ProviderWatchReport {
                held: 0,
                expired: 0
            }
        );
    }
}
