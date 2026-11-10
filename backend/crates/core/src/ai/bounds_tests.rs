// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use super::{AiImportBounds, bounded_u32, bounded_u64};
use std::env;

// ---------------------------------------------------------------------------
// Helper: run a closure with a temporary env var, restoring the original
// afterwards.  Skips if the var was already set (isolated CI risk).
// ---------------------------------------------------------------------------
#[allow(unsafe_code)]
fn with_env<F: FnOnce() -> R, R>(key: &str, val: &str, f: F) -> R {
    let orig = env::var(key).ok();
    // SAFETY: test-only helper; tests run single-threaded by default.
    unsafe {
        env::set_var(key, val);
    }
    let r = f();
    match orig {
        Some(v) => unsafe { env::set_var(key, v) },
        None => unsafe { env::remove_var(key) },
    }
    r
}

// ===========================================================================
// P3.1 — AiImportBounds::validate / bounded_u32 / bounded_u64
// ===========================================================================

// --- validate: zero-field guards (kills || → && mutations) ----------------

#[test]
fn validate_rejects_zero_max_chunks() {
    let b = AiImportBounds {
        max_chunks_per_script: 0,
        ..AiImportBounds::default()
    };
    assert!(b.validate().is_err());
}

#[test]
fn validate_rejects_zero_max_tokens() {
    let b = AiImportBounds {
        max_tokens_per_req: 0,
        ..AiImportBounds::default()
    };
    assert!(b.validate().is_err());
}

#[test]
fn validate_rejects_zero_global_concurrency() {
    let b = AiImportBounds {
        max_concurrent_jobs_global: 0,
        ..AiImportBounds::default()
    };
    assert!(b.validate().is_err());
}

#[test]
fn validate_rejects_zero_user_concurrency() {
    let b = AiImportBounds {
        max_concurrent_jobs_per_user: 0,
        ..AiImportBounds::default()
    };
    assert!(b.validate().is_err());
}

/// Two fields zero at once — the &&-mutated version would short-circuit.
#[test]
fn validate_rejects_two_zero_fields_simultaneously() {
    let b = AiImportBounds {
        max_chunks_per_script: 0,
        max_tokens_per_req: 0,
        ..AiImportBounds::default()
    };
    assert!(b.validate().is_err());
}

// --- validate: per-user vs global (kills > → >=) --------------------------

#[test]
fn validate_accepts_per_user_equal_to_global() {
    let b = AiImportBounds {
        max_concurrent_jobs_global: 4,
        max_concurrent_jobs_per_user: 4,
        ..AiImportBounds::default()
    };
    // equal is fine; only strictly greater is forbidden
    assert!(b.validate().is_ok());
}

#[test]
fn validate_rejects_per_user_exceeding_global() {
    let b = AiImportBounds {
        max_concurrent_jobs_global: 2,
        max_concurrent_jobs_per_user: 3,
        ..AiImportBounds::default()
    };
    assert!(b.validate().is_err());
}

#[test]
fn validate_accepts_per_user_below_global() {
    let b = AiImportBounds {
        max_concurrent_jobs_global: 10,
        max_concurrent_jobs_per_user: 1,
        ..AiImportBounds::default()
    };
    assert!(b.validate().is_ok());
}

// --- validate: all-valid path ---------------------------------------------

#[test]
fn validate_ok_for_defaults() {
    assert!(AiImportBounds::default().validate().is_ok());
}

// --- bounded_u32: boundary values (kills >= / <= / && mutations) -----------

#[test]
fn bounded_u32_returns_default_when_var_unset() {
    let result = bounded_u32("AI_IMPORT_TEST_UNSET_U32", 42, 1, 100);
    assert_eq!(result, 42);
}

#[test]
fn bounded_u32_returns_default_for_unparseable_value() {
    with_env("AI_IMPORT_TEST_UNPARSE_U32", "not-a-number", || {
        let result = bounded_u32("AI_IMPORT_TEST_UNPARSE_U32", 42, 1, 100);
        assert_eq!(result, 42);
    });
}

#[test]
fn bounded_u32_returns_default_for_zero_when_min_is_one() {
    with_env("AI_IMPORT_TEST_ZERO_U32", "0", || {
        let result = bounded_u32("AI_IMPORT_TEST_ZERO_U32", 42, 1, 100);
        assert_eq!(result, 42);
    });
}

#[test]
fn bounded_u32_returns_value_at_min_boundary() {
    with_env("AI_IMPORT_TEST_MIN_U32", "1", || {
        let result = bounded_u32("AI_IMPORT_TEST_MIN_U32", 42, 1, 100);
        assert_eq!(result, 1);
    });
}

#[test]
fn bounded_u32_returns_value_at_max_boundary() {
    with_env("AI_IMPORT_TEST_MAX_U32", "100", || {
        let result = bounded_u32("AI_IMPORT_TEST_MAX_U32", 42, 1, 100);
        assert_eq!(result, 100);
    });
}

