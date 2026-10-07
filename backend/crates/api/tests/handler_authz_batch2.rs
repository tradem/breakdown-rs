// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: claude-sonnet-4-20250514 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: hy4-preview (opencode-go)

//! Batch 2 — Authz-Handler 403-Tests for mutation-test hardening (issue #274).
//!
//! These tests kill survived mutants by exercising handler-internal AUTHZ-GATE
//! paths. Each test verifies that unauthorized callers receive 403 and authorized
//! callers succeed.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
#![allow(unsafe_code)] // test-only env var manipulation

mod common;

use axum::body::Bytes;
use axum::extract::State;

use api::auth::CurrentUser;
use api::handlers::{
    LinkContinuityPhotoRequest, ListParams, PhotoBytesQuery, VersionRequest, delete_costume_photo,
    dispo_report, dispo_report_pdf, get_costume_photo_bytes, link_continuity_photo,
    manual_archive_reports, planned_vs_actual_report_pdf, shoot_day_report, shoot_day_report_pdf,
    soll_ist_report, unlink_continuity_photo, upload_costume_photo,
};
use api::problems::{Json, Path, Query};
use api::state::AppState;
use breakdown_core::block::BlockView;
use breakdown_core::character::CharacterView;
use breakdown_core::costume::CostumeView;
use breakdown_core::episode::EpisodeView;
use breakdown_core::shared::{
    AggregateVersion, BlockId, EpisodeId, PhotoId, PhotoVariant, SceneShootId, SeasonId, SeriesId,
    ShootingDayId, UserId, VariantStatus,
};
use breakdown_core::shooting_day::ShootingDayView;
use common::FakePorts;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

fn season_id() -> SeasonId {
    SeasonId::new()
}

fn block_id() -> BlockId {
    BlockId::new()
}

fn episode_id() -> EpisodeId {
    EpisodeId::new()
}

fn shooting_day_id() -> ShootingDayId {
    ShootingDayId::new()
}

fn scene_shoot_id() -> SceneShootId {
    SceneShootId::new()
}

fn series_id() -> SeriesId {
    SeriesId::new()
}

/// Build an `AppState` with the given ports.
fn app_state(ports: FakePorts) -> AppState<FakePorts> {
    AppState::new(ports)
}

