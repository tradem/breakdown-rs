// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Integration tests for `GET /seasons` (issue #377).
//!
//! The seasons list returns every season, optionally narrowed to one series
//! via `project_id` — unlike the episode/scene lists, no scope parameter is
//! required, so the client's parameterless `fetchSeasonsList()` reconciliation
//! seam confirms a created id regardless of the series it was filed under.

use api::problems::{Json, Query};
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use chrono::Utc;
use uuid::Uuid;

use api::handlers::{SeasonListParams, list_seasons};
use api::state::AppState;

mod common;

fn season_view(id: Uuid, project_id: ProjectId, number: i32) -> SeasonView {
    season_view_archived(id, project_id, number, false)
}

fn season_view_archived(
    id: Uuid,
    project_id: ProjectId,
    number: i32,
    archived: bool,
) -> SeasonView {
    SeasonView {
        id,
        project_id,
        number,
        title: None,
        archived,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

fn list_params() -> SeasonListParams {
    SeasonListParams {
        limit: Some(50),
        offset: Some(0),
        project_id: None,
        include_archived: None,
    }
}

#[tokio::test]
async fn list_seasons_returns_only_the_queried_series() {
    let ports = common::FakePorts::default();
    let series_a = ProjectId::new();
    let series_b = ProjectId::new();
    {
        let mut seasons = ports.season_repo.seasons.lock().await;
        let id = Uuid::now_v7();
        seasons.insert(id, season_view(id, series_a, 2));
        let id = Uuid::now_v7();
        seasons.insert(id, season_view(id, series_a, 1));
        let id = Uuid::now_v7();
        seasons.insert(id, season_view(id, series_b, 1));
    }
    let state = AppState::new(ports);
    let mut params = list_params();
    params.project_id = Some(series_a);

    let result = list_seasons(State(state), Query(params)).await;
    let (status, Json(views)) = result.expect("handler should succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(views.len(), 2);
    assert!(views.iter().all(|v| v.project_id == series_a));
    assert_eq!(views[0].number, 1);
    assert_eq!(views[1].number, 2);
}

// Issue #533: archived seasons hidden by default, opt-in `include_archived`
// returns them.
#[tokio::test]
async fn list_seasons_hides_archived_by_default_and_returns_them_on_opt_in() {
    let ports = common::FakePorts::default();
    let series = ProjectId::new();
    {
        let mut seasons = ports.season_repo.seasons.lock().await;
        let id = Uuid::now_v7();
        seasons.insert(id, season_view(id, series, 1));
        let id = Uuid::now_v7();
        seasons.insert(id, season_view_archived(id, series, 2, true));
    }
    let state = AppState::new(ports);

    let result = list_seasons(State(state.clone()), Query(list_params())).await;
    let (status, Json(views)) = result.expect("handler should succeed");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(views.len(), 1, "archived season must be hidden by default");
    assert!(views.iter().all(|v| !v.archived));

    let mut opt_in = list_params();
    opt_in.include_archived = Some(true);
    let result = list_seasons(State(state), Query(opt_in)).await;
    let (status, Json(views)) = result.expect("handler should succeed");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(views.len(), 2, "opt-in must return the archived season too");
    assert!(views.iter().any(|v| v.archived));
}

#[tokio::test]
async fn list_seasons_without_project_id_returns_all_projects() {
    let ports = common::FakePorts::default();
    let series_a = ProjectId::new();
    let series_b = ProjectId::new();
    {
        let mut seasons = ports.season_repo.seasons.lock().await;
        let id = Uuid::now_v7();
        seasons.insert(id, season_view(id, series_a, 1));
        let id = Uuid::now_v7();
        seasons.insert(id, season_view(id, series_b, 1));
    }
    let state = AppState::new(ports);

    let result = list_seasons(State(state), Query(list_params())).await;
    let (status, Json(views)) = result.expect("handler should succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(views.len(), 2);
}

#[tokio::test]
async fn list_seasons_rejects_negative_pagination() {
    for params in [
        SeasonListParams {
            limit: Some(-1),
            offset: Some(0),
            project_id: None,
            include_archived: None,
        },
        SeasonListParams {
            limit: Some(50),
            offset: Some(-5),
            project_id: None,
            include_archived: None,
        },
    ] {
        let state = AppState::new(common::FakePorts::default());
        let problem = list_seasons(State(state), Query(params))
            .await
            .expect_err("negative pagination must get an error")
            .into_problem();
        assert_eq!(problem.status, 400);
        assert_eq!(problem.code, "http.bad-query-param");
        assert!(!problem.detail.is_empty());
    }
}

#[test]
fn openapi_doc_exposes_seasons_list() {
    let json = serde_json::to_value(api::api_doc()).expect("ApiDoc serializes to JSON");
    let get = &json["paths"]["/v1/seasons"]["get"];
    assert_eq!(
        get["operationId"].as_str(),
        Some("list_seasons"),
        "GET /v1/seasons must be list_seasons (issue #377)"
    );
    let names: Vec<&str> = get["parameters"]
        .as_array()
        .expect("seasons list has parameters")
        .iter()
        .filter_map(|p| p.get("name").and_then(serde_json::Value::as_str))
        .collect();
    assert!(
        names.contains(&"project_id"),
        "GET /v1/seasons must expose project_id (issue #377; renamed from series_id in issue #599), got {names:?}"
    );
    for ignored in ["episode_id", "season_id", "block_id"] {
        assert!(
            !names.contains(&ignored),
            "GET /v1/seasons must not advertise {ignored} (silently ignored, issue #377 review), got {names:?}"
        );
    }
    let responses = &get["responses"];
    for status in ["400", "409"] {
        assert_eq!(
            responses[status]["content"]["application/problem+json"]["schema"]["$ref"].as_str(),
            Some("#/components/schemas/ProblemDetails"),
            "GET /v1/seasons must document {status} as ProblemDetails (issue #377 review)"
        );
    }
}
