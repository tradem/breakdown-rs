#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod common;
// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

use axum::extract::State;

use breakdown_core::reporting::ReportRenderError;
use breakdown_core::shared::ShootingDayId;

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
    assert_eq!(problem.status, 408);
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
}

#[test]
fn test_map_render_error_template_not_found() {
    let err = ReportRenderError::TemplateNotFound {
        kind: "dispo".into(),
    };
    let problem = map_render_error(err).into_problem();
    assert_eq!(problem.status, 500);
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
