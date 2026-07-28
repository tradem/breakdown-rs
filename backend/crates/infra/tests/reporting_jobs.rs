// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use breakdown_core::reporting::*;

#[test]
fn truncate_error_redacts_secrets() {
    // Test that secrets are redacted in error messages
    let err = ReportStorageError::provider_failure("token=abc");
    assert_eq!(
        err.to_string(),
        "report storage provider failure: redacted provider error"
    );
    let err = ReportStorageError::provider_failure("timeout talking to provider");
    assert!(err.to_string().contains("timeout"));
}

#[test]
fn parse_kind_accepts_canonical_forms() {
    // Test that ReportKind can be serialized/deserialized
    let kinds = vec![
        ReportKind::Dispo,
        ReportKind::ShootDay,
        ReportKind::PlannedVsActual,
    ];
    for kind in &kinds {
        let json = serde_json::to_string(kind).unwrap();
        let deserialized: ReportKind = serde_json::from_str(&json).unwrap();
        assert_eq!(*kind, deserialized);
    }
}

/// SSOT guardrail: this module must not be re-exported from any core
/// domain query surface. Verified by source inspection of core.
#[test]
fn ssot_core_does_not_import_job_table() {
    // Walk core sources that must never mention report_ops.
    let core_reporting = include_str!("../../core/src/reporting/mod.rs");
    let core_storage = include_str!("../../core/src/reporting/storage.rs");
    let core_archival = include_str!("../../core/src/reporting/archival.rs");
    for src in [core_reporting, core_storage, core_archival] {
        assert!(
            !src.contains("report_ops"),
            "core must not reference report_ops schema"
        );
        assert!(
            !src.contains("report_job"),
            "core must not reference report_job table"
        );
    }
}
