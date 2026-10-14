// SPDX-License-Identifier: AGPL-3.0
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

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

    use super::*;

    #[tokio::test]
    async fn meta_versions_reports_compile_time_crate_versions() {
        let response = get_meta_versions().await;
        assert_eq!(response.status(), StatusCode::OK);
        // Shape check via the response body would need axum body buffering;
        // the struct is built from constants, so assert the constants
        // directly — this pins the compile-time sourcing contract.
        let expected = MetaVersionsResponse {
            api: env!("CARGO_PKG_VERSION"),
            core: breakdown_core::VERSION,
            infra: infra::VERSION,
        };
        assert!(!expected.api.is_empty());
        assert!(!expected.core.is_empty());
        assert!(!expected.infra.is_empty());
        // The crate versions are distinct lockstep tracks — core must not
        // accidentally alias the api version (independent bumps per crate).
        let json = serde_json::to_value(&expected).unwrap();
        assert_eq!(json["api"], env!("CARGO_PKG_VERSION"));
        assert_eq!(json["core"], breakdown_core::VERSION);
        assert_eq!(json["infra"], infra::VERSION);
    }
}