/// Seed the shooting-day repo chain: shooting_day → episode → block (→ season).
async fn seed_shooting_day_chain(ports: &FakePorts) -> (ShootingDayId, SeasonId) {
    let sd_id = shooting_day_id();
    let ep_id = episode_id();
    let bl_id = block_id();
    let sid = season_id();

    ports.block_repo.blocks.lock().await.insert(
        bl_id.0,
        BlockView {
            id: bl_id.0,
            series_id: series_id(),
            season_id: sid,
            number: 1,
            start_date: None,
            end_date: None,
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    ports.episode_repo.episodes.lock().await.insert(
        ep_id.0,
        EpisodeView {
            id: ep_id.0,
            block_id: bl_id,
            series_id: series_id(),
            number: 1,
            name: Some("Episode 1".into()),
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    ports.shooting_day_repo.days.lock().await.insert(
        sd_id,
        ShootingDayView {
            id: sd_id,
            episode_id: ep_id,
            label: Some("Day 1".into()),
            order_key: breakdown_core::shared::LexicalSortKey::from_static("a"),
            date: None,
            source: breakdown_core::shooting_day::events::ShootingDaySource::Manual,
            archived: false,
            wrapped_at: None,
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    (sd_id, sid)
}

/// Seed the costume → character chain for photo handlers.
async fn seed_costume_chain(ports: &FakePorts) -> (uuid::Uuid, SeasonId) {
    let costume_id = uuid::Uuid::now_v7();
    let char_id = uuid::Uuid::now_v7();
    let sid = season_id();

    ports.character_repo.characters.lock().await.insert(
        char_id,
        CharacterView {
            id: char_id,
            season_id: sid,
            name: "Test Character".into(),
            category: breakdown_core::character::CharacterCategory::MainCast,
            measurements: breakdown_core::character::CharacterMeasurements::default(),
            contact: breakdown_core::character::ContactInfo::default(),
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    ports.costume_repo.costumes.lock().await.insert(
        costume_id,
        CostumeView {
            id: costume_id,
            character_id: Some(char_id),
            category_id: None,
            category_name: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
            season_ids: vec![],
        },
    );
    (costume_id, sid)
}

// ---------------------------------------------------------------------------
// P2.1 — Costume Photo Handlers (upload, get, delete)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn upload_costume_photo_denies_non_member() {
    let ports = FakePorts::default();
    let (costume_id, _sid) = seed_costume_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let mut headers = axum::http::HeaderMap::new();
    headers.insert("content-type", "image/jpeg".parse().unwrap());
    let result = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        headers,
        Bytes::from_static(b"fake-image-data"),
    )
    .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

/// Regression for issue #514: an authorized upload must return **201** with a
/// view derived entirely from the dispatch/command output even when the photo
/// projector has not yet caught up. `FakePhotoRepo::find_by_id` returns
/// `NotFound` here (simulating projector lag), so the pre-fix handler — which
/// built its response via a synchronous `photo_repo().find_by_id` read-back —
/// turned the successful write into a spurious 404 `photo.not-found`.
#[tokio::test]
async fn upload_costume_photo_returns_201_despite_projection_lag() {
    let ports = FakePorts::default();
    let (costume_id, _sid) = seed_costume_chain(&ports).await;
    // Authorize the caller (the handler-internal AUTHZ-GATE must pass —
    // issue #535: the photo path is series-scoped, so the series predicate
    // is pinned instead of the season override).
    *ports
        .membership_repo
        .series_costume_role_override
        .lock()
        .await = Some(Ok(true));
    // Keep a handle on the photo-command spy before `ports` is moved into the state.
    let photo_commands = ports.photo_commands.clone();
    let state = app_state(ports);

    let mut headers = axum::http::HeaderMap::new();
    headers.insert("content-type", "image/jpeg".parse().unwrap());
    let payload = b"fake-image-data";
    let result = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        headers,
        Bytes::from_static(payload),
    )
    .await;

    let (status, Json(view)) =
        result.expect("authorized upload must succeed even when the photo projection lags");
    assert_eq!(status, axum::http::StatusCode::CREATED);

    // The response must be built solely from command output: the dispatched
    // `UploadPhoto` carries the authoritative id/content-type/size.
    let recorded = photo_commands
        .uploads
        .lock()
        .await
        .pop()
        .expect("UploadPhoto must have been dispatched");
    assert_eq!(
        view.id, recorded.id,
        "response id must be the dispatched photo id"
    );
    assert_eq!(view.content_type, "image/jpeg");
    assert_eq!(view.size_bytes, payload.len() as u64);
    // The immediate response must mirror the projection the photo projector
    // writes on `PhotoUploaded`: the Original variant carries the uploaded
    // size, Thumb/Medium are 0 until the thumbnail saga runs.
    assert_eq!(view.variants.len(), 3);
    let original = view
        .variants
        .iter()
        .find(|v| v.kind == PhotoVariant::Original)
        .expect("original variant present");
    assert_eq!(original.size_bytes, payload.len() as u64);
    for v in view
        .variants
        .iter()
        .filter(|v| v.kind != PhotoVariant::Original)
    {
        assert_eq!(v.size_bytes, 0, "non-original variants must start empty");
    }
    assert_eq!(view.version, AggregateVersion::INITIAL);
    assert_eq!(view.exif_stripped_at, None);
    assert_eq!(
        view.binding,
        breakdown_core::photo::binding::PhotoBinding::Costume { costume_id }
    );
    let statuses: Vec<_> = view.variants.iter().map(|v| (v.kind, v.status)).collect();
    assert_eq!(
        statuses,
        vec![
            (PhotoVariant::Original, VariantStatus::Pending),
            (PhotoVariant::Thumb, VariantStatus::Pending),
            (PhotoVariant::Medium, VariantStatus::Pending),
        ]
    );
}

#[tokio::test]
async fn get_costume_photo_bytes_denies_non_member() {
    let ports = FakePorts::default();
    let (costume_id, _sid) = seed_costume_chain(&ports).await;
    let photo_id = uuid::Uuid::now_v7();
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = get_costume_photo_bytes::<FakePorts>(
        State(state),
        dummy_user(),
        Path((costume_id, photo_id)),
        Query(PhotoBytesQuery {
            variant: Some("original".to_string()),
        }),
    )
    .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn delete_costume_photo_denies_non_member() {
    let ports = FakePorts::default();
    let (costume_id, _sid) = seed_costume_chain(&ports).await;
    let photo_id = uuid::Uuid::now_v7();
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result =
        delete_costume_photo::<FakePorts>(State(state), dummy_user(), Path((costume_id, photo_id)))
            .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

// ---------------------------------------------------------------------------
// P2.2 — Continuity Photos & Reports
// ---------------------------------------------------------------------------

#[tokio::test]
async fn link_continuity_photo_denies_non_member() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = link_continuity_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path((sd_id, uuid::Uuid::now_v7(), scene_shoot_id())),
        Json(LinkContinuityPhotoRequest {
            photo_id: PhotoId::new(),
            version: AggregateVersion(1),
        }),
    )
    .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn unlink_continuity_photo_denies_non_member() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = unlink_continuity_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path((
            sd_id,
            uuid::Uuid::now_v7(),
            scene_shoot_id(),
            PhotoId::new(),
        )),
        Query(VersionRequest {
            version: AggregateVersion(1),
        }),
    )
    .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn dispo_report_denies_non_member() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = dispo_report::<FakePorts>(State(state), dummy_user(), Path(sd_id)).await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn shoot_day_report_denies_non_member() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = shoot_day_report::<FakePorts>(State(state), dummy_user(), Path(sd_id)).await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn soll_ist_report_denies_non_member() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = soll_ist_report::<FakePorts>(State(state), dummy_user(), Path(sd_id)).await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn dispo_report_pdf_denies_non_member() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = dispo_report_pdf::<FakePorts>(State(state), dummy_user(), Path(sd_id)).await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn shoot_day_report_pdf_denies_non_member() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = shoot_day_report_pdf::<FakePorts>(State(state), dummy_user(), Path(sd_id)).await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn planned_vs_actual_report_pdf_denies_non_member() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result =
        planned_vs_actual_report_pdf::<FakePorts>(State(state), dummy_user(), Path(sd_id)).await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn manual_archive_reports_denies_non_member() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports
        .membership_repo
        .report_archive_role_override
        .lock()
        .await = Some(Ok(false));
    let state = app_state(ports);

    let result = manual_archive_reports::<FakePorts>(State(state), dummy_user(), Path(sd_id)).await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

// ---------------------------------------------------------------------------
// P2.3 — Settings/GDrive/AI-Handler: Authz + Bedingungslogik
// ---------------------------------------------------------------------------

#[tokio::test]
async fn create_gdrive_credential_denies_non_member() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = api::handlers::create_gdrive_credential::<FakePorts>(
        State(state),
        dummy_user(),
        Json(api::handlers::GDriveCredentialRequest {
            client_id: "id".into(),
            client_secret: "secret".into(),
            refresh_token: "token".into(),
            root_folder_id: None,
        }),
    )
    .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn rotate_gdrive_credential_denies_non_member() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = api::handlers::rotate_gdrive_credential::<FakePorts>(
        State(state),
        dummy_user(),
        Path(uuid::Uuid::now_v7()),
        Json(api::handlers::GDriveCredentialUpdateRequest {
            bundle: api::handlers::GDriveCredentialRequest {
                client_id: "id".into(),
                client_secret: "secret".into(),
                refresh_token: "token".into(),
                root_folder_id: None,
            },
            version: AggregateVersion(1),
        }),
    )
    .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn create_credential_denies_non_member() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = api::handlers::create_credential::<FakePorts>(
        State(state),
        dummy_user(),
        Json(api::handlers::CreateCredentialRequest {
            provider: "generic".into(),
            secret: "s3cret".into(),
        }),
    )
    .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn get_settings_denies_non_member() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = api::handlers::get_settings::<FakePorts>(
        State(state),
        dummy_user(),
        Path(uuid::Uuid::now_v7()),
    )
    .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn revoke_settings_denies_non_member() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));
    let state = app_state(ports);

    let result = api::handlers::revoke_settings::<FakePorts>(
        State(state),
        dummy_user(),
        Path(uuid::Uuid::now_v7()),
        Json(VersionRequest {
            version: AggregateVersion(1),
        }),
    )
    .await;

    let problem = result
        .expect_err("denied caller must get an error")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.forbidden");
    assert!(!problem.detail.is_empty());
}

// ---------------------------------------------------------------------------
// Issue #555 — settings credential binding ownership
//
// The credential *role* alone must not authorize touching a binding: the
// caller has to own it (`projection_settings.owner`, recorded once from the
// bind event's `EventMetadata.actor`, issue #552). Without this check any
// credential-role member could read, rotate — and thereby destroy — another
// user's Vault secret. Legacy rows with `owner IS NULL` fail closed exactly
// like foreign rows, so rotation can never be used to claim one.
// ---------------------------------------------------------------------------

/// Seed the caller as an active credential-role member, so the *ownership*
/// check — not the role gate — is what decides the settings handlers.
async fn seed_credential_role(ports: &FakePorts) {
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(USER))
        .await;
}

/// Body of `PATCH /settings/{id}/gdrive`.
fn gdrive_rotation_request() -> api::handlers::GDriveCredentialUpdateRequest {
    api::handlers::GDriveCredentialUpdateRequest {
        bundle: api::handlers::GDriveCredentialRequest {
            client_id: "id".into(),
            client_secret: "secret".into(),
            refresh_token: "token".into(),
            root_folder_id: None,
        },
        version: AggregateVersion(1),
    }
}

#[tokio::test]
async fn get_settings_denies_a_foreign_owner() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    // Active credential-role member, but the binding belongs to somebody else.
    seed_credential_role(&ports).await;
    ports
        .settings_repo
        .seed_gdrive_view(id, Some("someone-else"))
        .await;
    let state = app_state(ports);

    let problem = api::handlers::get_settings::<FakePorts>(State(state), dummy_user(), Path(id))
        .await
        .expect_err("a foreign binding must not be readable")
        .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.binding-forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn get_settings_allows_the_owner() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    seed_credential_role(&ports).await;
    ports.settings_repo.seed_gdrive_view(id, Some(USER)).await;
    let state = app_state(ports);

    let (status, _view) =
        api::handlers::get_settings::<FakePorts>(State(state), dummy_user(), Path(id))
            .await
            .expect("the owner may read their own binding");
    assert_eq!(status, 200);
}

#[tokio::test]
async fn rotate_gdrive_credential_denies_a_foreign_owner() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    seed_credential_role(&ports).await;
    ports
        .settings_repo
        .seed_gdrive_view(id, Some("someone-else"))
        .await;
    let commands = ports.settings_commands.clone();
    let state = app_state(ports);

    let problem = api::handlers::rotate_gdrive_credential::<FakePorts>(
        State(state),
        dummy_user(),
        Path(id),
        Json(gdrive_rotation_request()),
    )
    .await
    .expect_err("a foreign binding must not be rotated")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.binding-forbidden");
    // The denial happens before any Vault write and before the command port:
    // the fake vault is unavailable, so a passing gate would have surfaced
    // `503` instead of `403`.
    assert!(commands.last_rotate.lock().await.is_none());
}

