// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Table-driven tests for the pure breaker state machine (issue #871, D-X4).
//!
//! No wall-clock gating (AGENTS.md §4): every case passes an explicit `now`.

use jiff::SignedDuration;

use super::{
    BASE_OPEN_SECS, BreakerCounters, MAX_OPEN_SECS, MAX_PROBE_DEFER_SECS, STABLE_WINDOW_SECS,
    flap_count_on_open, min_open, on_probe_failure, on_probe_success, on_retryable_failure,
    on_success,
};
use crate::ai::views::ProviderBreakerState;

/// Fixed UTC instant spelled as civil time — `Utc.with_ymd_and_hms`'s jiff
/// equivalent, without the fallible `Offset`/`TimeZone` construction at every
/// call site (ADR-040).
fn utc(y: i16, mo: i8, d: i8, h: i8, mi: i8, s: i8) -> jiff::Timestamp {
    // A UTC civil datetime is never ambiguous, so the `Result` is always `Ok`;
    // the fallback keeps the helper panic-free without an `unwrap`.
    jiff::civil::date(y, mo, d)
        .at(h, mi, s, 0)
        .to_zoned_datetime(jiff::tz::TimeZone::UTC)
        .map(|zdt| zdt.timestamp())
        .unwrap_or(jiff::Timestamp::UNIX_EPOCH)
}

fn now() -> jiff::Timestamp {
    // Fixed instant: the machine is a pure function of its inputs.
    utc(2026, 11, 4, 7, 0, 0)
}

fn closed(failures: u32, flap_count: u32) -> BreakerCounters {
    BreakerCounters {
        state: ProviderBreakerState::Closed,
        consecutive_failures: failures,
        flap_count,
        closed_at: None,
        retry_at: None,
    }
}

#[test]
fn min_open_escalates_geometrically_and_caps() {
    assert_eq!(min_open(0).as_secs(), BASE_OPEN_SECS);
    assert_eq!(min_open(1).as_secs(), BASE_OPEN_SECS * 2);
    assert_eq!(min_open(2).as_secs(), BASE_OPEN_SECS * 4);
    assert_eq!(min_open(3).as_secs(), BASE_OPEN_SECS * 8);
    // Ceiling: 60 * 2^5 = 1920s > 1800s, so the cap binds from here on.
    assert_eq!(min_open(5).as_secs(), MAX_OPEN_SECS);
    assert_eq!(min_open(64).as_secs(), MAX_OPEN_SECS);
    assert_eq!(min_open(u32::MAX).as_secs(), MAX_OPEN_SECS);
}

#[test]
fn failure_below_threshold_only_counts() {
    let decision = on_retryable_failure(closed(0, 0), 3, now(), None);
    assert_eq!(decision.state, ProviderBreakerState::Closed);
    assert_eq!(decision.consecutive_failures, 1);
    assert!(!decision.opened);
    assert_eq!(decision.retry_at, None);

    let decision = on_retryable_failure(closed(1, 0), 3, now(), None);
    assert_eq!(decision.state, ProviderBreakerState::Closed);
    assert_eq!(decision.consecutive_failures, 2);
    assert!(!decision.opened);
}

#[test]
fn nth_consecutive_failure_opens() {
    let decision = on_retryable_failure(closed(2, 0), 3, now(), None);
    assert_eq!(decision.state, ProviderBreakerState::Open);
    assert_eq!(decision.consecutive_failures, 3);
    assert!(decision.opened);
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(BASE_OPEN_SECS))
    );
    assert_eq!(decision.flap_count, 0);
}

#[test]
fn threshold_one_opens_on_the_first_failure() {
    let decision = on_retryable_failure(closed(0, 0), 1, now(), None);
    assert_eq!(decision.state, ProviderBreakerState::Open);
    assert!(decision.opened);
}

#[test]
fn failure_while_open_does_not_flap() {
    // Same outage still failing to clear: no flap increment (that belongs to
    // `closed -> open`), window re-armed from the current flap count.
    let counters = BreakerCounters {
        state: ProviderBreakerState::Open,
        consecutive_failures: 3,
        flap_count: 2,
        closed_at: Some(now() - SignedDuration::from_secs(1)),
        retry_at: None,
    };
    let decision = on_retryable_failure(counters, 3, now(), None);
    assert_eq!(decision.state, ProviderBreakerState::Open);
    assert_eq!(decision.flap_count, 2);
    assert!(!decision.opened);
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(BASE_OPEN_SECS * 4))
    );
}

