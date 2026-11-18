// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

// Section 6.4: API-layer test asserting authorized / non-authorized
// dispatch through the real auth + authorization middleware stack.
use std::collections::HashMap;
use std::sync::Arc;

use axum::Router;
use axum::body::Body as AxumBody;
use axum::http::{Request, StatusCode};
use axum::middleware::from_fn_with_state;
use axum::routing::{get, post};
use jsonwebtoken::Algorithm;
use tower::ServiceExt;

use super::test_helpers::FakeMembershipRepo;
use breakdown_core::shared::{BlockId, UserId};

use crate::auth::AuthState;
use crate::auth::authorization::{AuthorizationState, MembershipAuthorizationPolicy};
use crate::auth::jwks::StaticJwksProvider;
use crate::auth::{CurrentUser, OidcConfig, auth_middleware, authorize_middleware};

const DEV_SUB: &str = "dev-user";

/// Tiny `Router<()>` that applies the real `auth_middleware` (outer) and
/// `authorize_middleware` (inner) around no-op handlers, so requests are
/// dispatched through the exact production gating path.
fn auth_router(auth: Arc<AuthState>, authz: Arc<AuthorizationState>) -> Router<()> {
    Router::new()
        .route("/seasons", post(|| async { StatusCode::OK }))
        .route("/blocks/{id}", get(|| async { StatusCode::OK }))
        .route("/blocks/{id}/members", get(|| async { StatusCode::OK }))
        .route(
            "/blocks/{id}/members/accept",
            post(|| async { StatusCode::OK }),
        )
        .route("/scenes", post(|| async { StatusCode::OK }))
        .route("/swagger-ui", get(|| async { StatusCode::OK }))
        .route("/api-docs", get(|| async { StatusCode::OK }))
        .layer(from_fn_with_state(authz, authorize_middleware))
        .layer(from_fn_with_state(auth, auth_middleware))
        .with_state(())
}

async fn status_of(router: &Router<()>, req: Request<AxumBody>) -> StatusCode {
    router.clone().oneshot(req).await.unwrap().status()
}

#[tokio::test]
async fn dev_mode_authenticated_write_is_allowed() {
    // POST /seasons needs only authentication -> dev dummy user passes.
    let auth = Arc::new(AuthState::dev(CurrentUser::dummy(DEV_SUB)));
    let repo = Arc::new(FakeMembershipRepo::default());
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));

    let app = auth_router(auth, authz);
    let req = Request::builder()
        .method("POST")
        .uri("/seasons")
        .body(AxumBody::empty())
        .unwrap();

    assert_eq!(status_of(&app, req).await, StatusCode::OK);
}

#[tokio::test]
async fn dev_mode_block_member_read_is_allowed() {
    // GET /blocks/{id} needs active membership; dev-user IS a member here.
    let auth = Arc::new(AuthState::dev(CurrentUser::dummy(DEV_SUB)));
    let block = BlockId::new();
    let repo = Arc::new(FakeMembershipRepo::default());
    repo.members
        .lock()
        .await
        .insert((block, UserId::from_sub(DEV_SUB)));
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));

    let app = auth_router(auth, authz);
    let req = Request::builder()
        .method("GET")
        .uri(format!("/blocks/{}", block.0))
        .header("X-Active-Block", block.0.to_string())
        .body(AxumBody::empty())
        .unwrap();

    assert_eq!(status_of(&app, req).await, StatusCode::OK);
}

