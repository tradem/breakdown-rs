// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

//! Handler tests for the deployment-scoped ops surface (issue #409):
//! `GET /v1/ops/projector-health` and the ops escalation guard on
//! `invite_member` / `grant_role`.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod common;

use axum::extract::State;
use axum::http::StatusCode;
use chrono::Utc;
use common::FakePorts;
use uuid::Uuid;

use api::auth::CurrentUser;
use api::handlers::{
    GrantRoleRequest, InviteMemberRequest, ProjectorHealthQuery, get_projector_health, grant_role,
    invite_member,
};
use api::problems::{Json, Path, Query};
use api::state::AppState;
use breakdown_core::membership::Role;
use breakdown_core::membership::views::MembershipStateKind;
use breakdown_core::ops::{CheckpointProgress, DeadLetterEntry, ProjectorHealthSnapshot};
use breakdown_core::shared::{BlockId, UserId};
use utoipa::OpenApi;

fn ops_user() -> CurrentUser {
    CurrentUser::dummy("ops-user")
}

fn plain_user() -> CurrentUser {
    CurrentUser::dummy("plain-user")
}

/// Seed an active `ops_admin` membership row for `sub` on `block_id`.
async fn seed_ops_member(ports: &FakePorts, block_id: BlockId, sub: &str) {
    ports.membership_repo.detailed.lock().await.insert(
        (block_id, UserId::from_sub(sub)),
        (Role::OpsAdmin, MembershipStateKind::Active),
    );
    ports
        .membership_repo
        .scopes
        .lock()
        .await
        .insert(block_id, (Default::default(), Default::default()));
}

fn sample_snapshot() -> ProjectorHealthSnapshot {
    ProjectorHealthSnapshot {
        dead_letter_count: 1,
        dead_letters: vec![DeadLetterEntry {
            projection_id: "costume".to_string(),
            partition_id: 3,
            sequence: 42,
            stream_id: "costume-1".to_string(),
            event_name: "CostumeAssigned".to_string(),
            sqlstate: Some("23505".to_string()),
            constraint_name: Some("uq_projection_costume".to_string()),
            error_message: "duplicate key".to_string(),
            attempts: 5,
            first_seen_at: Utc::now(),
            last_seen_at: Utc::now(),
        }],
        checkpoints: vec![CheckpointProgress {
            projection_id: "season".to_string(),
            partition_id: 0,
            sequence: 7,
        }],
    }
}

#[tokio::test]
async fn projector_health_denies_caller_without_ops_capability() {
    let ports = FakePorts::default();

    let result = get_projector_health::<FakePorts>(
        State(AppState::new(ports)),
        plain_user(),
        Query(ProjectorHealthQuery { limit: None }),
    )
    .await;

    let problem = result
        .expect_err("non-ops caller must be denied")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
}

