// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

//! HTTP-layer tests for the RFC 9457 problem-detail error surface (ADR-031).
//!
//! One test per error source from the http-error-surface spec, asserting the
//! full wire contract through the real middleware stack: envelope members,
//! `Content-Type: application/problem+json`, the stable `code`, and a
//! non-empty hex `trace_id`. The router reuses the production composition
//! builder (`apply_api_middleware`) plus the panic catch-all and the
//! unknown-route fallback, exactly as `app_router` does.

// Test code: workspace denies `clippy::expect_used`/`unwrap_used`; assertions
// on handler `Result` returns use `.expect()`/`.expect_err()` with explicit
// messages (same pattern as the other api test files).
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod common;

use std::collections::HashMap;
use std::sync::Arc;

use axum::Router;
use axum::body::Body as AxumBody;
use axum::extract::DefaultBodyLimit;
use axum::http::{Request, StatusCode, header};
use axum::response::IntoResponse as _;
use axum::routing;
use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header as JwtHeader, encode};
use rsa::pkcs1::{EncodeRsaPrivateKey, EncodeRsaPublicKey};
use rsa::{RsaPrivateKey, rand_core::OsRng};
use tower::ServiceExt;
use tower_http::catch_panic::CatchPanicLayer;

use api::auth::authorization::{AuthorizationState, MembershipAuthorizationPolicy};
use api::auth::jwks::StaticJwksProvider;
use api::auth::{AuthState, OidcConfig};
use api::handlers::{create_season, get_character, list_characters, upload_ai_script};
use api::problems::{self, PROBLEM_CONTENT_TYPE, route_not_found};
use api::routes::apply_api_middleware;
use api::state::AppState;
use api::versioning::DeprecationRegistry;
use breakdown_core::shared::{BlockId, UserId};
use common::{FakeMembershipRepo, FakePorts};

const DEV_SUB: &str = "dev-user";
const ISSUER: &str = "https://iss.example";
const AUDIENCE: &str = "audience";
const KID: &str = "signing";

/// A signed RS256 token for `DEV_SUB` matching the `OidcConfig` used by the
/// test router (the same `iss`/`aud` the production middleware validates).
fn signed_token(private_key: &RsaPrivateKey) -> String {
    let der = private_key.to_pkcs1_der().expect("rsa private der");
    encode(
        &JwtHeader {
            alg: Algorithm::RS256,
            kid: Some(KID.to_string()),
            ..JwtHeader::default()
        },
        &serde_json::json!({
            "sub": DEV_SUB,
            "iss": ISSUER,
            "aud": AUDIENCE,
            "exp": 4_000_000_000_u64,
        }),
        &EncodingKey::from_rsa_der(der.as_bytes()),
    )
    .expect("token signing must succeed")
}

/// Production-mode auth state: real OIDC config + a static JWKS with one RSA
/// key, so requests can be authenticated with signed tokens. No token (or a
/// garbage token) must be rejected with `401`.
fn prod_auth(private_key: &RsaPrivateKey) -> Arc<AuthState> {
    let mut keys = HashMap::new();
    let der = private_key
        .to_public_key()
        .to_pkcs1_der()
        .expect("rsa public der");
    keys.insert(KID.to_string(), DecodingKey::from_rsa_der(der.as_bytes()));
    Arc::new(AuthState::new(
        OidcConfig {
            iss: ISSUER.into(),
            audience: AUDIENCE.into(),
            jwks_url: format!("{ISSUER}/.well-known/jwks"),
            algorithm: Algorithm::RS256,
        },
        Arc::new(StaticJwksProvider::new(keys)),
    ))
}

/// Authz state enforcing active-block membership (empty repo by default;
/// tests seed it to grant the dev user).
fn prod_authz() -> Arc<AuthorizationState> {
    let policy = Arc::new(MembershipAuthorizationPolicy::new(Arc::new(
        FakeMembershipRepo::default(),
    )));
    Arc::new(AuthorizationState::new(policy, /*enforce=*/ true))
}

/// Handler that always panics — exercises the panic catch-all.
async fn panic_handler() -> StatusCode {
    panic!("boom")
}

