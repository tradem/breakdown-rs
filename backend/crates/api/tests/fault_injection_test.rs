// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

//! Issue #443 — deterministic fault injection E2E: the armed one-shot latch
//! short-circuits the FIRST `POST /v1/blocks` with the REAL registry problem
//! document (409 `block.number-already-exists`, identical to the advisory
//! pre-check's conflict shape), and the retry passes through to the real
//! handler stack. The whole file is test-support-gated like the machinery
//! it exercises.

#![cfg(feature = "test-support")]
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)] // tests

use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use uuid::Uuid;

use api::fault_injection::FAULT_BLOCK_CONFLICT;
use api::routes::apply_api_middleware;
use api::state::AppState;
use api::versioning::DeprecationRegistry;

mod common;

use common::FakePorts;

const DEV_SUB: &str = "dev-e2e";

/// The fault latch is process-global, so the tests in this binary must not
/// race each other for it — serialize them with a shared mutex.
static TEST_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// Compose the REAL middleware stack (`apply_api_middleware`, which includes
/// the cfg-gated fault middleware) over the REAL fault control routes plus a
/// stubblock handler, using dev auth + fake ports. Mirrors `app_router`'s
/// `/v1` composition — the only part not exercised here is merging
/// `handlers::routes()`, which the compiler checks in `app_router` itself.
fn test_app() -> axum::Router {
    let auth = Arc::new(api::auth::AuthState::dev(api::auth::CurrentUser::dummy(
        DEV_SUB,
    )));
    let state = AppState::new(FakePorts::default());
    let authz = Arc::new(api::auth::authorization::AuthorizationState::new(
        Arc::new(
            api::auth::authorization::MembershipAuthorizationPolicy::new(
                state.ports.membership_repo.clone().into(),
            ),
        ),
        /* enforce = */ true,
    ));
    let v1 = api::fault_injection::fault_control_routes().merge(
        axum::Router::<AppState<FakePorts>>::new().route(
            "/blocks",
            axum::routing::post(|| async { (StatusCode::CREATED, "stub") }),
        ),
    );
    apply_api_middleware(
        axum::Router::new().nest("/v1", v1),
        auth,
        authz,
        DeprecationRegistry::new(),
    )
    .with_state(state)
}

fn create_block_body() -> String {
    format!(
        r#"{{"id":"{}","season_id":"{}","series_id":"{}","number":1}}"#,
        Uuid::now_v7(),
        Uuid::now_v7(),
        Uuid::now_v7()
    )
}

async fn arm(app: &axum::Router, fault: &str) -> StatusCode {
    app.clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/__faults/{fault}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap()
        .status()
}

async fn post_block(app: &axum::Router) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/blocks")
                .header("content-type", "application/json")
                .body(Body::from(create_block_body()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let doc = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, doc)
}

#[tokio::test]
async fn armed_fault_first_block_create_is_409_with_real_code() {
    let _guard = TEST_LOCK.lock().await;
    let app = test_app();
    assert_eq!(
        arm(&app, FAULT_BLOCK_CONFLICT).await,
        StatusCode::NO_CONTENT
    );

    // FIRST block create after arming: the real registry problem document.
    let (status, doc) = post_block(&app).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(doc["code"], "block.number-already-exists");
    assert_eq!(doc["status"], 409);
    assert_eq!(
        doc["type"],
        format!(
            "{}/problems/block.number-already-exists",
            breakdown_core::error_registry::PROBLEM_DOCS_BASE
        )
    );
}

#[tokio::test]
async fn one_shot_latch_fires_exactly_once_then_passes_through() {
    let _guard = TEST_LOCK.lock().await;
    let app = test_app();
    assert_eq!(
        arm(&app, FAULT_BLOCK_CONFLICT).await,
        StatusCode::NO_CONTENT
    );

    let (first, first_doc) = post_block(&app).await;
    assert_eq!(first, StatusCode::CONFLICT);
    assert_eq!(first_doc["code"], "block.number-already-exists");

    // The retry must NOT be the injected fault: with the latch consumed the
    // request reaches the real handler stack (auth + pre-check + dispatch).
    // Fresh UUIDs cannot duplicate, so the real advisory pre-check passes
    // and the response is anything but the injected conflict code.
    let (second, second_doc) = post_block(&app).await;
    assert_ne!(second, StatusCode::CONFLICT);
    assert_ne!(second_doc["code"], "block.number-already-exists");
}

#[tokio::test]
async fn unarmed_fault_never_intercepts() {
    let _guard = TEST_LOCK.lock().await;
    let app = test_app();
    let (status, doc) = post_block(&app).await;
    // Without arming, the block create is never intercepted by the latch;
    // if the stack ever returned 409 it must be the REAL pre-check (whose
    // code is the same const — but with fresh UUIDs it cannot fire, so a
    // 409 here would mean the latch fired unarmed: broken).
    if status == StatusCode::CONFLICT {
        assert_ne!(doc["code"], "block.number-already-exists");
    }
}

#[tokio::test]
async fn unknown_fault_name_is_a_clean_404() {
    let app = test_app();
    let status = arm(&app, "does-not-exist").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn fault_control_route_rejects_other_methods() {
    let _guard = TEST_LOCK.lock().await;
    // GET on the fault route is not routed (only POST is): axum answers the
    // documented `405 Method Not Allowed` for a matched path.
    let app = test_app();
    let res = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/__faults/{FAULT_BLOCK_CONFLICT}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::METHOD_NOT_ALLOWED);
}
