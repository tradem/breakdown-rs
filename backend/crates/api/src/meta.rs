// SPDX-License-Identifier: AGPL-3.0
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Meta surface (issue #656): compile-time workspace crate versions for the
//! client's About screen.
//!
//! `GET /v1/meta/versions` reports the semantic version of every workspace
//! crate that is meaningful to a client (`api`, `core`, `infra`). Each value
//! is a `const` captured at build time from that crate's own
//! `CARGO_PKG_VERSION` — no runtime file reads, no manifest parsing. The
//! three crates carry independent versions (they bump in dependency lockstep
//! per PR, not in lockstep with each other), so the response reports each
//! crate individually with explicit fields — the generated Dart client gets
//! typed accessors, and new crates can be added additively later.

use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use utoipa::ToSchema;

/// Distinct LLM co-authors of this repository, deduped by `(model, provider)`.
///
/// Aggregation source (issue #655): the repo-wide
/// `Co-authored-by: <model> (<provider>)` header convention as documented in
/// the repository AGENTS.md files. A model that is attributed in many files
/// appears here exactly once per model+provider combination. Kept as a
/// compile-time const (no runtime scan, no git dependency in deployments);
/// `meta_credits_const_list_matches_agents_md_headers` in the tests below
/// enforces parity with the AGENTS.md files so drift is caught in CI.
/// Sorted by `(name, provider)` for a deterministic wire order.
const LLM_COAUTHORS: &[(&str, &str)] = &[
    ("deepseek-v4-flash", "neuralwatt"),
    ("deepseek-v4.1-flash", "neuralwatt"),
    ("glm-5.3", "neuralwatt"),
    ("glm-5.3-flash", "neuralwatt"),
    ("gpt-5.6-luna", "opencode-go"),
    ("hy3", "opencode-go"),
    ("omen-alpha", "opencode-go"),
    ("qwen3.8-flash", "opencode-go"),
    ("space-bunny-free", "opencode-go"),
];

/// Human contributors (issue #655): name → roles. Also sorted by name.
const HUMAN_CONTRIBUTORS: &[(&str, &[&str])] = &[
    ("digiwitcher", &["Developer"]),
    ("imacRic", &["Product Owner", "Tester"]),
];

/// One credit entry (issue #655): LLM co-author or human contributor.
///
/// One wire shape for both kinds so the client renders the word cloud from a
/// single payload: `provider` is set (and `roles` empty) for LLM co-authors;
/// `roles` is set (and `provider` null) for humans.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct MetaCreditsEntry {
    /// Display name — the model name (LLM) or the contributor handle (human).
    pub name: String,
    /// Provider/tool for LLM co-authors (e.g. `neuralwatt`); null for humans.
    pub provider: Option<String>,
    /// Roles for human contributors (e.g. `Developer`); empty for LLMs.
    pub roles: Vec<String>,
}

/// `GET /v1/meta/credits` response (issue #655): deduped LLM co-authors plus
/// the human contributors. LLM entries come first (sorted by name, provider),
/// humans second (sorted by name) — a fixed, deterministic order.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct MetaCreditsResponse {
    pub credits: Vec<MetaCreditsEntry>,
}

/// Builds the credit entries: const co-author list deduped by `(name, provider)`
/// (the const is already deduped — this is the belt-and-braces runtime dedupe,
/// so a future list edit cannot silently introduce a duplicate), then the
/// human contributors.
fn credits_entries() -> Vec<MetaCreditsEntry> {
    let mut seen = std::collections::BTreeSet::new();
    let mut entries = Vec::new();
    for (name, provider) in LLM_COAUTHORS {
        if seen.insert((*name, *provider)) {
            entries.push(MetaCreditsEntry {
                name: (*name).to_string(),
                provider: Some((*provider).to_string()),
                roles: Vec::new(),
            });
        }
    }
    for (name, roles) in HUMAN_CONTRIBUTORS {
        entries.push(MetaCreditsEntry {
            name: (*name).to_string(),
            provider: None,
            roles: roles.iter().map(|r| (*r).to_string()).collect(),
        });
    }
    entries
}

/// Compile-time versions of the workspace crates meaningful to clients.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct MetaVersionsResponse {
    /// Version of the `api` crate (the served HTTP surface itself).
    pub api: &'static str,
    /// Version of the `core` crate (domain logic).
    pub core: &'static str,
    /// Version of the `infra` crate (event store, projections).
    pub infra: &'static str,
}

/// `GET /v1/meta/versions` — compile-time workspace crate versions.
///
/// **Authenticated, not Public** (decided in the #656 change proposal):
/// unlike `/health` (a container probe that must run without any token),
/// this route serves the signed-in app's About screen, so requiring a valid
/// OIDC token costs the client nothing while denying anonymous probes a
/// backend version fingerprint. The response carries no tenant data and no
/// block-scoped action, so no membership requirement and no handler-internal
/// auth gate is needed — the `Authenticated` middleware classification is
/// the whole gate. The handler performs no I/O whatsoever.
#[utoipa::path(
    get,
    path = "/meta/versions",
    tag = "handlers",
    responses(
        (status = 200, description = "Compile-time versions of the workspace crates", body = MetaVersionsResponse),
        (status = 401, body = crate::problems::ProblemDetails, description = "Missing or invalid OIDC token"),
    )
)]
pub async fn get_meta_versions() -> Response {
    (
        StatusCode::OK,
        Json(MetaVersionsResponse {
            api: env!("CARGO_PKG_VERSION"),
            core: breakdown_core::VERSION,
            infra: infra::VERSION,
        }),
    )
        .into_response()
}

