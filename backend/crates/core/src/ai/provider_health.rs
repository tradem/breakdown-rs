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

use jiff::SignedDuration;
use jiff::Timestamp;

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
pub fn min_open(flap_count: u32) -> SignedDuration {
    let exponent = flap_count.min(16);
    let secs = BASE_OPEN_SECS.saturating_mul(1_i64 << exponent);
    SignedDuration::from_secs(secs.min(MAX_OPEN_SECS))
}

/// The `flap_count` a `closed → open` transition must record.
///
/// Increments only when the breaker closed recently (`closed_at` within
/// [`STABLE_WINDOW_SECS`]); otherwise this is a new incident and the counter
/// resets. `None` (a breaker that has never closed) resets as well.
#[must_use]
pub fn flap_count_on_open(
    closed_at: Option<Timestamp>,
    now: Timestamp,
    current_flap_count: u32,
) -> u32 {
    match closed_at {
        Some(closed_at) if now - closed_at < SignedDuration::from_secs(STABLE_WINDOW_SECS) => {
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
    pub closed_at: Option<Timestamp>,
    /// The `retry_at` the **stored row currently holds** (issue #926 review).
    ///
    /// `None` for a pair nobody has deferred, and — since
    /// [`on_retryable_failure`] writes `retry_at` unconditionally — the only
    /// memory of a provider hint that an earlier failure already earned. A later
    /// failure **without** a hint must not shorten it: the ordinary open window
    /// is often much shorter than a real rate-limit window, so recomputing
    /// `now + min_open(..)` alone would let the probe fire while the provider is
    /// still rate-limiting us.
    pub retry_at: Option<Timestamp>,
}

/// What a transition decided.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BreakerDecision {
    pub state: ProviderBreakerState,
    pub consecutive_failures: u32,
    pub flap_count: u32,
    /// The next probe time; `None` once the breaker is `closed`.
    pub retry_at: Option<Timestamp>,
    /// Whether the breaker just opened (the caller then materializes the holds,
    /// D-A4) or just closed (the caller then releases them, D-A6).
    pub opened: bool,
    pub closed: bool,
    /// The preflight passed and the breaker is `half_open` **without** a trial
    /// holder: the caller grants the single trial (issue #942 W1).
    ///
    /// Never set together with [`Self::closed`]: a metadata probe may not close
    /// a breaker, because a `200` from a zero-token endpoint proves the account,
    /// not that the model's chat path works — the exact flap loop issue #942 F2
    /// documents.
    pub trial_due: bool,
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
            trial_due: false,
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
    now: Timestamp,
    retry_after: Option<std::time::Duration>,
) -> BreakerDecision {
    // A failure while already `open` is the same outage still failing to clear:
    // no flap increment (that belongs to `closed → open`), and the open window is
    // re-armed from the current flap count.
    //
    // A failure while `half_open` is different since issue #942 W1: that attempt
    // was a **paid call the preflight explicitly cleared**, so the endpoint
    // flapped — the probe said usable and the chat path still failed. That is a
    // new incident by definition, so it escalates (`flap_count + 1`, the same
    // punishment a `closed → open` flap earns) instead of re-arming the first
    // 60 s window forever. It also re-opens *immediately* rather than granting
    // another trial, which is what bounds a broken model to one paid call per
    // window.
    if counters.state == ProviderBreakerState::HalfOpen {
        let flap_count = counters.flap_count.saturating_add(1);
        return BreakerDecision {
            state: ProviderBreakerState::Open,
            consecutive_failures: counters.consecutive_failures.saturating_add(1),
            flap_count,
            retry_at: Some(probe_at(now, flap_count, retry_after, counters.retry_at)),
            opened: true,
            closed: false,
            trial_due: false,
        };
    }
    if counters.state != ProviderBreakerState::Closed {
        let flap_count = counters.flap_count;
        return BreakerDecision {
            state: ProviderBreakerState::Open,
            consecutive_failures: counters.consecutive_failures.saturating_add(1),
            flap_count,
            retry_at: Some(probe_at(now, flap_count, retry_after, counters.retry_at)),
            opened: false,
            closed: false,
            trial_due: false,
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
            trial_due: false,
        };
    }

    let flap_count = flap_count_on_open(counters.closed_at, now, counters.flap_count);
    BreakerDecision {
        state: ProviderBreakerState::Open,
        consecutive_failures,
        flap_count,
        retry_at: Some(probe_at(now, flap_count, retry_after, counters.retry_at)),
        opened: true,
        closed: false,
        trial_due: false,
    }
}

/// When the next probe may run: the latest of the open window, the deadline an
/// earlier failure already earned, and the provider's own (clamped) wait hint
/// (issue #926).
///
/// One instant serves three consumers on purpose — the probe selector
/// (`state <> 'closed' AND retry_at <= now()`), [`BreakerDecision::retry_at`]
/// and a held job's `ProviderHold::until` — so "the provider asked us to wait"
/// is expressed once and inherited everywhere instead of being re-derived per
/// consumer.
///
/// `stored_retry_at` is why a **hint-less** failure cannot undo a hint: the
/// deadline is data on the row, but `cas` overwrites it with whatever this
/// function returns, so a plain `now + min_open(..)` would pull a 10-minute
/// rate-limit deferral back to the 60 s open window (review of issue #926). An
/// **expired** stored deadline is deliberately discarded — there is nothing left
/// to protect, and keeping it would extend the outage for free.
fn probe_at(
    now: Timestamp,
    flap_count: u32,
    retry_after: Option<std::time::Duration>,
    stored_retry_at: Option<Timestamp>,
) -> Timestamp {
    let window_end = now + min_open(flap_count);
    let deferred = stored_retry_at.filter(|stored| *stored > now);
    let earned = deferred.map_or(window_end, |stored| window_end.max(stored));
    let Some(hint) = retry_after else {
        return earned;
    };
    // A remote party must not be able to order an unbounded deferral, so the
    // hint is capped at the breaker's own maximum open window. `try_from`
    // cannot fail for a value we just clamped to 30 minutes; the fallback keeps
    // the "no panics" rule absolute anyway.
    let capped = hint.min(MAX_PROBE_DEFER);
    let hint_end = SignedDuration::try_from(capped).map_or(earned, |wait| now + wait);
    earned.max(hint_end)
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
        trial_due: false,
    }
}

