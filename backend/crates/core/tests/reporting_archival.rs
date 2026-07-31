// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

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
