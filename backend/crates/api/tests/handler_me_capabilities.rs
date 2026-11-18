// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! `GET /v1/me/capabilities` (issue #816) — the caller's global capability
//! self-report.
//!
//! The contract under test has three claims that each fail silently if they
//! regress:
//!
//! 1. **200 with booleans, never 403.** A denial is an ANSWER here (that is the
//!    whole point of the route: a client must be able to say "Keine
//!    Berechtigung" before it touches a gated surface).
//! 2. **The predicates are the ENFORCEMENT predicates.** Both are resolved
//!    through the injected `AuthorizationPolicy`, so the report cannot drift:
//!    the ops arm honours the `OPS_ADMIN_SUBS` bootstrap allowlist, and
//!    `wardrobe_supervisor` — which the season-scoped signal admits — does NOT
//!    grant the credential role (#809's reason for not reusing that signal).
//! 3. **A broken predicate is not a denial.** A read-model failure propagates
//!    as a server error; rendering it as `false` would put a permission problem
//!    in front of a user whose role is intact.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use crate::common;

use std::sync::Arc;

use api::auth::CurrentUser;
use api::me::get_my_capabilities;
use api::problems::Json;
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;

use breakdown_core::error::DomainError;
use breakdown_core::membership::Role;
use breakdown_core::membership::policy::{
    AuthContext, AuthorizationPolicy, PolicyDecision, SeasonAuthContext,
};
use breakdown_core::shared::{BlockId, ProjectId, SeasonId, UserId};
use common::*;

/// An active membership row in its own (irrelevant) block/season/project:
/// both global predicates are deployment-scoped, so the scope never matters.
async fn seed_role(ports: &FakePorts, sub: &str, role: Role) {
    ports
        .membership_repo
        .seed_active(
            BlockId::new(),
            UserId::from_sub(sub),
            role,
            SeasonId::new(),
            ProjectId::new(),
        )
        .await;
}

#[tokio::test]
async fn credential_role_is_reported_as_granted() {
    let ports = FakePorts::default();
    seed_role(&ports, "designer", Role::CostumeDesigner).await;

    let (status, Json(dto)) = get_my_capabilities::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("designer"),
    )
    .await
    .unwrap();

    assert_eq!(status, StatusCode::OK);
    assert!(dto.has_active_credential_role);
    assert!(!dto.has_active_ops_role);
}

/// The denial is a 200 with `false` — NOT a 403. This is the assertion that
/// keeps the route usable as a pre-tap gate.
#[tokio::test]
async fn missing_roles_are_reported_as_false_with_200() {
    let ports = FakePorts::default();
    let (status, Json(dto)) = get_my_capabilities::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("stranger"),
    )
    .await
    .unwrap();

    assert_eq!(status, StatusCode::OK);
    assert!(!dto.has_active_credential_role);
    assert!(!dto.has_active_ops_role);
}

/// `wardrobe_supervisor` is part of the season-scoped costume-role superset
/// (#535) but NOT of the credential-role gate (ADR-027: designer + assistant).
/// Reusing the season signal is exactly the approximation #816 removes, so the
/// difference must stay asserted.
#[tokio::test]
async fn wardrobe_supervisor_does_not_grant_the_credential_role() {
    let ports = FakePorts::default();
    seed_role(&ports, "supervisor", Role::WardrobeSupervisor).await;

    let (_status, Json(dto)) = get_my_capabilities::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("supervisor"),
    )
    .await
    .unwrap();

    assert!(
        !dto.has_active_credential_role,
        "the credential gate (ADR-027) excludes wardrobe_supervisor — the \
         season-scoped superset must not leak into the report"
    );
}

#[tokio::test]
async fn active_ops_admin_membership_is_reported() {
    let ports = FakePorts::default();
    seed_role(&ports, "ops", Role::OpsAdmin).await;

    let (_status, Json(dto)) =
        get_my_capabilities::<FakePorts>(State(AppState::new(ports)), CurrentUser::dummy("ops"))
            .await
            .unwrap();

    assert!(dto.has_active_ops_role);
    assert!(!dto.has_active_credential_role);
}

/// The ops arm is read through the POLICY, not the repository: a caller on the
/// deployment's `OPS_ADMIN_SUBS` allowlist holds ops access with no membership
/// row at all (cold start, issue #409). A report that bypassed the policy would
/// answer `false` here while the middleware enforces `true`.
#[tokio::test]
async fn ops_bootstrap_allowlist_is_honoured() {
    let ports = FakePorts::default();
    let state = AppState::with_ai_import(ports, false, 1024 * 1024, vec!["ops-boot".to_string()]);

    let (_status, Json(dto)) =
        get_my_capabilities::<FakePorts>(State(state), CurrentUser::dummy("ops-boot"))
            .await
            .unwrap();

    assert!(
        dto.has_active_ops_role,
        "the report must resolve through the policy, so the bootstrap \
         allowlist counts — otherwise the wire answer contradicts enforcement"
    );
    assert!(!dto.has_active_credential_role);
}

/// A policy implementation whose ops arm is broken but whose credential arm
/// works, to prove the two arms are resolved independently.
struct HalfBrokenPolicy;

#[async_trait::async_trait]
impl AuthorizationPolicy for HalfBrokenPolicy {
    async fn authorize(&self, _ctx: &AuthContext) -> PolicyDecision {
        PolicyDecision::Deny
    }

    async fn authorize_season(&self, _ctx: &SeasonAuthContext) -> PolicyDecision {
        PolicyDecision::Deny
    }

    async fn authorize_credential_role(
        &self,
        _actor: &UserId,
    ) -> Result<PolicyDecision, DomainError> {
        Ok(PolicyDecision::Allow)
    }

    async fn authorize_ops(&self, _actor: &UserId) -> Result<PolicyDecision, DomainError> {
        Err(DomainError::internal("membership table unavailable"))
    }
}

#[tokio::test]
async fn predicate_failure_is_a_server_error_not_a_false_answer() {
    let state = AppState::<FakePorts> {
        authorization_policy: Arc::new(HalfBrokenPolicy),
        ..AppState::new(FakePorts::default())
    };

    let problem = get_my_capabilities::<FakePorts>(State(state), CurrentUser::dummy("anyone"))
        .await
        .unwrap_err()
        .into_problem();

    assert_eq!(
        problem.status, 500,
        "a broken predicate must surface as an error — `false` would read as \
         \"you have no permission\" for a caller whose role is intact"
    );
    // The CODE is the contract the client branches on (ADR-031): assert the
    // registered internal-error entry, so a different 500 problem — or a
    // denial code smuggled in — cannot pass this test.
    assert_eq!(
        problem.code, "http.internal-error",
        "a read-model failure must land on the registered internal-error code"
    );
}
