// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! The provider circuit breaker's **pure** state machine (issue #871).
//!
//! Everything here is a function of `(state, counters, now)` and nothing else:
//! no clock read, no database, no logging. That is what makes the transition
//! table in `design.md` D-A6 testable as a table instead of through a Postgres
//! harness (D-X4), and it keeps the arithmetic (`min_open`, the flap rule) in
//! one place instead of duplicated across the repository's `UPDATE`s.
//!
//! The durable row lives in `ai_import.provider_health` and its `state` CHECK
//! accepts exactly the three breaker states below — [`ProviderBreakerState::Expired`]
//! is a *job-hold* state only and never reaches this module.

use chrono::{DateTime, Duration, Utc};

use super::views::ProviderBreakerState;

/// First open window: a provider that fails once is re-probed after this.
pub const BASE_OPEN_SECS: i64 = 60;

/// Ceiling of the open window. A flapping provider settles at one probe per
/// this window at worst — the geometric escalation is what damps the flap.
pub const MAX_OPEN_SECS: i64 = 30 * 60;

/// How long a breaker must have stayed **closed** for the next failure to count
/// as a *new* incident rather than a flap.
///
/// Measured against `closed_at` on the `closed → open` transition, because that
/// is where a new outage starts. Chosen comfortably above the first open window
/// ([`BASE_OPEN_SECS`]): a provider that a probe just cleared and that fails
/// again within ten minutes was never stable, so its punishment escalates
/// instead of resetting. A `closed → open` after a longer closed period resets
/// `flap_count` to `0` — the provider was genuinely stable, and its punishment
/// must not be inherited by the next, unrelated incident.
pub const STABLE_WINDOW_SECS: i64 = 10 * 60;

/// The longest deferral a provider's own wait hint may impose on the **probe
/// schedule** (issue #926).
///
/// Reuses [`MAX_OPEN_SECS`] rather than declaring a new knob: the probe schedule
/// already refuses to back off further than its maximum open window, so a
/// `Retry-After: 86400` must not defer a probe past the point where the breaker
/// itself would have given up on the geometric escalation. Deliberately **not**
/// `MAX_IN_ATTEMPT_HINT_SECS` — a probe holds no concurrency permit, so the
/// permit-driven clamp would make the hint nearly pointless here.
pub const MAX_PROBE_DEFER_SECS: u64 = MAX_OPEN_SECS as u64;

/// [`MAX_PROBE_DEFER_SECS`] as a `std::time::Duration`, so the comparison does
/// not leave the `std` clock domain.
const MAX_PROBE_DEFER: std::time::Duration = std::time::Duration::from_secs(MAX_PROBE_DEFER_SECS);

/// The open window after `flap_count` consecutive flaps:
/// `min(BASE_OPEN · 2^n, MAX_OPEN)`.
///
/// The exponent is clamped before it is applied so a long outage series cannot
/// overflow the shift — the ceiling is reached at `n = 5` anyway.
#[must_use]
pub fn min_open(flap_count: u32) -> Duration {
    let exponent = flap_count.min(16);
    let secs = BASE_OPEN_SECS.saturating_mul(1_i64 << exponent);
    Duration::seconds(secs.min(MAX_OPEN_SECS))
}

/// The `flap_count` a `closed → open` transition must record.
///
/// Increments only when the breaker closed recently (`closed_at` within
/// [`STABLE_WINDOW_SECS`]); otherwise this is a new incident and the counter
/// resets. `None` (a breaker that has never closed) resets as well.
#[must_use]
pub fn flap_count_on_open(
    closed_at: Option<DateTime<Utc>>,
    now: DateTime<Utc>,
    current_flap_count: u32,
) -> u32 {
    match closed_at {
        Some(closed_at) if now - closed_at < Duration::seconds(STABLE_WINDOW_SECS) => {
            current_flap_count.saturating_add(1)
        }
        _ => 0,
    }
}

/// One observed provider outcome, as the worker reports it.
///
/// Only retryable provider failures count toward opening the breaker (D-A1): a
/// revoked key or an entitlement 4xx is `dependency.auth-failed`-class
/// permanent (#637) and must never convert one user's misconfiguration into an
/// outage for everyone on that endpoint.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderOutcome {
    /// A retryable provider failure (`domain.service-unavailable` with the
    /// provider code `ai-import.llm-provider-unavailable`).
    ///
    /// `retry_after` is the wait the provider itself asked for (`Retry-After` /
    /// `X-RateLimit-Reset`, issue #926), carried **by value** from the HTTP
    /// response through the error payload. It extends the breaker's `retry_at`
    /// — which is both the probe schedule and a held job's `until` — so a known
    /// rate-limit window is respected instead of re-discovered by a probe.
    RetryableFailure {
        retry_after: Option<std::time::Duration>,
    },
    /// A permanent failure — never counted, never opens the breaker.
    PermanentFailure,
    /// A paid call or a probe answered.
    Success,
}

/// The counters a transition reads.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BreakerCounters {
    pub state: ProviderBreakerState,
    pub consecutive_failures: u32,
    pub flap_count: u32,
    pub closed_at: Option<DateTime<Utc>>,
}

/// What a transition decided.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BreakerDecision {
    pub state: ProviderBreakerState,
    pub consecutive_failures: u32,
    pub flap_count: u32,
    /// The next probe time; `None` once the breaker is `closed`.
    pub retry_at: Option<DateTime<Utc>>,
    /// Whether the breaker just opened (the caller then materializes the holds,
    /// D-A4) or just closed (the caller then releases them, D-A6).
    pub opened: bool,
    pub closed: bool,
}

