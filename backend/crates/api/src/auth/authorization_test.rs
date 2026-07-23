// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use std::sync::Arc;

use super::{AuthorizationState, Requirement, authorize_middleware};
use async_trait::async_trait;
use axum::Router;
use axum::body::Body as AxumBody;
use axum::http::{Request, StatusCode};
use axum::middleware::from_fn_with_state;
use axum::routing::post;
use breakdown_core::membership::policy::{AuthContext, AuthorizationPolicy, PolicyDecision};
use breakdown_core::shared::BlockId;
use tower::ServiceExt;

use crate::auth::{AuthState, CurrentUser, auth_middleware};

struct AllowAll;
#[async_trait]
impl AuthorizationPolicy for AllowAll {
    async fn authorize(&self, _ctx: &AuthContext) -> PolicyDecision {
        PolicyDecision::Allow
    }
}

// Single sequential test: env vars are process-global, so mutating
// them from two parallel tests would race. Cover both accessors here.
#[test]
fn authz_env_variants() {
    unsafe {
        std::env::remove_var("OIDC_ISS");
        std::env::remove_var("DEV_AUTH_SUB");
        std::env::remove_var("AUTHZ_ENFORCE");
    }

    // enforce_from_env defaults on; "false"/"0" disable; "true" enables.
    assert!(AuthorizationState::enforce_from_env());
    unsafe {
        std::env::set_var("AUTHZ_ENFORCE", "false");
    }
    assert!(!AuthorizationState::enforce_from_env());
    unsafe {
        std::env::set_var("AUTHZ_ENFORCE", "0");
    }
    assert!(!AuthorizationState::enforce_from_env());
    unsafe {
        std::env::set_var("AUTHZ_ENFORCE", "true");
    }
    assert!(AuthorizationState::enforce_from_env());
    unsafe {
        std::env::remove_var("AUTHZ_ENFORCE");
    }

    // Neither configured -> dev/prod is undecided; builder still returns a
    // usable (dev) state, defaulting enforcement off.
    unsafe {
        std::env::set_var("DEV_AUTH_SUB", "dev-user");
    }
    let st = AuthorizationState::from_env_or_dev(Arc::new(AllowAll));
    assert!(!st.enforce());
    // Dev + AUTHZ_ENFORCE=false must stay off (catches &&/|| flip).
    unsafe {
        std::env::set_var("AUTHZ_ENFORCE", "false");
    }
    let st = AuthorizationState::from_env_or_dev(Arc::new(AllowAll));
    assert!(!st.enforce());
    unsafe {
        std::env::remove_var("AUTHZ_ENFORCE");
    }
    // Dev + AUTHZ_ENFORCE=true -> on.
    unsafe {
        std::env::set_var("AUTHZ_ENFORCE", "true");
    }
    let st = AuthorizationState::from_env_or_dev(Arc::new(AllowAll));
    assert!(st.enforce());
    unsafe {
        std::env::remove_var("AUTHZ_ENFORCE");
        std::env::remove_var("DEV_AUTH_SUB");
    }

    // Production path: default on.
    unsafe {
        std::env::set_var("OIDC_ISS", "https://iss");
        std::env::set_var("OIDC_AUDIENCE", "aud");
        std::env::set_var("OIDC_JWKS_URL", "https://iss/.well-known/jwks");
    }
    let st = AuthorizationState::from_env_or_dev(Arc::new(AllowAll));
    assert!(st.enforce());
    unsafe {
        std::env::remove_var("OIDC_ISS");
        std::env::remove_var("OIDC_AUDIENCE");
        std::env::remove_var("OIDC_JWKS_URL");
    }
}

/// Policy that always panics — used to verify the fail-closed guarantee.
struct PanickingPolicy;
#[async_trait]
impl AuthorizationPolicy for PanickingPolicy {
    async fn authorize(&self, _ctx: &AuthContext) -> PolicyDecision {
        panic!("intentional policy panic");
    }
}

