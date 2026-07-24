// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kwaipilot/kat-coder-air-v2.5 (openrouter)

//! Unit tests for the `SceneShootAggregate` — lifecycle transitions, passive
//! freezing, note mutations, duplicate-plan rejection, and photo linking.

use chrono::{TimeDelta, Utc};
use kameo_es::Command;
use uuid::Uuid;

use crate::scene_shoot::aggregate::SceneShootAggregate;
use crate::scene_shoot::commands::{
    AddSceneShootNote, FinishSceneShoot, LinkContinuityPhoto, PlanSceneShoot, RemoveSceneShootNote,
    ReplanSceneShoot, SetActualOrder, SkipSceneShoot, StartSceneShoot, UnlinkContinuityPhoto,
    UpdateSceneShootNote,
};
use crate::scene_shoot::error::SceneShootError;
use crate::scene_shoot::events::SceneShootEvent;
use crate::shared::{
    AggregateVersion, LexicalSortKey, PhotoId, SceneShootId, SceneShootStatus, ShootingDayId,
};
use test_support::{make_ctx, replay_events};

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
                body: "Anschluss: Rock ist zu lang".into(),
                author: None,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert_eq!(state.notes.len(), 1);
    assert_eq!(state.notes[0].id, note_id);
    assert_eq!(state.notes[0].body, "Anschluss: Rock ist zu lang");
    assert_eq!(state.notes[0].author, None);

    assert_eq!(events.len(), 1);
    match &events[0] {
        SceneShootEvent::ShootDayNoteAdded {
            note_id: n,
            body,
            author,
            ..
        } => {
            assert_eq!(*n, note_id);
            assert_eq!(body.as_str(), "Anschluss: Rock ist zu lang");
            assert_eq!(*author, None);
        }
        other => panic!("expected ShootDayNoteAdded, got {other:?}"),
    }
}

#[test]
fn update_note_replaces_body() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let note_id = Uuid::now_v7();

    let events = state
        .handle(
            AddSceneShootNote {
                id: state.id,
                note_id,
                body: "original".into(),
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
                body: "updated".into(),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events.clone());

    assert_eq!(state.notes.len(), 1);
    assert_eq!(state.notes[0].body, "updated");
    assert_eq!(events.len(), 1);
    match &events[0] {
        SceneShootEvent::ShootDayNoteUpdated {
            note_id: n, body, ..
        } => {
            assert_eq!(*n, note_id);
            assert_eq!(body.as_str(), "updated");
        }
        other => panic!("expected ShootDayNoteUpdated, got {other:?}"),
    }
}

#[test]
fn update_nonexistent_note_fails() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let note_id = Uuid::now_v7();

    let err = state
        .handle(
            UpdateSceneShootNote {
                id: state.id,
                note_id,
                body: "nope".into(),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::NoteNotFound { .. }),
        "expected NoteNotFound, got {err:?}"
    );
}

#[test]
fn remove_note_drops_it() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let note_id = Uuid::now_v7();

    let events = state
        .handle(
            AddSceneShootNote {
                id: state.id,
                note_id,
                body: "remove me".into(),
                author: None,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);
    assert_eq!(state.notes.len(), 1);

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
    match &events[0] {
        SceneShootEvent::ShootDayNoteRemoved { note_id: n, .. } => {
            assert_eq!(*n, note_id);
        }
        other => panic!("expected ShootDayNoteRemoved, got {other:?}"),
    }
}

#[test]
fn remove_nonexistent_note_fails() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));

    let err = state
        .handle(
            RemoveSceneShootNote {
                id: state.id,
                note_id: Uuid::now_v7(),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::NoteNotFound { .. }),
        "expected NoteNotFound, got {err:?}"
    );
}

// ─── 2.9: Duplicate-plan rejection ───────────────────────────────────────────

#[test]
fn cannot_plan_already_existing_pair() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));

    let err = state
        .handle(
            PlanSceneShoot {
                id: SceneShootId::new(),
                scene_id,
                shooting_day_id: day_id,
                planned_order: LexicalSortKey::from_static("b"),
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::PairAlreadyExists),
        "expected PairAlreadyExists, got {err:?}"
    );
}

// ─── 2.9: Continuity photo linking ───────────────────────────────────────────

