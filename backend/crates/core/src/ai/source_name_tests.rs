// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for the document-name sanitizer (issue #763).
//!
//! The contract is a *display* contract: a name either survives as something a
//! human can read back verbatim, or it is absent. A half-sanitized value that
//! still looks intentional is the failure mode these tests rule out.

use super::{MAX_SOURCE_FILE_NAME_CHARS, sanitize_source_file_name};

#[test]
fn plain_name_is_kept_verbatim() {
    assert_eq!(
        sanitize_source_file_name("Erlösung Skript.pdf").as_deref(),
        Some("Erlösung Skript.pdf")
    );
}

#[test]
fn path_segments_are_dropped() {
    // Neither a POSIX path nor a Windows path contributes its directories: the
    // caller's layout is not display data.
    assert_eq!(
        sanitize_source_file_name("../../etc/passwd").as_deref(),
        Some("passwd")
    );
    assert_eq!(
        sanitize_source_file_name(r"C:\Users\costume\board.pdf").as_deref(),
        Some("board.pdf")
    );
    assert_eq!(
        sanitize_source_file_name("/tmp/imports/Ep. 299 Drehplan.csv").as_deref(),
        Some("Ep. 299 Drehplan.csv")
    );
}

#[test]
fn control_characters_cannot_round_trip() {
    // A header-injection attempt: the CRLF is stripped, the two halves join.
    assert_eq!(
        sanitize_source_file_name("a.pdf\r\nX-Injected: 1").as_deref(),
        Some("a.pdfX-Injected: 1")
    );
    // A NUL and a DEL are both control characters.
    assert_eq!(
        sanitize_source_file_name("scr\u{0}ipt\u{7f}.pdf").as_deref(),
        Some("script.pdf")
    );
}

#[test]
fn whitespace_runs_collapse_to_one_space() {
    assert_eq!(
        sanitize_source_file_name("  Drehplan \t\t Ep. 299  .csv ").as_deref(),
        Some("Drehplan Ep. 299 .csv")
    );
    // A non-breaking space is whitespace too, not a printable look-alike.
    assert_eq!(
        sanitize_source_file_name("Ep.\u{a0}299.pdf").as_deref(),
        Some("Ep. 299.pdf")
    );
}

#[test]
fn nothing_printable_is_absent() {
    assert_eq!(sanitize_source_file_name(""), None);
    assert_eq!(sanitize_source_file_name("    \t\n "), None);
    // Path-relative sentinels carry no name.
    assert_eq!(sanitize_source_file_name("."), None);
    assert_eq!(sanitize_source_file_name(".."), None);
    assert_eq!(sanitize_source_file_name("/tmp/"), None);
    assert_eq!(sanitize_source_file_name("\u{1}\u{2}\u{3}"), None);
}

#[test]
fn length_is_capped_on_a_char_boundary() {
    let long = "ä".repeat(MAX_SOURCE_FILE_NAME_CHARS + 50);
    let sanitized = sanitize_source_file_name(&long).expect("a long printable name survives");
    assert_eq!(sanitized.chars().count(), MAX_SOURCE_FILE_NAME_CHARS);
    // Byte length is twice the char count for `ä` — the cap is char-based, so
    // no character is cut in half.
    assert_eq!(sanitized.len(), MAX_SOURCE_FILE_NAME_CHARS * 2);
}

#[test]
fn a_cut_that_lands_on_a_space_is_re_trimmed() {
    // The boundary falls exactly on the space, so the cut leaves a trailing
    // space that must not be persisted.
    let name = format!("{}{}", "a".repeat(MAX_SOURCE_FILE_NAME_CHARS), " tail.pdf");
    let sanitized = sanitize_source_file_name(&name).expect("name survives");
    assert_eq!(sanitized.chars().count(), MAX_SOURCE_FILE_NAME_CHARS);
    assert!(!sanitized.ends_with(' '));
}