#[tokio::test]
async fn dev_mode_non_member_block_read_is_forbidden() {
    // GET /blocks/{id} needs active membership; dev-user is NOT a member.
    let auth = Arc::new(AuthState::dev(CurrentUser::dummy(DEV_SUB)));
    let block = BlockId::new();
    let repo = Arc::new(FakeMembershipRepo::default());
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));

    let app = auth_router(auth, authz);
    let req = Request::builder()
        .method("GET")
        .uri(format!("/blocks/{}", block.0))
        .header("X-Active-Block", block.0.to_string())
        .body(AxumBody::empty())
        .unwrap();

    assert_eq!(status_of(&app, req).await, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn missing_token_in_prod_mode_is_unauthorized() {
    // Production (non-dev) auth state with an empty JWKS: a request without a
    // valid bearer token must be rejected with 401 before authorization.
    let auth = Arc::new(AuthState::new(
        OidcConfig {
            iss: "https://issuer.example".into(),
            audience: "https://api.example".into(),
            jwks_url: "https://issuer.example/.well-known/jwks".into(),
            algorithm: Algorithm::RS256,
        },
        Arc::new(StaticJwksProvider::new(HashMap::new())),
    ));
    let repo = Arc::new(FakeMembershipRepo::default());
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));

    let app = auth_router(auth, authz);
    let req = Request::builder()
        .method("POST")
        .uri("/seasons")
        .body(AxumBody::empty())
        .unwrap();

    assert_eq!(status_of(&app, req).await, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn doc_endpoints_skip_authorization() {
    // `/swagger-ui` and `/api-docs` are public: the authz middleware
    // must short-circuit (skip gating) for them.
    let auth = Arc::new(AuthState::dev(CurrentUser::dummy(DEV_SUB)));
    let repo = Arc::new(FakeMembershipRepo::default());
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));
    let app = auth_router(auth, authz);
    for path in ["/swagger-ui", "/api-docs"] {
        let req = Request::builder()
            .uri(path)
            .body(AxumBody::empty())
            .unwrap();
        assert_eq!(
            status_of(&app, req).await,
            StatusCode::OK,
            "doc path {path} must be public"
        );
    }
}

#[tokio::test]
async fn doc_endpoints_public_in_prod_mode() {
    // In production (non-dev) auth, doc paths are still public:
    // `auth_middleware` short-circuits them before token validation.
    let auth = Arc::new(AuthState::new(
        OidcConfig {
            iss: "https://issuer.example".into(),
            audience: "https://api.example".into(),
            jwks_url: "https://issuer.example/.well-known/jwks".into(),
            algorithm: Algorithm::RS256,
        },
        Arc::new(StaticJwksProvider::new(HashMap::new())),
    ));
    let repo = Arc::new(FakeMembershipRepo::default());
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));
    let app = auth_router(auth, authz);
    for path in ["/swagger-ui", "/api-docs"] {
        let req = Request::builder()
            .uri(path)
            .body(AxumBody::empty())
            .unwrap();
        assert_eq!(
            status_of(&app, req).await,
            StatusCode::OK,
            "doc path {path} must be public even in prod mode"
        );
    }
}

#[tokio::test]
async fn block_member_can_list_members() {
    let auth = Arc::new(AuthState::dev(CurrentUser::dummy(DEV_SUB)));
    let block = BlockId::new();
    let repo = Arc::new(FakeMembershipRepo::default());
    repo.members
        .lock()
        .await
        .insert((block, UserId::from_sub(DEV_SUB)));
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));

    let app = auth_router(auth, authz);
    let req = Request::builder()
        .method("GET")
        .uri(format!("/blocks/{}/members", block.0))
        .header("X-Active-Block", block.0.to_string())
        .body(AxumBody::empty())
        .unwrap();

    assert_eq!(status_of(&app, req).await, StatusCode::OK);
}

#[tokio::test]
async fn non_member_cannot_list_members() {
    let auth = Arc::new(AuthState::dev(CurrentUser::dummy(DEV_SUB)));
    let block = BlockId::new();
    let repo = Arc::new(FakeMembershipRepo::default());
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));

    let app = auth_router(auth, authz);
    let req = Request::builder()
        .method("GET")
        .uri(format!("/blocks/{}/members", block.0))
        .header("X-Active-Block", block.0.to_string())
        .body(AxumBody::empty())
        .unwrap();

    assert_eq!(status_of(&app, req).await, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn pending_invitee_can_accept_invitation() {
    // The invitee is not yet an active member; the accept endpoint must be
    // reachable (gated `Authenticated`, not `BlockMember`).
    let auth = Arc::new(AuthState::dev(CurrentUser::dummy(DEV_SUB)));
    let block = BlockId::new();
    let repo = Arc::new(FakeMembershipRepo::default());
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));

    let app = auth_router(auth, authz);
    let req = Request::builder()
        .method("POST")
        .uri(format!("/blocks/{}/members/accept", block.0))
        .body(AxumBody::empty())
        .unwrap();

    assert_eq!(status_of(&app, req).await, StatusCode::OK);
}
