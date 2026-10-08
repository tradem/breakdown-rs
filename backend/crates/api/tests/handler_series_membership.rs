// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Series-level membership self-check (issue #535) — the client-side
//! AUTHZ-GATE signal for the series-wide costume-photo policy (ADR-035 B2/S2).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod common;

use api::auth::CurrentUser;
use api::handlers::get_series_membership;
use api::problems::{Json, Path};
use api::state::AppState;
use axum::extract::State;

use breakdown_core::membership::Role;
use breakdown_core::shared::{BlockId, ProjectId, SeasonId, UserId};
use common::*;

#[tokio::test]
async fn get_series_membership_returns_predicate_for_active_member() {
    let ports = FakePorts::default();
    let series = ProjectId::new();
    ports
        .membership_repo
        .seed_active(
            BlockId::new(),
            UserId::from_sub("user-1"),
            Role::CostumeDesigner,
            SeasonId::new(),
            series,
        )
        .await;
    let (_status, Json(dto)) = get_series_membership::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("user-1"),
        Path(series.0),
    )
    .await
    .unwrap();
    assert_eq!(dto.project_id, series.0);
    assert!(dto.has_active_costume_role_in_project);
    assert_eq!(
        dto.capabilities,
        vec![
            "upload_continuity_photos".to_string(),
            "assign_costumes".to_string()
        ]
    );
}

#[tokio::test]
async fn get_series_membership_returns_empty_capabilities_for_non_member() {
    let ports = FakePorts::default();
    let series = ProjectId::new();
    let (_status, Json(dto)) = get_series_membership::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("stranger"),
        Path(series.0),
    )
    .await
    .unwrap();
    assert!(!dto.has_active_costume_role_in_project);
    assert!(dto.capabilities.is_empty());
}

/// A season-scoped role in the same series does NOT satisfy the series
/// predicate through the season override — the series gate reads its own
/// predicate (fail closed against a broken series predicate).
#[tokio::test]
async fn get_series_membership_resolves_the_series_predicate_not_the_season_one() {
    let ports = FakePorts::default();
    let series = ProjectId::new();
    // Season predicate would allow (override true), series predicate is
    // unseeded → the DTO must report `false`.
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    *ports
        .membership_repo
        .series_costume_role_override
        .lock()
        .await = Some(Ok(false));
    let (_status, Json(dto)) = get_series_membership::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("user-1"),
        Path(series.0),
    )
    .await
    .unwrap();
    assert!(!dto.has_active_costume_role_in_project);
}

/// A failing series predicate is propagated as a server error (fail closed,
/// issue #537 doctrine) — never rendered as a permission answer.
#[tokio::test]
async fn get_series_membership_propagates_predicate_failure() {
    let ports = FakePorts::default();
    let series = ProjectId::new();
    *ports
        .membership_repo
        .series_costume_role_override
        .lock()
        .await = Some(Err(breakdown_core::error::DomainError::internal(
        "membership table unavailable",
    )));
    let result = get_series_membership::<FakePorts>(
        State(AppState::new(ports)),
        CurrentUser::dummy("user-1"),
        Path(series.0),
    )
    .await;
    let problem = result.unwrap_err().into_problem();
    assert_eq!(problem.status, 500);
}