#[test]
fn flap_count_escalates_only_inside_the_stable_window() {
    // Closed 1s ago: this is a flap.
    let just_closed = Some(now() - SignedDuration::from_secs(1));
    assert_eq!(flap_count_on_open(just_closed, now(), 0), 1);
    assert_eq!(flap_count_on_open(just_closed, now(), 4), 5);

    // Closed longer than the stable window: genuinely stable, punishment reset.
    let long_ago = Some(now() - SignedDuration::from_secs(STABLE_WINDOW_SECS + 1));
    assert_eq!(flap_count_on_open(long_ago, now(), 7), 0);

    // Never closed: a first-ever outage is not a flap.
    assert_eq!(flap_count_on_open(None, now(), 3), 0);
}

#[test]
fn flap_escalation_table() {
    // (flap_count before, closed_at offset, expected flap_count after)
    let cases = [
        (0_u32, None, 0_u32),
        (0, Some(1_i64), 1),
        (1, Some(1), 2),
        (2, Some(1), 3),
        (5, Some(1), 6),
        (5, Some(STABLE_WINDOW_SECS), 0),
        (5, Some(STABLE_WINDOW_SECS + 60), 0),
    ];
    for (before, offset, expected) in cases {
        let closed_at = offset.map(|secs| now() - SignedDuration::from_secs(secs));
        assert_eq!(
            flap_count_on_open(closed_at, now(), before),
            expected,
            "flap_count before={before} closed_at_offset={offset:?}"
        );
    }
}

#[test]
fn successful_paid_call_closes_and_keeps_flap_count() {
    let counters = BreakerCounters {
        state: ProviderBreakerState::HalfOpen,
        consecutive_failures: 3,
        flap_count: 2,
        closed_at: None,
        retry_at: None,
    };
    let decision = on_success(counters);
    assert_eq!(decision.state, ProviderBreakerState::Closed);
    assert_eq!(decision.consecutive_failures, 0);
    assert_eq!(
        decision.flap_count, 2,
        "a close must not erase the escalation"
    );
    assert_eq!(decision.retry_at, None);
    assert!(decision.closed);
}

#[test]
fn failed_probe_reopens_without_flapping() {
    let counters = BreakerCounters {
        state: ProviderBreakerState::HalfOpen,
        consecutive_failures: 3,
        flap_count: 1,
        closed_at: None,
        retry_at: None,
    };
    let decision = on_probe_failure(counters, now());
    assert_eq!(decision.state, ProviderBreakerState::Open);
    assert_eq!(decision.flap_count, 1, "same outage, no new flap");
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(BASE_OPEN_SECS * 2))
    );
    assert!(!decision.opened);
    assert!(!decision.closed);
}

/// Issue #942 W1 (AC1b): a passing preflight must **not** close the breaker.
///
/// The live evidence: `GET /key` answers `200` in 0.2 s while the very same
/// model's `POST /chat/completions` stalls at 120 s. Closing on that `200`
/// released the whole fleet into another `3 × 120 s` round and pushed
/// `flap_count` to 3 in 30 minutes. The preflight now only opens the
/// single-trial door; a real paid call is what closes (`on_success`).
#[test]
fn a_passing_preflight_opens_the_trial_door_without_closing() {
    let counters = BreakerCounters {
        state: ProviderBreakerState::HalfOpen,
        consecutive_failures: 3,
        flap_count: 1,
        closed_at: None,
        retry_at: None,
    };
    let decision = on_probe_success(counters, now());
    assert_eq!(
        decision.state,
        ProviderBreakerState::HalfOpen,
        "a metadata 200 proves the account, not the (provider, model) chat path"
    );
    assert!(decision.trial_due, "exactly one trial must be granted");
    assert!(
        !decision.closed,
        "only a real paid call may close the breaker"
    );
    assert!(
        decision.retry_at.is_some(),
        "the trial window must be armed, so a hung trial cannot wedge half_open"
    );
    // The escalation survives the preflight: the window is re-armed from the
    // pair's own flap history, not reset to the first 60 s window.
    assert_eq!(decision.flap_count, 1);

    // The contract in one place: `on_success` is the only closer.
    let closed = on_success(counters);
    assert_eq!(closed.state, ProviderBreakerState::Closed);
    assert!(closed.closed);
    assert!(!closed.trial_due);
}

