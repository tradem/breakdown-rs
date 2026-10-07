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
use breakdown_core::error::DomainError;
use breakdown_core::membership::Role;
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{
    AggregateVersion, BlockId, PhotoId, PhotoVariant, SeasonId, SeriesId, UserId,
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
// Costume photo scope resolution (issue #535, ADR-035 B2/S2)
//
// Since #535 the photo handlers authorize **series-wide**: the costume's
// owning series is resolved (character season ∪ repertoire → series) and a
// costume-dept role in any active block of it authorizes. The season union
// below is only the means to determine *which* series — it is no longer an
// authorization boundary. Pre-#535 the handlers checked the season predicate
// per scope; those season-union assertions are superseded by the series
// policy (deliberate widening, see the security architecture).
// ---------------------------------------------------------------------------

/// An **unassigned** costume bound to [repertoire] — the client case from
/// issue #532: `repo.create(seasonId)` never assigns a character.
async fn seed_repertoire_costume_with_series(
    ports: &FakePorts,
    repertoire: &[(SeasonId, SeriesId)],
) -> Uuid {
    let costume_id = Uuid::now_v7();
    ports.costume_repo.costumes.lock().await.insert(
        costume_id,
        CostumeView {
            id: costume_id,
            character_id: None,
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
        .costume_repo
        .repertoire
        .lock()
        .await
        .insert(costume_id, repertoire.iter().map(|(s, _)| *s).collect());
    let mut seasons = ports.season_repo.seasons.lock().await;
    for (idx, (season_id, series_id)) in repertoire.iter().enumerate() {
        seasons.insert(
            season_id.0,
            SeasonView {
                id: season_id.0,
                series_id: *series_id,
                number: idx as i32 + 1,
                title: None,
                archived: false,
                version: AggregateVersion::INITIAL,
                updated_at: Utc::now(),
            },
        );
    }
    costume_id
}

/// Seed an active costume-dept membership of [role] in a block of
/// [season_id] / [series_id].
async fn seed_series_member(
    ports: &FakePorts,
    season_id: SeasonId,
    series_id: SeriesId,
    role: Role,
    user: &str,
) {
    ports
        .membership_repo
        .seed_active(
            BlockId::new(),
            UserId::from_sub(user),
            role,
            season_id,
            series_id,
        )
        .await;
}

fn jpeg_headers() -> axum::http::HeaderMap {
    let mut headers = axum::http::HeaderMap::new();
    headers.insert("content-type", "image/jpeg".parse().expect("static header"));
    headers
}

/// An assigned costume whose character lives in [character_season], plus a
/// repertoire binding in [repertoire] — the repertoire now only serves the
/// series resolution, not the authorization (issue #535).
async fn seed_scoped_costume(
    ports: &FakePorts,
    character_season: SeasonId,
    character_series: SeriesId,
    repertoire: &[(SeasonId, SeriesId)],
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
        .costume_repo
        .repertoire
        .lock()
        .await
        .insert(costume_id, repertoire.iter().map(|(s, _)| *s).collect());
    let character_saison_view = SeasonView {
        id: character_season.0,
        series_id: character_series,
        number: 1,
        title: None,
        archived: false,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    };
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(character_season.0, character_saison_view);
    for (idx, (season_id, series_id)) in repertoire.iter().enumerate() {
        ports.season_repo.seasons.lock().await.insert(
            season_id.0,
            SeasonView {
                id: season_id.0,
                series_id: *series_id,
                number: (idx as i32) + 2,
                title: None,
                archived: false,
                version: AggregateVersion::INITIAL,
                updated_at: Utc::now(),
            },
        );
    }
    costume_id
}

#[tokio::test]
async fn upload_costume_photo_allows_unassigned_costume_in_repertoire() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let series = SeriesId::new();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[(season, series)]).await;
    seed_series_member(&ports, season, series, Role::CostumeDesigner, USER).await;
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
    let series = SeriesId::new();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[(season, series)]).await;
    seed_series_member(&ports, season, series, Role::CostumeDesigner, USER).await;
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
    let series = SeriesId::new();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[(season, series)]).await;
    seed_series_member(&ports, season, series, Role::CostumeDesigner, USER).await;
    let photo_id = Uuid::now_v7();
    let state = AppState::new(ports);

    let (status, Json(_)) =
        delete_costume_photo::<FakePorts>(State(state), dummy_user(), Path((costume_id, photo_id)))
            .await
            .expect("repertoire costume photo must be deletable");

    assert_eq!(status, StatusCode::NO_CONTENT);
}

/// A costume whose character lives in a different series than its repertoire
/// season resolves to the character's series (first resolution arm); the
/// series gate authorizes from a role in THAT series.
#[tokio::test]
async fn upload_costume_photo_authorizes_via_characters_series() {
    let ports = FakePorts::default();
    let character_season = SeasonId::new();
    let repertoire_season = SeasonId::new();
    let series = SeriesId::new();
    let other_series = SeriesId::new();
    let costume_id = seed_scoped_costume(
        &ports,
        character_season,
        series,
        &[(repertoire_season, other_series)],
    )
    .await;
    seed_series_member(
        &ports,
        character_season,
        series,
        Role::WardrobeSupervisor,
        USER,
    )
    .await;
    let state = AppState::new(ports);

    let (status, Json(_)) = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await
    .expect("a role in the character's series must authorize the upload");

    assert_eq!(status, StatusCode::CREATED);
}