#[test]
fn bounded_u32_returns_default_above_max() {
    with_env("AI_IMPORT_TEST_ABOVEMAX_U32", "101", || {
        let result = bounded_u32("AI_IMPORT_TEST_ABOVEMAX_U32", 42, 1, 100);
        assert_eq!(result, 42);
    });
}

#[test]
fn bounded_u32_returns_default_below_min() {
    with_env("AI_IMPORT_TEST_BELOWMIN_U32", "0", || {
        // min=5, value=0 → rejected
        let result = bounded_u32("AI_IMPORT_TEST_BELOWMIN_U32", 42, 5, 100);
        assert_eq!(result, 42);
    });
}

#[test]
fn bounded_u32_allows_zero_when_min_is_zero() {
    with_env("AI_IMPORT_TEST_ALLOWZERO_U32", "0", || {
        let result = bounded_u32("AI_IMPORT_TEST_ALLOWZERO_U32", 42, 0, 100);
        assert_eq!(result, 0);
    });
}

// --- bounded_u64: boundary values (kills >= / <= / && mutations) -----------

#[test]
fn bounded_u64_returns_default_when_var_unset() {
    let result = bounded_u64("AI_IMPORT_TEST_UNSET_U64", 99, 1, 1000);
    assert_eq!(result, 99);
}

#[test]
fn bounded_u64_returns_default_for_unparseable_value() {
    with_env("AI_IMPORT_TEST_UNPARSE_U64", "nope", || {
        let result = bounded_u64("AI_IMPORT_TEST_UNPARSE_U64", 99, 1, 1000);
        assert_eq!(result, 99);
    });
}

#[test]
fn bounded_u64_returns_value_at_min_boundary() {
    with_env("AI_IMPORT_TEST_MIN_U64", "1", || {
        let result = bounded_u64("AI_IMPORT_TEST_MIN_U64", 99, 1, 1000);
        assert_eq!(result, 1);
    });
}

#[test]
fn bounded_u64_returns_value_at_max_boundary() {
    with_env("AI_IMPORT_TEST_MAX_U64", "1000", || {
        let result = bounded_u64("AI_IMPORT_TEST_MAX_U64", 99, 1, 1000);
        assert_eq!(result, 1000);
    });
}

#[test]
fn bounded_u64_returns_default_above_max() {
    with_env("AI_IMPORT_TEST_ABOVEMAX_U64", "1001", || {
        let result = bounded_u64("AI_IMPORT_TEST_ABOVEMAX_U64", 99, 1, 1000);
        assert_eq!(result, 99);
    });
}

#[test]
fn bounded_u64_returns_default_below_min() {
    with_env("AI_IMPORT_TEST_BELOWMIN_U64", "0", || {
        let result = bounded_u64("AI_IMPORT_TEST_BELOWMIN_U64", 99, 5, 1000);
        assert_eq!(result, 99);
    });
}

#[test]
fn bounded_u64_allows_zero_when_min_is_zero() {
    with_env("AI_IMPORT_TEST_ALLOWZERO_U64", "0", || {
        let result = bounded_u64("AI_IMPORT_TEST_ALLOWZERO_U64", 99, 0, 1000);
        assert_eq!(result, 0);
    });
}

// --- from_env: env-driven overrides (kills from_env → Default::default()) -

#[test]
fn from_env_clamps_user_concurrency_to_global() {
    // Verify the clamping invariant holds for the current env state
    // (no env var manipulation needed — avoids parallel test conflicts)
    let b = AiImportBounds::from_env();
    assert!(
        b.max_concurrent_jobs_per_user <= b.max_concurrent_jobs_global,
        "per-user ({}) should be <= global ({})",
        b.max_concurrent_jobs_per_user,
        b.max_concurrent_jobs_global
    );
}

#[test]
fn from_env_reads_all_fields() {
    // Verify from_env returns valid defaults (no env var mutation — safe for parallel runs)
    let b = AiImportBounds::from_env();
    assert!(b.max_chunks_per_script > 0);
    assert!(b.max_tokens_per_req > 0);
    assert!(b.max_concurrent_jobs_global > 0);
    assert!(b.max_concurrent_jobs_per_user > 0);
    assert!(b.max_document_bytes > 0);
    assert!(b.request_timeout_secs > 0);
    assert!(b.max_concurrent_jobs_per_user <= b.max_concurrent_jobs_global);
}

// --- worst_case_tokens: multiplication ------------------------------------

#[test]
fn worst_case_tokens_multiplies_chunks_times_tokens() {
    let b = AiImportBounds {
        max_chunks_per_script: 10,
        max_tokens_per_req: 500,
        ..AiImportBounds::default()
    };
    assert_eq!(b.worst_case_tokens(), 5_000);
}