#[tokio::test]
async fn rotate_gdrive_credential_denies_a_legacy_unknown_owner() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    // `owner IS NULL` — a binding that predates the owner column. Fail closed:
    // otherwise rotation would let any credential-role member claim it.
    seed_credential_role(&ports).await;
    ports.settings_repo.seed_gdrive_view(id, None).await;
    let commands = ports.settings_commands.clone();
    let state = app_state(ports);

    let problem = api::handlers::rotate_gdrive_credential::<FakePorts>(
        State(state),
        dummy_user(),
        Path(id),
        Json(gdrive_rotation_request()),
    )
    .await
    .expect_err("a legacy unknown-owner binding must not be rotatable")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.binding-forbidden");
    assert!(commands.last_rotate.lock().await.is_none());
}

#[tokio::test]
async fn revoke_settings_denies_a_foreign_owner() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    seed_credential_role(&ports).await;
    ports
        .settings_repo
        .seed_gdrive_view(id, Some("someone-else"))
        .await;
    let commands = ports.settings_commands.clone();
    let state = app_state(ports);

    let problem = api::handlers::revoke_settings::<FakePorts>(
        State(state),
        dummy_user(),
        Path(id),
        Json(VersionRequest {
            version: AggregateVersion(1),
        }),
    )
    .await
    .expect_err("a foreign binding must not be revoked")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.binding-forbidden");
    assert!(
        commands.revokes.lock().await.is_empty(),
        "the revoke command must never be dispatched for a foreign binding"
    );
}

