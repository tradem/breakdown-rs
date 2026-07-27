// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Unit tests for PDF report handlers.
//!
//! Covers:
//! - `sanitize_pdf_filename` — safe header generation
//! - `map_render_error` — typed error → HTTP response mapping
//! - `dispo_report_pdf` / `shoot_day_report_pdf` / `planned_vs_actual_report_pdf`
//!   — authz gate and response behavior

use axum::http::StatusCode;
use axum::{Json, extract::State};

use breakdown_core::reporting::ReportRenderError;
use breakdown_core::shared::ShootingDayId;

use super::test_helpers::*;
use super::{
    dispo_report_pdf, map_render_error, sanitize_pdf_filename, shoot_day_report_pdf,
    planned_vs_actual_report_pdf,
};
use crate::auth::CurrentUser;
use crate::state::AppState;

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
    let (status, Json(_resp)) = map_render_error(err);
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(_resp.message.contains("50"));
}

#[test]
fn test_map_render_error_input_bounds() {
    let err = ReportRenderError::InputBoundsExceeded {
        limit: 1000,
        field: "rows".into(),
    };
    let (status, Json(_resp)) = map_render_error(err);
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(_resp.message.contains("rows"));
}

#[test]
fn test_map_render_error_timeout() {
    let err = ReportRenderError::RenderTimeout;
    let (status, Json(resp)) = map_render_error(err);
    assert_eq!(status, StatusCode::REQUEST_TIMEOUT);
    assert_eq!(resp.message, "Render timeout");
}

#[test]
fn test_map_render_error_generic() {
    let err = ReportRenderError::CompilerFailure {
        detail: "syntax error".into(),
    };
    let (status, Json(resp)) = map_render_error(err);
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(resp.message.contains("syntax error"));
}

#[test]
fn test_map_render_error_locale_unsupported() {
    let err = ReportRenderError::LocaleUnsupported {
        locale: "xx".into(),
    };
    let (status, Json(_resp)) = map_render_error(err);
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
}

#[test]
fn test_map_render_error_template_not_found() {
    let err = ReportRenderError::TemplateNotFound {
        kind: "dispo".into(),
    };
    let (status, Json(_resp)) = map_render_error(err);
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
}

// ---------------------------------------------------------------------------
// PDF handler tests — failure paths
// ---------------------------------------------------------------------------

#[tokio::test]
async fn test_dispo_report_pdf_shooting_day_not_found() {
    let state = AppState::new(FakePorts::default());
    let day_id = ShootingDayId::new();
    let user = CurrentUser::dummy("test-user");

    let result = dispo_report_pdf(State(state), user, axum::extract::Path(day_id)).await;

    let (status, Json(resp)) = result.expect_err("handler should fail for missing shooting day");
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert!(!resp.message.is_empty());
}

#[tokio::test]
async fn test_shoot_day_report_pdf_shooting_day_not_found() {
    let state = AppState::new(FakePorts::default());
    let day_id = ShootingDayId::new();
    let user = CurrentUser::dummy("test-user");

    let result = shoot_day_report_pdf(State(state), user, axum::extract::Path(day_id)).await;

    let (status, Json(resp)) = result.expect_err("handler should fail for missing shooting day");
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert!(!resp.message.is_empty());
}

#[tokio::test]
async fn test_planned_vs_actual_report_pdf_shooting_day_not_found() {
    let state = AppState::new(FakePorts::default());
    let day_id = ShootingDayId::new();
    let user = CurrentUser::dummy("test-user");

    let result =
        planned_vs_actual_report_pdf(State(state), user, axum::extract::Path(day_id)).await;

    let (status, Json(resp)) = result.expect_err("handler should fail for missing shooting day");
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert!(!resp.message.is_empty());
}