/// A **failed trial** is a flap: the preflight explicitly cleared the endpoint
/// and the paid call still failed, so the window escalates instead of re-arming
/// the first window forever (issue #942 W1, anti-flap).
#[test]
fn a_failed_trial_escalates_the_open_window() {
    let counters = BreakerCounters {
        state: ProviderBreakerState::HalfOpen,
        consecutive_failures: 3,
        flap_count: 1,
        closed_at: None,
        retry_at: None,
    };
    let decision = on_retryable_failure(counters, 3, now(), None);
    assert_eq!(decision.state, ProviderBreakerState::Open);
    assert!(
        decision.opened,
        "the fleet must re-arm the hold immediately"
    );
    assert_eq!(
        decision.flap_count, 2,
        "a paid call failing right after a passing preflight is a new incident"
    );
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(BASE_OPEN_SECS * 4)),
        "the window is the escalated one, not the base window"
    );
    assert!(!decision.trial_due, "a reopened breaker grants no trial");
}

#[test]
fn flapping_provider_settles_at_the_cap() {
    // A provider that answers one probe and fails again immediately: every
    // flap lengthens the open window, so probe frequency decays to the cap
    // instead of oscillating at a fixed rate (D-A6).
    let mut counters = closed(0, 0);
    let mut windows = Vec::new();
    for _ in 0..8 {
        // Open it.
        let opened = on_retryable_failure(counters, 1, now(), None);
        assert_eq!(opened.state, ProviderBreakerState::Open);
        windows.push((opened.retry_at.unwrap_or_default() - now()).as_secs());
        // The preflight passes — it opens the trial door but never closes
        // (issue #942 W1) …
        let trial = on_probe_success(
            BreakerCounters {
                state: ProviderBreakerState::HalfOpen,
                consecutive_failures: opened.consecutive_failures,
                flap_count: opened.flap_count,
                closed_at: None,
                retry_at: opened.retry_at,
            },
            now(),
        );
        assert_eq!(trial.state, ProviderBreakerState::HalfOpen);
        assert!(trial.trial_due);
        // … and the single trial call fails, which is a flap.
        let reopened = on_retryable_failure(
            BreakerCounters {
                state: trial.state,
                consecutive_failures: trial.consecutive_failures,
                flap_count: trial.flap_count,
                closed_at: None,
                retry_at: trial.retry_at,
            },
            1,
            now(),
            None,
        );
        assert_eq!(reopened.state, ProviderBreakerState::Open);
        counters = BreakerCounters {
            state: reopened.state,
            consecutive_failures: reopened.consecutive_failures,
            flap_count: reopened.flap_count,
            closed_at: None,
            retry_at: reopened.retry_at,
        };
    }
    // Monotone non-decreasing, capped.
    assert!(
        windows.windows(2).all(|pair| pair[1] >= pair[0]),
        "{windows:?}"
    );
    assert_eq!(windows.last().copied(), Some(MAX_OPEN_SECS));
}

// ---------------------------------------------------------------------------
// Hint-aware probe schedule (issue #926)
// ---------------------------------------------------------------------------

/// A hint's `Duration` in the `std` clock domain the state machine takes.
fn wait(secs: u64) -> std::time::Duration {
    std::time::Duration::from_secs(secs)
}

#[test]
fn a_hint_longer_than_the_open_window_defers_the_probe() {
    // `BASE_OPEN_SECS` is 60 s; the provider asked for 10 min. Probing after one
    // window is exactly the "rediscover the 429" waste #926 removes.
    let decision = on_retryable_failure(closed(2, 0), 3, now(), Some(wait(600)));
    assert!(decision.opened);
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(600))
    );
}

#[test]
fn a_hint_shorter_than_the_open_window_is_ignored() {
    // The hint is a floor, not a target: a provider asking for 5 s must not
    // shorten the breaker's own cooling window.
    let decision = on_retryable_failure(closed(2, 0), 3, now(), Some(wait(5)));
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(BASE_OPEN_SECS))
    );
}

#[test]
fn a_hint_is_capped_at_the_maximum_open_window() {
    // A remote party must not order an unbounded deferral: `Retry-After: 86400`
    // defers the probe by the breaker's own maximum window, not by a day.
    let decision = on_retryable_failure(closed(2, 0), 3, now(), Some(wait(86_400)));
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(MAX_OPEN_SECS))
    );
    assert_eq!(MAX_PROBE_DEFER_SECS, MAX_OPEN_SECS as u64);
}

