// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for the bounded Poppler subprocess plumbing (issue #958).
//!
//! These cover the bounds that must hold even when the tool misbehaves; the
//! tests that need a real PDF live next to the adapters.

use std::time::Duration;

use breakdown_core::error::DomainError;

use super::{render_page_png, run_bounded};

#[tokio::test]
async fn run_bounded_reports_a_missing_program_as_validation() {
    let error = run_bounded(
        "breakdown-rs-definitely-not-a-tool",
        &["--version"],
        b"",
        1024,
        Duration::from_secs(5),
    )
    .await
    .expect_err("an unknown program must fail");
    assert!(matches!(error, DomainError::Validation { .. }));
    assert!(error.to_string().contains("could not start"));
}

#[tokio::test]
async fn run_bounded_caps_oversized_output_and_names_the_tool() {
    // `cat` echoes stdin back, so a 100-byte payload against a 10-byte ceiling
    // exercises exactly the oversize branch (and the kill+reap behind it).
    let payload = vec![b'x'; 100];
    let error = run_bounded("cat", &[], &payload, 10, Duration::from_secs(5))
        .await
        .expect_err("oversized output must be rejected");
    assert!(error.to_string().contains("exceeds the configured bound"));
    assert!(error.to_string().contains("cat"));
}

#[tokio::test]
async fn run_bounded_passes_output_through_below_the_ceiling() {
    let output = run_bounded("cat", &[], b"hello", 1024, Duration::from_secs(5))
        .await
        .expect("cat must succeed");
    assert_eq!(output, b"hello");
}

#[tokio::test]
async fn run_bounded_times_out_and_reaps_the_child() {
    // `sleep` never reads stdin and never writes stdout: the exchange can only
    // end through the timeout branch.
    let error = run_bounded("sleep", &["30"], b"", 1024, Duration::from_millis(50))
        .await
        .expect_err("a hung child must time out");
    assert!(error.to_string().contains("did not finish within"));
}

#[tokio::test]
async fn run_bounded_reports_a_failing_exit_status() {
    let error = run_bounded("false", &[], b"", 1024, Duration::from_secs(5))
        .await
        .expect_err("a non-zero exit must fail");
    assert!(error.to_string().contains("failed with status"));
}

#[tokio::test]
async fn render_page_rejects_page_zero() {
    let error = render_page_png(b"%PDF-1.4", 0, 150, 1024, Duration::from_secs(5))
        .await
        .expect_err("page numbers are 1-based");
    assert!(error.to_string().contains("1-based"));
}
