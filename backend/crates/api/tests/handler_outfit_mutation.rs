// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! CR-002: **every** outfit mutation route refuses an archived season with
//! `409 season.archived` (issue #533 — the archive is the terminal lifecycle
//! state), while the outfit **reads** keep answering 200 for that same season.
//!
//! The invariant ("Archived season blocks outfit mutation", delta spec
//! `outfit-management`) was previously enforced only by `create_outfit`; these
//! cases pin all eight mutation routes to the shared `authorize_outfit_mutation`
//! gate so they cannot drift apart again.

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
    AddOutfitPieceRequest, CreateOutfitRequest, CreateOutfitVariantRequest, RenameOutfitRequest,
    UpdateOutfitNotesRequest, VersionRequest, add_outfit_piece, create_outfit,
    create_outfit_variant, delete_outfit_photo, get_outfit, list_character_outfits,
    remove_outfit_piece, rename_outfit, update_outfit_notes, upload_outfit_photo,
};
use api::problems::{ApiError, Json, Path, Query};
use api::state::AppState;
use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::events::{CharacterMeasurements, ContactInfo};
use breakdown_core::character::views::CharacterView;
use breakdown_core::membership::Role;
use breakdown_core::outfit::views::OutfitView;
use breakdown_core::piece::views::PieceView;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, BlockId, ProjectId, SeasonId, UserId};
use chrono::Utc;
use common::FakePorts;
use uuid::Uuid;

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

/// One outfit of a character who lives in an **archived** season, plus a piece
/// of the same season for the `add piece` pre-check.
struct ArchivedWardrobe {
    outfit_id: Uuid,
    character_id: Uuid,
    piece_id: Uuid,
}

