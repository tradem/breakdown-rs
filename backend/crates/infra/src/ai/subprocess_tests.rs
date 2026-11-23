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
    // `sh` records its own pid and then `exec`s a `sleep` that never reads stdin
    // and never writes stdout: the exchange can only end through the timeout
    // branch. The pid file is what makes the child observable *after*
    // `run_bounded` returned — a killed-but-unreaped child stays in `/proc` as a
    // zombie, which is exactly what the timeout branch's `reap_child` prevents.
    let pid_file = std::env::temp_dir().join(format!(
        "breakdown-rs-run-bounded-reap-{}.pid",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&pid_file);
    let script = format!("echo $$ > {}; exec sleep 30", pid_file.display());
    let error = run_bounded("sh", &["-c", &script], b"", 1024, Duration::from_secs(1))
        .await
        .expect_err("a hung child must time out");
    assert!(error.to_string().contains("did not finish within"));

    let pid = std::fs::read_to_string(&pid_file)
        .map(|text| text.trim().to_owned())
        .expect("the child recorded its pid before the timeout fired");
    let _ = std::fs::remove_file(&pid_file);
    // The only honest proof of reaping is that the pid left `/proc` entirely: a
    // zombie (`Z`) was killed but never collected, and a `R`/`S` entry means the
    // child is still running. Both fail; only `NotFound` passes, and an
    // unreadable `/proc` is reported as unsupported instead of as success.
    match child_presence(&pid) {
        ChildPresence::Gone => {}
        ChildPresence::Present(state) => panic!(
            "child {pid} is still in /proc with state `{state}`: the timeout branch \
             did not reap it"
        ),
        ChildPresence::Unsupported => {
            eprintln!("skipped: /proc is unavailable, so the reap cannot be observed")
        }
    }
}

/// What `/proc` says about a pid after [`run_bounded`] returned.
#[derive(Debug, PartialEq, Eq)]
enum ChildPresence {
    /// No `/proc/<pid>` entry: the child was waited for, not merely killed.
    Gone,
    /// The entry exists — `Z` for a zombie, `R`/`S`/… for a still-running child.
    /// `?` means the entry existed but its state could not be read.
    Present(char),
    /// No `/proc` on this host: the lifecycle check cannot be made.
    Unsupported,
}

fn child_presence(pid: &str) -> ChildPresence {
    match std::fs::read_to_string(format!("/proc/{pid}/stat")) {
        Ok(stat) => ChildPresence::Present(state_of(&stat)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => ChildPresence::Gone,
        // A read error only means "no /proc" when /proc itself is missing;
        // treating every error as `Gone` is exactly what made this check vacuous.
        Err(_) if !std::path::Path::new("/proc/self/stat").exists() => ChildPresence::Unsupported,
        Err(_) => ChildPresence::Present('?'),
    }
}

/// The process state letter of one `/proc/<pid>/stat` line.
///
/// Field 3 is the state, but field 2 (`comm`) is parenthesized and may itself
/// contain `)`, so the state is whatever follows the LAST `)`.
fn state_of(stat: &str) -> char {
    stat.rsplit_once(')')
        .and_then(|(_, rest)| rest.trim_start().chars().next())
        .unwrap_or('?')
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
