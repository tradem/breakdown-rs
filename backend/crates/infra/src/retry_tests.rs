// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Tests for the shared retry core (issue #925): the header matrix the parsers
//! have to survive, and the exact numeric behaviour of the two jitter formulas
//! the call sites use (they replaced hand-rolled copies, so the values they
//! produce are pinned here against the pre-#925 arithmetic).

use std::time::{Duration, SystemTime};

use reqwest::StatusCode;
use reqwest::header::{HeaderMap, HeaderValue};

use super::{
    Backoff, MAX_SERVER_HINT, RetryClass, RetryHint, effective_in_attempt_delay,
    parse_limit_remaining, parse_limit_reset, parse_retry_after, parse_retry_hint,
    parse_retry_hint_at,
};

/// The fixed reference clock every relative-header test parses against.
///
/// The parsers take `now` as a parameter precisely so no assertion depends on
/// how long the test itself runs (AGENTS.md §4). 1_763_500_000 s ≈ 2025-11-19,
/// safely above the delta/epoch split in `parse_limit_reset`.
fn now() -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs(1_763_500_000)
}

/// A header map with the given `(name, value)` pairs.
fn headers(pairs: &[(&'static str, &str)]) -> HeaderMap {
    let mut map = HeaderMap::new();
    for (name, value) in pairs {
        let value = HeaderValue::from_str(value).expect("a visible-ASCII test value is valid");
        map.insert(*name, value);
    }
    map
}

// ===========================================================================
// Classification
// ===========================================================================

#[test]
fn a_429_and_every_5xx_are_retryable() {
    for status in [
        StatusCode::TOO_MANY_REQUESTS,
        StatusCode::INTERNAL_SERVER_ERROR,
        StatusCode::BAD_GATEWAY,
        StatusCode::SERVICE_UNAVAILABLE,
        StatusCode::GATEWAY_TIMEOUT,
        StatusCode::from_u16(599).expect("599 is a valid status code"),
    ] {
        assert_eq!(
            RetryClass::of(status),
            RetryClass::Retryable,
            "{status} must be retryable"
        );
    }
}

#[test]
fn a_4xx_other_than_429_is_rejected() {
    for status in [
        StatusCode::BAD_REQUEST,
        StatusCode::UNAUTHORIZED,
        StatusCode::FORBIDDEN,
        StatusCode::NOT_FOUND,
        StatusCode::from_u16(499).expect("499 is a valid status code"),
    ] {
        assert_eq!(
            RetryClass::of(status),
            RetryClass::Rejected,
            "{status} must be rejected, not retried"
        );
    }
}

#[test]
fn a_non_error_status_is_unexpected() {
    // The function is only reached for a non-success status, so 1xx/3xx must
    // land in the "neither" bucket instead of silently becoming retryable.
    for status in [
        StatusCode::CONTINUE,
        StatusCode::MOVED_PERMANENTLY,
        StatusCode::FOUND,
    ] {
        assert_eq!(RetryClass::of(status), RetryClass::Unexpected, "{status}");
    }
}

#[test]
fn classification_is_independent_of_the_hint_headers() {
    // A 200 with hostile headers must not acquire a retryable class — the class
    // comes from the status alone.
    let hint = parse_retry_hint(&headers(&[("retry-after", "120")]), StatusCode::OK);
    assert_eq!(hint.class, RetryClass::Unexpected);
    assert_eq!(hint.wait, Some(Duration::from_secs(120)));
}

// ===========================================================================
// Retry-After
// ===========================================================================

#[test]
fn retry_after_delta_seconds_is_read() {
    let hint = parse_retry_hint(
        &headers(&[("retry-after", "120")]),
        StatusCode::TOO_MANY_REQUESTS,
    );
    assert_eq!(hint.wait, Some(Duration::from_secs(120)));
    assert!(hint.carries_server_hint());
}

#[test]
fn retry_after_surrounding_whitespace_is_tolerated() {
    assert_eq!(
        parse_retry_after("  7 ", now()),
        Some(Duration::from_secs(7))
    );
}

#[test]
fn retry_after_http_date_is_read() {
    // Both the header and the clock are fixed, so the answer is an exact
    // duration — nothing here can drift with the test's runtime.
    let at = now() + Duration::from_secs(90);
    let raw = httpdate::fmt_http_date(at);
    assert_eq!(
        parse_retry_after(&raw, now()),
        Some(Duration::from_secs(90)),
        "an IMF-fixdate resolves to the time left until it"
    );
}

#[test]
fn retry_after_in_the_past_is_no_wait() {
    let at = now() - Duration::from_secs(600);
    let raw = httpdate::fmt_http_date(at);
    assert_eq!(
        parse_retry_after(&raw, now()),
        Some(Duration::ZERO),
        "a date that already passed means 'retry now', not a negative wait"
    );
}

#[test]
fn an_unparsable_retry_after_is_ignored() {
    assert_eq!(parse_retry_after("soon", now()), None);
    assert_eq!(parse_retry_after("", now()), None);
    assert_eq!(parse_retry_after("-5", now()), None);
}

#[test]
fn an_absurd_retry_after_is_capped() {
    assert_eq!(
        parse_retry_after(&u64::MAX.to_string(), now()),
        Some(MAX_SERVER_HINT)
    );
    let hint = parse_retry_hint(
        &headers(&[("retry-after", "999999999")]),
        StatusCode::SERVICE_UNAVAILABLE,
    );
    assert_eq!(hint.wait, Some(MAX_SERVER_HINT));
}

// ===========================================================================
// X-RateLimit-*
// ===========================================================================

#[test]
fn rate_limit_remaining_is_read() {
    assert_eq!(parse_limit_remaining("42"), Some(42));
    assert_eq!(parse_limit_remaining(" 0 "), Some(0));
    assert_eq!(parse_limit_remaining("many"), None);
    assert_eq!(parse_limit_remaining("-1"), None);
}

#[test]
fn rate_limit_reset_as_delta_seconds_is_read() {
    assert_eq!(
        parse_limit_reset("60", now()),
        Some(Duration::from_secs(60))
    );
}

#[test]
fn rate_limit_reset_as_epoch_seconds_is_normalised() {
    let epoch = now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .expect("the fixed clock is after 1970")
        .as_secs()
        + 120;
    assert_eq!(
        parse_limit_reset(&epoch.to_string(), now()),
        Some(Duration::from_secs(120)),
        "an epoch stamp normalises to 'until the reset', exactly"
    );
}

#[test]
fn a_past_epoch_reset_is_no_wait() {
    // 2001-09-09: above the delta/epoch split, far in the past.
    assert_eq!(parse_limit_reset("1000000000", now()), Some(Duration::ZERO));
}

#[test]
fn an_unparsable_rate_limit_reset_is_ignored() {
    assert_eq!(
        parse_limit_reset("Wed, 21 Oct 2015 07:28:00 GMT", now()),
        None
    );
    assert_eq!(parse_limit_reset("-1", now()), None);
}

#[test]
fn a_huge_epoch_reset_is_capped_instead_of_overflowing() {
    assert_eq!(
        parse_limit_reset(&u64::MAX.to_string(), now()),
        Some(MAX_SERVER_HINT)
    );
}

// ===========================================================================
// Absent / unreadable headers
// ===========================================================================

#[test]
fn a_response_without_hints_carries_none() {
    let hint = parse_retry_hint(&HeaderMap::new(), StatusCode::OK);
    assert!(!hint.carries_server_hint());
    assert_eq!(hint.wait, None);
    assert_eq!(hint.limit_remaining, None);
    assert_eq!(hint.limit_reset, None);
}

#[test]
fn an_unreadable_header_value_degrades_to_none() {
    // Obs-text bytes are legal in a header value but not ASCII, so `to_str`
    // fails: the hint is dropped, and the request is NOT failed.
    let opaque = HeaderValue::from_bytes(&[0xC3, 0x28]).expect("obs-text is a legal header byte");
    assert!(opaque.to_str().is_err(), "the value must not be ASCII");

    let mut map = HeaderMap::new();
    map.insert("retry-after", opaque);
    let hint = parse_retry_hint(&map, StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(hint.wait, None);
    assert_eq!(hint.class, RetryClass::Retryable);
}

#[test]
fn every_hint_field_is_reported_together() {
    // Delta-only headers do not consult the clock, but pinning it keeps the
    // suite clock-free end to end — and a test that reads `SystemTime::now()`
    // nowhere cannot flake on a slow runner.
    let hint = parse_retry_hint_at(
        &headers(&[
            ("retry-after", "3"),
            ("x-ratelimit-remaining", "0"),
            ("x-ratelimit-reset", "12"),
        ]),
        StatusCode::TOO_MANY_REQUESTS,
        now(),
    );
    assert_eq!(
        hint,
        RetryHint {
            class: RetryClass::Retryable,
            wait: Some(Duration::from_secs(3)),
            limit_remaining: Some(0),
            limit_reset: Some(Duration::from_secs(12)),
        }
    );
}

// ===========================================================================
// Backoff — the formulas the call sites use
// ===========================================================================

#[test]
fn a_fixed_backoff_pauses_the_same_on_every_attempt() {
    let policy = Backoff::Fixed(Duration::from_millis(250));
    for attempt in [0, 1, 5, 42] {
        assert_eq!(policy.delay(attempt), Duration::from_millis(250));
    }
}

#[test]
fn equal_jitter_doubles_and_stays_within_its_bounds() {
    // The projector supervisor's pre-#925 formula: base·2^attempt capped at
    // `max`, plus up to 25 % jitter, capped at `max`.
    let base = Duration::from_millis(500);
    let max = Duration::from_secs(30);
    let policy = Backoff::EqualJitter { base, max };

    for attempt in 0..=10_usize {
        let planned = base.as_millis() * 2_u128.pow(attempt as u32);
        let floor = Duration::from_millis(u64::try_from(planned).expect("planned < u64::MAX"));
        let delay = policy.delay(attempt);
        assert!(
            delay >= floor.min(max),
            "attempt {attempt}: {delay:?} must be at least the capped floor {floor:?}"
        );
        assert!(
            delay <= max,
            "attempt {attempt}: {delay:?} must never exceed the cap"
        );
        // Equal jitter: at most a quarter of the planned delay on top.
        let ceiling = (floor + floor / 4).min(max);
        assert!(
            delay <= ceiling,
            "attempt {attempt}: {delay:?} exceeds base + 25 % jitter ({ceiling:?})"
        );
    }
}

#[test]
fn equal_jitter_at_attempt_zero_is_half_a_second_plus_jitter() {
    let policy = Backoff::EqualJitter {
        base: Duration::from_millis(500),
        max: Duration::from_secs(30),
    };
    for _ in 0..64 {
        let delay = policy.delay(0);
        assert!(
            delay >= Duration::from_millis(500) && delay <= Duration::from_millis(625),
            "expected 500..=625 ms, got {delay:?}"
        );
    }
}

#[test]
fn equal_jitter_caps_at_the_maximum() {
    let policy = Backoff::EqualJitter {
        base: Duration::from_millis(500),
        max: Duration::from_secs(30),
    };
    for attempt in [6, 10, usize::MAX] {
        assert!(
            policy.delay(attempt) <= Duration::from_secs(30),
            "attempt {attempt} must stay capped"
        );
    }
}

#[test]
fn full_jitter_stays_between_zero_and_the_cap() {
    // The report-archival formula: full jitter in [0, capped].
    let base = Duration::from_secs(1);
    let max = Duration::from_secs(10);
    let policy = Backoff::FullJitter { base, max };
    for attempt in [0, 1, 4, 16, 100] {
        let delay = policy.delay(attempt);
        assert!(
            delay <= max,
            "attempt {attempt}: {delay:?} must never exceed the cap"
        );
    }
}

#[test]
fn full_jitter_reaches_the_cap_for_far_attempts() {
    // Once the exponent saturates, the draw is uniform over the whole cap, so
    // SOME draw near the cap must appear (2^−? probability of never doing so
    // over 64 draws is negligible).
    let policy = Backoff::FullJitter {
        base: Duration::from_secs(1),
        max: Duration::from_secs(10),
    };
    let draws = (0..64).map(|_| policy.delay(100)).collect::<Vec<_>>();
    assert!(
        draws.iter().any(|delay| *delay > Duration::from_secs(5)),
        "full jitter must be able to exceed half the cap at saturation: {draws:?}"
    );
}

#[test]
fn a_beyond_ceiling_attempt_is_finite_in_both_formulas() {
    // Pre-#925 the equal-jitter copy multiplied `base_ms` with a saturated
    // `2^attempt`, which overflows in debug builds. Clamping the exponent keeps
    // both formulas finite for any input, while every reachable attempt stays
    // bit-identical.
    for policy in [
        Backoff::EqualJitter {
            base: Duration::from_millis(500),
            max: Duration::from_secs(30),
        },
        Backoff::FullJitter {
            base: Duration::from_millis(500),
            max: Duration::from_secs(30),
        },
    ] {
        assert!(policy.delay(usize::MAX) <= Duration::from_secs(30));
    }
}

// ---------------------------------------------------------------------------
// The in-attempt hint floor (issue #926)
// ---------------------------------------------------------------------------

/// The clamp the scheduling tests refer to, read from the single declaration in
/// `core` rather than re-typed here.
fn hint_clamp() -> Duration {
    Duration::from_secs(breakdown_core::ai::MAX_IN_ATTEMPT_HINT_SECS)
}

#[test]
fn a_hint_larger_than_the_computed_backoff_wins() {
    // The motivating case: attempt 1 of the equal-jitter policy is ~1 s, and the
    // provider asked for 5 s. Retrying after 1 s is what the pre-#926 build did.
    let planned = Duration::from_millis(1_000);
    assert_eq!(
        effective_in_attempt_delay(planned, Some(Duration::from_secs(5))),
        Duration::from_secs(5)
    );
}

#[test]
fn a_hint_smaller_than_the_computed_backoff_is_ignored() {
    // The hint is a floor, not a target: a provider asking for 200 ms must not
    // shorten a backoff the worker already decided on.
    let planned = Duration::from_secs(8);
    assert_eq!(
        effective_in_attempt_delay(planned, Some(Duration::from_millis(200))),
        planned
    );
}

#[test]
fn an_absent_hint_leaves_the_computed_backoff_untouched() {
    // This is the byte-compatibility guarantee for every non-provider failure
    // and every hint-less 429: the delay is exactly what `Backoff` returned.
    let planned = Duration::from_millis(2_500);
    assert_eq!(effective_in_attempt_delay(planned, None), planned);
}

#[test]
fn a_hint_at_the_clamp_boundary_is_exactly_the_clamp() {
    let planned = Duration::from_millis(1_000);
    assert_eq!(
        effective_in_attempt_delay(planned, Some(hint_clamp())),
        hint_clamp()
    );
}

#[test]
fn a_hint_beyond_the_clamp_is_capped_at_the_clamp() {
    // `Retry-After: 3600` must not hold a concurrency permit for an hour. The
    // clamp is the number `attempt_worst_case_secs` multiplies, so this assertion
    // is what keeps the documented 22/28 min honest.
    let planned = Duration::from_millis(1_000);
    assert_eq!(
        effective_in_attempt_delay(planned, Some(Duration::from_secs(3_600))),
        hint_clamp()
    );
    assert_eq!(
        effective_in_attempt_delay(planned, Some(Duration::from_secs(86_400))),
        hint_clamp()
    );
}

#[test]
fn a_clamped_hint_still_loses_to_a_larger_computed_backoff() {
    // The clamp is applied to the hint BEFORE the maximum is taken, so a planned
    // backoff above the clamp is never shortened by clamping the hint.
    let planned = hint_clamp() + Duration::from_secs(10);
    assert_eq!(
        effective_in_attempt_delay(planned, Some(Duration::from_secs(3_600))),
        planned
    );
}

#[test]
fn the_in_attempt_clamp_is_the_constant_from_core() {
    // One declaration: `core::ai::MAX_IN_ATTEMPT_HINT_SECS` is what both the
    // scheduler and the permit bound read, so retuning it cannot leave the
    // documented worst case describing a different number.
    assert_eq!(hint_clamp(), Duration::from_secs(120));
}
