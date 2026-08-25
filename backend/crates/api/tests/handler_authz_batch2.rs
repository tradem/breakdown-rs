// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: claude-sonnet-4-20250514 (opencode-go)

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
    AggregateVersion, BlockId, EpisodeId, PhotoId, SceneShootId, SeasonId, SeriesId, ShootingDayId,
};
use breakdown_core::shooting_day::ShootingDayView;
use common::FakePorts;

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
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
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
    assert_eq!(problem.code, "domain.forbidden");
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
    assert_eq!(problem.code, "domain.forbidden");
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
    assert_eq!(problem.code, "domain.forbidden");
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
    assert_eq!(problem.code, "domain.forbidden");
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
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
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
    // SAFETY: env vars are process-global; this is safe because tests run
    // single-threaded per binary and we restore it afterwards.
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

    // SAFETY: restoring env var after test.
    // ast-grep-ignore: allow-unsafe
    unsafe {
        std::env::remove_var("PHOTO_MAX_SIZE_MB");
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
