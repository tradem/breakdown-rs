// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

//! `PATCH` / `DELETE /v1/pieces/{id}/details/{detail_id}` (issue #544).
//!
//! Before this change `POST /v1/pieces/{id}/details` was the only detail
//! route: a detail could be added but never changed or removed. Both routes
//! are gated by `Requirement::Authenticated` (block membership only), so each
//! handler must additionally call `authorize_piece_scoped` **inside** the
//! handler body (`// AUTHZ-GATE:`, AGENTS.md §3).
//!
//! Covered here: the 200 path, the 404 `piece.not-found` / 404
//! `piece-detail.not-found` distinction, the 409 version fence, the 403
//! authz gate (with the assertion that **no command is dispatched**), and the
//! body/path `detail.id` agreement.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

use crate::common;

use api::auth::CurrentUser;
use api::handlers::{
    PieceDetailRequest, UpdatePieceDetailRequest, VersionRequest, remove_piece_detail,
    update_piece_detail,
};
use api::problems::{Json, Path};
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::error::DomainError;
use breakdown_core::error_registry::PIECE_DETAIL_NOT_FOUND;
use breakdown_core::piece::PieceView;
use breakdown_core::shared::{AggregateVersion, SeasonId};
use chrono::Utc;
use common::{DetailCommandKind, FakePorts};
use uuid::Uuid;

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

async fn seed_piece(ports: &FakePorts, repertoire: &[SeasonId]) -> Uuid {
    let outfit_id = Uuid::now_v7();
    ports.piece_repo.pieces.lock().await.insert(
        outfit_id,
        PieceView {
            id: outfit_id,
            name: "Fundus-Piece".to_string(),
            category_id: None,
            category_name: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
            season_ids: vec![],
        },
    );
    ports
        .piece_repo
        .repertoire
        .lock()
        .await
        .insert(outfit_id, repertoire.to_vec());
    outfit_id
}

async fn grant_piece_role(ports: &FakePorts, season: SeasonId) {
    ports
        .membership_repo
        .piece_role_by_season
        .lock()
        .await
        .insert(season.0, Ok(true));
}

fn detail_request(detail_id: Uuid, text: &str) -> UpdatePieceDetailRequest {
    UpdatePieceDetailRequest {
        detail: PieceDetailRequest {
            id: detail_id,
            subject: Some("Rote Lederjacke".into()),
            text: text.into(),
        },
        version: AggregateVersion::INITIAL,
    }
}

// --- PATCH -----------------------------------------------------------------

#[tokio::test]
async fn update_piece_detail_returns_new_version() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    grant_piece_role(&ports, season).await;
    let state = AppState::new(ports);
    let detail_id = Uuid::now_v7();

    let (status, Json(version)) = update_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, detail_id)),
        Json(detail_request(detail_id, "leder")),
    )
    .await
    .expect("an authorized edit must succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(version, AggregateVersion::INITIAL.next());
}

#[tokio::test]
async fn update_piece_detail_dispatches_exactly_one_command_for_the_path_id() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    grant_piece_role(&ports, season).await;
    // Clone before the state takes ownership: the fakes are `Arc`-backed,
    // so the clone observes the very same command-call log.
    let commands = ports.piece_commands.clone();
    let state = AppState::new(ports);
    let detail_id = Uuid::now_v7();

    update_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, detail_id)),
        Json(detail_request(detail_id, "leder")),
    )
    .await
    .expect("edit succeeds");

    assert_eq!(
        commands.detail_ids().await,
        vec![(DetailCommandKind::Update, detail_id)]
    );
}

#[tokio::test]
async fn update_piece_detail_rejects_body_id_mismatch() {
    // A body id that disagrees with the path is a client bug. Forwarding the
    // body's id would let a typo rewrite (or create) the wrong row.
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    grant_piece_role(&ports, season).await;
    // Clone before the state takes ownership: the fakes are `Arc`-backed,
    // so the clone observes the very same command-call log.
    let commands = ports.piece_commands.clone();
    let state = AppState::new(ports);
    let path_detail = Uuid::now_v7();
    let other_detail = Uuid::now_v7();

    let problem = update_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, path_detail)),
        Json(detail_request(other_detail, "leder")),
    )
    .await
    .expect_err("a mismatched detail id must be rejected")
    .into_problem();

    assert_eq!(problem.status, 422);
    assert!(
        commands.detail_ids().await.is_empty(),
        "no command may be dispatched for a mismatched id"
    );
}

#[tokio::test]
async fn update_piece_detail_unknown_piece_is_404_piece_not_found() {
    let ports = FakePorts::default();
    // Clone before the state takes ownership: the fakes are `Arc`-backed,
    // so the clone observes the very same command-call log.
    let commands = ports.piece_commands.clone();
    let state = AppState::new(ports);
    let detail_id = Uuid::now_v7();

    let problem = update_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((Uuid::now_v7(), detail_id)),
        Json(detail_request(detail_id, "leder")),
    )
    .await
    .expect_err("an unknown piece must not dispatch")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "piece.not-found");
    assert!(commands.detail_ids().await.is_empty());
}