/// A **failed probe** (`half_open → open`, D-A6).
///
/// No flap increment: this is the same outage that opened the breaker, not a
/// new one. The open window is re-armed from the current flap count, which is
/// what makes probe frequency decay instead of oscillating.
#[must_use]
pub fn on_probe_failure(counters: BreakerCounters, now: Timestamp) -> BreakerDecision {
    BreakerDecision {
        state: ProviderBreakerState::Open,
        consecutive_failures: counters.consecutive_failures,
        flap_count: counters.flap_count,
        retry_at: Some(now + min_open(counters.flap_count)),
        opened: false,
        closed: false,
        trial_due: false,
    }
}

/// A **passing preflight**: `open → half_open` plus one trial token
/// (issue #942 W1, superseding the `half_open → closed` table of D-A6).
///
/// Why it must not close: the preflight proves the *account* (credential
/// accepted, budget left) — verified against the live endpoint, EURouter's
/// `GET /key` answers `200` in 0.2 s while the very same model's
/// `POST /chat/completions` stalls at 120 s. Closing on that `200` released the
/// whole fleet into another `3 × 120 s` of timeouts and pushed `flap_count` to
/// 3 in 30 minutes (issue #942 F2). Only [`on_success`] — a real paid call
/// answered — closes.
#[must_use]
pub fn on_probe_success(counters: BreakerCounters, now: Timestamp) -> BreakerDecision {
    BreakerDecision {
        state: ProviderBreakerState::HalfOpen,
        consecutive_failures: 0,
        flap_count: counters.flap_count,
        // The trial may start immediately; the window is re-armed by every
        // consumed trial so a permanently broken model costs one call per
        // window instead of a fleet-wide storm.
        retry_at: Some(now + min_open(counters.flap_count)),
        opened: false,
        closed: false,
        trial_due: true,
    }
}

#[cfg(test)]
#[path = "provider_health_tests.rs"]
mod provider_health_tests;
