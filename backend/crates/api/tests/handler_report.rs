// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use crate::common;
// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

use axum::extract::State;
use std::sync::Arc;

use breakdown_core::membership::Role;
use breakdown_core::reporting::{ReportKind, ReportRenderError};
use breakdown_core::scene_shoot::views::{DispoRow, ShootDayRow};
use breakdown_core::shared::{
    AggregateVersion, BlockId, EpisodeId, LexicalSortKey, ProjectId, SeasonId, ShootingDayId,
    UserId,
};
use breakdown_core::shooting_day::views::ShootingDayView;

use api::auth::CurrentUser;
use api::handlers::{
    dispo_report_pdf, map_render_error, planned_vs_actual_report_pdf, sanitize_pdf_filename,
    shoot_day_report_pdf,
};
use api::state::AppState;
use common::*;

// ---------------------------------------------------------------------------
// sanitize_pdf_filename
// ---------------------------------------------------------------------------

#[test]
fn test_sanitize_pdf_filename_simple() {
    let name = sanitize_pdf_filename("dispo", "de-DE");
    assert_eq!(name, "report-dispo-de-DE.pdf");
}

#[test]
fn test_sanitize_pdf_filename_sanitizes_bad_chars() {
    let name = sanitize_pdf_filename("dispo/../../etc", "de-DE");
    assert_eq!(name, "report-dispoetc-de-DE.pdf");
}

#[test]
fn test_sanitize_pdf_filename_allows_hyphens() {
    let name = sanitize_pdf_filename("shoot-day", "de-DE");
    assert_eq!(name, "report-shoot-day-de-DE.pdf");
}

// ---------------------------------------------------------------------------
// map_render_error
// ---------------------------------------------------------------------------

#[test]
fn test_map_render_error_page_limit() {
    let err = ReportRenderError::PageLimitExceeded {
        max: 50,
        actual: 51,
    };
    let problem = map_render_error(err).into_problem();
    assert_eq!(problem.status, 422);
    assert_eq!(problem.code, "domain.validation");
    assert!(!problem.detail.is_empty());
}

#[test]
fn test_map_render_error_input_bounds() {
    let err = ReportRenderError::InputBoundsExceeded {
        limit: 1000,
        field: "rows".into(),
    };
    let problem = map_render_error(err).into_problem();
    assert_eq!(problem.status, 422);
    assert_eq!(problem.code, "domain.validation");
    assert!(!problem.detail.is_empty());
}

#[test]
fn test_map_render_error_timeout() {
    let err = ReportRenderError::RenderTimeout;
    let problem = map_render_error(err).into_problem();
    // The renderer is the slow party — 504 Gateway Timeout, not 408
    // (which would tell the client to resend its request).
    assert_eq!(problem.status, 504);
    assert_eq!(problem.code, "http.request-timeout");
}

#[test]
fn test_map_render_error_generic() {
    let err = ReportRenderError::CompilerFailure {
        detail: "syntax error".into(),
    };
    let problem = map_render_error(err).into_problem();
    assert_eq!(problem.status, 500);
    // Internal renderer text must never leave the server (ADR-031 decision 6).
    assert_eq!(problem.code, "http.internal-error");
    assert!(!problem.detail.contains("syntax error"));
}

#[test]
fn test_map_render_error_locale_unsupported() {
    let err = ReportRenderError::LocaleUnsupported {
        locale: "xx".into(),
    };
    let problem = map_render_error(err).into_problem();
    assert_eq!(problem.status, 500);
    // Internal renderer text must never leave the server (ADR-031 decision 6).
    assert_eq!(problem.code, "http.internal-error");
    assert!(!problem.detail.contains("xx"));
}

#[test]
fn test_map_render_error_template_not_found() {
    let err = ReportRenderError::TemplateNotFound {
        kind: "dispo".into(),
    };
    let problem = map_render_error(err).into_problem();
    // A missing template is a misconfigured/unavailable renderer, not an
    // internal bug (issue #642): 503 with a distinct code so clients can
    // show an honest "report feature unavailable" message.
    assert_eq!(problem.status, 503);
    assert_eq!(problem.code, "report.renderer-unavailable");
    assert!(!problem.detail.contains("dispo"));
}

// ---------------------------------------------------------------------------
// PDF handler tests — failure paths
// ---------------------------------------------------------------------------

