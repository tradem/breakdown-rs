// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: ox-alpha-free (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

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

/// Regression guard for issue #334: every `{var}` in a path template must be
/// defined as a required `in: path` parameter on the operation (or the
/// path item).
///
/// `utoipa` only infers tuple `Path<(A, B, ...)>` extractors, so a handler
/// using a single-value `Path(id): Path<Newtype>` documents no parameter at
/// all unless it is declared explicitly via `params(...)`. The generated
/// client then emits a literal `{id}` in the request URL — the three PDF
/// report routes shipped exactly this defect until PR #344 declared the
/// parameters explicitly. This test fails the contract the moment any
/// operation reintroduces an undeclared template variable.
#[test]
fn every_path_template_variable_is_defined() {
    let json = serde_json::to_value(api::api_doc()).expect("serialize OpenAPI doc");
    let paths = json["paths"].as_object().expect("paths object present");
    // Operations that may carry `parameters:` in this contract (OpenAPI Path
    // Item operations; utoipa supports `trace`, so it must not bypass this
    // guard — CodeRabbit review on PR #349).
    const METHODS: [&str; 8] = [
        "get", "post", "put", "patch", "delete", "options", "head", "trace",
    ];
    let mut failures: Vec<String> = Vec::new();
    for (path, item) in paths {
        let template_vars = template_variables(path);
        if template_vars.is_empty() {
            continue;
        }
        let item_params = item.get("parameters");
        for method in METHODS {
            let Some(op) = item.get(method) else {
                continue;
            };
            let op_params = op.get("parameters");
            let missing: Vec<String> = template_vars
                .iter()
                .filter(|var| {
                    !(parameter_defined(item_params, var) || parameter_defined(op_params, var))
                })
                .map(|var| format!("{{{var}}}"))
                .collect();
            if !missing.is_empty() {
                failures.push(format!(
                    "{method} {path}: undeclared {}",
                    missing.join(", ")
                ));
            }
        }
    }
    assert!(
        failures.is_empty(),
        "path template variables without a required `in: path` parameter (issue #334):\n  {}",
        failures.join("\n  ")
    );
}

/// Extract `{var}` names from an OpenAPI path template.
fn template_variables(path: &str) -> Vec<&str> {
    let mut vars = Vec::new();
    let mut rest = path;
    while let Some(open) = rest.find('{') {
        let after = &rest[open + 1..];
        if let Some(close) = after.find('}') {
            let name = &after[..close];
            if !name.is_empty() && !name.contains('/') && !name.contains('{') {
                vars.push(name);
            }
            rest = &after[close + 1..];
        } else {
            break;
        }
    }
    vars
}

/// Regression guard for issue #343 (ADR-031): every operation must document
/// at least one non-2xx response with an `application/problem+json` body, so
/// the generated Dart client keeps a typed error contract and new handlers
/// cannot regress to success-only documentation.
///
/// The `application/problem+json` media type is the post-`api_doc()` rewrite
/// of any `body = ProblemDetails` response (the rewrite keys on the
/// `ProblemDetails` schema ref). The test asserts both halves explicitly —
/// media type AND schema `$ref` — instead of relying on the rewrite, so a
/// hand-written problem media type with an unrelated schema still fails.
#[test]
fn every_operation_documents_an_error_response() {
    let json = serde_json::to_value(api::api_doc()).expect("serialize OpenAPI doc");
    let paths = json["paths"].as_object().expect("paths object present");
    const METHODS: [&str; 8] = [
        "get", "post", "put", "patch", "delete", "options", "head", "trace",
    ];
    let mut failures: Vec<String> = Vec::new();
    for (path, item) in paths {
        for method in METHODS {
            let Some(op) = item.get(method) else {
                continue;
            };
            let Some(responses) = op.get("responses").and_then(serde_json::Value::as_object) else {
                failures.push(format!("{method} {path}: no responses documented"));
                continue;
            };
            let mut has_problem_error = false;
            for (status, response) in responses {
                let is_error = status.starts_with('4') || status.starts_with('5');
                if !is_error {
                    continue;
                }
                // Assert the schema `$ref`, not just the media type: any schema
                // under `application/problem+json` would otherwise pass and a
                // future unrelated schema could silently break the typed error
                // contract of the generated client.
                let has_problem_body = response
                    .get("content")
                    .and_then(|content| content.get("application/problem+json"))
                    .and_then(|media| media.get("schema"))
                    .and_then(|schema| schema.get("$ref"))
                    .and_then(serde_json::Value::as_str)
                    .is_some_and(|ref_location| ref_location.ends_with("/ProblemDetails"));
                if has_problem_body {
                    has_problem_error = true;
                } else {
                    failures.push(format!(
                        "{method} {path}: response {status} has no ProblemDetails application/problem+json body (issue #343)"
                    ));
                }
            }
            if !has_problem_error {
                failures.push(format!(
                    "{method} {path}: no non-2xx application/problem+json response (issue #343)"
                ));
            }
        }
    }
    assert!(
        failures.is_empty(),
        "operations without a documented RFC 9457 error response (issue #343):\n  {}",
        failures.join("\n  ")
    );
}

/// True when `parameters` (an OpenAPI parameter list) defines `name` as a
/// required `in: path` parameter.
fn parameter_defined(parameters: Option<&serde_json::Value>, name: &str) -> bool {
    let Some(params) = parameters.and_then(serde_json::Value::as_array) else {
        return false;
    };
    params.iter().any(|p| {
        p.get("name").and_then(serde_json::Value::as_str) == Some(name)
            && p.get("in").and_then(serde_json::Value::as_str) == Some("path")
            && p.get("required").and_then(serde_json::Value::as_bool) == Some(true)
    })
}