/// Build the test router through the *same* composition builder the
/// production router uses (auth → authorize → deprecation), with the panic
/// catch-all and unknown-route fallback — mirroring `app_router`.
fn test_router(auth: Arc<AuthState>, authz: Arc<AuthorizationState>) -> Router<()> {
    apply_api_middleware(
        Router::new()
            .route(
                "/v1/characters/{id}",
                routing::get(get_character::<FakePorts>),
            )
            .route("/v1/characters", routing::get(list_characters::<FakePorts>))
            .route("/v1/seasons", routing::post(create_season::<FakePorts>))
            .route(
                "/v1/ai-import/scripts",
                routing::post(upload_ai_script::<FakePorts>).route_layer(DefaultBodyLimit::max(64)),
            )
            .route("/v1/panic", routing::get(panic_handler))
            .fallback(route_not_found),
        auth,
        authz,
        DeprecationRegistry::new(),
    )
    .layer(CatchPanicLayer::custom(problems::panic_response))
    .with_state(AppState::new(FakePorts::default()))
}

/// Router whose authz policy grants the dev user membership in `block`.
async fn router_with_membership(key: &RsaPrivateKey, block: BlockId) -> Router<()> {
    let repo = Arc::new(FakeMembershipRepo::default());
    repo.members
        .lock()
        .await
        .insert((block, UserId::from_sub(DEV_SUB)));
    let policy = Arc::new(MembershipAuthorizationPolicy::new(repo));
    let authz = Arc::new(AuthorizationState::new(policy, /*enforce=*/ true));
    test_router(prod_auth(key), authz)
}

async fn send(
    router: &Router<()>,
    request: Request<AxumBody>,
) -> (StatusCode, axum::http::HeaderMap, serde_json::Value) {
    let response = router
        .clone()
        .oneshot(request)
        .await
        .expect("dispatch through router");
    let status = response.status();
    let headers = response.headers().clone();
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("read body");
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap_or(serde_json::Value::Null);
    (status, headers, json)
}

/// Assert the full RFC 9457 wire contract for one error source.
fn assert_problem(
    status: StatusCode,
    headers: &axum::http::HeaderMap,
    json: &serde_json::Value,
    expected_code: &str,
) {
    assert_eq!(
        headers
            .get(header::CONTENT_TYPE)
            .map(|v| v.to_str().unwrap_or("")),
        Some(PROBLEM_CONTENT_TYPE),
        "content-type must be application/problem+json"
    );
    assert_eq!(json["code"], expected_code, "code mismatch");
    assert_eq!(json["status"], status.as_u16(), "status mismatch");
    assert!(
        json["type"].as_str().is_some_and(|t| !t.is_empty()),
        "type URI must be present"
    );
    assert!(
        json["title"].as_str().is_some_and(|t| !t.is_empty()),
        "title must be present"
    );
    assert!(
        json["detail"].as_str().is_some_and(|t| !t.is_empty()),
        "detail must be present"
    );
    let trace_id = json["trace_id"].as_str().expect("trace_id must be present");
    assert_eq!(trace_id.len(), 32, "trace_id must be 32 hex chars");
    assert!(
        trace_id.chars().all(|c| c.is_ascii_hexdigit()),
        "trace_id must be hex"
    );
}

fn authed_request(
    token: &str,
    block: Option<BlockId>,
    method: &str,
    path: &str,
    body: Option<Vec<u8>>,
    content_type: Option<&str>,
) -> Request<AxumBody> {
    let mut builder = Request::builder()
        .method(method)
        .uri(path)
        .header("Authorization", format!("Bearer {token}"));
    if let Some(block) = block {
        builder = builder.header("X-Active-Block", block.0.to_string());
    }
    if let Some(content_type) = content_type {
        builder = builder.header(header::CONTENT_TYPE, content_type);
    }
    builder
        .body(body.map(AxumBody::from).unwrap_or_else(AxumBody::empty))
        .expect("request build")
}

