// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use api::problems::{Json, Query};
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::shared::{AggregateVersion, BlockId, SeriesId};
use chrono::Utc;
use uuid::Uuid;

use api::handlers::{EpisodeListParams, list_episodes};
use api::state::AppState;

mod common;

fn episode_view(id: Uuid, block_id: BlockId, series_id: SeriesId, number: i32) -> EpisodeView {
    EpisodeView {
        id,
        block_id,
        series_id,
        number,
        name: None,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

fn list_params() -> EpisodeListParams {
    EpisodeListParams {
        limit: Some(50),
        offset: Some(0),
        series_id: None,
        block_id: None,
    }
}

#[tokio::test]
async fn list_episodes_filters_by_block_id_without_series_id() {
    let ports = common::FakePorts::default();
    let series_id = SeriesId::new();
    let block_a = BlockId::new();
    let block_b = BlockId::new();
    {
        let mut episodes = ports.episode_repo.episodes.lock().await;
        episodes.insert(
            Uuid::now_v7(),
            episode_view(Uuid::now_v7(), block_a, series_id, 1),
        );
        episodes.insert(
            Uuid::now_v7(),
            episode_view(Uuid::now_v7(), block_a, series_id, 2),
        );
        episodes.insert(
            Uuid::now_v7(),
            episode_view(Uuid::now_v7(), block_b, series_id, 3),
        );
    }
    let state = AppState::new(ports);
    let mut params = list_params();
    params.block_id = Some(block_a);

    let result = list_episodes(State(state), Query(params)).await;
    let (status, Json(views)) = result.expect("handler should succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(views.len(), 2);
    assert!(views.iter().all(|v| v.block_id == block_a));
}

#[tokio::test]
async fn list_episodes_by_series_still_returns_whole_series() {
    let ports = common::FakePorts::default();
    let series_id = SeriesId::new();
    {
        let mut episodes = ports.episode_repo.episodes.lock().await;
        episodes.insert(
            Uuid::now_v7(),
            episode_view(Uuid::now_v7(), BlockId::new(), series_id, 1),
        );
        episodes.insert(
            Uuid::now_v7(),
            episode_view(Uuid::now_v7(), BlockId::new(), series_id, 2),
        );
    }
    let state = AppState::new(ports);
    let mut params = list_params();
    params.series_id = Some(series_id);

    let result = list_episodes(State(state), Query(params)).await;
    let (status, Json(views)) = result.expect("handler should succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(views.len(), 2);
}

#[tokio::test]
async fn list_episodes_without_any_scope_is_rejected() {
    let state = AppState::new(common::FakePorts::default());

    let result = list_episodes(State(state), Query(list_params())).await;
    let problem = result
        .expect_err("missing scope must get an error")
        .into_problem();

    assert_eq!(problem.status, 400);
    assert_eq!(problem.code, "http.bad-query-param");
    assert!(!problem.detail.is_empty());
}

#[test]
fn openapi_doc_exposes_block_id_on_episode_list() {
    let json = serde_json::to_value(api::api_doc()).expect("ApiDoc serializes to JSON");
    let params = &json["paths"]["/v1/episodes"]["get"]["parameters"];
    let names: Vec<&str> = params
        .as_array()
        .expect("episode list has parameters")
        .iter()
        .filter_map(|p| p.get("name").and_then(serde_json::Value::as_str))
        .collect();
    assert!(
        names.contains(&"block_id"),
        "GET /v1/episodes must expose block_id (issue #335), got {names:?}"
    );
}

/// `block_id` is consumed only by `list_episodes`: sibling list operations
/// must not advertise a filter they ignore (issue #335 review).
#[test]
fn openapi_doc_hides_block_id_on_sibling_lists() {
    let json = serde_json::to_value(api::api_doc()).expect("ApiDoc serializes to JSON");
    for path in [
        "/v1/audit",
        "/v1/blocks",
        "/v1/blocks/{id}/audit",
        "/v1/blocks/{id}/members",
        "/v1/characters",
        "/v1/costumes",
        "/v1/scenes",
    ] {
        let params = &json["paths"][path]["get"]["parameters"];
        let names: Vec<&str> = params
            .as_array()
            .unwrap_or_else(|| panic!("{path} has no parameters"))
            .iter()
            .filter_map(|p| p.get("name").and_then(serde_json::Value::as_str))
            .collect();
        assert!(
            !names.contains(&"block_id"),
            "GET {path} must not expose block_id (issue #335 review), got {names:?}"
        );
    }
}
