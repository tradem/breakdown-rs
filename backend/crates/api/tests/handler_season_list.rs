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
//! via `series_id` — unlike the episode/scene lists, no scope parameter is
//! required, so the client's parameterless `fetchSeasonsList()` reconciliation
//! seam confirms a created id regardless of the series it was filed under.

use api::problems::{Json, Query};
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, SeriesId};
use chrono::Utc;
use uuid::Uuid;

use api::handlers::{SeasonListParams, list_seasons};
use api::state::AppState;

mod common;

fn season_view(id: Uuid, series_id: SeriesId, number: i32) -> SeasonView {
    SeasonView {
        id,
        series_id,
        number,
        title: None,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

fn list_params() -> SeasonListParams {
    SeasonListParams {
        limit: Some(50),
        offset: Some(0),
        series_id: None,
    }
}

#[tokio::test]
async fn list_seasons_returns_only_the_queried_series() {
    let ports = common::FakePorts::default();
    let series_a = SeriesId::new();
    let series_b = SeriesId::new();
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
    params.series_id = Some(series_a);

    let result = list_seasons(State(state), Query(params)).await;
    let (status, Json(views)) = result.expect("handler should succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(views.len(), 2);
    assert!(views.iter().all(|v| v.series_id == series_a));
    assert_eq!(views[0].number, 1);
    assert_eq!(views[1].number, 2);
}

#[tokio::test]
async fn list_seasons_without_series_id_returns_all_series() {
    let ports = common::FakePorts::default();
    let series_a = SeriesId::new();
    let series_b = SeriesId::new();
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
        names.contains(&"series_id"),
        "GET /v1/seasons must expose series_id (issue #377), got {names:?}"
    );
    for ignored in ["episode_id", "season_id", "block_id"] {
        assert!(
            !names.contains(&ignored),
            "GET /v1/seasons must not advertise {ignored} (silently ignored, issue #377 review), got {names:?}"
        );
    }
}