/// A fresh RSA keypair (RS256) for the auth middleware tests.
fn test_key() -> RsaPrivateKey {
    RsaPrivateKey::new(&mut OsRng, 2048).expect("rsa keygen")
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn missing_bearer_token_is_401_auth_unauthenticated() {
    let key = test_key();
    let app = test_router(prod_auth(&key), prod_authz());

    let request = Request::builder()
        .method("GET")
        .uri("/v1/characters/00000000-0000-0000-0000-000000000001")
        .body(AxumBody::empty())
        .expect("request");
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "auth.unauthenticated");
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn invalid_bearer_token_is_401_auth_unauthenticated() {
    let key = test_key();
    let app = test_router(prod_auth(&key), prod_authz());

    let request = Request::builder()
        .method("GET")
        .uri("/v1/characters/00000000-0000-0000-0000-000000000001")
        .header("Authorization", "Bearer not.a.jwt")
        .body(AxumBody::empty())
        .expect("request");
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "auth.unauthenticated");
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn missing_active_block_is_400_auth_missing_active_block() {
    let key = test_key();
    let token = signed_token(&key);
    let app = test_router(prod_auth(&key), prod_authz());

    // Block-scoped route without the X-Active-Block header.
    let request = authed_request(
        &token,
        None,
        "GET",
        "/v1/characters/00000000-0000-0000-0000-000000000001",
        None,
        None,
    );
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "auth.missing-active-block");
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn invalid_active_block_is_400_auth_invalid_active_block() {
    let key = test_key();
    let token = signed_token(&key);
    let app = test_router(prod_auth(&key), prod_authz());

    let request = Request::builder()
        .method("GET")
        .uri("/v1/characters/00000000-0000-0000-0000-000000000001")
        .header("Authorization", format!("Bearer {token}"))
        .header("X-Active-Block", "not-a-uuid")
        .body(AxumBody::empty())
        .expect("request");
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "auth.invalid-active-block");
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn idp_unavailable_is_503_auth_idp_unavailable() {
    // A CachingJwksProvider pointed at a dead port fails closed to 503.
    let provider = Arc::new(api::auth::jwks::CachingJwksProvider::new(
        "http://127.0.0.1:1/.well-known/jwks",
        reqwest::Client::new(),
        std::time::Duration::from_secs(3600),
    ));
    let auth = Arc::new(AuthState::new(
        OidcConfig {
            iss: ISSUER.into(),
            audience: AUDIENCE.into(),
            jwks_url: format!("{ISSUER}/.well-known/jwks"),
            algorithm: Algorithm::RS256,
        },
        provider,
    ));
    let app = test_router(auth, prod_authz());

    // The token's header must decode (kid present) so the middleware reaches
    // the JWKS fetch; the fetch itself fails against the dead port → 503.
    let key = test_key();
    let token = signed_token(&key);
    let request = Request::builder()
        .method("GET")
        .uri("/v1/characters/00000000-0000-0000-0000-000000000001")
        .header("Authorization", format!("Bearer {token}"))
        .body(AxumBody::empty())
        .expect("request");
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "auth.idp-unavailable");
    assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
}

#[tokio::test]
async fn domain_not_found_is_404_domain_not_found() {
    let key = test_key();
    let token = signed_token(&key);
    let block = BlockId::new();
    let app = router_with_membership(&key, block).await;

    let request = authed_request(
        &token,
        Some(block),
        "GET",
        "/v1/characters/00000000-0000-0000-0000-000000000001",
        None,
        None,
    );
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "domain.not-found");
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn missing_query_param_is_400_http_bad_query_param() {
    let key = test_key();
    let token = signed_token(&key);
    let block = BlockId::new();
    let app = router_with_membership(&key, block).await;

    // `list_characters` requires `season_id`; missing → http.bad-query-param.
    let request = authed_request(&token, Some(block), "GET", "/v1/characters", None, None);
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "http.bad-query-param");
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn domain_validation_is_422_domain_validation() {
    // Domain validation (well-formed document violating a domain rule) is
    // mapped by the registry to 422 (ADR-031 D6). The `IntoResponse` path is
    // identical to the one the HTTP layer uses for handler errors.
    let problem = problems::ApiError::from(breakdown_core::error::DomainError::ValidationError(
        "empty name".into(),
    ))
    .into_problem();
    assert_eq!(problem.status, 422);
    assert_eq!(problem.code, "domain.validation");

    let response = problems::ApiError::from(breakdown_core::error::DomainError::ValidationError(
        "empty name".into(),
    ))
    .into_response();
    assert_eq!(
        response.headers().get(header::CONTENT_TYPE).unwrap(),
        PROBLEM_CONTENT_TYPE
    );
}

#[tokio::test]
async fn version_conflict_is_409_with_typed_extensions() {
    // Optimistic-concurrency failure rendered through the same builder the
    // HTTP layer uses; the extensions carry the S0 versions.
    let document = problems::ApiError::from(breakdown_core::error::DomainError::VersionConflict {
        entity: "Season".into(),
        expected: breakdown_core::shared::AggregateVersion(2),
        current: breakdown_core::shared::AggregateVersion(3),
    })
    .into_problem();
    assert_eq!(document.status, 409);
    assert_eq!(document.code, "concurrency.version-mismatch");
    let extensions = document.extensions.expect("extensions present");
    assert_eq!(extensions["expected_version"], 2);
    assert_eq!(extensions["current_version"], 3);
}

