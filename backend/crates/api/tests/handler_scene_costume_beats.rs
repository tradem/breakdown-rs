// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

//! Handler tests for the scene costume-beat routes (issue #546):
//! `POST /v1/scenes/{id}/costumes`,
//! `PATCH /v1/scenes/{id}/costumes/{character_id}/{order}`,
//! `DELETE /v1/scenes/{id}/costumes/{character_id}/{order}`,
//! `DELETE /v1/scenes/{id}/costumes/{character_id}`.
//!
//! The aggregate-level invariants are covered by the `core` tests
//! (`scene_aggregate.rs`); this file pins the HTTP surface: 200 echo, the
//! 404 audit-resolution gate (`series_id_for_scene`), and the 422
//! problem-code mapping of the new aggregate errors.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use axum::extract::State;
use chrono::Utc;
use uuid::Uuid;

use api::auth::CurrentUser;
use api::handlers::{
    AddSceneCostumeBeatRequest, UpdateSceneCostumeBeatRequest, VersionRequest,
    add_scene_costume_beat, clear_scene_costume_beats, remove_scene_costume_beat,
    update_scene_costume_beat,
};
use api::problems::{Json, Path, Query};
use api::state::AppState;
use breakdown_core::error::DomainError;
use breakdown_core::error_registry::SCENE_CHARACTER_NOT_IN_SCENE;
use breakdown_core::scene::events::SceneSource;
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{AggregateVersion, EpisodeId};

mod common;

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy("test-user")
}

async fn seed_scene(ports: &common::FakePorts, scene_id: Uuid) {
    ports.scene_repo.scenes.lock().await.insert(
        scene_id,
        SceneView {
            id: scene_id,
            episode_id: EpisodeId::from_uuid(Uuid::now_v7()),
            scene_number: Some(3),
            location: None,
            mood: None,
            is_schedule_set: false,
            summary: None,
            script_day: None,
            shooting_day_ids: Vec::new(),
            assigned_characters: Vec::new(),
            costume_beats: Vec::new(),
            source: Some(SceneSource::Manual),
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
}

#[tokio::test]
async fn add_scene_costume_beat_returns_200_version() {
    let ports = common::FakePorts::default();
    let scene_id = Uuid::now_v7();
    seed_scene(&ports, scene_id).await;
    let state = AppState::new(ports);

    let result = add_scene_costume_beat::<common::FakePorts>(
        State(state),
        dummy_user(),
        Path(scene_id),
        Json(AddSceneCostumeBeatRequest {
            character_id: Uuid::now_v7(),
            costume_id: Uuid::now_v7(),
            note: Some("Mantel".into()),
            version: AggregateVersion::INITIAL,
        }),
    )
    .await;

    let (status, Json(version)) = result.expect("handler should succeed");
    assert_eq!(status, axum::http::StatusCode::OK);
    assert_eq!(version, AggregateVersion::INITIAL.next());
}

#[tokio::test]
async fn add_scene_costume_beat_unknown_scene_is_404_scene_not_found() {
    // The audit resolution (`series_id_for_scene`) runs before dispatch: an
    // unknown scene must not reach the aggregate.
    let state = AppState::new(common::FakePorts::default());

    let problem = add_scene_costume_beat::<common::FakePorts>(
        State(state),
        dummy_user(),
        Path(Uuid::now_v7()),
        Json(AddSceneCostumeBeatRequest {
            character_id: Uuid::now_v7(),
            costume_id: Uuid::now_v7(),
            note: None,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("unknown scene must not dispatch")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "scene.not-found");
}

#[tokio::test]
async fn add_scene_costume_beat_character_not_in_scene_is_422_registered_code() {
    let ports = common::FakePorts::default();
    let scene_id = Uuid::now_v7();
    seed_scene(&ports, scene_id).await;
    let stranger = Uuid::now_v7();
    ports
        .scene_commands
        .fail_next_beat(DomainError::Validation {
            code: &SCENE_CHARACTER_NOT_IN_SCENE,
            reason: format!("character {stranger} is not assigned to this scene"),
        })
        .await;
    let state = AppState::new(ports);

    let problem = add_scene_costume_beat::<common::FakePorts>(
        State(state),
        dummy_user(),
        Path(scene_id),
        Json(AddSceneCostumeBeatRequest {
            character_id: stranger,
            costume_id: Uuid::now_v7(),
            note: None,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await
    .expect_err("injected failure must surface")
    .into_problem();

    assert_eq!(problem.status, 422);
    assert_eq!(problem.code, "scene.character-not-in-scene");
}

#[tokio::test]
async fn update_scene_costume_beat_returns_200_version() {
    let ports = common::FakePorts::default();
    let scene_id = Uuid::now_v7();
    seed_scene(&ports, scene_id).await;
    let state = AppState::new(ports);

    let result = update_scene_costume_beat::<common::FakePorts>(
        State(state),
        dummy_user(),
        Path((scene_id, Uuid::now_v7(), 1u32)),
        Json(UpdateSceneCostumeBeatRequest {
            costume_id: Uuid::now_v7(),
            note: None,
            version: AggregateVersion::INITIAL,
        }),
    )
    .await;

    let (status, Json(version)) = result.expect("handler should succeed");
    assert_eq!(status, axum::http::StatusCode::OK);
    assert_eq!(version, AggregateVersion::INITIAL.next());
}

#[tokio::test]
async fn remove_scene_costume_beat_returns_200_version() {
    let ports = common::FakePorts::default();
    let scene_id = Uuid::now_v7();
    seed_scene(&ports, scene_id).await;
    let state = AppState::new(ports);

    let result = remove_scene_costume_beat::<common::FakePorts>(
        State(state),
        dummy_user(),
        Path((scene_id, Uuid::now_v7(), 0u32)),
        Query(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await;

    let (status, Json(version)) = result.expect("handler should succeed");
    assert_eq!(status, axum::http::StatusCode::OK);
    assert_eq!(version, AggregateVersion::INITIAL.next());
}

#[tokio::test]
async fn clear_scene_costume_beats_returns_200_version() {
    let ports = common::FakePorts::default();
    let scene_id = Uuid::now_v7();
    seed_scene(&ports, scene_id).await;
    let state = AppState::new(ports);

    let result = clear_scene_costume_beats::<common::FakePorts>(
        State(state),
        dummy_user(),
        Path((scene_id, Uuid::now_v7())),
        Query(VersionRequest {
            version: AggregateVersion::INITIAL,
        }),
    )
    .await;

    let (status, Json(version)) = result.expect("handler should succeed");
    assert_eq!(status, axum::http::StatusCode::OK);
    assert_eq!(version, AggregateVersion::INITIAL.next());
}
