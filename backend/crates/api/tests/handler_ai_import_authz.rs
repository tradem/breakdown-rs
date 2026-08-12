// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Handler-level authorization tests for the AI import gates (issue #175).
//!
//! The AI import handlers on `Authenticated`-only routes must authorize
//! handler-internally via the `AuthorizationPolicy` held in `AppState`:
//! granted callers pass (200), denied callers get `403`, and *read-model
//! failures must stay visible as mapped server errors* (503), never silently
//! converted into a denial.

// Test code: the workspace denies `clippy::expect_used`; assertions on
// handler `Result` returns use `.expect()`/`.expect_err()` with explicit
// messages. No other lints are suppressed — the allow list is kept minimal.
#![allow(clippy::expect_used)]
mod common;

use api::problems::Json; // test-only alias for the wrapper extractor (ADR-031)
use axum::extract::State;
use axum::http::StatusCode;

use api::auth::CurrentUser;
use api::handlers::{list_ai_models, list_ai_providers};
use api::state::AppState;
use breakdown_core::error::DomainError;
use common::FakePorts;

/// Build a handler state with AI import enabled and a membership repo whose
/// credential-role gate is controlled by `credential_role_override`.
async fn ai_import_state(ports: FakePorts) -> AppState<FakePorts> {
    AppState::with_ai_import(
        ports, /*ai_import_enabled=*/ true, /*max_document_bytes=*/ 1024,
    )
}

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy("ai-import-test-user")
}

#[tokio::test]
async fn list_ai_providers_allows_credential_role_member() {
    let ports = FakePorts::default();
    // Default fake grants the credential role.
    let state = ai_import_state(ports).await;

    let result = list_ai_providers::<FakePorts>(State(state), dummy_user()).await;
    let (status, Json(_)) = result.expect("granted caller should succeed");
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn list_ai_providers_denies_non_credential_role_member() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));
    let state = ai_import_state(ports).await;

    let result = list_ai_providers::<FakePorts>(State(state), dummy_user()).await;
    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(problem.detail.contains("not authorized"));
}

#[tokio::test]
async fn list_ai_providers_propagates_repo_failure_as_server_error() {
    let ports = FakePorts::default();
    // A read-model failure must remain a mapped server error (503), NOT be
    // conflated with an authorization denial (403) — issue #175 requirement.
    *ports.membership_repo.credential_role_override.lock().await = Some(Err(
        DomainError::service_unavailable("membership repo down"),
    ));
    let state = ai_import_state(ports).await;

    let result = list_ai_providers::<FakePorts>(State(state), dummy_user()).await;
    let problem = result
        .expect_err("repo failure must surface as an error")
        .into_problem();
    assert_eq!(problem.status, 503);
    // Tranche 1: internal error text never leaves the server; the code is the
    // contract (ADR-031 decision 6).
    assert_eq!(problem.code, "domain.service-unavailable");
    assert!(!problem.detail.contains("membership repo down"));
}

#[tokio::test]
async fn list_ai_models_allows_credential_role_member() {
    let ports = FakePorts::default();
    // Default fake grants the credential role.
    let state = ai_import_state(ports).await;

    let result = list_ai_models::<FakePorts>(
        State(state),
        dummy_user(),
        api::problems::Path("neuralwatt".to_owned()),
    )
    .await;
    let (status, Json(_)) = result.expect("granted caller should succeed");
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn list_ai_models_denies_non_credential_role_member() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));
    let state = ai_import_state(ports).await;

    let result = list_ai_models::<FakePorts>(
        State(state),
        dummy_user(),
        api::problems::Path("neuralwatt".to_owned()),
    )
    .await;
    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(problem.detail.contains("not authorized"));
}

#[tokio::test]
async fn list_ai_models_propagates_repo_failure_as_server_error() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Err(
        DomainError::service_unavailable("membership repo down"),
    ));
    let state = ai_import_state(ports).await;

    let result = list_ai_models::<FakePorts>(
        State(state),
        dummy_user(),
        api::problems::Path("neuralwatt".to_owned()),
    )
    .await;
    let problem = result
        .expect_err("repo failure must surface as an error")
        .into_problem();
    assert_eq!(problem.status, 503);
    // Tranche 1: internal error text never leaves the server; the code is the
    // contract (ADR-031 decision 6).
    assert_eq!(problem.code, "domain.service-unavailable");
    assert!(!problem.detail.contains("membership repo down"));
}
