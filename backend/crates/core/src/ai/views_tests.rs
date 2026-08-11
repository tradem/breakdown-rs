// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use super::SourceFormat;

#[test]
fn only_csv_uses_the_native_parser() {
    // Issue #221: the schedule worker routes by this predicate; CSV is the
    // only format parsed in-process, PDF and plain text go to the LLM.
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