#[tokio::test]
async fn revoke_settings_denies_a_legacy_unknown_owner() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    seed_credential_role(&ports).await;
    ports.settings_repo.seed_gdrive_view(id, None).await;
    let commands = ports.settings_commands.clone();
    let state = app_state(ports);

    let problem = api::handlers::revoke_settings::<FakePorts>(
        State(state),
        dummy_user(),
        Path(id),
        Json(VersionRequest {
            version: AggregateVersion(1),
        }),
    )
    .await
    .expect_err("a legacy unknown-owner binding must not be revocable")
    .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.binding-forbidden");
    assert!(commands.revokes.lock().await.is_empty());
}

#[tokio::test]
async fn revoke_settings_allows_the_owner() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    seed_credential_role(&ports).await;
    ports.settings_repo.seed_gdrive_view(id, Some(USER)).await;
    *ports.settings_commands.revoke_result.lock().await = Some(Ok(AggregateVersion(2)));
    let commands = ports.settings_commands.clone();
    let state = app_state(ports);

    let (status, _version) = api::handlers::revoke_settings::<FakePorts>(
        State(state),
        dummy_user(),
        Path(id),
        Json(VersionRequest {
            version: AggregateVersion(1),
        }),
    )
    .await
    .expect("the owner may revoke their own binding");

    assert_eq!(status, 200);
    let revokes = commands.revokes.lock().await;
    assert_eq!(revokes.len(), 1);
    // The command must carry the *requested* binding id — a count-only
    // assertion would pass for a revoke of some other binding.
    assert_eq!(revokes[0].id, id);
}