#[tokio::test]
async fn bad_json_body_is_400_http_bad_json_body() {
    let key = test_key();
    let token = signed_token(&key);
    let app = test_router(prod_auth(&key), prod_authz());

    // `/v1/seasons` is Authenticated-only (no active block needed). Send a
    // syntactically invalid JSON body.
    let request = authed_request(
        &token,
        None,
        "POST",
        "/v1/seasons",
        Some(b"{ not json".to_vec()),
        Some("application/json"),
    );
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "http.bad-json-body");
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn bad_path_param_is_400_http_bad_path_param() {
    let key = test_key();
    let token = signed_token(&key);
    let block = BlockId::new();
    let app = router_with_membership(&key, block).await;

    let request = authed_request(
        &token,
        Some(block),
        "GET",
        "/v1/characters/not-a-uuid",
        None,
        None,
    );
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "http.bad-path-param");
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn payload_too_large_is_413_http_payload_too_large() {
    let key = test_key();
    let token = signed_token(&key);
    let app = test_router(prod_auth(&key), prod_authz());

    // The ai-import scripts route is limited to 64 bytes; a larger body is
    // rejected by the Bytes wrapper with http.payload-too-large (413).
    let request = authed_request(
        &token,
        None,
        "POST",
        "/v1/ai-import/scripts",
        Some(vec![b'x'; 4096]),
        Some("application/pdf"),
    );
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "http.payload-too-large");
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
}

#[tokio::test]
async fn unknown_route_is_404_http_route_not_found() {
    let key = test_key();
    let token = signed_token(&key);
    let block = BlockId::new();
    let app = router_with_membership(&key, block).await;

    let request = authed_request(&token, Some(block), "GET", "/v1/does-not-exist", None, None);
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "http.route-not-found");
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn unhandled_panic_is_500_http_internal_error() {
    let key = test_key();
    let token = signed_token(&key);
    let block = BlockId::new();
    let app = router_with_membership(&key, block).await;

    let request = authed_request(&token, Some(block), "GET", "/v1/panic", None, None);
    let (status, headers, json) = send(&app, request).await;
    assert_problem(status, &headers, &json, "http.internal-error");
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    // Internal error text must never reach the client (static detail only).
    let detail = json["detail"].as_str().unwrap_or("");
    assert!(!detail.contains("boom"));
}

#[test]
fn openapi_documents_problem_details_with_problem_json_media_type() {
    let doc = api::api_doc();
    let json = serde_json::to_value(&doc).expect("ApiDoc must serialize");

    // Every error response carrying the ProblemDetails schema must be
    // documented with the RFC 9457 media type (api_doc() rewrites it).
    let mut problem_media_count = 0;
    let mut problem_schema_count = 0;
    for item in json["paths"].as_object().expect("paths").values() {
        for operation in item.as_object().expect("path item").values() {
            if !operation.is_object() || operation.get("responses").is_none() {
                continue;
            }
            for response in operation["responses"]
                .as_object()
                .expect("responses")
                .values()
            {
                let Some(content) = response["content"].as_object() else {
                    continue;
                };
                if content
                    .get("application/problem+json")
                    .and_then(|c| c.get("schema"))
                    .is_some()
                {
                    problem_media_count += 1;
                }
                for media in content.values() {
                    if media["schema"]["$ref"]
                        .as_str()
                        .is_some_and(|r| r.ends_with("/ProblemDetails"))
                    {
                        problem_schema_count += 1;
                    }
                }
            }
        }
    }
    assert!(
        problem_media_count > 0,
        "no response documents application/problem+json"
    );
    assert_eq!(
        problem_media_count, problem_schema_count,
        "every ProblemDetails response must use application/problem+json \
         (no application/json leaks for the error schema)"
    );

    // The code registry is published as a machine-readable extension.
    let registry = json["x-code-registry"].as_array().expect("x-code-registry");
    assert!(
        registry.len() >= 19,
        "registry must contain the framework codes"
    );
    assert!(
        registry
            .iter()
            .any(|entry| entry["code"] == "concurrency.version-mismatch"),
        "registry must list concurrency.version-mismatch"
    );
    assert!(
        registry
            .iter()
            .any(|entry| entry["code"] == "http.route-not-found"),
        "registry must list http.route-not-found"
    );
}