async fn seed_archived_season_wardrobe(ports: &FakePorts) -> ArchivedWardrobe {
    let season_id = SeasonId::new();
    let project_id = ProjectId::new();
    let character_id = Uuid::now_v7();
    let outfit_id = Uuid::now_v7();
    let piece_id = Uuid::now_v7();

    ports.character_repo.characters.lock().await.insert(
        character_id,
        CharacterView {
            id: character_id,
            season_id,
            name: "BEN".into(),
            category: CharacterCategory::MainCast,
            measurements: CharacterMeasurements::default(),
            contact: ContactInfo::default(),
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    ports.season_repo.seasons.lock().await.insert(
        season_id.0,
        SeasonView {
            id: season_id.0,
            project_id,
            number: 1,
            title: Some("Staffel 1".into()),
            // The terminal lifecycle state (issue #533).
            archived: true,
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    // The role is active on purpose: the refusal must come from the archived
    // gate, not from a missing membership.
    ports
        .membership_repo
        .seed_active(
            BlockId::new(),
            UserId::from_sub(USER),
            Role::CostumeDesigner,
            season_id,
            project_id,
        )
        .await;
    ports.outfit_repo.outfits.lock().await.insert(
        outfit_id,
        OutfitView {
            id: outfit_id,
            character_id,
            character_name: Some("BEN".into()),
            season_id: Some(season_id.0),
            name: "Outfit 1: Büro".into(),
            variant_of: None,
            piece_ids: Vec::new(),
            pieces: Vec::new(),
            notes: String::new(),
            photos: Vec::new(),
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    ports.piece_repo.pieces.lock().await.insert(
        piece_id,
        PieceView {
            id: piece_id,
            name: "Marineblau".into(),
            category_id: None,
            category_name: None,
            notes: String::new(),
            details: Vec::new(),
            photos: Vec::new(),
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
            season_ids: vec![season_id.0],
        },
    );

    ArchivedWardrobe {
        outfit_id,
        character_id,
        piece_id,
    }
}

/// The refusal must be the registered RFC 9457 problem, not a generic conflict.
fn expect_season_archived<T: std::fmt::Debug>(result: Result<T, ApiError>) {
    let problem = result
        .expect_err("an archived season must refuse the outfit mutation")
        .into_problem();
    assert_eq!(problem.status, StatusCode::CONFLICT);
    assert_eq!(problem.code, "season.archived");
}

fn jpeg_headers() -> axum::http::HeaderMap {
    let mut headers = axum::http::HeaderMap::new();
    headers.insert("content-type", "image/jpeg".parse().expect("static header"));
    headers
}

#[tokio::test]
async fn create_outfit_is_refused_for_an_archived_season() {
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let state = AppState::new(ports);

    expect_season_archived(
        create_outfit::<FakePorts>(
            State(state),
            dummy_user(),
            Json(CreateOutfitRequest {
                character_id: wardrobe.character_id,
                name: "Outfit 2: OP".into(),
                piece_ids: Vec::new(),
            }),
        )
        .await,
    );
}

#[tokio::test]
async fn create_outfit_variant_is_refused_for_an_archived_season() {
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let state = AppState::new(ports);

    expect_season_archived(
        create_outfit_variant::<FakePorts>(
            State(state),
            dummy_user(),
            Path(wardrobe.outfit_id),
            Json(CreateOutfitVariantRequest {
                name: Some("Outfit 1b".into()),
                piece_ids: None,
                notes: None,
            }),
        )
        .await,
    );
}

#[tokio::test]
async fn rename_outfit_is_refused_for_an_archived_season() {
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let state = AppState::new(ports);

    expect_season_archived(
        rename_outfit::<FakePorts>(
            State(state),
            dummy_user(),
            Path(wardrobe.outfit_id),
            Json(RenameOutfitRequest {
                name: "Outfit 1b".into(),
                version: AggregateVersion::INITIAL,
            }),
        )
        .await,
    );
}

#[tokio::test]
async fn update_outfit_notes_is_refused_for_an_archived_season() {
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let state = AppState::new(ports);

    expect_season_archived(
        update_outfit_notes::<FakePorts>(
            State(state),
            dummy_user(),
            Path(wardrobe.outfit_id),
            Json(UpdateOutfitNotesRequest {
                notes: "nach dem Telefonat".into(),
                version: AggregateVersion::INITIAL,
            }),
        )
        .await,
    );
}

#[tokio::test]
async fn add_outfit_piece_is_refused_for_an_archived_season() {
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let state = AppState::new(ports);

    expect_season_archived(
        add_outfit_piece::<FakePorts>(
            State(state),
            dummy_user(),
            Path(wardrobe.outfit_id),
            Json(AddOutfitPieceRequest {
                piece_id: wardrobe.piece_id,
                version: AggregateVersion::INITIAL,
            }),
        )
        .await,
    );
}

#[tokio::test]
async fn remove_outfit_piece_is_refused_for_an_archived_season() {
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let state = AppState::new(ports);

    expect_season_archived(
        remove_outfit_piece::<FakePorts>(
            State(state),
            dummy_user(),
            Path((wardrobe.outfit_id, wardrobe.piece_id)),
            Query(VersionRequest {
                version: AggregateVersion::INITIAL,
            }),
        )
        .await,
    );
}

#[tokio::test]
async fn upload_outfit_photo_is_refused_for_an_archived_season() {
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let state = AppState::new(ports);

    expect_season_archived(
        upload_outfit_photo::<FakePorts>(
            State(state),
            dummy_user(),
            Path(wardrobe.outfit_id),
            jpeg_headers(),
            Bytes::from_static(b"fake-image-data"),
        )
        .await,
    );
}

#[tokio::test]
async fn delete_outfit_photo_is_refused_for_an_archived_season() {
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let state = AppState::new(ports);

    expect_season_archived(
        delete_outfit_photo::<FakePorts>(
            State(state),
            dummy_user(),
            Path((wardrobe.outfit_id, Uuid::now_v7())),
        )
        .await,
    );
}

/// Counter-check (#533): the archived season stays **readable** — the gate that
/// refuses mutations deliberately lives outside `authorize_outfit_scoped`.
#[tokio::test]
async fn outfit_reads_stay_available_for_an_archived_season() {
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let state = AppState::new(ports);

    let (status, Json(view)) =
        get_outfit::<FakePorts>(State(state), dummy_user(), Path(wardrobe.outfit_id))
            .await
            .expect("an archived season keeps its outfits readable");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(view.id, wardrobe.outfit_id);

    // The list read shares the seam and must stay open as well.
    let ports = FakePorts::default();
    let wardrobe = seed_archived_season_wardrobe(&ports).await;
    let (status, Json(views)) = list_character_outfits::<FakePorts>(
        State(AppState::new(ports)),
        dummy_user(),
        Path(wardrobe.character_id),
    )
    .await
    .expect("an archived season keeps the outfit list readable");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(views.len(), 1);
}