#[test]
fn no_hint_keeps_the_pre_926_probe_time() {
    // Byte-compatibility for every hint-less 429 and every non-provider failure:
    // a `closed -> open` with no `closed_at` resets `flap_count`, so the probe
    // time is the plain first window.
    let decision = on_retryable_failure(closed(2, 3), 3, now(), None);
    assert_eq!(
        decision.flap_count, 0,
        "a new incident resets the flap count"
    );
    assert_eq!(decision.retry_at, Some(now() + min_open(0)));
}

#[test]
fn a_hint_extends_the_probe_time_while_the_breaker_is_open() {
    // The already-open branch re-arms the window on every failure; the hint must
    // extend THAT branch too, otherwise a retried chunk shortens the deferral the
    // first failure asked for.
    let counters = BreakerCounters {
        state: ProviderBreakerState::Open,
        consecutive_failures: 4,
        flap_count: 1,
        closed_at: None,
        retry_at: None,
    };
    let decision = on_retryable_failure(counters, 3, now(), Some(wait(900)));
    assert!(!decision.opened);
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(900))
    );
}

/// Counters for an **open** breaker whose row already carries `retry_at`.
fn open_deferred(flap_count: u32, retry_at: Option<jiff::Timestamp>) -> BreakerCounters {
    BreakerCounters {
        state: ProviderBreakerState::Open,
        consecutive_failures: 3,
        flap_count,
        closed_at: None,
        retry_at,
    }
}

#[test]
fn a_hintless_failure_does_not_shorten_a_deferral_an_earlier_hint_earned() {
    // The review finding on #926: `cas` writes `retry_at` unconditionally, so a
    // later failure WITHOUT a hint used to recompute `now + min_open(..)` and pull
    // a 10-minute rate-limit deferral back to the 60 s open window — the probe
    // then fired while the provider was still rate-limiting us.
    let stored = now() + SignedDuration::from_secs(600);
    let decision = on_retryable_failure(open_deferred(0, Some(stored)), 3, now(), None);
    assert!(!decision.opened, "the breaker was already open");
    assert_eq!(
        decision.retry_at,
        Some(stored),
        "an unexpired stored deadline survives a hint-less failure"
    );
}

#[test]
fn a_hintless_failure_on_a_never_deferred_pair_keeps_the_open_window() {
    // Byte-compatibility for the ordinary outage: nothing stored, nothing added.
    let decision = on_retryable_failure(open_deferred(2, None), 3, now(), None);
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(BASE_OPEN_SECS * 4))
    );
}

#[test]
fn an_expired_stored_deadline_is_discarded() {
    // Once the deferral has run out there is nothing left to protect; keeping it
    // would extend an outage for free. The open window wins again.
    let stored = now() - SignedDuration::from_secs(1);
    let decision = on_retryable_failure(open_deferred(0, Some(stored)), 3, now(), None);
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(BASE_OPEN_SECS))
    );
}

#[test]
fn a_stored_deadline_and_a_fresh_hint_take_the_later() {
    // Both sources can be present; the probe waits for whichever ends last.
    let stored = now() + SignedDuration::from_secs(120);
    let decision = on_retryable_failure(open_deferred(0, Some(stored)), 3, now(), Some(wait(600)));
    assert_eq!(
        decision.retry_at,
        Some(now() + SignedDuration::from_secs(600))
    );
    // ...and the other way round.
    let stored = now() + SignedDuration::from_secs(900);
    let decision = on_retryable_failure(open_deferred(0, Some(stored)), 3, now(), Some(wait(600)));
    assert_eq!(decision.retry_at, Some(stored));
}

#[test]
fn an_unexpired_hint_is_not_selected_by_the_probe_predicate() {
    // The probe (and the watch sweeper) select `state <> 'closed' AND retry_at <=
    // now()`. Asserting the ordering property here is what keeps a hint-unexpired
    // pair out of that set without a database round-trip.
    let decision = on_retryable_failure(closed(2, 0), 3, now(), Some(wait(600)));
    let retry_at = decision.retry_at.unwrap_or_else(now);
    assert!(
        retry_at > now(),
        "a hint-deferred probe must not look due at the instant it was scheduled"
    );
    assert!(retry_at > now() + SignedDuration::from_secs(BASE_OPEN_SECS));
}