#[tokio::test]
async fn test_dispo_report_pdf_shooting_day_not_found() {
    let state = AppState::new(FakePorts::default());
    let day_id = ShootingDayId::new();
    let user = CurrentUser::dummy("test-user");

    let result = dispo_report_pdf(State(state), user, api::problems::Path(day_id)).await;

    let problem = result
        .expect_err("handler should fail for missing shooting day")
        .into_problem();
    assert_eq!(problem.status, 404);
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn test_shoot_day_report_pdf_shooting_day_not_found() {
    let state = AppState::new(FakePorts::default());
    let day_id = ShootingDayId::new();
    let user = CurrentUser::dummy("test-user");

    let result = shoot_day_report_pdf(State(state), user, api::problems::Path(day_id)).await;

    let problem = result
        .expect_err("handler should fail for missing shooting day")
        .into_problem();
    assert_eq!(problem.status, 404);
    assert!(!problem.detail.is_empty());
}

// ---------------------------------------------------------------------------
// Renderer payload contract — the Typst templates read `data.rows`, so the
// handlers must hand the renderer the `{ rows: [...] }` envelope, never a
// bare JSON array (a bare array fails Typst compilation and surfaces as an
// opaque HTTP 500 on every PDF download; found via the dev stack 2026-10-18).
// ---------------------------------------------------------------------------

/// Seed the full resolution chain of the shoot-day PDF handlers:
/// shooting_day → episode → block (season scope) + an active piece-department
/// membership for `test-user`, plus the (empty) report rows.
async fn seed_pdf_chain(ports: &FakePorts) -> ShootingDayId {
    let season_id = SeasonId::new();
    let project_id = ProjectId::new();
    let block_id = BlockId::new();
    let episode_id = EpisodeId::new();
    let sd_id = ShootingDayId::new();

    ports.block_repo.blocks.lock().await.insert(
        block_id.0,
        breakdown_core::block::views::BlockView {
            id: block_id.0,
            season_id,
            project_id,
            number: 1,
            start_date: None,
            end_date: None,
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    ports.episode_repo.episodes.lock().await.insert(
        episode_id.0,
        breakdown_core::episode::views::EpisodeView {
            id: episode_id.0,
            block_id,
            project_id,
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
            episode_id,
            label: Some("Day 1".into()),
            order_key: LexicalSortKey::from_static("a"),
            date: None,
            source: breakdown_core::shooting_day::events::ShootingDaySource::Manual,
            archived: false,
            wrapped_at: None,
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    ports
        .membership_repo
        .seed_active(
            block_id,
            UserId("test-user".into()),
            Role::CostumeAssistant,
            season_id,
            project_id,
        )
        .await;
    sd_id
}

#[tokio::test]
async fn test_dispo_report_pdf_sends_rows_envelope_to_renderer() {
    let mut ports = FakePorts::default();
    let day_id = seed_pdf_chain(&ports).await;
    *ports.scene_shoot_report_repo.dispo_rows.lock().await = vec![DispoRow {
        planned_order: LexicalSortKey::from_static("a"),
        scene_id: uuid::Uuid::now_v7(),
        scene_number: Some(1),
        script_day: Some("Tag 1".into()),
        location: Some("Studio".into()),
        mood: None,
        summary: None,
    }];
    let renderer = Arc::new(CapturingReportRenderer::default());
    ports.report_renderer = renderer.clone();
    let state = AppState::new(ports);
    let user = CurrentUser::dummy("test-user");

    let result = dispo_report_pdf(State(state), user, api::problems::Path(day_id)).await;

    assert!(result.is_ok(), "handler must succeed: {:?}", result.err());
    let (kind, data) = renderer
        .last
        .lock()
        .await
        .clone()
        .expect("renderer must have been called");
    assert_eq!(kind, ReportKind::Dispo);
    // The template contract: an object with a `rows` array.
    assert!(
        data.get("rows").is_some_and(|rows| rows.is_array()),
        "renderer payload must be the {{ rows: [...] }} envelope, got: {data}"
    );
}

#[tokio::test]
async fn test_shoot_day_report_pdf_sends_rows_envelope_to_renderer() {
    let mut ports = FakePorts::default();
    let day_id = seed_pdf_chain(&ports).await;
    *ports.scene_shoot_report_repo.shoot_day_rows.lock().await = vec![ShootDayRow {
        actual_order: Some(LexicalSortKey::from_static("a")),
        scene_id: uuid::Uuid::now_v7(),
        scene_number: Some(1),
        script_day: Some("Tag 1".into()),
        location: Some("Studio".into()),
        status: breakdown_core::shared::SceneShootStatus::Shot,
        start_dt: None,
        end_dt: None,
        notes: Vec::new(),
        continuity_photo_ids: Vec::new(),
    }];
    let renderer = Arc::new(CapturingReportRenderer::default());
    ports.report_renderer = renderer.clone();
    let state = AppState::new(ports);
    let user = CurrentUser::dummy("test-user");

    let result = shoot_day_report_pdf(State(state), user, api::problems::Path(day_id)).await;

    assert!(result.is_ok(), "handler must succeed: {:?}", result.err());
    let (kind, data) = renderer
        .last
        .lock()
        .await
        .clone()
        .expect("renderer must have been called");
    assert_eq!(kind, ReportKind::ShootDay);
    assert!(
        data.get("rows").is_some_and(|rows| rows.is_array()),
        "renderer payload must be the {{ rows: [...] }} envelope, got: {data}"
    );
}

#[tokio::test]
async fn test_planned_vs_actual_report_pdf_shooting_day_not_found() {
    let state = AppState::new(FakePorts::default());
    let day_id = ShootingDayId::new();
    let user = CurrentUser::dummy("test-user");

    let result =
        planned_vs_actual_report_pdf(State(state), user, api::problems::Path(day_id)).await;

    let problem = result
        .expect_err("handler should fail for missing shooting day")
        .into_problem();
    assert_eq!(problem.status, 404);
    assert!(!problem.detail.is_empty());
}