/// All known block-scoped paths (i.e. every route not on the allowlist) MUST
/// resolve to `Requirement::BlockMember` — this is the Deny-by-Default
/// guarantee.
///
/// Keep this list in sync with the route definitions in `handlers/mod.rs`.
#[test]
fn block_scoped_paths_default_to_block_member() {
    let block_scoped: &[&str] = &[
        // Blocks (detail + sub-resources except /members/accept)
        "/blocks/00000000-0000-7000-8000-000000000000",
        "/blocks/00000000-0000-7000-8000-000000000000/audit",
        "/blocks/00000000-0000-7000-8000-000000000000/members",
        "/blocks/00000000-0000-7000-8000-000000000000/members/leave",
        "/blocks/00000000-0000-7000-8000-000000000000/members/some-user-id",
        "/blocks/00000000-0000-7000-8000-000000000000/members/some-user-id/role",
        "/blocks/00000000-0000-7000-8000-000000000000/time-span",
        // Episodes
        "/episodes",
        "/episodes/00000000-0000-7000-8000-000000000000",
        "/episodes/00000000-0000-7000-8000-000000000000/name",
        "/episodes/00000000-0000-7000-8000-000000000000/shooting-days",
        // Scenes
        "/scenes",
        "/scenes/00000000-0000-7000-8000-000000000000",
        "/scenes/00000000-0000-7000-8000-000000000000/details",
        "/scenes/00000000-0000-7000-8000-000000000000/characters",
        "/scenes/00000000-0000-7000-8000-000000000000/characters/00000000-0000-7000-8000-000000000000",
        "/scenes/00000000-0000-7000-8000-000000000000/shooting-days",
        "/scenes/00000000-0000-7000-8000-000000000000/shooting-days/00000000-0000-7000-8000-000000000000",
        // Shooting days
        "/shooting-days/00000000-0000-7000-8000-000000000000",
        "/shooting-days/00000000-0000-7000-8000-000000000000/archive",
        // Characters
        "/characters",
        "/characters/00000000-0000-7000-8000-000000000000",
        "/characters/00000000-0000-7000-8000-000000000000/measurements",
        "/characters/00000000-0000-7000-8000-000000000000/contact",
        // Costumes (non-photo)
        "/costumes",
        "/costumes/00000000-0000-7000-8000-000000000000",
        "/costumes/00000000-0000-7000-8000-000000000000/notes",
        "/costumes/00000000-0000-7000-8000-000000000000/assign",
        "/costumes/00000000-0000-7000-8000-000000000000/details",
        "/costumes/00000000-0000-7000-8000-000000000000/unassign",
        // Costume categories (non-season-scoped)
        "/costume-categories/00000000-0000-7000-8000-000000000000",
        "/costume-categories/00000000-0000-7000-8000-000000000000/archive",
    ];

    for path in block_scoped {
        assert!(
            matches!(super::requirement_for(path), Requirement::BlockMember),
            "expected BlockMember for block-scoped path: {path}"
        );
    }
}

/// All known allowlist paths MUST resolve to `Requirement::Authenticated`.
///
/// Keep this list in sync with the arms in `requirement_for()`.
#[test]
fn allowlist_paths_map_to_authenticated_only() {
    let allowlist: &[&str] = &[
        // Seasons (everything under /seasons)
        "/seasons",
        "/seasons/00000000-0000-7000-8000-000000000000",
        "/seasons/00000000-0000-7000-8000-000000000000/costume-categories",
        "/seasons/00000000-0000-7000-8000-000000000000/name",
        // Block listing/creation (exact /blocks only)
        "/blocks",
        // Photo paths (contain "/photos")
        "/costumes/00000000-0000-7000-8000-000000000000/photos",
        "/costumes/00000000-0000-7000-8000-000000000000/photos/00000000-0000-7000-8000-000000000000/bytes",
        "/costumes/00000000-0000-7000-8000-000000000000/photos/00000000-0000-7000-8000-000000000000",
        // Accept invitation
        "/blocks/00000000-0000-7000-8000-000000000000/members/accept",
    ];

    for path in allowlist {
        assert!(
            matches!(super::requirement_for(path), Requirement::Authenticated),
            "expected Authenticated for allowlist path: {path}"
        );
    }
}

#[tokio::test]
async fn panicking_policy_yields_403_never_500() {
    // Build a router with dev auth (injects dummy CurrentUser) and the
    // authorize_middleware backed by a panicking policy with enforcement on.
    let auth = Arc::new(AuthState::dev(CurrentUser::dummy("panic-test")));
    let policy = Arc::new(PanickingPolicy);
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));

    let app = Router::new()
        .route("/scenes", post(|| async { StatusCode::OK }))
        .layer(from_fn_with_state(authz, authorize_middleware))
        .layer(from_fn_with_state(auth, auth_middleware))
        .with_state(());

    let block_id = BlockId::new();
    let req = Request::builder()
        .method("POST")
        .uri("/scenes")
        .header("X-Active-Block", block_id.0.to_string())
        .body(AxumBody::empty())
        .unwrap();

    let resp = app.clone().oneshot(req).await.unwrap();
    assert_eq!(
        resp.status(),
        StatusCode::FORBIDDEN,
        "panicking policy must yield 403 (fail-closed), never 500"
    );
}