/// THE DOCUMENTED BEHAVIOR CHANGE (issue #535, explicit regression test in the
/// issue): a caller whose only costume-dept role lives in season B of the
/// same series can now manage photos of a costume standing in season A of
/// that series. Pre-#535 this was a 403 (the season union denied); under the
/// series policy it must be 2xx.
#[tokio::test]
async fn upload_costume_photo_allows_role_in_other_season_of_same_series() {
    let ports = FakePorts::default();
    let season_a = SeasonId::new();
    let season_b = SeasonId::new();
    let series = SeriesId::new();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[(season_a, series)]).await;
    // Role ONLY in season B of the same series — no season-A membership.
    seed_series_member(&ports, season_b, series, Role::CostumeDesigner, USER).await;
    let state = AppState::new(ports);

    let (status, Json(_)) = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await
    .expect("a costume-dept role in another season of the same series must authorize");

    assert_eq!(status, StatusCode::CREATED);
}

/// Same broadening, negative control: a role in a **different series** must
/// stay a 403 — the tenant boundary does not move up with the predicate.
#[tokio::test]
async fn upload_costume_photo_denies_role_in_foreign_series() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let home_series = SeriesId::new();
    let foreign_series = SeriesId::new();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[(season, home_series)]).await;
    let foreign_season = SeasonId::new();
    seed_series_member(
        &ports,
        foreign_season,
        foreign_series,
        Role::CostumeDesigner,
        USER,
    )
    .await;
    let state = AppState::new(ports);

    let problem = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await
    .expect_err("a role in another series must not authorize")
    .into_problem();

    assert_eq!(problem.status, StatusCode::FORBIDDEN);
    assert_eq!(problem.code, "domain.forbidden");
}

/// A costume with **no** scope at all (unassigned, not in any repertoire)
/// cannot name its owning series → 422 `costume.container-unresolved`
/// (registered problem code, issue #535).
#[tokio::test]
async fn upload_costume_photo_rejects_costume_without_any_scope() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let series = SeriesId::new();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[]).await;
    seed_series_member(&ports, season, series, Role::CostumeDesigner, USER).await;
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
    assert_eq!(problem.code, "costume.container-unresolved");
}

/// Scopes exist but the caller holds no costume-dept role in the owning
/// series → 403, not 422.
#[tokio::test]
async fn upload_costume_photo_denies_when_no_scope_authorizes() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let series = SeriesId::new();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[(season, series)]).await;
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

/// A failing membership lookup must fail **closed** (no access) but must not
/// masquerade as a permission error: `unwrap_or(false)` would turn a database
/// outage into a 403 that neither the caller nor an operator can explain
/// (issue #537 doctrine). The predicate's only production error is
/// `DomainError::Internal` → 500.
#[tokio::test]
async fn upload_costume_photo_reports_lookup_failure_as_server_error() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let series = SeriesId::new();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[(season, series)]).await;
    *ports
        .membership_repo
        .series_costume_role_override
        .lock()
        .await = Some(Err(DomainError::internal("membership table unavailable")));
    let photo_commands = ports.photo_commands.clone();
    let state = AppState::new(ports);

    let problem = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await
    .expect_err("a failing predicate must never authorize")
    .into_problem();

    // Fail closed: nothing was written.
    assert!(photo_commands.uploads.lock().await.is_empty());
    assert_ne!(problem.status, StatusCode::FORBIDDEN);
    assert_eq!(problem.status, StatusCode::INTERNAL_SERVER_ERROR);
}

/// The series gate is a **single** series-typed predicate (ADR-035 B2/S2) —
/// an infra hiccup resolving ONE potential scope no longer exists as a
/// branch, so unlike the pre-#535 multi-scope ANY gate there is no
/// "other scope wins despite a lookup failure" path: the series lookup is
/// best-effort and a series resolution failure for a scopeless costume
/// answers 422 `costume.container-unresolved`. Pinned negatively: the
/// old per-season lookup-error propagation must NOT resurface.
#[tokio::test]
async fn upload_costume_photo_scopeless_costume_collapses_to_container_unresolved() {
    let ports = FakePorts::default();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[]).await;
    // Even a permissive costume-role override must not rescue the missing
    // container — the gate never reaches a predicate for this costume.
    *ports
        .membership_repo
        .series_costume_role_override
        .lock()
        .await = Some(Ok(true));
    let state = AppState::new(ports);

    let problem = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await
    .expect_err("no container → no authorization, even with a permissive predicate")
    .into_problem();

    assert_eq!(problem.code, "costume.container-unresolved");
}

/// A repertoire lookup **failure** during the gate's series resolution is an
/// infrastructure outage, not a projection miss: the strict resolver
/// (issue #535 review, #537 doctrine) propagates it as a 500 — never as the
/// misleading 422 `costume.container-unresolved` that would tell the client
/// to refetch during an outage. Fail-closed is unchanged.
#[tokio::test]
async fn upload_costume_photo_reports_repertoire_lookup_failure_as_server_error() {
    let ports = FakePorts::default();
    let costume_id = seed_repertoire_costume_with_series(&ports, &[]).await;
    *ports.costume_repo.repertoire_error.lock().await = Some(DomainError::internal(
        "projection_costume_season unavailable",
    ));
    let photo_commands = ports.photo_commands.clone();
    let state = AppState::new(ports);

    let problem = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        jpeg_headers(),
        Bytes::from_static(b"fake-image-data"),
    )
    .await
    .expect_err("a failing series resolver must never authorize")
    .into_problem();

    // Fail closed: nothing was written.
    assert!(photo_commands.uploads.lock().await.is_empty());
    assert_eq!(problem.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert_ne!(problem.code, "costume.container-unresolved");
}