/// `GET /v1/meta/credits` — deduped LLM co-authors + human contributors.
///
/// **Authenticated, not Public** (same decision as `/meta/versions`, issue
/// #656, applied to this route per user decision on issue #655): the route
/// serves the signed-in app's credits screen, carries no tenant data and no
/// block-scoped action, so `Authenticated` is the whole gate — no
/// handler-internal auth gate needed. The handler performs no I/O.
#[utoipa::path(
    get,
    path = "/meta/credits",
    tag = "handlers",
    responses(
        (status = 200, description = "Deduped LLM co-authors and human contributors", body = MetaCreditsResponse),
        (status = 401, body = crate::problems::ProblemDetails, description = "Missing or invalid OIDC token"),
    )
)]
pub async fn get_meta_credits() -> Response {
    (
        StatusCode::OK,
        Json(MetaCreditsResponse {
            credits: credits_entries(),
        }),
    )
        .into_response()
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

    use super::*;

    #[tokio::test]
    async fn meta_versions_reports_compile_time_crate_versions() {
        let response = get_meta_versions().await;
        assert_eq!(response.status(), StatusCode::OK);
        // Assert the ACTUAL response body (not an independently built
        // struct): the wire JSON must carry each crate's compile-time
        // version — this pins both the serialization and the sourcing.
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["api"], env!("CARGO_PKG_VERSION"));
        assert_eq!(json["core"], breakdown_core::VERSION);
        assert_eq!(json["infra"], infra::VERSION);
        // No extra fields on the wire (explicit-fields contract).
        assert_eq!(
            json.as_object().unwrap().len(),
            3,
            "MetaVersionsResponse must expose exactly api/core/infra"
        );
    }

    #[tokio::test]
    async fn meta_credits_returns_deduped_coauthors_and_humans() {
        let response = get_meta_credits().await;
        assert_eq!(response.status(), StatusCode::OK);
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let credits = json["credits"].as_array().unwrap();

        // Dedupe behavior (issue #655): every (name, provider) combination
        // appears at most once across the whole payload.
        let mut seen = std::collections::BTreeSet::new();
        for entry in credits {
            let name = entry["name"].as_str().unwrap();
            let provider = entry["provider"].as_str();
            assert!(
                seen.insert((name.to_string(), provider.map(str::to_string))),
                "duplicate credit entry: {name} ({provider:?})"
            );
        }

        // Each documented co-author is present exactly once; the two humans
        // carry their roles and a null provider.
        let count_of = |name: &str| credits.iter().filter(|e| e["name"] == name).count();
        assert_eq!(
            count_of("glm-5.3"),
            1,
            "attributed in many files, listed once"
        );
        assert_eq!(count_of("omen-alpha"), 1);
        assert_eq!(count_of("deepseek-v4-flash"), 1);
        assert_eq!(count_of("deepseek-v4.1-flash"), 1);

        let digiwitcher = credits.iter().find(|e| e["name"] == "digiwitcher").unwrap();
        assert!(digiwitcher["provider"].is_null());
        assert_eq!(digiwitcher["roles"], serde_json::json!(["Developer"]));

        let imacric = credits.iter().find(|e| e["name"] == "imacRic").unwrap();
        assert!(imacric["provider"].is_null());
        assert_eq!(
            imacric["roles"],
            serde_json::json!(["Product Owner", "Tester"])
        );
    }

    /// Strips an HTML comment wrapper and returns the inner text of a line.
    fn comment_inner(line: &str) -> &str {
        let trimmed = line.trim();
        trimmed
            .strip_prefix("<!--")
            .and_then(|s| s.strip_suffix("-->"))
            .unwrap_or(trimmed)
            .trim()
    }

    /// Extracts the deduped `(model, provider)` set from one AGENTS.md file.
    fn coauthors_of(path: &std::path::Path) -> std::collections::BTreeSet<(String, String)> {
        let text = std::fs::read_to_string(path).unwrap();
        text.lines()
            .filter_map(|line| {
                comment_inner(line)
                    .strip_prefix("Co-authored-by: ")
                    .and_then(|rest| rest.rsplit_once(" ("))
                    .map(|(model, provider)| {
                        (
                            model.trim().to_string(),
                            provider.trim_end_matches(")").trim().to_string(),
                        )
                    })
            })
            .collect()
    }

    /// Parity guard (issue #655): the const list must exactly match the
    /// deduped `Co-authored-by: <model> (<provider>)` headers across the
    /// repository AGENTS.md files — the aggregation source the route
    /// documents. Adding a co-author to an AGENTS.md file fails this test
    /// until the const list is updated, so the credits endpoint never serves
    /// a stale list.
    #[test]
    fn meta_credits_const_list_matches_agents_md_headers() {
        let manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let agents_files = [
            manifest.join("../../AGENTS.md"),    // backend/
            manifest.join("../../../AGENTS.md"), // repo root
            manifest.join("../../../frontend-flutter/AGENTS.md"),
        ];
        let mut documented = std::collections::BTreeSet::new();
        for file in agents_files {
            documented.extend(coauthors_of(&file));
        }
        let const_set: std::collections::BTreeSet<(String, String)> = LLM_COAUTHORS
            .iter()
            .map(|(n, p)| ((*n).to_string(), (*p).to_string()))
            .collect();
        assert_eq!(
            const_set, documented,
            "LLM_COAUTHORS must match the deduped AGENTS.md co-author headers"
        );
    }
}
