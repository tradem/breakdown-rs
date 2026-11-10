// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Table-driven tests for the pure breaker state machine (issue #871, D-X4).
//!
//! No wall-clock gating (AGENTS.md §4): every case passes an explicit `now`.

use chrono::{Duration, TimeZone, Utc};

use super::{
    BASE_OPEN_SECS, BreakerCounters, MAX_OPEN_SECS, STABLE_WINDOW_SECS, flap_count_on_open,
    min_open, on_probe_failure, on_probe_success, on_retryable_failure, on_success,
};
use crate::ai::views::ProviderBreakerState;

fn now() -> chrono::DateTime<Utc> {
    // Fixed instant: the machine is a pure function of its inputs.
    Utc.with_ymd_and_hms(2026, 11, 4, 7, 0, 0)
        .single()
        .unwrap_or_else(|| Utc.timestamp_opt(0, 0).single().unwrap_or_default())
}

fn closed(failures: u32, flap_count: u32) -> BreakerCounters {
    BreakerCounters {
        state: ProviderBreakerState::Closed,
        consecutive_failures: failures,
        flap_count,
        closed_at: None,
    }
}

#[test]
fn min_open_escalates_geometrically_and_caps() {
    assert_eq!(min_open(0).num_seconds(), BASE_OPEN_SECS);
    assert_eq!(min_open(1).num_seconds(), BASE_OPEN_SECS * 2);
    assert_eq!(min_open(2).num_seconds(), BASE_OPEN_SECS * 4);
    assert_eq!(min_open(3).num_seconds(), BASE_OPEN_SECS * 8);
    // Ceiling: 60 * 2^5 = 1920s > 1800s, so the cap binds from here on.
    assert_eq!(min_open(5).num_seconds(), MAX_OPEN_SECS);
    assert_eq!(min_open(64).num_seconds(), MAX_OPEN_SECS);
    assert_eq!(min_open(u32::MAX).num_seconds(), MAX_OPEN_SECS);
}

#[test]
fn failure_below_threshold_only_counts() {
    let decision = on_retryable_failure(closed(0, 0), 3, now());
    assert_eq!(decision.state, ProviderBreakerState::Closed);
    assert_eq!(decision.consecutive_failures, 1);
    assert!(!decision.opened);
    assert_eq!(decision.retry_at, None);

    let decision = on_retryable_failure(closed(1, 0), 3, now());
    assert_eq!(decision.state, ProviderBreakerState::Closed);
    assert_eq!(decision.consecutive_failures, 2);
    assert!(!decision.opened);
}

#[test]
fn nth_consecutive_failure_opens() {
    let decision = on_retryable_failure(closed(2, 0), 3, now());
    assert_eq!(decision.state, ProviderBreakerState::Open);
    assert_eq!(decision.consecutive_failures, 3);
    assert!(decision.opened);
    assert_eq!(
        decision.retry_at,
        Some(now() + Duration::seconds(BASE_OPEN_SECS))
    );
    assert_eq!(decision.flap_count, 0);
}

#[test]
fn threshold_one_opens_on_the_first_failure() {
    let decision = on_retryable_failure(closed(0, 0), 1, now());
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
        closed_at: Some(now() - Duration::seconds(1)),
    };
    let decision = on_retryable_failure(counters, 3, now());
    assert_eq!(decision.state, ProviderBreakerState::Open);
    assert_eq!(decision.flap_count, 2);
    assert!(!decision.opened);
    assert_eq!(
        decision.retry_at,
        Some(now() + Duration::seconds(BASE_OPEN_SECS * 4))
    );
}

#[test]
fn flap_count_escalates_only_inside_the_stable_window() {
    // Closed 1s ago: this is a flap.
    let just_closed = Some(now() - Duration::seconds(1));
    assert_eq!(flap_count_on_open(just_closed, now(), 0), 1);
    assert_eq!(flap_count_on_open(just_closed, now(), 4), 5);

    // Closed longer than the stable window: genuinely stable, punishment reset.
    let long_ago = Some(now() - Duration::seconds(STABLE_WINDOW_SECS + 1));
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
        let closed_at = offset.map(|secs| now() - Duration::seconds(secs));
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
    };
    let decision = on_probe_failure(counters, now());
    assert_eq!(decision.state, ProviderBreakerState::Open);
    assert_eq!(decision.flap_count, 1, "same outage, no new flap");
    assert_eq!(
        decision.retry_at,
        Some(now() + Duration::seconds(BASE_OPEN_SECS * 2))
    );
    assert!(!decision.opened);
    assert!(!decision.closed);
}

#[test]
fn successful_probe_closes() {
    let counters = BreakerCounters {
        state: ProviderBreakerState::HalfOpen,
        consecutive_failures: 3,
        flap_count: 1,
        closed_at: None,
    };
    let decision = on_probe_success(counters);
    assert_eq!(decision.state, ProviderBreakerState::Closed);
    assert!(decision.closed);
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
        let opened = on_retryable_failure(counters, 1, now());
        assert_eq!(opened.state, ProviderBreakerState::Open);
        windows.push((opened.retry_at.unwrap_or_default() - now()).num_seconds());
        // The probe answers: closes, keeping the flap count.
        let closed_again = on_probe_success(BreakerCounters {
            state: ProviderBreakerState::HalfOpen,
            consecutive_failures: opened.consecutive_failures,
            flap_count: opened.flap_count,
            closed_at: None,
        });
        assert_eq!(closed_again.state, ProviderBreakerState::Closed);
        // It fails again within the stable window.
        counters = BreakerCounters {
            state: ProviderBreakerState::Closed,
            consecutive_failures: 0,
            flap_count: closed_again.flap_count,
            closed_at: Some(now() - Duration::seconds(1)),
        };
    }
    // Monotone non-decreasing, capped.
    assert!(
        windows.windows(2).all(|pair| pair[1] >= pair[0]),
        "{windows:?}"
    );
    assert_eq!(windows.last().copied(), Some(MAX_OPEN_SECS));
}