#[tokio::test]
async fn get_settings_denies_a_legacy_unknown_owner() {
    let ports = FakePorts::default();
    let id = Uuid::now_v7();
    seed_credential_role(&ports).await;
    ports.settings_repo.seed_gdrive_view(id, None).await;
    let state = app_state(ports);

    let problem = api::handlers::get_settings::<FakePorts>(State(state), dummy_user(), Path(id))
        .await
        .expect_err("a legacy unknown-owner binding must not be readable")
        .into_problem();

    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "settings.binding-forbidden");
}

// ---------------------------------------------------------------------------
// P2.4 — `series_id_for_*` / `require_*` Audit-Helfer
// ---------------------------------------------------------------------------

#[tokio::test]
async fn get_audit_history_requires_series_id() {
    let ports = FakePorts::default();
    let state = app_state(ports);

    // Omit series_id from query params — require_series should reject.
    let result = api::handlers::get_audit_history::<FakePorts>(
        State(state),
        dummy_user(),
        Query(ListParams {
            limit: None,
            offset: None,
            episode_id: None,
            season_id: None,
            series_id: None,
        }),
    )
    .await;

    let problem = result
        .expect_err("missing series_id must get an error")
        .into_problem();
    assert_eq!(problem.status, 400);
    assert_eq!(problem.code, "http.bad-query-param");
    assert!(!problem.detail.is_empty());
}