#[test]
fn link_continuity_photo_appends_to_list() {
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

    assert_eq!(state.continuity_photos.len(), 1);
    assert_eq!(state.continuity_photos[0], photo_id);
    assert_eq!(events.len(), 1);
    match &events[0] {
        SceneShootEvent::ContinuityPhotoLinked { photo_id: p, .. } => {
            assert_eq!(*p, photo_id);
        }
        other => panic!("expected ContinuityPhotoLinked, got {other:?}"),
    }
}

#[test]
fn duplicate_link_rejected() {
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

    let err = state
        .handle(
            LinkContinuityPhoto {
                id: state.id,
                photo_id,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::AlreadyLinked { .. }),
        "expected AlreadyLinked, got {err:?}"
    );
}

#[test]
fn unlink_continuity_photo_removes_it() {
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
    assert_eq!(state.continuity_photos.len(), 1);

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

    assert!(state.continuity_photos.is_empty());
    assert_eq!(events.len(), 1);
    match &events[0] {
        SceneShootEvent::ContinuityPhotoUnlinked { photo_id: p, .. } => {
            assert_eq!(*p, photo_id);
        }
        other => panic!("expected ContinuityPhotoUnlinked, got {other:?}"),
    }
}

// ─── 2.9: Version / optimistic-locking ───────────────────────────────────────

#[test]
fn version_mismatch_rejected() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));

    let bad_version = AggregateVersion::INITIAL.next();
    let err = state
        .handle(
            StartSceneShoot {
                id: state.id,
                start_dt: Utc::now(),
                version: bad_version,
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::VersionMismatch { .. }),
        "expected VersionMismatch, got {err:?}"
    );
}

#[test]
fn terminal_state_rejects_mutations() {
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
    replay_events(&mut state, events);

    let err = state
        .handle(
            StartSceneShoot {
                id: state.id,
                start_dt: Utc::now(),
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::TerminalState { .. }),
        "expected TerminalState, got {err:?}"
    );
}

// ─── 2.9: Idempotent start ──────────────────────────────────────────────────

#[test]
fn start_is_idempotent_with_same_value() {
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
    assert_eq!(state.version, AggregateVersion::INITIAL.next());

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
    assert_eq!(events.len(), 0);
}

#[test]
fn start_rejects_different_value_after_already_started() {
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

    let later = now + TimeDelta::try_hours(1).unwrap();
    let err = state
        .handle(
            StartSceneShoot {
                id: state.id,
                start_dt: later,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap_err();

    assert!(
        matches!(err, SceneShootError::AlreadyStarted),
        "expected AlreadyStarted, got {err:?}"
    );
}

// ─── 2.9: Note with author round-trip ────────────────────────────────────────

#[test]
fn note_with_author_round_trips() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));
    let note_id = Uuid::now_v7();

    let events = state
        .handle(
            AddSceneShootNote {
                id: state.id,
                note_id,
                body: "author note".into(),
                author: Some(crate::shared::UserId::from_sub("user123")),
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    assert_eq!(state.notes.len(), 1);
    assert_eq!(
        state.notes[0].author,
        Some(crate::shared::UserId::from_sub("user123"))
    );
}

// ─── 2.9: Multiple notes ─────────────────────────────────────────────────────

#[test]
fn multiple_notes_accumulate_and_can_be_individually_removed() {
    let scene_id = make_scene_id();
    let day_id = make_shooting_day_id();
    let (mut state, _) = plan_and_apply(make_plan_cmd(scene_id, day_id));

    let id1 = Uuid::now_v7();
    let id2 = Uuid::now_v7();

    let events = state
        .handle(
            AddSceneShootNote {
                id: state.id,
                note_id: id1,
                body: "first".into(),
                author: None,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    let events = state
        .handle(
            AddSceneShootNote {
                id: state.id,
                note_id: id2,
                body: "second".into(),
                author: None,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    assert_eq!(state.notes.len(), 2);

    let events = state
        .handle(
            RemoveSceneShootNote {
                id: state.id,
                note_id: id1,
                version: state.version,
            },
            make_ctx(),
        )
        .unwrap();
    replay_events(&mut state, events);

    assert_eq!(state.notes.len(), 1);
    assert_eq!(state.notes[0].id, id2);
}
