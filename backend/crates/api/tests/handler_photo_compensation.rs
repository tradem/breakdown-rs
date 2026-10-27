// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! CR-001: the photo-upload handlers compensate the bytes they already stored
//! when the following link command is refused.
//!
//! The upload order is `store bytes → UploadPhoto → LinkPhoto`. A refused link
//! (a stale `version`, the realistic case) used to leave the original object in
//! Garage forever: the previous compensation was
//! `.inspect_err(|_| drop(state.ports.photo_storage().delete_all(photo_id)))`,
//! which dropped the `async fn` future **before its first poll** — a no-op. The
//! `PhotoGcSweep` cannot help either: it only deletes ids the `projection_photo`
//! does not know, and this id *is* known (the `UploadPhoto` already landed).
//!
//! These cases pin the fixed behaviour for both upload paths: the stored object
//! is gone afterwards and the handler's original 409 is still the response.

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
use api::handlers::{upload_outfit_photo, upload_piece_photo};
use api::problems::{ApiError, Json, Path};
use api::state::AppState;
use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::events::{CharacterMeasurements, ContactInfo};
use breakdown_core::character::views::CharacterView;
use breakdown_core::error::DomainError;
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

fn jpeg_headers() -> axum::http::HeaderMap {
    let mut headers = axum::http::HeaderMap::new();
    headers.insert("content-type", "image/jpeg".parse().expect("static header"));
    headers
}

/// A stale-version refusal is the realistic link failure (another mutation
/// advanced the stream between the read and the dispatch).
fn stale_version() -> DomainError {
    DomainError::VersionConflict {
        expected: AggregateVersion::INITIAL,
        current: AggregateVersion(3),
    }
}

async fn seed_season(
    ports: &FakePorts,
    season_id: SeasonId,
    project_id: ProjectId,
    archived: bool,
) {
    ports.season_repo.seasons.lock().await.insert(
        season_id.0,
        SeasonView {
            id: season_id.0,
            project_id,
            number: 1,
            title: None,
            archived,
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
}

/// A fundus piece whose only scope is its season repertoire, plus the role that
/// authorizes the series the repertoire resolves to.
async fn seed_piece_with_repertoire(ports: &FakePorts) -> Uuid {
    let season_id = SeasonId::new();
    let project_id = ProjectId::new();
    let piece_id = Uuid::now_v7();
    seed_season(ports, season_id, project_id, false).await;
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
    ports
        .piece_repo
        .repertoire
        .lock()
        .await
        .insert(piece_id, vec![season_id]);
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
    piece_id
}

/// A character-bound outfit plus the role that authorizes its season.
async fn seed_outfit(ports: &FakePorts) -> Uuid {
    let season_id = SeasonId::new();
    let project_id = ProjectId::new();
    let character_id = Uuid::now_v7();
    let outfit_id = Uuid::now_v7();
    seed_season(ports, season_id, project_id, false).await;
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
    outfit_id
}

/// The one `photo_id` the handler dispatched through `UploadPhoto`, i.e. the id
/// whose original bytes the compensation has to remove.
async fn uploaded_photo_id(ports: &FakePorts) -> Uuid {
    let uploads = ports.photo_commands.uploads.lock().await;
    assert_eq!(
        uploads.len(),
        1,
        "the upload command must have been dispatched once"
    );
    uploads[0].id.0
}

/// `true` when no object of any variant is stored for `photo_id`.
async fn storage_is_clean(ports: &FakePorts, photo_id: Uuid) -> bool {
    ports
        .photo_storage
        .objects
        .lock()
        .await
        .keys()
        .all(|(id, _variant)| *id != photo_id)
}

fn expect_version_conflict<T: std::fmt::Debug>(result: Result<T, ApiError>) {
    let problem = result
        .expect_err("a refused link must fail the upload")
        .into_problem();
    assert_eq!(problem.status, StatusCode::CONFLICT);
    assert_eq!(problem.code, "concurrency.version-mismatch");
}

#[tokio::test]
async fn piece_photo_upload_compensates_the_stored_bytes_when_the_link_is_refused() {
    let ports = FakePorts::default();
    let piece_id = seed_piece_with_repertoire(&ports).await;
    ports.piece_commands.fail_link_photo(stale_version()).await;

    let state = AppState::new(ports.clone());
    let result = upload_piece_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(piece_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await;

    let photo_id = uploaded_photo_id(&ports).await;
    expect_version_conflict(result);
    assert!(
        storage_is_clean(&ports, photo_id).await,
        "the compensating delete must remove the original object (CR-001)"
    );
    assert_eq!(
        ports.piece_commands.link_photo_ids().await,
        vec![photo_id],
        "the refusal must come from the photo-link dispatch"
    );
}

#[tokio::test]
async fn outfit_photo_upload_compensates_the_stored_bytes_when_the_link_is_refused() {
    let ports = FakePorts::default();
    let outfit_id = seed_outfit(&ports).await;
    ports.piece_commands.fail_link_photo(stale_version()).await;

    let state = AppState::new(ports.clone());
    let result = upload_outfit_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(outfit_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await;

    let photo_id = uploaded_photo_id(&ports).await;
    expect_version_conflict(result);
    assert!(
        storage_is_clean(&ports, photo_id).await,
        "the compensating delete must remove the original object (CR-001)"
    );
}

/// The successful path must keep its bytes: the compensation may only run on a
/// refusal.
#[tokio::test]
async fn piece_photo_upload_keeps_the_stored_bytes_on_success() {
    let ports = FakePorts::default();
    let piece_id = seed_piece_with_repertoire(&ports).await;

    let state = AppState::new(ports.clone());
    let (status, Json(view)) = upload_piece_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(piece_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await
    .expect("an authorized upload with a working link must succeed");

    assert_eq!(status, StatusCode::CREATED);
    assert!(
        !storage_is_clean(&ports, view.id.0).await,
        "a successful upload must keep its bytes"
    );
}
