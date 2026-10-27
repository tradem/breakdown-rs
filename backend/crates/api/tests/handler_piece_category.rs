// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! `POST /v1/pieces/{id}/category` (issue #543): one piece = one category.
//!
//! The handler performs the API-edge pre-check for the cross-aggregate season
//! invariant (doctrine, AGENTS.md §1) *before* dispatch:
//! `category.season_id ∈ (repertoire_seasons(piece) ∪ season(character))`.
//! Failures: 404 piece/category not found, 409 `costume-category.archived`,
//! 409 `costume-category.season-mismatch` (extension `category_id`), 403 on a
//! caller without the piece role in ANY season scope of the piece.

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
use api::handlers::{SetPieceCategoryRequest, set_piece_category};
use api::problems::ApiError;
use api::problems::{Json, Path};
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::views::CharacterView;
use breakdown_core::costume_category::views::CostumeCategoryView;
use breakdown_core::piece::PieceView;
use breakdown_core::shared::{
    AggregateVersion, CostumeCategoryId, LexicalSortKey, ProjectId, SeasonId, UserId,
};
use chrono::Utc;
use common::FakePorts;
use uuid::Uuid;

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

async fn seed_piece(
    ports: &FakePorts,
    character_season: Option<SeasonId>,
    repertoire: &[SeasonId],
) -> Uuid {
    let outfit_id = Uuid::now_v7();
    let character_id = character_season.map(|_| Uuid::now_v7());
    if let (Some(season_id), Some(character_id)) = (character_season, character_id) {
        ports.character_repo.characters.lock().await.insert(
            character_id,
            CharacterView {
                id: character_id,
                season_id,
                name: "Test Character".into(),
                category: CharacterCategory::MainCast,
                measurements: breakdown_core::character::events::CharacterMeasurements::default(),
                contact: breakdown_core::character::events::ContactInfo::default(),
                version: AggregateVersion::INITIAL,
                updated_at: Utc::now(),
            },
        );
    }
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

async fn seed_category(
    ports: &FakePorts,
    id: Uuid,
    season_id: SeasonId,
    archived: bool,
) -> CostumeCategoryId {
    ports.costume_category_repo.categories.lock().await.insert(
        id,
        CostumeCategoryView {
            id,
            season_id,
            name: "Oberteil".into(),
            order_key: LexicalSortKey("a".into()),
            archived,
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    CostumeCategoryId(id)
}

/// Authorize [USER] with the piece role in [season].
async fn grant_piece_role(ports: &FakePorts, season: SeasonId) {
    ports
        .membership_repo
        .piece_role_by_season
        .lock()
        .await
        .insert(season.0, Ok(true));
}

#[tokio::test]
async fn set_piece_category_accepts_category_in_repertoire_season() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, None, &[season]).await;
    let cat_id = seed_category(&ports, Uuid::now_v7(), season, false).await;
    grant_piece_role(&ports, season).await;
    let state = AppState::new(ports);

    let result = set_piece_category::<FakePorts>(
        State(state),
        dummy_user(),
        Path(outfit_id),
        Json(SetPieceCategoryRequest {
            category_id: Some(cat_id.0),
            version: AggregateVersion::INITIAL,
        }),
    )
    .await;

    let (status, Json(version)) = result.expect("repertoire-season category must be accepted");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(version, AggregateVersion(2));
}

/// A piece without any repertoire has no season scope at all, so the category
/// invariant cannot be evaluated — the edge answers 422 rather than guessing.
/// (Before the piece/outfit split this case was covered by the character
/// binding; the binding now lives on the outfit.)
#[tokio::test]
async fn set_piece_category_without_repertoire_has_no_scope() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, None, &[]).await;
    let cat_id = seed_category(&ports, Uuid::now_v7(), season, false).await;
    grant_piece_role(&ports, season).await;
    let state = AppState::new(ports);

    let result = set_piece_category::<FakePorts>(
        State(state),
        dummy_user(),
        Path(outfit_id),
        Json(SetPieceCategoryRequest {
            category_id: Some(cat_id.0),
            version: AggregateVersion::INITIAL,
        }),
    )
    .await;

    let err = result.expect_err("a piece with no repertoire cannot be scoped");
    assert!(
        matches!(err, ApiError::Validation(_)),
        "expected a 422 validation problem, got {err:?}"
    );
}

