// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

//! Season lifecycle wire tests (issue #533): `POST /seasons/{id}/archive`.
//!
//! - an active costume-dept member archives with 200 + bumped version;
//! - a caller without the season role is denied with a handler-internal
//!   AUTHZ-GATE 403 (generic `domain.forbidden`, like every other
//!   season-scoped gate — ADR-035 B2: no new `*_in_season` predicate);
//! - the idempotent-reject of a repeat archive maps `SeasonError::
//!   ArchivedCannotBeMutated` to the registered `season.archived` 409.
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
use api::handlers::{VersionRequest, archive_season};
use api::problems::{Json, Path};
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::error::DomainError;
use breakdown_core::error_registry::SEASON_NOT_FOUND;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, SeriesId};
use chrono::Utc;
use common::FakePorts;
use uuid::Uuid;

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

fn season_view(id: Uuid, series_id: SeriesId, number: i32) -> SeasonView {
    SeasonView {
        id,
        series_id,
        number,
        title: None,
        archived: false,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

#[tokio::test]
async fn archive_season_returns_200_with_bumped_version() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(id, season_view(id, SeriesId::new(), 1));
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let (status, Json(version)) = archive_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path(id),
        Json(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect("archive must succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(version, AggregateVersion::INITIAL.next());
}

#[tokio::test]
async fn archive_season_denied_without_costume_role() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(id, season_view(id, SeriesId::new(), 1));
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = AppState::new(ports);

    let problem = archive_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path(id),
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
async fn archive_season_unknown_season_returns_404() {
    let mut ports = FakePorts::default();
    ports.season_repo.season_exists = false;
    let state = AppState::new(ports);

    let problem = archive_season::<FakePorts>(
        State(state),
        dummy_user(),
        Path(Uuid::now_v7()),
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

/// The domain-level repeat-archive reject maps to the registered
/// `season.archived` 409 (same mapping the aggregate→wire path produces).
#[test]
fn archived_conflict_maps_to_registered_season_archived_code() {
    let id = Uuid::now_v7();
    let domain = DomainError::from(
        breakdown_core::season::error::SeasonError::ArchivedCannotBeMutated { id },
    );
    let problem = api::problems::ApiError::from(domain).into_problem();
    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "season.archived");
    // Mirrors the neighbouring archived codes (`costume-category.archived`,
    // `shooting-day.archived`): the generic Conflict path ships without a
    // wire extension; `id` stays diagnostic (`extensions: &["id"]` in the
    // registry is the S-classification, asserted nowhere on the wire).
    let _ = id;
}
