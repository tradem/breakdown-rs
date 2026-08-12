// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

//! Golden-file snapshots of the problem document per registered code
//! (ADR-031 D4 / http-error-surface spec "Extension diff is review-visible").
//!
//! Every registry entry renders one `application/problem+json` document;
//! the snapshot captures `type` (derived from the code), constant English
//! `title`, `status`, and the declared S0/S1 extension whitelist (rendered
//! as the `extensions` member with the declared field names — the values are
//! request-dependent, so the snapshot records the field *names*).
//!
//! CI fails on any envelope/extension diff: adding, renaming, or
//! reclassifying an extension field — or changing a code's status/title —
//! must be an explicit, review-visible change to the golden files.
//!
//! Regenerate with `UPDATE_GOLDEN=1 cargo test -p api --test problem_golden`.

// Test code: workspace denies `clippy::expect_used`/`unwrap_used`; this file
// uses `.expect()` with explicit messages (same pattern as the other api
// tests).
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

use std::fs;
use std::path::PathBuf;

use api::problems::{PROBLEM_CONTENT_TYPE, problem};
use breakdown_core::error_registry::PROBLEM_CODES;

/// Golden dir: `crates/api/tests/golden/problems/`.
fn golden_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("golden")
        .join("problems")
}

/// Sample value for a declared extension field (golden rendering only).
///
/// Every declared field must be bound when the snapshot is built: the
/// localized `detail` has to lock in the *bound* message. Without
/// arguments, Fluent renders unbound placeholders surrounded by bidi-isolate
/// markers (U+2068/U+2069) — a snapshot of that would pin rendering internals
/// instead of the contract.
fn sample_extension_value(field: &str) -> serde_json::Value {
    match field {
        // Integers per the OpenAPI example (`expected_version: 2,
        // current_version: 3`).
        "expected_version" => serde_json::json!(2),
        "current_version" => serde_json::json!(3),
        // UUID-typed S1 fields (character/shooting-day/photo ids): a
        // syntactically valid placeholder id.
        _ => serde_json::json!("00000000-0000-0000-0000-000000000001"),
    }
}

#[test]
fn problem_documents_match_golden_snapshots() {
    let update = std::env::var("UPDATE_GOLDEN")
        .is_ok_and(|v| !v.is_empty() && v != "0" && !v.eq_ignore_ascii_case("false"));
    let mut failures: Vec<String> = Vec::new();

    for entry in PROBLEM_CODES {
        let mut builder = problem(*entry);
        for field in entry.extensions {
            builder = builder.extension(*field, sample_extension_value(field));
        }
        let document = builder.build();
        let mut json = serde_json::to_value(&document).expect("problem serializes");
        // `trace_id` is request-scoped (otel span / random fallback) and must
        // not be part of the stable snapshot.
        json.as_object_mut().expect("object").remove("trace_id");

        let rendered = serde_json::to_string_pretty(&json).expect("pretty") + "\n";
        let path = golden_dir().join(format!("{}.json", entry.code));

        if update {
            fs::create_dir_all(golden_dir()).expect("create golden dir");
            fs::write(&path, &rendered).expect("write golden");
            continue;
        }

        match fs::read_to_string(&path) {
            Ok(expected) => {
                if expected != rendered {
                    failures.push(format!(
                        "DIFF  {} — run `UPDATE_GOLDEN=1 cargo test -p api --test problem_golden` after reviewing\n--- expected ---\n{expected}--- actual ---\n{rendered}",
                        entry.code
                    ));
                }
            }
            Err(_) => failures.push(format!("MISSING golden for code {}", entry.code)),
        }
    }

    // Reverse direction: a golden file with no registry entry is a leftover
    // from a renamed or deleted code and must fail the build (renaming is
    // otherwise only half-visible in review). Skipped in update mode.
    if !update && let Ok(dir) = fs::read_dir(golden_dir()) {
        for file in dir.flatten() {
            let name = file.file_name().to_string_lossy().into_owned();
            let Some(code) = name.strip_suffix(".json") else {
                continue;
            };
            if !PROBLEM_CODES.iter().any(|entry| entry.code == code) {
                failures.push(format!("ORPHAN golden {name} has no registry entry"));
            }
        }
    }

    assert!(
        failures.is_empty(),
        "Golden-file mismatches ({count}):\n{failures}",
        count = failures.len(),
        failures = failures.join("\n")
    );
}

/// The media type of every problem is fixed (RFC 9457).
#[test]
fn content_type_is_application_problem_json() {
    assert_eq!(PROBLEM_CONTENT_TYPE, "application/problem+json");
}

/// Extension whitelist sanity: membership codes never declare a person
/// identifier (S2 ban, ADR-031 D4) — enforced mechanically by the golden
/// snapshots (their `extensions` member would show the field).
#[test]
fn membership_codes_carry_no_person_identifiers() {
    for entry in PROBLEM_CODES
        .iter()
        .filter(|e| e.code.starts_with("membership."))
    {
        for field in entry.extensions {
            assert!(
                !field.contains("user_id") && !field.contains("email") && !field.contains("sub"),
                "membership code {} declares banned S2 field {field}",
                entry.code
            );
        }
    }
}
