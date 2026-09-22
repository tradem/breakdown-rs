// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

//! Deterministic fault injection for E2E test scenarios (issue #443).
//!
//! **Entirely compiled out of production builds:** every item in this module
//! lives behind `#[cfg(feature = "test-support")]` at the `pub mod` site in
//! `lib.rs` — a release binary (`cargo build` without `--features
//! test-support`) does not contain this code at all. The E2E/Gherkin backend
//! must be booted with `cargo run -p api --features api/test-support`
//! (dev only). This satisfies the AGENTS.md §3 `test-helper-gate` checklist
//! item by compile-time absence, not by naming convention.
//!
//! # Mechanism
//!
//! A process-global one-shot latch keyed by a fault name. The Gherkin
//! arrange step (host-side runner process, which has network access to the
//! dev backend) arms the fault via the cfg-gated control route
//! [`fault_control_routes`]. The NEXT `POST /v1/blocks` then fires the latch
//! and short-circuits with the REAL registry problem — 409
//! `block.number-already-exists`, the same code the advisory API-edge
//! pre-check in [`crate::handlers::create_block`] emits — rendered through
//! the standard [`crate::problems::ApiError`] path, so the wire document is
//! identical to a genuine conflict. The latch is consumed, so the wizard's
//! in-session retry passes through to the real handler.
//!
//! The wizard derives its block numbers from the projections (`max + 1`), so
//! a client-side arrange cannot hit the real pre-check deterministically —
//! this latch is the server-side injection point the scenario needs.
//!
//! No new problem code is registered (the `problem-code-registry` rule is
//! untouched); the middleware reuses [`BLOCK_NUMBER_ALREADY_EXISTS`] from
//! the `problem_codes!` registry. The control route is deliberately NOT in
//! the utoipa derive — it must never appear in `backend/openapi.yaml` (the
//! `openapi_drift` test fails if a mounted route leaks into the documented
//! spec, so the route stays out of `handlers::routes()` and the `#[openapi]`
//! `paths`).

use std::sync::OnceLock;

use axum::Router;
use axum::extract::State;
use axum::http::{Method, Request, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use axum::routing::post;

use breakdown_core::error::DomainError;
use breakdown_core::error_registry::BLOCK_NUMBER_ALREADY_EXISTS;

use crate::problems::{ApiError, Path};
use crate::state::AppState;

/// The designated fault name of this module (issue #443): the next block
/// create is rejected with a conflict. A scoped one-shot namespace — a
/// generic fault DSL (if ever) extends from here.
pub const FAULT_BLOCK_CONFLICT: &str = "block-conflict";

/// The one-shot latch. Process-global instead of an `AppState` field: the
/// fault machinery must not touch production state construction, and a
/// global keeps the composition-root diff to two cfg-gated lines in
/// `app_router`. Contention (two concurrent armed requests) is a test-only
/// concern; the latch is atomic either way.
static FAULTS: OnceLock<std::sync::Mutex<std::collections::HashMap<String, ()>>> = OnceLock::new();

fn faults() -> &'static std::sync::Mutex<std::collections::HashMap<String, ()>> {
    FAULTS.get_or_init(|| std::sync::Mutex::new(std::collections::HashMap::new()))
}

/// Record a pending one-shot fault for [name]. Never blocks command
/// processing on poisoning: a panicked lock holder cannot corrupt this
/// map, so the guard is recovered rather than propagated.
fn arm(name: &str) {
    let mut map = faults()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    map.insert(name.to_string(), ());
}

/// Atomically consume the pending fault for [name] — `true` exactly once.
fn take(name: &str) -> bool {
    let mut map = faults()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    map.remove(name).is_some()
}

/// The fault-injection middleware. Compile-time absent in release builds.
///
/// Intercepts ONLY `POST /v1/blocks` requests while a
/// [`FAULT_BLOCK_CONFLICT`] latch is armed; everything else (other methods,
/// other paths, unreached latches) passes through untouched. The header/
/// method sniffing is by-absence inert in non-test builds: this function is
/// not compiled.
pub async fn fault_injection_middleware(
    request: Request<axum::body::Body>,
    next: Next,
) -> Response {
    if request.method() == Method::POST
        && request.uri().path() == "/v1/blocks"
        && take(FAULT_BLOCK_CONFLICT)
    {
        tracing::warn!("injected fault: one-shot block-conflict latch fired (issue #443)");
        // The REAL registry problem via the single rendering path — the
        // response is byte-identical to the advisory pre-check's 409.
        return ApiError::Domain(DomainError::Conflict {
            code: &BLOCK_NUMBER_ALREADY_EXISTS,
            reason: "injected fault: block number already taken".into(),
        })
        .into_response();
    }
    next.run(request).await
}

/// The cfg-gated control routes the host-side Gherkin arrange step calls:
/// `POST /v1/__faults/{fault}` arms the one-shot fault named [fault]
/// (`204 No Content`). Generic over the state's `Ports` so integration
/// tests can mount the routes over `FakePorts` the same way `app_router`
/// mounts them over `ProductionPorts`.
///
/// The path param uses the ADR-031 problem-document wrapper
/// [`crate::problems::Path`], not the raw `axum::extract::Path`, so even the
/// never-in-practice rejection path (a `String`-typed segment always parses)
/// answers with `http.bad-path-param` (RFC 9457) instead of axum's plain-text
/// rejection — the same contract every production handler follows (issue
/// #483, follow-up to #467). No rejection regression test is added here:
/// `Path<String>` against a path template cannot reject, so the switching is
/// defense-in-depth for a future segment-type change, not a reachable branch
/// today.
pub fn fault_control_routes<P: crate::state::Ports>() -> Router<AppState<P>> {
    Router::new().route("/__faults/{fault}", post(arm_fault::<P>))
}

async fn arm_fault<P: crate::state::Ports>(
    State(_state): State<AppState<P>>,
    Path(fault): Path<String>,
) -> Result<Response, ApiError> {
    // Whitelist the designated faults so a typo (or a stray prod curl on a
    // misconfigured test-support build) never silently arms a no-op.
    if fault != FAULT_BLOCK_CONFLICT {
        return Err(ApiError::NotFound(
            "unknown fault for this test-support build",
        ));
    }
    arm(&fault);
    tracing::warn!(fault = %fault, "fault armed (test-support build)");
    Ok(StatusCode::NO_CONTENT.into_response())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn latch_is_one_shot() {
        arm("block-conflict");
        assert!(take("block-conflict"));
        // Consumed: the retry (and any later request) passes through.
        assert!(!take("block-conflict"));
    }

    #[test]
    fn unarmed_latch_never_fires() {
        assert!(!take("block-conflict"));
    }

    #[test]
    fn latch_keys_are_independent() {
        arm("other-fault");
        assert!(!take("block-conflict"));
        assert!(take("other-fault"));
    }
}
