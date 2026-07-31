// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Unit tests for the `SceneShootAggregate` — lifecycle transitions, passive
//! freezing, note mutations, duplicate-plan rejection, and photo linking.

use breakdown_core::scene_shoot::*;
use breakdown_core::shared::{
    AggregateVersion, LexicalSortKey, PhotoId, SceneShootId, SceneShootStatus, ShootingDayId,
};
use chrono::{TimeDelta, Utc};
use kameo_es::Command;
use test_support::{make_ctx, replay_events};
use uuid::Uuid;

fn make_plan_cmd(scene_id: Uuid, shooting_day_id: ShootingDayId) -> PlanSceneShoot {
    PlanSceneShoot {
        id: SceneShootId::new(),
        scene_id,
        shooting_day_id,
        planned_order: LexicalSortKey::from_static("a"),
    }
}

fn make_scene_id() -> Uuid {
    Uuid::now_v7()
}

fn make_shooting_day_id() -> ShootingDayId {
    ShootingDayId::new()
}

/// Helper: emit a plan event from a PlanSceneShoot command via the handler.
fn plan_and_apply(cmd: PlanSceneShoot) -> (SceneShootAggregate, Vec<SceneShootEvent>) {
    let agg = SceneShootAggregate::default();
    let events = agg.handle(cmd, make_ctx()).unwrap();
    let mut state = agg;
    replay_events(&mut state, events.clone());
    (state, events)
}

// ─── 2.9: Lifecycle transitions ───────────────────────────────────────────────

#[test]
fn plan_creates_scene_shoot_in_planned_status() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let cmd = make_plan_cmd(scene_id, day_id);

    let (state, events) = plan_and_apply(cmd);

    assert_eq!(state.status, SceneShootStatus::Planned);
    assert_eq!(state.scene_id, scene_id);
    assert_eq!(state.shooting_day_id, day_id);
    assert_eq!(state.actual_order, None);
    assert_eq!(state.start_dt, None);
    assert!(state.notes.is_empty());
    assert!(state.continuity_photos.is_empty());
    assert_eq!(state.version, AggregateVersion::INITIAL);

    assert_eq!(events.len(), 1);
    match &events[0] {
        SceneShootEvent::SceneShootPlanned { status, .. } => {
            assert_eq!(*status, SceneShootStatus::Planned);
        }
        other => panic!("expected SceneShootPlanned, got {other:?}"),
    }
}

