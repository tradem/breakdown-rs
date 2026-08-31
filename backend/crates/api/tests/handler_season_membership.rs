// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

//! Integration tests for `GET /seasons/{id}/membership` (issue #311).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod common;

use std::sync::Arc;

use api::auth::CurrentUser;
use api::problems::{Json, Path};
use axum::extract::State;
use tokio::sync::Mutex;
use uuid::Uuid;

use api::handlers::get_season_membership;
use api::state::AppState;
use common::*;

#[tokio::test]
async fn get_season_membership_returns_404_for_missing_season() {
    let mut ports = FakePorts::default();
    ports.season_repo = FakeSeasonRepo {
        season_exists: false,
    };
    let id = Uuid::now_v7();
    let result = get_season_membership::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("user-1"),
        Path(id),
    )
    .await;
    let problem = result.unwrap_err().into_problem();
    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "season.not-found");
}

#[tokio::test]
async fn get_season_membership_returns_capabilities_for_active_member() {
    let ports = FakePorts {
        season_repo: FakeSeasonRepo {
            season_exists: true,
        },
        membership_repo: FakeMembershipRepo {
            members: Default::default(),
            credential_role_override: Default::default(),
            costume_role_override: Arc::new(Mutex::new(Some(Ok(true)))),
            report_archive_role_override: Default::default(),
        },
        ..Default::default()
    };
    let id = Uuid::now_v7();
    let (_status, Json(dto)) = get_season_membership::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("user-1"),
        Path(id),
    )
    .await
    .unwrap();
    assert_eq!(dto.season_id, id);
    assert!(dto.has_active_costume_role_in_season);
    assert_eq!(
        dto.capabilities,
        vec![
            "upload_continuity_photos".to_string(),
            "assign_costumes".to_string()
        ]
    );
}

#[tokio::test]
async fn get_season_membership_returns_empty_capabilities_for_non_member() {
    let ports = FakePorts {
        season_repo: FakeSeasonRepo {
            season_exists: true,
        },
        membership_repo: FakeMembershipRepo {
            members: Default::default(),
            credential_role_override: Default::default(),
            costume_role_override: Arc::new(Mutex::new(Some(Ok(false)))),
            report_archive_role_override: Default::default(),
        },
        ..Default::default()
    };
    let id = Uuid::now_v7();
    let (_status, Json(dto)) = get_season_membership::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("user-1"),
        Path(id),
    )
    .await
    .unwrap();
    assert_eq!(dto.season_id, id);
    assert!(!dto.has_active_costume_role_in_season);
    assert!(dto.capabilities.is_empty());
}
