// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use std::sync::Arc;

use super::{AuthorizationState, authorize_middleware};
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