#[tokio::test]
async fn projector_health_allows_active_ops_admin_member() {
    let mut ports = FakePorts::default();
    ports.projector_health_repo.snapshot =
        std::sync::Arc::new(tokio::sync::Mutex::new(Some(sample_snapshot())));
    seed_ops_member(&ports, BlockId::from_uuid(Uuid::now_v7()), "ops-user").await;

    let (status, Json(snapshot)) = get_projector_health::<FakePorts>(
        State(AppState::new(ports)),
        ops_user(),
        Query(ProjectorHealthQuery { limit: None }),
    )
    .await
    .expect("ops member must be allowed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(snapshot.dead_letter_count, 1);
    assert_eq!(snapshot.dead_letters.len(), 1);
    assert_eq!(snapshot.dead_letters[0].event_name, "CostumeAssigned");
    assert_eq!(snapshot.checkpoints.len(), 1);
    assert_eq!(snapshot.checkpoints[0].sequence, 7);
}

#[tokio::test]
async fn projector_health_allows_ops_bootstrap_allowlist_without_membership() {
    let mut ports = FakePorts::default();
    ports.projector_health_repo.snapshot =
        std::sync::Arc::new(tokio::sync::Mutex::new(Some(sample_snapshot())));
    // No membership rows at all — the OPS_ADMIN_SUBS allowlist grants access.
    let state = AppState::with_ai_import(ports, true, 1024, vec!["ops-user".to_string()]);

    let (status, Json(snapshot)) = get_projector_health::<FakePorts>(
        State(state),
        ops_user(),
        Query(ProjectorHealthQuery { limit: None }),
    )
    .await
    .expect("allowlisted bootstrap caller must be allowed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(snapshot.dead_letter_count, 1);
}

#[tokio::test]
async fn projector_health_rejects_out_of_range_limit() {
    let ports = FakePorts::default();
    seed_ops_member(&ports, BlockId::from_uuid(Uuid::now_v7()), "ops-user").await;

    for limit in [0, -1, 501] {
        let problem = get_projector_health::<FakePorts>(
            State(AppState::new(ports.clone())),
            ops_user(),
            Query(ProjectorHealthQuery { limit: Some(limit) }),
        )
        .await
        .expect_err("out-of-range limit must be rejected")
        .into_problem();
        assert_eq!(problem.status, 400, "limit={limit}");
        assert_eq!(problem.code, "http.bad-query-param", "limit={limit}");
    }
}

#[tokio::test]
async fn projector_health_maps_read_model_failure_to_500() {
    let ports = FakePorts::default();
    *ports.projector_health_repo.error.lock().await = Some("db down".to_string());
    seed_ops_member(&ports, BlockId::from_uuid(Uuid::now_v7()), "ops-user").await;

    let problem = get_projector_health::<FakePorts>(
        State(AppState::new(ports)),
        ops_user(),
        Query(ProjectorHealthQuery { limit: None }),
    )
    .await
    .expect_err("read-model failure must surface as a problem")
    .into_problem();
    assert_eq!(problem.status, 500);
    assert_eq!(problem.code, "http.internal-error");
}

// --- Ops escalation guard on invite_member / grant_role (issue #409) ------

#[tokio::test]
async fn invite_member_rejects_ops_role_from_non_ops_caller() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());

    let problem = invite_member::<FakePorts>(
        State(AppState::new(ports)),
        plain_user(),
        Path(block_id.0),
        Json(InviteMemberRequest {
            user_id: "invitee-2".to_string(),
            role: Role::OpsAdmin,
        }),
    )
    .await
    .expect_err("non-ops caller must not be able to grant ops role")
    .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
}

#[tokio::test]
async fn invite_member_allows_ops_role_from_ops_caller() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ops_member(&ports, block_id, "ops-user").await;

    let result = invite_member::<FakePorts>(
        State(AppState::new(ports.clone())),
        ops_user(),
        Path(block_id.0),
        Json(InviteMemberRequest {
            user_id: "invitee-2".to_string(),
            role: Role::OpsAdmin,
        }),
    )
    .await;
    assert_eq!(result.unwrap().0, StatusCode::NO_CONTENT);
    let last = ports
        .membership_commands
        .last_invite
        .lock()
        .await
        .clone()
        .expect("ops caller must get past the escalation guard");
    assert_eq!(last.1.role, Role::OpsAdmin);
}

#[tokio::test]
async fn grant_role_rejects_ops_role_from_non_ops_caller() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());

    let problem = grant_role::<FakePorts>(
        State(AppState::new(ports)),
        plain_user(),
        Path((block_id.0, "target-user".to_string())),
        Json(GrantRoleRequest {
            role: Role::OpsAdmin,
        }),
    )
    .await
    .expect_err("non-ops caller must not be able to grant ops role")
    .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
}

#[tokio::test]
async fn grant_role_allows_ops_role_from_ops_caller() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ops_member(&ports, block_id, "ops-user").await;

    let result = grant_role::<FakePorts>(
        State(AppState::new(ports.clone())),
        ops_user(),
        Path((block_id.0, "target-user".to_string())),
        Json(GrantRoleRequest {
            role: Role::OpsAdmin,
        }),
    )
    .await;
    assert_eq!(result.unwrap().0, StatusCode::NO_CONTENT);
    let last = ports
        .membership_commands
        .last_grant
        .lock()
        .await
        .clone()
        .expect("ops caller must get past the escalation guard");
    assert_eq!(last.1.role, Role::OpsAdmin);
}

#[test]
fn openapi_doc_includes_ops_path_and_schemas() {
    let doc = api::ApiDoc::openapi();
    let json = serde_json::to_string(&doc).expect("ApiDoc serializes to JSON");
    assert!(
        json.contains("/ops/projector-health"),
        "GET /ops/projector-health must be registered in ApiDoc"
    );
    for schema in [
        "DeadLetterEntry",
        "CheckpointProgress",
        "ProjectorHealthSnapshot",
    ] {
        assert!(
            json.contains(schema),
            "{schema} schema must be registered in ApiDoc components"
        );
    }
}
