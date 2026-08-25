// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use super::{DocumentKind, SourceFormat, TelemetryApplyState};

// ===========================================================================
// SourceFormat tests
// ===========================================================================

#[test]
fn only_csv_uses_the_native_parser() {
    assert!(SourceFormat::Csv.uses_native_csv());
    assert!(!SourceFormat::Pdf.uses_native_csv());
    assert!(!SourceFormat::PlainText.uses_native_csv());
}

#[test]
fn as_str_matches_the_database_check_constraint_values() {
    for (format, text) in [
        (SourceFormat::Csv, "csv"),
        (SourceFormat::Pdf, "pdf"),
        (SourceFormat::PlainText, "plain_text"),
    ] {
        assert_eq!(format.as_str(), text);
    }
}

// ===========================================================================
// P3.4 — DocumentKind::as_str (kills return "" / "xyzzy")
// ===========================================================================

#[test]
fn document_kind_as_str_script() {
    assert_eq!(DocumentKind::Script.as_str(), "script");
}

#[test]
fn document_kind_as_str_schedule() {
    assert_eq!(DocumentKind::Schedule.as_str(), "schedule");
}

#[test]
fn document_kind_as_str_never_empty() {
    for kind in [DocumentKind::Script, DocumentKind::Schedule] {
        assert!(!kind.as_str().is_empty(), "{kind:?} returns empty");
    }
}

// ===========================================================================
// P3.4 — TelemetryApplyState::accept_as_is (kills None / Some(false) / Some(true))
// ===========================================================================

#[test]
fn accept_as_is_not_applied_returns_none() {
    assert_eq!(TelemetryApplyState::NotApplied.accept_as_is(), None);
}

#[test]
fn accept_as_is_applied_true_returns_some_true() {
    let state = TelemetryApplyState::Applied {
        accept_as_is: true,
        edit_distance: 0,
    };
    assert_eq!(state.accept_as_is(), Some(true));
}

#[test]
fn accept_as_is_applied_false_returns_some_false() {
    let state = TelemetryApplyState::Applied {
        accept_as_is: false,
        edit_distance: 5,
    };
    assert_eq!(state.accept_as_is(), Some(false));
}

// ===========================================================================
// P3.4 — TelemetryApplyState::edit_distance (kills None / Some(0) / Some(1))
// ===========================================================================

#[test]
fn edit_distance_not_applied_returns_none() {
    assert_eq!(TelemetryApplyState::NotApplied.edit_distance(), None);
}

#[test]
fn edit_distance_applied_zero_returns_some_zero() {
    let state = TelemetryApplyState::Applied {
        accept_as_is: true,
        edit_distance: 0,
    };
    assert_eq!(state.edit_distance(), Some(0));
}

#[test]
fn edit_distance_applied_nonzero_returns_correct_value() {
    let state = TelemetryApplyState::Applied {
        accept_as_is: false,
        edit_distance: 42,
    };
    assert_eq!(state.edit_distance(), Some(42));
}

// ===========================================================================
// TelemetryApplyState default
// ===========================================================================

#[test]
fn telemetry_apply_state_default_is_not_applied() {
    assert_eq!(
        TelemetryApplyState::default(),
        TelemetryApplyState::NotApplied
    );
}

// ===========================================================================
// JobStatus::as_str
// ===========================================================================

#[test]
fn job_status_as_str_matches_variant() {
    assert_eq!(super::JobStatus::Pending.as_str(), "pending");
    assert_eq!(super::JobStatus::Running.as_str(), "running");
    assert_eq!(super::JobStatus::Succeeded.as_str(), "succeeded");
    assert_eq!(super::JobStatus::Failed.as_str(), "failed");
    assert_eq!(super::JobStatus::DeadLetter.as_str(), "dead_letter");
    assert_eq!(
        super::JobStatus::PayloadUnavailable.as_str(),
        "payload_unavailable"
    );
}

// ===========================================================================
// JobStatus::is_terminal
// ===========================================================================

#[test]
fn succeeded_is_terminal() {
    assert!(super::JobStatus::Succeeded.is_terminal());
}

#[test]
fn dead_letter_is_terminal() {
    assert!(super::JobStatus::DeadLetter.is_terminal());
}

#[test]
fn payload_unavailable_is_terminal() {
    assert!(super::JobStatus::PayloadUnavailable.is_terminal());
}

#[test]
fn pending_is_not_terminal() {
    assert!(!super::JobStatus::Pending.is_terminal());
}

#[test]
fn running_is_not_terminal() {
    assert!(!super::JobStatus::Running.is_terminal());
}

#[test]
fn failed_is_not_terminal() {
    assert!(!super::JobStatus::Failed.is_terminal());
}

// ===========================================================================
// JobStatus::is_non_resumable
// ===========================================================================

#[test]
fn payload_unavailable_is_non_resumable() {
    assert!(super::JobStatus::PayloadUnavailable.is_non_resumable());
}

#[test]
fn dead_letter_is_resumable() {
    // DeadLetter is terminal but not non-resumable; only PayloadUnavailable is non-resumable
    assert!(!super::JobStatus::DeadLetter.is_non_resumable());
}

#[test]
fn failed_is_resumable() {
    assert!(!super::JobStatus::Failed.is_non_resumable());
}
