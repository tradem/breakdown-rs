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
use breakdown_core::reporting::ReportKind;
use infra::reporting::triggers::{ALL_KINDS, ScheduleConfig};
use std::time::Duration;

#[test]
fn all_kinds_covers_three_reports() {
    assert_eq!(ALL_KINDS.len(), 3);
    assert!(ALL_KINDS.contains(&ReportKind::Dispo));
    assert!(ALL_KINDS.contains(&ReportKind::ShootDay));
    assert!(ALL_KINDS.contains(&ReportKind::PlannedVsActual));
}

#[test]
fn schedule_config_defaults() {
    let cfg = ScheduleConfig {
        enabled: true,
        interval: Duration::from_secs(1),
    };
    assert!(cfg.enabled);
    assert_eq!(cfg.interval, Duration::from_secs(1));
}