#[tokio::test]
async fn update_piece_detail_unknown_detail_is_404_piece_detail_not_found() {
    // The reason #544 adds a dedicated 404 instead of reusing
    // `piece.validation` (422): the client must be able to tell "the detail
    // is gone" apart from a real validation failure and reconcile by refetch.
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    grant_piece_role(&ports, season).await;
    let missing = Uuid::now_v7();
    ports
        .piece_commands
        .fail_detail(
            DetailCommandKind::Update,
            DomainError::NotFound {
                code: &PIECE_DETAIL_NOT_FOUND,
                resource: "piece-detail",
                id: missing,
            },
        )
        .await;
    let state = AppState::new(ports);

    let problem = update_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, missing)),
        Json(detail_request(missing, "leder")),
    )
    .await
    .expect_err("an unknown detail must not succeed")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "piece-detail.not-found");
}

#[tokio::test]
async fn update_piece_detail_version_conflict_is_409() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    grant_piece_role(&ports, season).await;
    let detail_id = Uuid::now_v7();
    ports
        .piece_commands
        .fail_detail(
            DetailCommandKind::Update,
            DomainError::VersionConflict {
                expected: AggregateVersion::INITIAL,
                current: AggregateVersion::INITIAL.next().next(),
            },
        )
        .await;
    let state = AppState::new(ports);

    let problem = update_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, detail_id)),
        Json(detail_request(detail_id, "leder")),
    )
    .await
    .expect_err("a stale version must not succeed")
    .into_problem();

    assert_eq!(problem.status, 409);
}

#[tokio::test]
async fn update_piece_detail_without_piece_role_is_403_and_sends_nothing() {
    // The authz gate runs BEFORE dispatch: a caller without the piece role
    // in any season scope must not even reach the command port.
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    // No `grant_piece_role` — the membership lookup answers `Ok(false)`.
    // Clone before the state takes ownership: the fakes are `Arc`-backed,
    // so the clone observes the very same command-call log.
    let commands = ports.piece_commands.clone();
    let state = AppState::new(ports);
    let detail_id = Uuid::now_v7();

    let problem = update_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, detail_id)),
        Json(detail_request(detail_id, "leder")),
    )
    .await
    .expect_err("an unauthorized edit must be denied")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert!(
        commands.detail_ids().await.is_empty(),
        "the authz gate must run before the command dispatch"
    );
}

// --- DELETE ----------------------------------------------------------------

#[tokio::test]
async fn remove_piece_detail_returns_new_version() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    grant_piece_role(&ports, season).await;
    // Clone before the state takes ownership: the fakes are `Arc`-backed,
    // so the clone observes the very same command-call log.
    let commands = ports.piece_commands.clone();
    let state = AppState::new(ports);
    let detail_id = Uuid::now_v7();

    let (status, Json(version)) = remove_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, detail_id)),
        Json(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect("an authorized delete must succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(version, AggregateVersion::INITIAL.next());
    assert_eq!(
        commands.detail_ids().await,
        vec![(DetailCommandKind::Remove, detail_id)]
    );
}

#[tokio::test]
async fn remove_piece_detail_unknown_detail_is_404_piece_detail_not_found() {
    // `RemovePieceDetail` was implemented long before issue #544 but answered a
    // 422 `piece.validation` string for this case; both routes now share the
    // dedicated 404 so a client can react the same way to either.
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    grant_piece_role(&ports, season).await;
    let missing = Uuid::now_v7();
    ports
        .piece_commands
        .fail_detail(
            DetailCommandKind::Remove,
            DomainError::NotFound {
                code: &PIECE_DETAIL_NOT_FOUND,
                resource: "piece-detail",
                id: missing,
            },
        )
        .await;
    let state = AppState::new(ports);

    let problem = remove_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, missing)),
        Json(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("an unknown detail must not succeed")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "piece-detail.not-found");
}

#[tokio::test]
async fn remove_piece_detail_version_conflict_is_409() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    grant_piece_role(&ports, season).await;
    ports
        .piece_commands
        .fail_detail(
            DetailCommandKind::Remove,
            DomainError::VersionConflict {
                expected: AggregateVersion::INITIAL,
                current: AggregateVersion::INITIAL.next(),
            },
        )
        .await;
    let state = AppState::new(ports);

    let problem = remove_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, Uuid::now_v7())),
        Json(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("a stale version must not succeed")
    .into_problem();

    assert_eq!(problem.status, 409);
}

#[tokio::test]
async fn remove_piece_detail_without_piece_role_is_403_and_sends_nothing() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, &[season]).await;
    // Clone before the state takes ownership: the fakes are `Arc`-backed,
    // so the clone observes the very same command-call log.
    let commands = ports.piece_commands.clone();
    let state = AppState::new(ports);
    let detail_id = Uuid::now_v7();

    let problem = remove_piece_detail::<FakePorts>(
        State(state),
        dummy_user(),
        Path((outfit_id, detail_id)),
        Json(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("an unauthorized delete must be denied")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert!(
        commands.detail_ids().await.is_empty(),
        "the authz gate must run before the command dispatch"
    );
}
