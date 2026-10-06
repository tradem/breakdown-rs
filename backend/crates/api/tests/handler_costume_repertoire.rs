// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

//! Costume repertoire wire tests (issue #534):
//! `POST /costumes/{id}/seasons` + `DELETE /costumes/{id}/seasons/{season_id}`.
//!
//! - an active costume-dept member of the **target** season adds/removes with
//!   200 + bumped version (handler-internal AUTHZ-GATE);
//! - a caller without the target-season role is denied with 403
//!   `domain.forbidden` (ADR-035 B2: no new `*_in_season` predicate);
//! - an unknown target season answers 404 `season.not-found`;
//! - an archived target season answers 409 `season.archived` (#533
//!   terminal-state semantics: no further repertoire mutations).
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
use api::handlers::{
    AddCostumeToSeasonRequest, VersionRequest, add_costume_to_season, remove_costume_from_season,
};
use api::problems::{Json, Path};
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::costume::views::CostumeView;
use breakdown_core::error_registry::SEASON_NOT_FOUND;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, SeasonId, SeriesId};
use chrono::Utc;
use common::FakePorts;
use uuid::Uuid;

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

fn costume_view(id: Uuid, character_id: Option<Uuid>) -> CostumeView {
    CostumeView {
        id,
        character_id,
        category_id: None,
        category_name: None,
        notes: String::new(),
        details: vec![],
        photos: vec![],
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
        season_ids: vec![],
    }
}

/// Seed a costume with the given repertoire seasons (its current authz
/// scopes alongside the character season it has none of here).
async fn seed_costume(ports: &FakePorts, costume_id: Uuid, repertoire: &[Uuid]) {
    ports
        .costume_repo
        .costumes
        .lock()
        .await
        .insert(costume_id, costume_view(costume_id, None));
    ports.costume_repo.repertoire.lock().await.insert(
        costume_id,
        repertoire.iter().map(|s| SeasonId::from_uuid(*s)).collect(),
    );
}

fn season_view(id: Uuid) -> SeasonView {
    SeasonView {
        id,
        series_id: SeriesId::new(),
        number: 1,
        title: None,
        archived: false,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

#[tokio::test]
async fn add_to_season_returns_200_with_bumped_version() {
    let ports = FakePorts::default();
    let costume = Uuid::now_v7();
    let season = Uuid::now_v7();
    // The costume's current scope: season `scope` (repertoire). The caller
    // holds the costume role there AND in the target season.
    let scope = Uuid::now_v7();
    seed_costume(&ports, costume, &[scope]).await;
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(season, season_view(season));
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let (status, Json(version)) = add_costume_to_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume),
        Json(AddCostumeToSeasonRequest {
            season_id: season,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect("add must succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(version, AggregateVersion::INITIAL.next());
}

#[tokio::test]
async fn add_to_season_denied_without_target_season_role() {
    let ports = FakePorts::default();
    let costume = Uuid::now_v7();
    let season = Uuid::now_v7();
    seed_costume(&ports, costume, &[Uuid::now_v7()]).await;
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(season, season_view(season));
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = AppState::new(ports);

    let problem = add_costume_to_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume),
        Json(AddCostumeToSeasonRequest {
            season_id: season,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("denial must surface as an error")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
}

#[tokio::test]
async fn add_to_season_unknown_season_returns_404() {
    let mut ports = FakePorts::default();
    ports.season_repo.season_exists = false;
    // The costume under test EXISTS (its own 404 would mask the season's).
    let costume = Uuid::now_v7();
    seed_costume(&ports, costume, &[Uuid::now_v7()]).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let problem = add_costume_to_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume),
        Json(AddCostumeToSeasonRequest {
            season_id: Uuid::now_v7(),
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("unknown season must surface as an error")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, SEASON_NOT_FOUND.code);
}

#[tokio::test]
async fn add_to_season_archived_season_returns_409() {
    let ports = FakePorts::default();
    let costume = Uuid::now_v7();
    let season = Uuid::now_v7();
    seed_costume(&ports, costume, &[Uuid::now_v7()]).await;
    let mut view = season_view(season);
    view.archived = true;
    ports.season_repo.seasons.lock().await.insert(season, view);
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let problem = add_costume_to_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume),
        Json(AddCostumeToSeasonRequest {
            season_id: season,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("archived season must surface as an error")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "season.archived");
}

#[tokio::test]
async fn add_to_season_denied_without_costume_scope_role() {
    // CodeRabbit review: a caller with a costume role ONLY in the TARGET
    // season (and in no current scope of the costume) must not be able to
    // pull the costume into the target season's repertoire — that would
    // make the target season one of the costume's authz scopes and open
    // the any-scope gates with the caller's role. 403, zero dispatch.
    let ports = FakePorts::default();
    let costume = Uuid::now_v7();
    let season = Uuid::now_v7();
    let scope = Uuid::now_v7();
    seed_costume(&ports, costume, &[scope]).await;
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(season, season_view(season));
    // Role in the TARGET season only; the costume's own scope denies.
    ports
        .membership_repo
        .costume_role_by_season
        .lock()
        .await
        .insert(season, Ok(true));
    ports
        .membership_repo
        .costume_role_by_season
        .lock()
        .await
        .insert(scope, Ok(false));
    let state = AppState::new(ports);

    let problem = add_costume_to_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume),
        Json(AddCostumeToSeasonRequest {
            season_id: season,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("foreign-scope adoption must be denied")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
}

#[tokio::test]
async fn add_to_season_scopeless_costume_returns_422() {
    // A costume with no character and no repertoire has no resolvable
    // season scope — the same rule every other `authorize_costume_scoped`
    // consumer enforces (422 validation; adopting a dead shell through
    // this route is not an authz bypass).
    let ports = FakePorts::default();
    let costume = Uuid::now_v7();
    let season = Uuid::now_v7();
    seed_costume(&ports, costume, &[]).await;
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(season, season_view(season));
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let problem = add_costume_to_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume),
        Json(AddCostumeToSeasonRequest {
            season_id: season,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("scopeless costume must be rejected")
    .into_problem();

    assert_eq!(problem.status, 422);
}

#[tokio::test]
async fn remove_from_season_returns_200_with_bumped_version() {
    let ports = FakePorts::default();
    let season = Uuid::now_v7();
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(season, season_view(season));
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let (status, Json(version)) = remove_costume_from_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path((Uuid::now_v7(), season)),
        Json(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect("remove must succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(version, AggregateVersion::INITIAL.next());
}

#[tokio::test]
async fn remove_from_season_denied_without_target_season_role() {
    let ports = FakePorts::default();
    let season = Uuid::now_v7();
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(season, season_view(season));
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = AppState::new(ports);

    let problem = remove_costume_from_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path((Uuid::now_v7(), season)),
        Json(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("denial must surface as an error")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
}

#[tokio::test]
async fn remove_from_season_archived_season_returns_409() {
    let ports = FakePorts::default();
    let season = Uuid::now_v7();
    let mut view = season_view(season);
    view.archived = true;
    ports.season_repo.seasons.lock().await.insert(season, view);
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let problem = remove_costume_from_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path((Uuid::now_v7(), season)),
        Json(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("archived season must surface as an error")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "season.archived");
}

#[tokio::test]
async fn remove_from_season_unknown_season_returns_404() {
    let mut ports = FakePorts::default();
    ports.season_repo.season_exists = false;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let problem = remove_costume_from_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path((Uuid::now_v7(), Uuid::now_v7())),
        Json(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("unknown season must surface as an error")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, SEASON_NOT_FOUND.code);
}