// ---------------------------------------------------------------------------
// P2.4b — Series-scoped audit AUTHZ-GATE (issue #342)
// ---------------------------------------------------------------------------

/// Build `ListParams` carrying only a `series_id`.
fn audit_params(sid: SeriesId) -> ListParams {
    ListParams {
        limit: Some(50),
        offset: Some(0),
        episode_id: None,
        season_id: None,
        series_id: Some(sid),
    }
}

/// A caller with **no** active membership in the queried series is denied
/// with 403 — even though they are an active member of *some* block (which is
/// all the middleware can see). This is the gap issue #342 closes.
#[tokio::test]
async fn get_audit_history_denies_caller_without_series_membership() {
    let ports = FakePorts::default();
    *ports
        .membership_repo
        .series_membership_override
        .lock()
        .await = Some(Ok(false));
    let state = app_state(ports);

    let result = api::handlers::get_audit_history::<FakePorts>(
        State(state),
        dummy_user(),
        Query(audit_params(series_id())),
    )
    .await;

    let problem = result
        .expect_err("non-member of the series must be denied")
        .into_problem();
    assert_eq!(problem.status, 403);
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}

/// A repository error must fail closed (deny), never open the journal. Since
/// issue #537 the gate reports the *honest* reason — 500
/// `http.internal-error` — instead of collapsing the outage into a 403 the
/// caller cannot explain (this test previously pinned the 403 — issue #537
/// changes exactly that). The remaining predicate families live in the
/// P2.5 section at the bottom of this file.
#[tokio::test]
async fn get_audit_history_predicate_error_is_500_fail_closed() {
    let ports = FakePorts::default();
    *ports
        .membership_repo
        .series_membership_override
        .lock()
        .await = Some(Err(breakdown_core::error::DomainError::internal("boom")));
    let state = app_state(ports);

    let result = api::handlers::get_audit_history::<FakePorts>(
        State(state),
        dummy_user(),
        Query(audit_params(series_id())),
    )
    .await;

    let problem = result
        .expect_err("a failing membership lookup must deny")
        .into_problem();
    assert_eq!(problem.status, 500);
    assert_eq!(problem.code, "http.internal-error");
    assert!(!problem.detail.is_empty());
}

/// An active member of the series reads the journal of exactly that series.
#[tokio::test]
async fn get_audit_history_returns_series_journal_for_series_member() {
    let ports = FakePorts::default();
    *ports
        .membership_repo
        .series_membership_override
        .lock()
        .await = Some(Ok(true));

    let sid = series_id();
    let other_series = Uuid::now_v7();
    ports
        .audit_repo
        .entries
        .lock()
        .await
        .push(breakdown_core::audit::AuditEntry {
            id: Uuid::now_v7(),
            entity_type: "season".to_string(),
            entity_id: Uuid::now_v7().to_string(),
            event_type: "SeasonCreated".to_string(),
            block_id: None,
            series_id: Some(sid.0),
            actor: Some(breakdown_core::shared::UserId::from_sub(USER)),
            payload: serde_json::json!({ "number": 1 }),
            occurred_at: chrono::Utc::now(),
        });
    // Entry of a foreign series must not leak into the result.
    ports
        .audit_repo
        .entries
        .lock()
        .await
        .push(breakdown_core::audit::AuditEntry {
            id: Uuid::now_v7(),
            entity_type: "season".to_string(),
            entity_id: Uuid::now_v7().to_string(),
            event_type: "SeasonCreated".to_string(),
            block_id: None,
            series_id: Some(other_series),
            actor: Some(breakdown_core::shared::UserId::from_sub("other-user")),
            payload: serde_json::json!({ "number": 2 }),
            occurred_at: chrono::Utc::now(),
        });

    let state = app_state(ports);
    let (status, Json(entries)) = api::handlers::get_audit_history::<FakePorts>(
        State(state),
        dummy_user(),
        Query(audit_params(sid)),
    )
    .await
    .expect("series member must be allowed");

    assert_eq!(status, axum::http::StatusCode::OK);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].series_id, Some(sid.0));
}

