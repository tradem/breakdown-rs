// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::scene::events::SceneDetails;
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{AggregateVersion, EpisodeId};
use chrono::Utc;
use uuid::Uuid;

use super::test_helpers::*;
use crate::handlers::{CreateSceneRequest, create_scene, get_scene};
use crate::state::AppState;

#[tokio::test]
async fn create_scene_returns_201_with_id_and_version() {
    let state = AppState::new(FakePorts::default());
    let req = CreateSceneRequest {
        episode_id: EpisodeId::new(),
        details: SceneDetails::default(),
    };

    let result = create_scene(State(state), Json(req)).await;
    let (status, Json(body)) = result.expect("handler should succeed");

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body.version, AggregateVersion::INITIAL);
    assert_eq!(body.id.get_version(), Some(uuid::Version::SortRand));
}

#[tokio::test]
async fn get_scene_returns_view_from_repo() {
    let ports = FakePorts::default();
    let scene_id = Uuid::now_v7();
    let view = SceneView {
        id: scene_id,
        episode_id: EpisodeId::new(),
        scene_number: None,
        location: None,
        mood: None,
        is_schedule_set: false,
        assigned_characters: Vec::new(),
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    };
    ports
        .scene_repo
        .scenes
        .lock()
        .await
        .insert(scene_id, view.clone());
    let state = AppState::new(ports);

    let result = get_scene(State(state), axum::extract::Path(scene_id)).await;
    let (status, Json(body)) = result.expect("handler should succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.id, scene_id);
}

#[tokio::test]
async fn get_scene_returns_404_when_missing() {
    let state = AppState::new(FakePorts::default());

    let result = get_scene(State(state), axum::extract::Path(Uuid::now_v7())).await;
    let (status, Json(body)) = result.expect_err("handler should fail");

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert!(!body.message.is_empty());
}
