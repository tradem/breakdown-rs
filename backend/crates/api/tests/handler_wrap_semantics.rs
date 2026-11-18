// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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

use api::auth::CurrentUser;
use api::handlers::{
    AddNoteRequest, FinishSceneShootRequest, PlanSceneShootRequest, StartSceneShootRequest,
    add_scene_shoot_note, plan_scene_shoot, start_scene_shoot,
};
use api::problems::{Json, Path};
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::scene::events::SceneSource;
use breakdown_core::scene::views::SceneView;
use breakdown_core::scene_shoot::views::SceneShootView;
use breakdown_core::shared::{
    AggregateVersion, EpisodeId, LexicalSortKey, SceneShootId, SceneShootStatus, ShootingDayId,
};
use breakdown_core::shooting_day::ShootingDayView;
use breakdown_core::shooting_day::events::ShootingDaySource;
use common::FakePorts;
use uuid::Uuid;

use crate::common;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

/// Seed a shooting day with the given `wrapped_at` state.
async fn seed_day(ports: &FakePorts, wrapped_at: Option<jiff::Timestamp>) -> ShootingDayId {
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
            updated_at: jiff::Timestamp::now(),
        },
    );
    day_id
}

/// Seed a scene (plus its episode) so the plan handler can resolve
/// `project_id` at the API edge. Returns `(scene_id,)`.
async fn seed_scene_with_episode(ports: &FakePorts) -> Uuid {
    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    ports.episode_repo.episodes.lock().await.insert(
        episode_id.0,
        EpisodeView {
            id: episode_id.0,
            block_id: breakdown_core::shared::BlockId::new(),
            project_id: breakdown_core::shared::ProjectId::new(),
            number: 1,
            name: Some("Episode 1".into()),
            version: AggregateVersion::INITIAL,
            updated_at: jiff::Timestamp::now(),
        },
    );
    ports.scene_repo.scenes.lock().await.insert(
        scene_id,
        SceneView {
            scene_score: None,
            synopsis_score: None,
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
            outfit_beats: Vec::new(),
            version: AggregateVersion::INITIAL,
            updated_at: jiff::Timestamp::now(),
            source: Some(SceneSource::Manual),
        },
    );
    scene_id
}

/// Seed a scene-shoot projection associated with the given day (and scene,
/// so `project_id` resolution at the API edge succeeds).
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
            updated_at: jiff::Timestamp::now(),
        },
    );
}

// ---------------------------------------------------------------------------
// Planning stays supported on a wrapped day
// ---------------------------------------------------------------------------

#[tokio::test]
async fn wrap_then_plan_returns_201() {
    let ports = FakePorts::default();
    let day = seed_day(&ports, Some(jiff::Timestamp::now())).await;
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
    let day = seed_day(&ports, Some(jiff::Timestamp::now())).await;
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
    let day = seed_day(&ports, Some(jiff::Timestamp::now())).await;
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
    let wrapped_day = seed_day(&ports, Some(jiff::Timestamp::now())).await;
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
    let wrapped_day = seed_day(&ports, Some(jiff::Timestamp::now())).await;
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

/// The request timestamps of the scene-shoot transitions are absolute instants
/// on the aggregate, and `format: date-time` in `openapi.yaml` promises RFC 3339.
/// Both spellings — the canonical `Z` instant the generated Flutter client
/// emits and a numeric `±HH:MM` offset — must therefore resolve to the same UTC
/// instant, and an out-of-range value must be a 422, never a silent
/// `Timestamp::now()` fallback (ADR-040).
#[test]
fn scene_shoot_requests_parse_rfc3339_offsets_and_naive_utc_without_silent_fallback() {
    let expected_utc: jiff::Timestamp = "2026-11-17T08:30:00Z".parse().expect("valid instant");

    // 1. Omitted and explicit null both deserialize to None.
    let omitted: StartSceneShootRequest =
        serde_json::from_str(r#"{"version":1}"#).expect("omitted start_dt");
    assert_eq!(omitted.start_dt, None);
    let explicit_null: FinishSceneShootRequest =
        serde_json::from_str(r#"{"end_dt":null,"version":1}"#).expect("null end_dt");
    assert_eq!(explicit_null.end_dt, None);

    // 2. Canonical Z instant (emitted by the generated Flutter client) works.
    let zulu: StartSceneShootRequest =
        serde_json::from_str(r#"{"start_dt":"2026-11-17T08:30:00Z","version":1}"#)
            .expect("Z instant must parse");
    assert_eq!(zulu.start_dt, Some(expected_utc));

    // 3. Numeric offset is converted to UTC (10:30+02:00 == 08:30Z), never stripped.
    let offset: StartSceneShootRequest =
        serde_json::from_str(r#"{"start_dt":"2026-11-17T10:30:00+02:00","version":1}"#)
            .expect("+02:00 instant must parse");
    assert_eq!(offset.start_dt, Some(expected_utc));
    let finish_offset: FinishSceneShootRequest =
        serde_json::from_str(r#"{"end_dt":"2026-11-17T10:30:00+02:00","version":2}"#)
            .expect("+02:00 end_dt must parse");
    assert_eq!(finish_offset.end_dt, Some(expected_utc));

    // 4. Legacy naive ISO 8601 without offset stays supported and pins to UTC.
    let naive: StartSceneShootRequest =
        serde_json::from_str(r#"{"start_dt":"2026-11-17T08:30:00","version":1}"#)
            .expect("naive datetime must parse as UTC");
    assert_eq!(naive.start_dt, Some(expected_utc));

    // 5. Out-of-range datetimes and bare dates fail (422) instead of falling back to now().
    for invalid in [
        r#"{"start_dt":"9999-12-31T12:00:00","version":1}"#,
        r#"{"start_dt":"9999-12-30T21:00:00-02:00","version":1}"#,
        r#"{"start_dt":"2026-11-17","version":1}"#,
    ] {
        assert!(
            serde_json::from_str::<StartSceneShootRequest>(invalid).is_err(),
            "invalid payload {invalid} must be rejected, not replaced with Timestamp::now()"
        );
    }
}