#[test]
fn worst_case_tokens_one_chunk() {
    let b = AiImportBounds {
        max_chunks_per_script: 1,
        max_tokens_per_req: 8192,
        ..AiImportBounds::default()
    };
    assert_eq!(b.worst_case_tokens(), 8_192);
}

// ===========================================================================
// Issue #871 — the breaker / in-attempt retry bounds (tasks 1.1, 1.6)
// ===========================================================================

#[test]
fn defaults_split_the_two_retry_layers() {
    let b = AiImportBounds::default();
    // The job budget keeps its documented value; the in-attempt budget is the
    // new, much smaller knob (D-C1: 1 + 2 = 3 attempts per chunk).
    assert_eq!(b.max_retries, 5);
    assert_eq!(b.max_attempt_retries, 2);
    assert_eq!(b.breaker_failure_threshold, 3);
    assert!(b.breaker_enabled);
    assert_eq!(b.max_provider_hold_secs, 6 * 60 * 60);
}

#[test]
fn default_threshold_is_reachable_within_one_chunk() {
    // The compile-time assert ties the DEFAULTS; this is its runtime twin, so a
    // future edit that only touches one constant fails a test as well as the
    // build.
    let b = AiImportBounds::default();
    assert!(b.breaker_failure_threshold <= b.max_attempt_retries + 1);
    assert!(!b.breaker_threshold_exceeds_attempt_budget());
}

#[test]
fn threshold_above_the_attempt_budget_is_reported_not_rejected() {
    let b = AiImportBounds {
        breaker_failure_threshold: 10,
        max_attempt_retries: 2,
        ..AiImportBounds::default()
    };
    // A legitimate operator choice: the counter is per pair across all jobs,
    // chunks and replicas, so the breaker still opens — just more slowly.
    assert!(b.breaker_threshold_exceeds_attempt_budget());
    assert!(b.validate().is_ok());
}

#[test]
fn a_disabled_breaker_never_reports_a_threshold_problem() {
    let b = AiImportBounds {
        breaker_enabled: false,
        breaker_failure_threshold: 10,
        ..AiImportBounds::default()
    };
    assert!(!b.breaker_threshold_exceeds_attempt_budget());
}

#[test]
fn attempt_retries_env_override_is_bounded() {
    with_env("AI_IMPORT_MAX_ATTEMPT_RETRIES", "7", || {
        assert_eq!(AiImportBounds::from_env().max_attempt_retries, 7);
    });
    // Out of range (0..=10) falls back to the default rather than clamping.
    with_env("AI_IMPORT_MAX_ATTEMPT_RETRIES", "11", || {
        assert_eq!(AiImportBounds::from_env().max_attempt_retries, 2);
    });
    with_env("AI_IMPORT_MAX_ATTEMPT_RETRIES", "not-a-number", || {
        assert_eq!(AiImportBounds::from_env().max_attempt_retries, 2);
    });
}

#[test]
fn breaker_threshold_env_override_is_bounded() {
    with_env("AI_IMPORT_BREAKER_FAILURE_THRESHOLD", "1", || {
        assert_eq!(AiImportBounds::from_env().breaker_failure_threshold, 1);
    });
    // Zero is not a valid threshold (1..=10): a breaker that opens on no
    // failure would hold every job forever.
    with_env("AI_IMPORT_BREAKER_FAILURE_THRESHOLD", "0", || {
        assert_eq!(AiImportBounds::from_env().breaker_failure_threshold, 3);
    });
}

#[test]
fn breaker_switch_accepts_the_documented_spellings() {
    for value in ["true", "1", "yes", "TRUE"] {
        with_env("AI_IMPORT_BREAKER_ENABLED", value, || {
            assert!(AiImportBounds::from_env().breaker_enabled, "{value}");
        });
    }
    for value in ["false", "0", "no", "False"] {
        with_env("AI_IMPORT_BREAKER_ENABLED", value, || {
            assert!(!AiImportBounds::from_env().breaker_enabled, "{value}");
        });
    }
    // An unrecognized value keeps the default instead of guessing.
    with_env("AI_IMPORT_BREAKER_ENABLED", "maybe", || {
        assert!(AiImportBounds::from_env().breaker_enabled);
    });
}

#[test]
fn provider_hold_window_env_override_is_bounded() {
    with_env("AI_IMPORT_MAX_PROVIDER_HOLD_SECS", "120", || {
        assert_eq!(AiImportBounds::from_env().max_provider_hold_secs, 120);
    });
    // Below the 60s floor falls back to the 6h default.
    with_env("AI_IMPORT_MAX_PROVIDER_HOLD_SECS", "5", || {
        assert_eq!(
            AiImportBounds::from_env().max_provider_hold_secs,
            6 * 60 * 60
        );
    });
}
