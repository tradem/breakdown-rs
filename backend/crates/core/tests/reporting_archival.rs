// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: hy3 (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use breakdown_core::reporting::*;
use breakdown_core::shared::ShootingDayId;
use uuid::Uuid;

#[test]
fn dedup_key_is_stable_across_triggers() {
    let day = ShootingDayId(Uuid::now_v7());
    let base = |trigger: ArchivalTrigger| EnqueueArchivalRequest {
        kind: ReportKind::Dispo,
        shooting_day_id: day,
        locale: ReportLocale::de_de(),
        template_version: "1.0.0".into(),
        snapshot_identity: SnapshotIdentity::current(),
        trigger,
    };
    let a = base(ArchivalTrigger::Wrapped).dedup_key();
    let b = base(ArchivalTrigger::Manual).dedup_key();
    let c = base(ArchivalTrigger::Schedule).dedup_key();
    assert_eq!(a, b);
    assert_eq!(b, c);
    assert!(a.contains("dispo"));
    assert!(a.contains("1.0.0"));
    assert!(a.contains("de-DE"));
    assert!(a.contains("current"));
}

#[test]
fn job_status_roundtrip() {
    for s in [
        ReportJobStatus::Pending,
        ReportJobStatus::Claimed,
        ReportJobStatus::Staged,
        ReportJobStatus::Uploading,
        ReportJobStatus::Succeeded,
        ReportJobStatus::Failed,
        ReportJobStatus::DeadLetter,
    ] {
        assert_eq!(ReportJobStatus::parse(s.as_str()), Some(s));
    }
    assert_eq!(ReportJobStatus::parse("nope"), None);
}

#[test]
fn archival_error_has_no_byte_payload() {
    let err = ReportArchivalError::Storage {
        detail: "timeout".into(),
    };
    assert!(!err.to_string().contains("%PDF"));
}

// --- P4.5 mutation-hardening: sanitize_error_detail + Archival identity ---
//
// These tests pin the private `sanitize_error_detail` length branch (the `>`
// comparison at storage.rs:187) and the archival identity string formats so the
// surviving mutants (`>` replaced by `<` / `==` / `>=`, empty/placeholder
// `as_str`, and an empty `Display for ReportJobId`) are killed.

#[test]
fn report_job_id_display_is_uuid_string() {
    let uuid = Uuid::now_v7();
    let id = ReportJobId(uuid);
    assert_eq!(format!("{id}"), uuid.to_string());
    assert!(!format!("{id}").is_empty());
}

#[test]
fn archival_trigger_as_str_covers_all_variants() {
    assert_eq!(ArchivalTrigger::Schedule.as_str(), "schedule");
    assert_eq!(ArchivalTrigger::Wrapped.as_str(), "wrapped");
    assert_eq!(ArchivalTrigger::Manual.as_str(), "manual");
    for trigger in [
        ArchivalTrigger::Schedule,
        ArchivalTrigger::Wrapped,
        ArchivalTrigger::Manual,
    ] {
        let s = trigger.as_str();
        assert!(
            !s.is_empty(),
            "ArchivalTrigger::as_str must not be empty for {trigger:?}"
        );
        assert_ne!(
            s, "xyzzy",
            "ArchivalTrigger::as_str must not return a placeholder for {trigger:?}"
        );
    }
}

#[test]
fn sanitize_truncates_overlong_detail_with_ellipsis() {
    let long = "x".repeat(256 + 50);
    let long_len = long.len();
    let err = ReportStorageError::provider_failure(long);
    let detail = match err {
        ReportStorageError::ProviderFailure { detail } => detail,
        other => panic!("expected ProviderFailure, got {other:?}"),
    };
    // Truncation uses byte length (String::truncate) and appends the 3-byte
    // '…', so the result is strictly shorter than the input and ends in '…'.
    assert!(
        detail.len() < long_len,
        "overlong detail must be truncated, got len {}",
        detail.len()
    );
    assert!(
        detail.ends_with('…'),
        "truncated detail must end with an ellipsis, got {detail:?}"
    );
}

#[test]
fn sanitize_keeps_exact_boundary_length_unchanged() {
    // Exactly MAX length: the `>` branch must be false, so no truncation and no
    // ellipsis. This kills the `>` -> `==` and `>` -> `>=` mutants.
    let exact = "x".repeat(256);
    let err = ReportStorageError::provider_failure(exact.clone());
    let detail = match err {
        ReportStorageError::ProviderFailure { detail } => detail,
        other => panic!("expected ProviderFailure, got {other:?}"),
    };
    assert_eq!(
        detail, exact,
        "exact-boundary detail must be unchanged (no ellipsis)"
    );
    assert!(!detail.ends_with('…'));
}

#[test]
fn sanitize_keeps_short_detail_unchanged() {
    let short = "disk full".to_string();
    let err = ReportStorageError::provider_failure(short.clone());
    let detail = match err {
        ReportStorageError::ProviderFailure { detail } => detail,
        other => panic!("expected ProviderFailure, got {other:?}"),
    };
    assert_eq!(detail, short);
    assert!(!detail.ends_with('…'));
}

#[test]
fn sanitize_redacts_sensitive_substrings() {
    let err = ReportStorageError::provider_failure("connection failed: password=supersecret");
    let detail = match err {
        ReportStorageError::ProviderFailure { detail } => detail,
        other => panic!("expected ProviderFailure, got {other:?}"),
    };
    assert_eq!(detail, "redacted provider error");
    assert!(!detail.to_ascii_lowercase().contains("password"));
}
