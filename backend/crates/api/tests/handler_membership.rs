// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod common;
// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use api::auth::CurrentUser;
use api::problems::Json; // test-only alias for the wrapper extractor (ADR-031)
use api::problems::{Path, Query};
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::membership::Role;
use breakdown_core::shared::{BlockId, UserId};
use uuid::Uuid;

use api::handlers::{
    GrantRoleRequest, InviteMemberRequest, ListParams, accept_invitation, get_member, grant_role,
    invite_member, leave_block, list_members, remove_member,
};
use api::state::AppState;
use common::*;

fn fresh_block() -> Uuid {
    Uuid::now_v7()
}

#[tokio::test]
async fn invite_member_dispatches_command_with_actor_and_target() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(fresh_block());
    let result = invite_member::<FakePorts>(
        State(AppState::new(ports.clone())),
        CurrentUser::dummy("owner-1"),
        Path(block_id.0),
        Json(InviteMemberRequest {
            user_id: "invitee-2".to_string(),
            role: Role::CostumeAssistant,
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
        .unwrap();
    assert_eq!(last.0, UserId::from_sub("owner-1"));
    assert_eq!(last.1.block_id, block_id);
    assert_eq!(last.1.user_id, UserId::from_sub("invitee-2"));
}

#[tokio::test]
async fn accept_invitation_binds_target_to_authenticated_user() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(fresh_block());
    let result = accept_invitation::<FakePorts>(
        State(AppState::new(ports.clone())),
        CurrentUser::dummy("invitee-2"),
        Path(block_id.0),
    )
    .await;
    assert_eq!(result.unwrap().0, StatusCode::NO_CONTENT);
    let last = ports
        .membership_commands
        .last_accept
        .lock()
        .await
        .clone()
        .unwrap();
    // actor == target == authenticated user (cannot accept on behalf of another)
    assert_eq!(last.0, UserId::from_sub("invitee-2"));
    assert_eq!(last.1.user_id, UserId::from_sub("invitee-2"));
    assert_eq!(last.1.block_id, block_id);
}

#[tokio::test]
async fn grant_role_dispatches_with_target_from_path() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(fresh_block());
    let result = grant_role::<FakePorts>(
        State(AppState::new(ports.clone())),
        CurrentUser::dummy("owner-1"),
        Path((block_id.0, "member-3".to_string())),
        Json(GrantRoleRequest {
            role: Role::WardrobeSupervisor,
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
        .unwrap();
    assert_eq!(last.0, UserId::from_sub("owner-1"));
    assert_eq!(last.1.user_id, UserId::from_sub("member-3"));
}

#[tokio::test]
async fn remove_member_dispatches_with_target_from_path() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(fresh_block());
    let result = remove_member::<FakePorts>(
        State(AppState::new(ports.clone())),
        CurrentUser::dummy("owner-1"),
        Path((block_id.0, "member-3".to_string())),
    )
    .await;
    assert_eq!(result.unwrap().0, StatusCode::NO_CONTENT);
    let last = ports
        .membership_commands
        .last_remove
        .lock()
        .await
        .clone()
        .unwrap();
    assert_eq!(last.0, UserId::from_sub("owner-1"));
    assert_eq!(last.1.user_id, UserId::from_sub("member-3"));
}

#[tokio::test]
async fn leave_block_dispatches_with_actor_as_leaver() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(fresh_block());
    let result = leave_block::<FakePorts>(
        State(AppState::new(ports.clone())),
        CurrentUser::dummy("member-3"),
        Path(block_id.0),
    )
    .await;
    assert_eq!(result.unwrap().0, StatusCode::NO_CONTENT);
    let last = ports
        .membership_commands
        .last_leave
        .lock()
        .await
        .clone()
        .unwrap();
    assert_eq!(last.0, UserId::from_sub("member-3"));
    assert_eq!(last.1.block_id, block_id);
}

#[tokio::test]
async fn list_members_returns_projection_views() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(fresh_block());
    ports
        .membership_repo
        .members
        .lock()
        .await
        .insert((block_id, UserId::from_sub("member-3")));
    let result = list_members::<FakePorts>(
        State(AppState::new(ports.clone())),
        Path(block_id.0),
        Query(ListParams {
            limit: Some(50),
            offset: Some(0),
            episode_id: None,
            season_id: None,
            series_id: None,
        }),
    )
    .await;
    let (status, Json(views)) = result.unwrap();
    assert_eq!(status, StatusCode::OK);
    assert_eq!(views.len(), 1);
    assert_eq!(views[0].user_id, UserId::from_sub("member-3"));
}

#[tokio::test]
async fn get_member_returns_404_when_absent() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(fresh_block());
    let result = get_member::<FakePorts>(
        State(AppState::new(ports.clone())),
        Path((block_id.0, "ghost".to_string())),
    )
    .await;
    let problem = result.unwrap_err().into_problem();
    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "membership.not-found");
}

#[tokio::test]
async fn get_member_returns_view_when_present() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(fresh_block());
    ports
        .membership_repo
        .members
        .lock()
        .await
        .insert((block_id, UserId::from_sub("member-3")));
    let result = get_member::<FakePorts>(
        State(AppState::new(ports.clone())),
        Path((block_id.0, "member-3".to_string())),
    )
    .await;
    let (status, Json(view)) = result.unwrap();
    assert_eq!(status, StatusCode::OK);
    assert_eq!(view.user_id, UserId::from_sub("member-3"));
}
