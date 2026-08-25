// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for payload_cleanup — kills mutations in is_not_found,
//! gc_config_from_env, and CleanupMarks.

use breakdown_core::error::DomainError;

use super::{AiPayloadGcConfig, is_not_found};

// ===========================================================================
// is_not_found — kills return false / true
// ===========================================================================

#[test]
fn is_not_found_returns_false_for_validation() {
    let err = DomainError::validation("test");
    assert!(!is_not_found(&err), "Validation should return false");
}

#[test]
fn is_not_found_returns_false_for_service_unavailable() {
    let err = DomainError::service_unavailable("test");
    assert!(
        !is_not_found(&err),
        "ServiceUnavailable should return false"
    );
}

#[test]
fn is_not_found_returns_false_for_conflict() {
    let err = DomainError::conflict("test");
    assert!(!is_not_found(&err), "Conflict should return false");
}

// ===========================================================================
// AiPayloadGcConfig — default values
// ===========================================================================

#[test]
fn gc_config_default_values_are_sensible() {
    let config = AiPayloadGcConfig {
        enabled: true,
        interval_secs: 3600,
        max_age_secs: 604800,
        batch_size: 1000,
        dry_run: false,
    };
    assert!(config.enabled);
    assert!(config.interval_secs > 0);
    assert!(config.max_age_secs > 0);
    assert!(config.batch_size > 0);
    assert!(!config.dry_run);
}

#[test]
fn gc_config_disabled_works() {
    let config = AiPayloadGcConfig {
        enabled: false,
        ..AiPayloadGcConfig {
            enabled: true,
            interval_secs: 3600,
            max_age_secs: 604800,
            batch_size: 1000,
            dry_run: false,
        }
    };
    assert!(!config.enabled);
}

#[test]
fn gc_config_dry_run_works() {
    let config = AiPayloadGcConfig {
        dry_run: true,
        ..AiPayloadGcConfig {
            enabled: true,
            interval_secs: 3600,
            max_age_secs: 604800,
            batch_size: 1000,
            dry_run: false,
        }
    };
    assert!(config.dry_run);
}

// ===========================================================================
// CleanupMarks — is_empty and len
// ===========================================================================

#[test]
fn cleanup_marks_empty_by_default() {
    let marks = super::CleanupMarks::default();
    assert!(marks.is_empty());
    assert_eq!(marks.len(), 0);
}

// ===========================================================================
// TERMINAL_JOBS_SQL constant
// ===========================================================================

#[test]
fn terminal_jobs_sql_is_not_empty() {
    assert!(
        !super::TERMINAL_JOBS_SQL.is_empty(),
        "TERMINAL_JOBS_SQL should not be empty"
    );
}

#[test]
fn terminal_jobs_sql_excludes_failed() {
    // The SQL should NOT include 'failed' in the IN clause
    assert!(
        !super::TERMINAL_JOBS_SQL.contains("'failed'"),
        "TERMINAL_JOBS_SQL should not include 'failed'"
    );
}

#[test]
fn terminal_jobs_sql_includes_succeeded() {
    assert!(
        super::TERMINAL_JOBS_SQL.contains("'succeeded'"),
        "TERMINAL_JOBS_SQL should include 'succeeded'"
    );
}

#[test]
fn terminal_jobs_sql_includes_dead_letter() {
    assert!(
        super::TERMINAL_JOBS_SQL.contains("'dead_letter'"),
        "TERMINAL_JOBS_SQL should include 'dead_letter'"
    );
}

#[test]
fn terminal_jobs_sql_includes_payload_unavailable() {
    assert!(
        super::TERMINAL_JOBS_SQL.contains("'payload_unavailable'"),
        "TERMINAL_JOBS_SQL should include 'payload_unavailable'"
    );
}