impl BreakerDecision {
    /// The no-op decision: nothing changed, nothing to write.
    #[must_use]
    pub fn unchanged(counters: BreakerCounters) -> Self {
        Self {
            state: counters.state,
            consecutive_failures: counters.consecutive_failures,
            flap_count: counters.flap_count,
            retry_at: None,
            opened: false,
            closed: false,
        }
    }
}

/// The `closed → open` verdict for one retryable failure (D-A3, D-A6).
///
/// Returns `opened = false` while the consecutive-failure count is still below
/// `threshold`; the caller then only bumps the counter. Once it reaches the
/// threshold the breaker opens, the flap rule escalates the open window, and
/// the caller materializes the holds.
///
/// `retry_after` is the provider's own hint (issue #926). It **extends** the
/// probe time when it is longer than the open window, so a provider that says
/// "wait 10 min" is not probed after the first 60 s window — and, because the
/// same instant becomes a held job's `until`, the hold honours it too. The hint
/// is clamped to [`MAX_OPEN_SECS`]: a probe is never deferred longer than the
/// breaker's own maximum open window, whatever a remote party claims.
#[must_use]
pub fn on_retryable_failure(
    counters: BreakerCounters,
    threshold: u32,
    now: DateTime<Utc>,
    retry_after: Option<std::time::Duration>,
) -> BreakerDecision {
    // A failure while already open or half-open is the same outage still
    // failing to clear: no flap increment (that belongs to `closed → open`),
    // and the open window is re-armed from the current flap count.
    if counters.state != ProviderBreakerState::Closed {
        let flap_count = counters.flap_count;
        return BreakerDecision {
            state: ProviderBreakerState::Open,
            consecutive_failures: counters.consecutive_failures.saturating_add(1),
            flap_count,
            retry_at: Some(probe_at(now, flap_count, retry_after)),
            opened: false,
            closed: false,
        };
    }

    let consecutive_failures = counters.consecutive_failures.saturating_add(1);
    if consecutive_failures < threshold.max(1) {
        return BreakerDecision {
            state: ProviderBreakerState::Closed,
            consecutive_failures,
            flap_count: counters.flap_count,
            retry_at: None,
            opened: false,
            closed: false,
        };
    }

    let flap_count = flap_count_on_open(counters.closed_at, now, counters.flap_count);
    BreakerDecision {
        state: ProviderBreakerState::Open,
        consecutive_failures,
        flap_count,
        retry_at: Some(probe_at(now, flap_count, retry_after)),
        opened: true,
        closed: false,
    }
}

/// When the next probe may run: the later of the open window and the provider's
/// own (clamped) wait hint (issue #926).
///
/// One instant serves three consumers on purpose — the probe selector
/// (`state <> 'closed' AND retry_at <= now()`), [`BreakerDecision::retry_at`]
/// and a held job's `ProviderHold::until` — so "the provider asked us to wait"
/// is expressed once and inherited everywhere instead of being re-derived per
/// consumer.
fn probe_at(
    now: DateTime<Utc>,
    flap_count: u32,
    retry_after: Option<std::time::Duration>,
) -> DateTime<Utc> {
    let window_end = now + min_open(flap_count);
    let Some(hint) = retry_after else {
        return window_end;
    };
    // A remote party must not be able to order an unbounded deferral, so the
    // hint is capped at the breaker's own maximum open window. `from_std` cannot
    // fail for a value we just clamped to 30 minutes; the fallback keeps the
    // "no panics" rule absolute anyway.
    let capped = hint.min(MAX_PROBE_DEFER);
    let hint_end = Duration::from_std(capped).map_or(window_end, |wait| now + wait);
    window_end.max(hint_end)
}

/// A successful **paid call** (`half_open → closed`, or a reset while closed).
///
/// A success while `open` cannot happen through a paid call (no job of the pair
/// is claimed while the breaker is open), but it is still handled as a close:
/// the endpoint demonstrably answered, which is the only thing the breaker
/// tracks.
#[must_use]
pub fn on_success(counters: BreakerCounters) -> BreakerDecision {
    BreakerDecision {
        state: ProviderBreakerState::Closed,
        consecutive_failures: 0,
        // `flap_count` survives a close on purpose: the escalation must be
        // inherited by the next incident unless the provider stayed stable for
        // `STABLE_WINDOW` (see `flap_count_on_open`).
        flap_count: counters.flap_count,
        retry_at: None,
        opened: false,
        closed: true,
    }
}

/// A **failed probe** (`half_open → open`, D-A6).
///
/// No flap increment: this is the same outage that opened the breaker, not a
/// new one. The open window is re-armed from the current flap count, which is
/// what makes probe frequency decay instead of oscillating.
#[must_use]
pub fn on_probe_failure(counters: BreakerCounters, now: DateTime<Utc>) -> BreakerDecision {
    BreakerDecision {
        state: ProviderBreakerState::Open,
        consecutive_failures: counters.consecutive_failures,
        flap_count: counters.flap_count,
        retry_at: Some(now + min_open(counters.flap_count)),
        opened: false,
        closed: false,
    }
}

/// A **successful probe** (`half_open → closed`, D-A6).
#[must_use]
pub fn on_probe_success(counters: BreakerCounters) -> BreakerDecision {
    on_success(counters)
}

#[cfg(test)]
#[path = "provider_health_tests.rs"]
mod provider_health_tests;
