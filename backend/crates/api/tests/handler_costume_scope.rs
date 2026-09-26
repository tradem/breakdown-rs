// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

//! Costume create block-scope gate (issue #453 CodeRabbit review).
//!
//! `POST /v1/costumes` is middleware-gated on block *membership* only; the
//! handler must therefore verify INSIDE the handler body that the requested
//! repertoire `season_id` belongs to the caller's active `X-Active-Block`
//! before dispatching `CreateCostume` — otherwise a member of block A could
//! plant a repertoire row for a season of another block and expose it
//! through season-scoped costume reads. A cross-block (or unknown) season is
//! rejected as `season.not-found` (no scope oracle), and no command runs.

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
    CreateCostumeRequest, PhotoBytesQuery, create_costume, delete_costume_photo,
    get_costume_photo_bytes, upload_costume_photo,
};
use api::problems::{Json, Path, Query};
use api::state::AppState;
use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::block::views::BlockView;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::views::CharacterView;
use breakdown_core::costume::CostumeView;
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::shared::{
    AggregateVersion, BlockId, PhotoId, PhotoVariant, SeasonId, SeriesId,
};
use chrono::Utc;
use common::FakePorts;
use uuid::Uuid;

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

fn block_view(id: Uuid, season_id: SeasonId, series_id: SeriesId) -> BlockView {
    BlockView {
        id,
        season_id,
        series_id,
        number: 1,
        start_date: None,
        end_date: None,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

#[tokio::test]
async fn create_costume_accepts_repertoire_season_of_active_block() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let series = SeriesId::new();
    let active_block = BlockId::new();
    ports
        .block_repo
        .blocks
        .lock()
        .await
        .insert(active_block.0, block_view(active_block.0, season, series));
    let state = AppState::new(ports);

    let result = create_costume::<FakePorts>(
        State(state),
        dummy_user(),
        api::auth::ActiveBlock(active_block),
        Json(CreateCostumeRequest {
            season_id: Some(season),
        }),
    )
    .await;

    let (status, Json(resp)) = result.expect("same-block season must be accepted");
    assert_eq!(status, StatusCode::CREATED);
    assert!(!resp.id.is_nil());
    assert_eq!(resp.version, AggregateVersion::INITIAL);
}

#[tokio::test]
async fn create_costume_rejects_cross_block_season_with_season_not_found() {
    let ports = FakePorts::default();
    let active_season = SeasonId::new();
    let other_season = SeasonId::new();
    let series = SeriesId::new();
    let active_block = BlockId::new();
    ports.block_repo.blocks.lock().await.insert(
        active_block.0,
        block_view(active_block.0, active_season, series),
    );
    let state = AppState::new(ports);

    let problem = create_costume::<FakePorts>(
        State(state),
        dummy_user(),
        api::auth::ActiveBlock(active_block),
        Json(CreateCostumeRequest {
            season_id: Some(other_season),
        }),
    )
    .await
    .expect_err("cross-block season must be rejected")
    .into_problem();

    assert_eq!(problem.status, StatusCode::NOT_FOUND);
    assert_eq!(problem.code, "season.not-found");
    assert!(!problem.detail.is_empty());
}

/// A season-less create (legacy `{}` body) dispatches without any scope
/// check — the repertoire binding is optional.
#[tokio::test]
async fn create_costume_without_season_still_dispatches() {
    let ports = FakePorts::default();
    let active_block = BlockId::new();
    let state = AppState::new(ports);

    let result = create_costume::<FakePorts>(
        State(state),
        dummy_user(),
        api::auth::ActiveBlock(active_block),
        Json(CreateCostumeRequest { season_id: None }),
    )
    .await;

    let (status, Json(resp)) = result.expect("season-less create must not be scope-checked");
    assert_eq!(status, StatusCode::CREATED);
    assert!(!resp.id.is_nil());
}

// ---------------------------------------------------------------------------
// Costume photo scope resolution (issue #532)
//
// The photo handlers resolve a costume's season scopes as
// `character season ∪ repertoire seasons` and authorize against ANY of them.
// A costume the client created with a repertoire season (issue #453) is
// unassigned by design and must still be uploadable/readable/deletable.
// ---------------------------------------------------------------------------

/// An **unassigned** costume bound to [repertoire] — the client case from
/// issue #532: `repo.create(seasonId)` never assigns a character.
async fn seed_repertoire_costume(ports: &FakePorts, repertoire: &[SeasonId]) -> Uuid {
    let costume_id = Uuid::now_v7();
    ports.costume_repo.costumes.lock().await.insert(
        costume_id,
        CostumeView {
            id: costume_id,
            character_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    ports
        .costume_repo
        .repertoire
        .lock()
        .await
        .insert(costume_id, repertoire.to_vec());
    costume_id
}

fn jpeg_headers() -> axum::http::HeaderMap {
    let mut headers = axum::http::HeaderMap::new();
    headers.insert("content-type", "image/jpeg".parse().expect("static header"));
    headers
}

/// An assigned costume whose character lives in [character_season], plus a
/// repertoire binding in [repertoire] — pins the union semantics.
async fn seed_scoped_costume(
    ports: &FakePorts,
    character_season: SeasonId,
    repertoire: &[SeasonId],
) -> Uuid {
    let costume_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    ports.character_repo.characters.lock().await.insert(
        character_id,
        CharacterView {
            id: character_id,
            season_id: character_season,
            name: "Test Character".into(),
            category: CharacterCategory::MainCast,
            measurements: breakdown_core::character::events::CharacterMeasurements::default(),
            contact: breakdown_core::character::events::ContactInfo::default(),
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    ports.costume_repo.costumes.lock().await.insert(
        costume_id,
        CostumeView {
            id: costume_id,
            character_id: Some(character_id),
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    ports
        .costume_repo
        .repertoire
        .lock()
        .await
        .insert(costume_id, repertoire.to_vec());
    costume_id
}

#[tokio::test]
async fn upload_costume_photo_allows_unassigned_costume_in_repertoire() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let costume_id = seed_repertoire_costume(&ports, &[season]).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let result = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await;

    let (status, Json(_view)) = result.expect("repertoire costume must be uploadable");
    assert_eq!(status, StatusCode::CREATED);
}

#[tokio::test]
async fn get_costume_photo_bytes_allows_unassigned_costume_in_repertoire() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let costume_id = seed_repertoire_costume(&ports, &[season]).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let photo_id = Uuid::now_v7();
    ports
        .photo_storage
        .store(
            PhotoId::from_uuid(photo_id),
            PhotoVariant::Original,
            b"fake-image-data".to_vec(),
            "image/jpeg".to_string(),
        )
        .await
        .expect("seed photo bytes");
    let state = AppState::new(ports);

    let result = get_costume_photo_bytes::<FakePorts>(
        State(state),
        dummy_user(),
        Path((costume_id, photo_id)),
        Query(PhotoBytesQuery {
            variant: Some("original".to_string()),
        }),
    )
    .await;

    let (status, _headers, bytes) = result.expect("repertoire costume bytes must be readable");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(bytes, b"fake-image-data");
}

#[tokio::test]
async fn delete_costume_photo_allows_unassigned_costume_in_repertoire() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let costume_id = seed_repertoire_costume(&ports, &[season]).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let photo_id = Uuid::now_v7();
    let state = AppState::new(ports);

    let (status, Json(_)) =
        delete_costume_photo::<FakePorts>(State(state), dummy_user(), Path((costume_id, photo_id)))
            .await
            .expect("repertoire costume photo must be deletable");

    assert_eq!(status, StatusCode::NO_CONTENT);
}

/// The union semantics: the character's season denies, the repertoire season
/// allows — the ANY check authorizes (issue #532).
#[tokio::test]
async fn upload_costume_photo_authorizes_via_repertoire_when_character_season_denies() {
    let ports = FakePorts::default();
    let character_season = SeasonId::new();
    let repertoire_season = SeasonId::new();
    let costume_id = seed_scoped_costume(&ports, character_season, &[repertoire_season]).await;
    {
        let mut by_season = ports.membership_repo.costume_role_by_season.lock().await;
        by_season.insert(character_season.0, false);
        by_season.insert(repertoire_season.0, true);
    }
    let state = AppState::new(ports);

    let result = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await;

    let (status, Json(_)) = result.expect("repertoire season must authorize the upload");
    assert_eq!(status, StatusCode::CREATED);
}

/// A costume with **no** scope at all (unassigned, not in any repertoire) is
/// still rejected — the fix is a lookup, not a blanket permission.
#[tokio::test]
async fn upload_costume_photo_rejects_costume_without_any_scope() {
    let ports = FakePorts::default();
    let costume_id = seed_repertoire_costume(&ports, &[]).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = AppState::new(ports);

    let problem = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await
    .expect_err("a costume without any season scope must be rejected")
    .into_problem();

    assert_eq!(problem.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(problem.code, "domain.validation");
}

/// Scopes exist but none authorizes → 403, not 422.
#[tokio::test]
async fn upload_costume_photo_denies_when_no_scope_authorizes() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let costume_id = seed_repertoire_costume(&ports, &[season]).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = AppState::new(ports);

    let problem = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await
    .expect_err("a non-member must be denied even with a repertoire scope")
    .into_problem();

    assert_eq!(problem.status, StatusCode::FORBIDDEN);
    assert_eq!(problem.code, "domain.forbidden");
}
