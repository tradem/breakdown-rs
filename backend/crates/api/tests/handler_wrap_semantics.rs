// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (pi)

//! Wrap-semantics tests (issue #376).
//!
//! Codified contract: wrapping a shooting day freezes **execution**
//! transitions (start / actual-order / finish / skip / notes → 409
//! `scene-shoot.shooting-day-wrapped`) while **planning (Soll)** stays
//! supported (plan → 201, replan → 200 post-wrap).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

mod common;

use axum::extract::State;
use axum::http::StatusCode;

use api::auth::CurrentUser;
use api::handlers::{
    AddNoteRequest, PlanSceneShootRequest, StartSceneShootRequest, add_scene_shoot_note,
    plan_scene_shoot, start_scene_shoot,
};
use api::problems::{Json, Path};
use api::state::AppState;
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{
    AggregateVersion, EpisodeId, LexicalSortKey, SceneShootId, ShootingDayId,
};
use breakdown_core::shooting_day::ShootingDayView;
use breakdown_core::shooting_day::events::ShootingDaySource;
use common::FakePorts;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

/// Seed a shooting day with the given `wrapped_at` state.
async fn seed_day(
    ports: &FakePorts,
    wrapped_at: Option<chrono::DateTime<chrono::Utc>>,
) -> ShootingDayId {
    let day_id = ShootingDayId::new();
    ports.shooting_day_repo.days.lock().await.insert(
        day_id,
        ShootingDayView {
            id: day_id,
            episode_id: EpisodeId::new(),
            label: Some("Day 1".into()),
            order_key: LexicalSortKey::from_static("a"),
            date: None,
            source: ShootingDaySource::Manual,
            archived: false,
            wrapped_at,
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    day_id
}

/// Seed a scene (plus its episode) so the plan handler can resolve
/// `series_id` at the API edge. Returns `(scene_id,)`.
async fn seed_scene_with_episode(ports: &FakePorts) -> Uuid {
    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    ports.episode_repo.episodes.lock().await.insert(
        episode_id.0,
        EpisodeView {
            id: episode_id.0,
            block_id: breakdown_core::shared::BlockId::new(),
            series_id: breakdown_core::shared::SeriesId::new(),
            number: 1,
            name: Some("Episode 1".into()),
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    ports.scene_repo.scenes.lock().await.insert(
        scene_id,
        SceneView {
            id: scene_id,
            episode_id,
            scene_number: None,
            location: None,
            mood: None,
            is_schedule_set: false,
            summary: None,
            script_day: None,
            shooting_day_ids: Vec::new(),
            assigned_characters: Vec::new(),
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    scene_id
}

// ---------------------------------------------------------------------------
// Planning stays supported on a wrapped day
// ---------------------------------------------------------------------------

#[tokio::test]
async fn wrap_then_plan_returns_201() {
    let ports = FakePorts::default();
    let day = seed_day(&ports, Some(chrono::Utc::now())).await;
    let scene = seed_scene_with_episode(&ports).await;
    let state = AppState::new(ports);

    let result = plan_scene_shoot::<FakePorts>(
        State(state),
        dummy_user(),
        Path((day, scene)),
        Json(PlanSceneShootRequest {
            planned_order: LexicalSortKey::from_static("m"),
        }),
    )
    .await;

    let (status, Json(body)) = result.expect("plan must succeed on a wrapped day");
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body.version, AggregateVersion::INITIAL.next());
}

// ---------------------------------------------------------------------------
// Execution is frozen on a wrapped day
// ---------------------------------------------------------------------------

#[tokio::test]
async fn wrap_then_start_returns_409_shooting_day_wrapped() {
    let ports = FakePorts::default();
    let day = seed_day(&ports, Some(chrono::Utc::now())).await;
    let state = AppState::new(ports);

    let problem = start_scene_shoot::<FakePorts>(
        State(state),
        dummy_user(),
        Path((day, Uuid::now_v7(), SceneShootId::new())),
        Json(StartSceneShootRequest {
            start_dt: None,
            version: AggregateVersion(1),
        }),
    )
    .await
    .expect_err("start must be frozen on a wrapped day")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "scene-shoot.shooting-day-wrapped");
    assert!(!problem.detail.is_empty());
    // S0 extension: the shooting day id echoes the request path parameter.
    let ext = problem.extensions.expect("extension must be present");
    assert_eq!(
        ext.get("shooting_day_id"),
        Some(&serde_json::Value::String(day.0.to_string()))
    );
}

#[tokio::test]
async fn wrap_then_add_note_returns_409_shooting_day_wrapped() {
    let ports = FakePorts::default();
    let day = seed_day(&ports, Some(chrono::Utc::now())).await;
    let state = AppState::new(ports);

    let problem = add_scene_shoot_note::<FakePorts>(
        State(state),
        dummy_user(),
        Path((day, Uuid::now_v7(), SceneShootId::new())),
        Json(AddNoteRequest {
            body: "note".into(),
            note_id: None,
        }),
    )
    .await
    .expect_err("notes must be frozen on a wrapped day")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "scene-shoot.shooting-day-wrapped");
}

// ---------------------------------------------------------------------------
// The freeze keys on `wrapped_at`, not on day existence
// ---------------------------------------------------------------------------

#[tokio::test]
async fn start_on_open_day_is_not_blocked_by_the_wrap_gate() {
    let ports = FakePorts::default();
    let day = seed_day(&ports, None).await;
    let state = AppState::new(ports);

    let problem = start_scene_shoot::<FakePorts>(
        State(state),
        dummy_user(),
        Path((day, Uuid::now_v7(), SceneShootId::new())),
        Json(StartSceneShootRequest {
            start_dt: None,
            version: AggregateVersion(1),
        }),
    )
    .await
    .expect_err("scene shoot projection is absent → not-found")
    .into_problem();

    // The gate passed (day is open); the failure comes from the missing
    // scene-shoot projection downstream — NOT the wrapped-day freeze.
    assert_eq!(problem.status, 404);
    assert_ne!(problem.code, "scene-shoot.shooting-day-wrapped");
}