// ---------------------------------------------------------------------------
// P2.5 — Upload-Validierung & Variant-Routing
// ---------------------------------------------------------------------------

/// Helper: build a valid jpeg header (first 3 bytes: FF D8 FF).
#[tokio::test]
async fn upload_costume_photo_rejects_payload_too_large() {
    let ports = FakePorts::default();
    let (costume_id, _sid) = seed_costume_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = app_state(ports);

    // Set PHOTO_MAX_SIZE_MB to 1 so we can trigger the rejection easily.
    // Save original value to restore after the test.
    // SAFETY: env vars are process-global; this is safe because tests run
    // single-threaded per binary and we restore the original value afterwards.
    let original = std::env::var_os("PHOTO_MAX_SIZE_MB");
    // ast-grep-ignore: allow-unsafe
    unsafe {
        std::env::set_var("PHOTO_MAX_SIZE_MB", "1");
    }

    let mut headers = axum::http::HeaderMap::new();
    headers.insert("content-type", "image/jpeg".parse().unwrap());
    // 2 MB payload — exceeds the 1 MB limit.
    let big_payload = vec![0u8; 2 * 1024 * 1024];
    let result = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        headers,
        Bytes::from(big_payload),
    )
    .await;

    // Restore the original environment variable value.
    // SAFETY: restoring env var after test.
    // ast-grep-ignore: allow-unsafe
    unsafe {
        match original {
            Some(val) => std::env::set_var("PHOTO_MAX_SIZE_MB", val),
            None => std::env::remove_var("PHOTO_MAX_SIZE_MB"),
        }
    }

    let problem = result
        .expect_err("oversized upload must fail")
        .into_problem();
    assert_eq!(problem.status, 413);
    assert_eq!(problem.code, "http.payload-too-large");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn upload_costume_photo_rejects_wrong_content_type() {
    let ports = FakePorts::default();
    let (costume_id, _sid) = seed_costume_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = app_state(ports);

    let mut headers = axum::http::HeaderMap::new();
    headers.insert("content-type", "text/plain".parse().unwrap());
    let result = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        headers,
        Bytes::from_static(b"hello"),
    )
    .await;

    let problem = result
        .expect_err("wrong content-type must fail")
        .into_problem();
    assert_eq!(problem.status, 415);
    assert_eq!(problem.code, "http.unsupported-media-type");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn upload_costume_photo_rejects_heic_content_type() {
    let ports = FakePorts::default();
    let (costume_id, _sid) = seed_costume_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(true));
    let state = app_state(ports);

    let mut headers = axum::http::HeaderMap::new();
    headers.insert("content-type", "image/heic".parse().unwrap());
    let result = upload_costume_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path(costume_id),
        headers,
        Bytes::from_static(b"heic-data"),
    )
    .await;

    let problem = result
        .expect_err("HEIC content-type must fail")
        .into_problem();
    assert_eq!(problem.status, 415);
    assert_eq!(problem.code, "http.unsupported-media-type");
    assert!(!problem.detail.is_empty());
}

// ---------------------------------------------------------------------------
// P2.5 — Predicate lookup errors are 500, never 403 (issue #537)
// ---------------------------------------------------------------------------

