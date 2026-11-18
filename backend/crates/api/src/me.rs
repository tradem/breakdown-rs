// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! The self surface (`GET /v1/me/…`, issue #816): what the **caller** may do.
//!
//! `GET /v1/me/capabilities` is the first and (for now) only member of the
//! `/me` namespace. It publishes the two **deployment-scoped** predicates the
//! authorization policy enforces — `has_active_credential_role` (settings /
//! AI-config management, ADR-027) and `has_active_ops_role` (issue #409) — so a
//! client can state "Keine Berechtigung" *before* it taps, instead of
//! interpreting a 403 from the surface it was about to use.
//!
//! Why a self-report and not a gate: the season-scoped membership signal the
//! client had is the wrong tool for a deployment-scoped predicate (it is a
//! superset — it also admits `wardrobe_supervisor` — and it is ambient, so a
//! stale scope reads as a denial; see #809 C3a/C3b). ADR-035 B2 forbids adding
//! a new `*_in_season` predicate for this, and a second 403-armed route would
//! only restate the denial the caller is trying to avoid provoking.
//!
//! Both values are resolved through the **injected**
//! [`crate::state::AppState::authorization_policy`] — the same instance the
//! middleware enforces with — so the reported answer cannot drift from
//! enforcement: the ops arm includes the deployment's `OPS_ADMIN_SUBS`
//! bootstrap allowlist, and a read-model failure surfaces as an error response
//! (registered problem code) instead of a fabricated `false`.

use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::membership::policy::PolicyDecision;
use serde::Serialize;
use utoipa::ToSchema;

use crate::auth::CurrentUser;
use crate::problems::{ApiError, Json, ProblemDetails};
use crate::state::{AppState, Ports};

/// The caller's global (deployment-scoped) capabilities — the wire shape of
/// [`crate::state::AppState::authorization_policy`]'s two global arms.
///
/// Field names are the repository predicates verbatim on purpose: the client
/// consumes them *as* the backend-computed answer (CQRS-boundary rule), so a
/// rename here must be a deliberate wire change, not a cosmetic one.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct MyCapabilitiesResponse {
    /// The caller holds an active credential role (`costume_designer` /
    /// `costume_assistant`) in **any** block — the settings / AI-configuration
    /// management gate.
    pub has_active_credential_role: bool,
    /// The caller holds the ops capability: an active `ops_admin` membership in
    /// any block **or** a place on the deployment's `OPS_ADMIN_SUBS` bootstrap
    /// allowlist (cold start, issue #409).
    pub has_active_ops_role: bool,
}

/// Map one resolved policy decision to a boolean capability.
///
/// `Allow` is `true`, `Deny` is `false` — a denial is an ANSWER here, not a
/// failure. (The failure case never reaches this function: the fallible policy
/// call is `?`-propagated in [`get_my_capabilities`].)
fn resolved(decision: PolicyDecision) -> bool {
    matches!(decision, PolicyDecision::Allow)
}

/// `GET /v1/me/capabilities` — the caller's global capability self-report.
///
/// **200 with booleans, never 403** (decided on issue #816): the route performs
/// no privileged action, and its entire purpose is to let the client
/// distinguish "denied" from "unknown" before it acts. A 403 here would be a
/// second form of the denial the client is trying to pre-empt — and would hide
/// the ops answer from exactly the callers who lack the credential role.
///
/// Error handling: both policy arms are FALLIBLE, and a failure is NOT a
/// denial — the read model could not be read, so the response is the mapped
/// server error (registered `http.internal-error`), never a fabricated
/// `false` (the client would render a permission problem for a server fault).
///
/// AUTHZ-GATE (issue #816): `Requirement::Authenticated` at the middleware —
/// this route is deliberately exempt from the block-scoped membership check,
/// because a deployment-scoped capability says nothing about the caller's
/// `X-Active-Block`. Both predicates are therefore resolved **inside this
/// handler** through the injected `AuthorizationPolicy` (never the repository
/// directly, so the report and the enforcement cannot diverge). Unlike the
/// privileged `Authenticated`-only routes, this handler does not answer 403 on
/// denial: it *reports* the decision instead of enforcing one.
#[utoipa::path(
    get,
    path = "/me/capabilities",
    tag = "handlers",
    responses(
        (status = 200, body = MyCapabilitiesResponse, description = "The caller's deployment-scoped capabilities (both predicates are resolved through the authorization policy)"),
        (status = 401, body = ProblemDetails, description = "Missing or invalid OIDC token"),
        (status = 500, body = ProblemDetails, description = "Membership read model failure — a predicate could not be resolved"),
    )
)]
pub async fn get_my_capabilities<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
) -> Result<(StatusCode, Json<MyCapabilitiesResponse>), ApiError> {
    let credential = state
        .authorization_policy
        .authorize_credential_role(&current_user.sub)
        .await
        .map_err(ApiError::from)?;
    let ops = state
        .authorization_policy
        .authorize_ops(&current_user.sub)
        .await
        .map_err(ApiError::from)?;
    Ok((
        StatusCode::OK,
        Json(MyCapabilitiesResponse {
            has_active_credential_role: resolved(credential),
            has_active_ops_role: resolved(ops),
        }),
    ))
}