#[test]
fn start_transitions_to_in_progress_and_records_start_dt() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let now = Utc::now();

    let events = state
        .handle(
            StartSceneShoot {
                id: state.id,
                start_dt: now,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    let mut state = state;
    replay_events(&mut state, events.clone());

    assert_eq!(state.status, SceneShootStatus::InProgress);
    assert_eq!(state.start_dt, Some(now));
    assert_eq!(state.version, AggregateVersion::INITIAL.next());
    assert_eq!(events.len(), 1);
    match &events[0] {
        SceneShootEvent::SceneShootStarted { start_dt, .. } => {
            assert_eq!(*start_dt, now);
        }
        other => panic!("expected SceneShootStarted, got {other:?}"),
    }
}

#[test]
fn setting_actual_order_transitions_to_in_progress() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let order = LexicalSortKey::from_static("b");

    let events = state
        .handle(
            SetActualOrder {
                id: state.id,
                actual_order: order.clone(),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    let mut state = state;
    replay_events(&mut state, events.clone());

    assert_eq!(state.status, SceneShootStatus::InProgress);
    assert_eq!(state.actual_order, Some(order));
    assert_eq!(events.len(), 1);
}

#[test]
fn finish_transitions_to_shot() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));

    let now = Utc::now();
    let events = state
        .handle(
            StartSceneShoot {
                id: state.id,
                start_dt: now,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    let end_dt = now + TimeDelta::try_hours(2).unwrap();
    let events = state
        .handle(
            FinishSceneShoot {
                id: state.id,
                end_dt,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert_eq!(state.status, SceneShootStatus::Shot);
    assert_eq!(state.end_dt, Some(end_dt));
    assert_eq!(events.len(), 1);
    match &events[0] {
        SceneShootEvent::SceneShootFinished { end_dt: e, .. } => {
            assert_eq!(*e, end_dt);
        }
        other => panic!("expected SceneShootFinished, got {other:?}"),
    }
}

#[test]
fn skip_transitions_to_skipped() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));

    let events = state
        .handle(
            SkipSceneShoot {
                id: state.id,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert_eq!(state.status, SceneShootStatus::Skipped);
    assert_eq!(events.len(), 1);
    match &events[0] {
        SceneShootEvent::SceneShootSkipped { .. } => {}
        other => panic!("expected SceneShootSkipped, got {other:?}"),
    }
}

#[test]
fn finish_only_allowed_from_in_progress() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let end_dt = Utc::now();

    let err = state
        .handle(
            FinishSceneShoot {
                id: state.id,
                end_dt,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::ValidationError(ref msg) if msg.contains("InProgress")),
        "expected ValidationError about InProgress, got {err:?}"
    );
}

// ─── 2.9: Passive freezing ───────────────────────────────────────────────────

#[test]
fn planned_order_editable_before_execution_data() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let new_order = LexicalSortKey::from_static("z");

    let events = state
        .handle(
            ReplanSceneShoot {
                id: state.id,
                planned_order: new_order.clone(),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert_eq!(state.planned_order, new_order);
    assert_eq!(events.len(), 1);
    match &events[0] {
        SceneShootEvent::SceneShootReplanned { planned_order, .. } => {
            assert_eq!(*planned_order, new_order);
        }
        other => panic!("expected SceneShootReplanned, got {other:?}"),
    }
}

#[test]
fn planned_order_frozen_after_start_dt_set() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let now = Utc::now();

    let events = state
        .handle(
            StartSceneShoot {
                id: state.id,
                start_dt: now,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    let err = state
        .handle(
            ReplanSceneShoot {
                id: state.id,
                planned_order: LexicalSortKey::from_static("z"),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::PlannedOrderFrozen),
        "expected PlannedOrderFrozen, got {err:?}"
    );
}

#[test]
fn planned_order_frozen_after_actual_order_set() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));

    let events = state
        .handle(
            SetActualOrder {
                id: state.id,
                actual_order: LexicalSortKey::from_static("b"),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    let err = state
        .handle(
            ReplanSceneShoot {
                id: state.id,
                planned_order: LexicalSortKey::from_static("z"),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::PlannedOrderFrozen),
        "expected PlannedOrderFrozen, got {err:?}"
    );
}

// ─── 2.9: Note mutations ─────────────────────────────────────────────────────

#[test]
fn add_note_appends_to_notes() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let note_id = Uuid::now_v7();

    let events = state
        .handle(
            AddSceneShootNote {
                id: state.id,
                note_id,
                body: "First note".into(),
                author: None,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert_eq!(state.notes.len(), 1);
    assert_eq!(state.notes[0].body, "First note");
    assert_eq!(events.len(), 1);
}

#[test]
fn update_note_body_changes_body() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let note_id = Uuid::now_v7();

    let events = state
        .handle(
            AddSceneShootNote {
                id: state.id,
                note_id,
                body: "Original".into(),
                author: None,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    let events = state
        .handle(
            UpdateSceneShootNote {
                id: state.id,
                note_id,
                body: "Updated".into(),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert_eq!(state.notes[0].body, "Updated");
    assert_eq!(events.len(), 1);
}

#[test]
fn remove_note_removes_from_notes() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let note_id = Uuid::now_v7();

    let events = state
        .handle(
            AddSceneShootNote {
                id: state.id,
                note_id,
                body: "To be removed".into(),
                author: None,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    let events = state
        .handle(
            RemoveSceneShootNote {
                id: state.id,
                note_id,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert!(state.notes.is_empty());
    assert_eq!(events.len(), 1);
}

// ─── 2.9: Duplicate-plan rejection ──────────────────────────────────────────

#[test]
fn duplicate_plan_same_scene_and_day_is_rejected() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));

    let result = state.handle(make_plan_cmd(scene_id, day_id), make_ctx());
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        SceneShootError::PairAlreadyExists
    ));
}

// ─── 2.9: Photo linking ─────────────────────────────────────────────────────

#[test]
fn link_continuity_photo_adds_to_set() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let photo_id = PhotoId::new();

    let events = state
        .handle(
            LinkContinuityPhoto {
                id: state.id,
                photo_id,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert!(state.continuity_photos.contains(&photo_id));
    assert_eq!(events.len(), 1);
}

#[test]
fn link_same_photo_twice_is_rejected() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let photo_id = PhotoId::new();

    let events = state
        .handle(
            LinkContinuityPhoto {
                id: state.id,
                photo_id,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    let result = state.handle(
        LinkContinuityPhoto {
            id: state.id,
            photo_id,
            version: state.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        SceneShootError::AlreadyLinked { .. }
    ));
}

#[test]
fn unlink_continuity_photo_removes_from_set() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let photo_id = PhotoId::new();

    let events = state
        .handle(
            LinkContinuityPhoto {
                id: state.id,
                photo_id,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    let events = state
        .handle(
            UnlinkContinuityPhoto {
                id: state.id,
                photo_id,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert!(!state.continuity_photos.contains(&photo_id));
    assert_eq!(events.len(), 1);
}