// Since issue #537 every handler-internal membership AUTHZ-GATE routes its
// predicate through `membership_gate`: the gate stays **fail-closed** (an
// error grants nothing), but a projection-store outage surfaces as 500
// `http.internal-error` instead of being swallowed into a 403 no operator
// can trace. One test per predicate family, each also proving that no write
// access is granted on the error path.

/// Production error shape of the membership predicates.
fn predicate_outage() -> breakdown_core::error::DomainError {
    breakdown_core::error::DomainError::internal("projection store outage (issue #537 test)")
}

/// Costume-role family — `unlink_continuity_photo` is a **write**: the fake
/// command port panics (`unreachable!`) when reached, so the test only passes
/// if the gate failed closed *before* dispatch.
#[tokio::test]
async fn unlink_continuity_photo_predicate_error_is_500_fail_closed() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports.membership_repo.costume_role_override.lock().await = Some(Err(predicate_outage()));
    let state = app_state(ports);

    let result = unlink_continuity_photo::<FakePorts>(
        State(state),
        dummy_user(),
        Path((
            sd_id,
            uuid::Uuid::now_v7(),
            scene_shoot_id(),
            PhotoId::new(),
        )),
        Query(VersionRequest {
            version: AggregateVersion(1),
        }),
    )
    .await;

    let problem = result
        .expect_err("a failing predicate must deny")
        .into_problem();
    assert_eq!(problem.status, 500);
    assert_eq!(problem.code, "http.internal-error");
    assert!(!problem.detail.is_empty());
    // Fail-closed proof: the unlink command port must never have been
    // reached — reaching it would panic (`unreachable!` in the fake).
}

// Series-membership family — the audit gate denies, and the journal is not
// opened (covered by
// `get_audit_history_predicate_error_is_500_fail_closed` above).

/// Report-archive-role family — `manual_archive_reports` **writes** to the
/// archival queue: on a predicate error nothing may be enqueued.
#[tokio::test]
async fn manual_archive_reports_predicate_error_is_500_fail_closed() {
    let ports = FakePorts::default();
    let (sd_id, _sid) = seed_shooting_day_chain(&ports).await;
    *ports
        .membership_repo
        .report_archive_role_override
        .lock()
        .await = Some(Err(predicate_outage()));
    // Clone before the state takes ownership: the fake queue is `Arc`-backed,
    // so the clone observes the same job map.
    let queue_jobs = ports.report_archival_queue.jobs.clone();
    let state = app_state(ports);

    let result =
        api::handlers::manual_archive_reports::<FakePorts>(State(state), dummy_user(), Path(sd_id))
            .await;

    let problem = result
        .expect_err("a failing predicate must deny")
        .into_problem();
    assert_eq!(problem.status, 500);
    assert_eq!(problem.code, "http.internal-error");
    assert!(!problem.detail.is_empty());
    assert!(
        queue_jobs.lock().await.is_empty(),
        "fail-closed proof: a predicate error must never enqueue archival work"
    );
}

/// Credential-role family — `revoke_settings` destroys a Vault secret: on a
/// predicate error no revoke may reach the command port.
#[tokio::test]
async fn revoke_settings_predicate_error_is_500_fail_closed() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Err(predicate_outage()));
    let revokes = ports.settings_commands.revokes.clone();
    let state = app_state(ports);

    let result = api::handlers::revoke_settings::<FakePorts>(
        State(state),
        dummy_user(),
        Path(uuid::Uuid::now_v7()),
        Json(VersionRequest {
            version: AggregateVersion(1),
        }),
    )
    .await;

    let problem = result
        .expect_err("a failing predicate must deny")
        .into_problem();
    assert_eq!(problem.status, 500);
    assert_eq!(problem.code, "http.internal-error");
    assert!(!problem.detail.is_empty());
    assert!(
        revokes.lock().await.is_empty(),
        "fail-closed proof: a predicate error must never dispatch a revoke"
    );
}
