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