#[tokio::test]
async fn set_piece_category_rejects_foreign_season_with_409() {
    let ports = FakePorts::default();
    let repertoire_season = SeasonId::new();
    let foreign_season = SeasonId::new();
    let outfit_id = seed_piece(&ports, None, &[repertoire_season]).await;
    let cat_id = seed_category(&ports, Uuid::now_v7(), foreign_season, false).await;
    grant_piece_role(&ports, repertoire_season).await;
    let state = AppState::new(ports);

    let problem = set_piece_category::<FakePorts>(
        State(state),
        dummy_user(),
        Path(outfit_id),
        Json(SetPieceCategoryRequest {
            category_id: Some(cat_id.0),
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("a foreign-season category must be rejected")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "costume-category.season-mismatch");
    let extensions = problem.extensions.as_ref().expect("extensions present");
    assert_eq!(
        extensions.get("category_id"),
        Some(&serde_json::json!(cat_id.0.to_string())),
        "the 409 must carry the S0 `category_id` extension"
    );
}

#[tokio::test]
async fn set_piece_category_rejects_archived_category_with_409() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, None, &[season]).await;
    let cat_id = seed_category(&ports, Uuid::now_v7(), season, true).await;
    grant_piece_role(&ports, season).await;
    let state = AppState::new(ports);

    let problem = set_piece_category::<FakePorts>(
        State(state),
        dummy_user(),
        Path(outfit_id),
        Json(SetPieceCategoryRequest {
            category_id: Some(cat_id.0),
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("an archived category must be rejected")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "costume-category.archived");
}

#[tokio::test]
async fn set_piece_category_404_on_unknown_category() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, None, &[season]).await;
    grant_piece_role(&ports, season).await;
    let state = AppState::new(ports);

    let problem = set_piece_category::<FakePorts>(
        State(state),
        dummy_user(),
        Path(outfit_id),
        Json(SetPieceCategoryRequest {
            category_id: Some(Uuid::now_v7()),
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("an unknown category must 404")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "costume-category.not-found");
}

#[tokio::test]
async fn set_piece_category_404_on_unknown_piece() {
    let ports = FakePorts::default();
    let state = AppState::new(ports);

    let problem = set_piece_category::<FakePorts>(
        State(state),
        dummy_user(),
        Path(Uuid::now_v7()),
        Json(SetPieceCategoryRequest {
            category_id: None,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("an unknown piece must 404")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "piece.not-found");
}

#[tokio::test]
async fn set_piece_category_denies_caller_without_piece_role() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, None, &[season]).await;
    let cat_id = seed_category(&ports, Uuid::now_v7(), season, false).await;
    // No piece role granted for any scope of the piece.
    let state = AppState::new(ports);

    let problem = set_piece_category::<FakePorts>(
        State(state),
        dummy_user(),
        Path(outfit_id),
        Json(SetPieceCategoryRequest {
            category_id: Some(cat_id.0),
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("a caller without the piece role must be denied")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
}

#[tokio::test]
async fn set_piece_category_none_clears_without_a_category_lookup() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let outfit_id = seed_piece(&ports, None, &[season]).await;
    grant_piece_role(&ports, season).await;
    let state = AppState::new(ports);

    let result = set_piece_category::<FakePorts>(
        State(state),
        dummy_user(),
        Path(outfit_id),
        Json(SetPieceCategoryRequest {
            category_id: None,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await;

    let (status, Json(version)) = result.expect("clearing must dispatch without a pre-check");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(version, AggregateVersion(2));
}

// Silence unused warnings for helpers only used in some configurations.
#[allow(dead_code)]
fn _touch(_u: &UserId, _s: &ProjectId) {}
