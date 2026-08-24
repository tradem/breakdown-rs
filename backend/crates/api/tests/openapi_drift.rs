// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: ox-alpha-free (opencode-go)

//! OpenAPI drift check between the checked-in review artifact
//! `backend/openapi.yaml` and the utoipa-generated document [`api::api_doc`]
//! (issue #29).
//!
//! The API contract is authored **code-first** via utoipa derives (ADR-006),
//! but it is *reviewed* through a checked-in YAML snapshot: every PR that
//! changes the wire contract must regenerate the artifact, so the diff shows
//! up in review instead of only appearing at runtime under `/swagger-ui`.
//! CI fails when the two diverge.
//!
//! Regenerate with `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`.
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

/// Checked-in review artifact: `backend/openapi.yaml`.
fn artifact_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../openapi.yaml")
}

/// Render the generated document as canonical YAML.
///
/// `serde_json::Value` orders object keys alphabetically (no
/// `preserve_order` feature), so the rendering is deterministic across
/// builds regardless of utoipa's insertion order.
fn rendered_yaml() -> String {
    let doc = api::api_doc();
    let json = serde_json::to_value(&doc).expect("serialize OpenAPI doc to JSON");
    let yaml = serde_yaml::to_string(&json).expect("render OpenAPI doc as YAML");
    // Normalize the trailing newline so git sees a stable file.
    yaml.trim_end().to_string() + "\n"
}

#[test]
fn openapi_yaml_matches_generated_doc() {
    let rendered = rendered_yaml();
    let path = artifact_path();

    if std::env::var_os("UPDATE_OPENAPI").is_some() {
        fs::write(&path, &rendered).expect("write openapi.yaml");
        println!("rewrote {}", path.display());
        return;
    }

    match fs::read_to_string(&path) {
        Ok(checked_in) if checked_in.trim_end() == rendered.trim_end() => {}
        Ok(_) => panic!(
            "DIFF  openapi.yaml is stale — run \
             `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`, \
             then commit backend/openapi.yaml"
        ),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => panic!(
            "MISSING openapi.yaml — run \
             `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`, \
             then commit backend/openapi.yaml"
        ),
        Err(e) => panic!("cannot read {}: {e}", path.display()),
    }
}

#[test]
fn generated_doc_is_a_sane_openapi_contract() {
    let json = serde_json::to_value(api::api_doc()).expect("serialize OpenAPI doc");
    assert_eq!(
        json["openapi"], "3.1.0",
        "unexpected OpenAPI version (utoipa 5.x emits 3.1.0)"
    );
    let paths = json["paths"].as_object().expect("paths object present");
    assert!(!paths.is_empty(), "generated contract documents no paths");
    assert!(
        paths.keys().all(|p| p.starts_with("/v1/")),
        "ADR-021: every documented path carries the /v1 prefix"
    );
    assert_eq!(
        json["info"]["version"], "v1",
        "ADR-021 pins info.version to v1"
    );
}
