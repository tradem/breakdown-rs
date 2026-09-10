// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

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
use breakdown_core::scene_shoot::views::SceneShootView;
use breakdown_core::shared::{
    AggregateVersion, EpisodeId, LexicalSortKey, SceneShootId, SceneShootStatus, ShootingDayId,
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

/// Seed a scene-shoot projection associated with the given day (and scene,
/// so `series_id` resolution at the API edge succeeds).
async fn seed_scene_shoot(
    ports: &FakePorts,
    shoot_id: SceneShootId,
    scene_id: Uuid,
    day_id: ShootingDayId,
) {
    ports.scene_shoot_repo.shoots.lock().await.insert(
        shoot_id,
        SceneShootView {
            id: shoot_id,
            scene_id,
            shooting_day_id: day_id,
            planned_order: LexicalSortKey::from_static("m"),
            actual_order: None,
            status: SceneShootStatus::Planned,
            start_dt: None,
            end_dt: None,
            notes: Vec::new(),
            continuity_photo_ids: Vec::new(),
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
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

/// Issue #404: planning a *second* scene shoot for the same
/// (scene_id, shooting_day_id) pair under a fresh stream id is rejected with
/// a clean 409 at the API edge — before dispatch — instead of the old 2xx
/// whose `SceneShootPlanned` event becomes a projector-killing poison event.
#[tokio::test]
async fn plan_returns_409_when_pair_already_projected() {
    let ports = FakePorts::default();
    let day = seed_day(&ports, None).await;
    let scene = seed_scene_with_episode(&ports).await;
    // Existing shoot for the same pair under a *different* stream id.
    seed_scene_shoot(&ports, SceneShootId::new(), scene, day).await;
    let state = AppState::new(ports);

    let problem = plan_scene_shoot::<FakePorts>(
        State(state),
        dummy_user(),
        Path((day, scene)),
        Json(PlanSceneShootRequest {
            planned_order: LexicalSortKey::from_static("m"),
        }),
    )
    .await
    .expect_err("a duplicate pair must be rejected at the API edge")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "scene-shoot.pair-already-exists");
}

// ---------------------------------------------------------------------------
// Execution is frozen on a wrapped day
// ---------------------------------------------------------------------------

#[tokio::test]
async fn wrap_then_start_returns_409_shooting_day_wrapped() {
    let ports = FakePorts::default();
    let day = seed_day(&ports, Some(chrono::Utc::now())).await;
    let scene = seed_scene_with_episode(&ports).await;
    let shoot = SceneShootId::new();
    seed_scene_shoot(&ports, shoot, scene, day).await;
    let state = AppState::new(ports);

    let problem = start_scene_shoot::<FakePorts>(
        State(state),
        dummy_user(),
        Path((day, Uuid::now_v7(), shoot)),
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
    let scene = seed_scene_with_episode(&ports).await;
    let shoot = SceneShootId::new();
    seed_scene_shoot(&ports, shoot, scene, day).await;
    let state = AppState::new(ports);

    let problem = add_scene_shoot_note::<FakePorts>(
        State(state),
        dummy_user(),
        Path((day, Uuid::now_v7(), shoot)),
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

    // The failure comes from the missing scene-shoot projection — NOT the
    // wrapped-day freeze. (The association load precedes the wrap gate; on
    // an open day no wrapped problem could have fired anyway.)
    assert_eq!(problem.status, 404);
    assert_ne!(problem.code, "scene-shoot.shooting-day-wrapped");
}

// ---------------------------------------------------------------------------
// Route `day_id` must match the SceneShoot association (PR #389 review)
// ---------------------------------------------------------------------------

/// A wrapped-day scene shoot cannot be mutated through an unrelated **open**
/// day: the wrap freeze cannot be bypassed by addressing the globally unique
/// `shoot_id` via a mismatched route `day_id`.
#[tokio::test]
async fn execution_via_unrelated_open_day_cannot_bypass_wrap_freeze() {
    let ports = FakePorts::default();
    let wrapped_day = seed_day(&ports, Some(chrono::Utc::now())).await;
    let open_day = seed_day(&ports, None).await;
    let shoot = SceneShootId::new();
    seed_scene_shoot(&ports, shoot, Uuid::now_v7(), wrapped_day).await;
    let state = AppState::new(ports);

    let problem = start_scene_shoot::<FakePorts>(
        State(state),
        dummy_user(),
        Path((open_day, Uuid::now_v7(), shoot)),
        Json(StartSceneShootRequest {
            start_dt: None,
            version: AggregateVersion(1),
        }),
    )
    .await
    .expect_err("mismatched route day must not bypass the wrap freeze")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "domain.not-found");
    assert_ne!(problem.code, "scene-shoot.shooting-day-wrapped");
}

/// An open-day scene shoot addressed through an unrelated **wrapped** day is
/// rejected with 404 (route mismatch), not a spurious 409 wrap freeze.
#[tokio::test]
async fn execution_via_unrelated_wrapped_day_returns_404_not_spurious_409() {
    let ports = FakePorts::default();
    let wrapped_day = seed_day(&ports, Some(chrono::Utc::now())).await;
    let open_day = seed_day(&ports, None).await;
    let shoot = SceneShootId::new();
    seed_scene_shoot(&ports, shoot, Uuid::now_v7(), open_day).await;
    let state = AppState::new(ports);

    let problem = start_scene_shoot::<FakePorts>(
        State(state),
        dummy_user(),
        Path((wrapped_day, Uuid::now_v7(), shoot)),
        Json(StartSceneShootRequest {
            start_dt: None,
            version: AggregateVersion(1),
        }),
    )
    .await
    .expect_err("mismatched route day must be rejected as a routing error")
    .into_problem();

    assert_eq!(problem.status, 404);
    assert_eq!(problem.code, "domain.not-found");
}
