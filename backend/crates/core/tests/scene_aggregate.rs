// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use breakdown_core::scene::events::SceneSource;
use breakdown_core::scene::*;
use breakdown_core::shared::{AggregateVersion, EpisodeId, ProjectId, ShootingDayId};
use kameo_es::Command;
use test_support::make_ctx;
use uuid::Uuid;

fn project_id() -> ProjectId {
    ProjectId::new()
}

fn create_scene() -> SceneAggregate {
    let episode_id = EpisodeId::new();
    let details = SceneDetails {
        scene_number: Some(1),
        location: Some("Studio A".to_string()),
        mood: Some("IN".to_string()),
        is_schedule_set: false,
        summary: None,
        script_day: None,
    };
    let events = SceneAggregate::default().handle(
        CreateScene {
            id: Uuid::now_v7(),
            episode_id,
            project_id: Some(project_id()),
            details: details.clone(),
            source: SceneSource::Manual,
        },
        make_ctx(),
    );
    let _ = events;
    let mut applied = SceneAggregate::default();
    let events = SceneAggregate::default()
        .handle(
            CreateScene {
                id: Uuid::now_v7(),
                episode_id,
                project_id: Some(project_id()),
                details,
                source: SceneSource::Manual,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut applied, events);
    applied
}

#[test]
fn test_create_scene_success() {
    let episode_id = EpisodeId::new();
    let details = SceneDetails {
        scene_number: Some(5),
        location: Some("Berlin".into()),
        mood: Some("DA".into()),
        is_schedule_set: true,
        summary: None,
        script_day: None,
    };
    let result = SceneAggregate::default().handle(
        CreateScene {
            id: Uuid::now_v7(),
            episode_id,
            project_id: Some(project_id()),
            details,
            source: SceneSource::Manual,
        },
        make_ctx(),
    );
    assert!(result.is_ok());
    let events = result.unwrap();
    assert_eq!(events.len(), 1);
    match events.into_iter().next().unwrap() {
        SceneEvent::SceneCreated {
            id,
            episode_id,
            version,
            assigned_characters,
            ..
        } => {
            assert_ne!(id, Uuid::nil());
            assert_eq!(version, AggregateVersion::INITIAL);
            assert!(assigned_characters.is_empty());
            assert_eq!(episode_id, episode_id);
        }
        _ => panic!("Expected SceneCreated"),
    }
}

#[test]
fn test_update_scene_details_success() {
    let mut agg = create_scene();
    let details = SceneDetails {
        scene_number: Some(10),
        location: Some("Exterior".into()),
        mood: Some("AT".into()),
        is_schedule_set: true,
        summary: None,
        script_day: None,
    };
    let event = agg.handle(
        UpdateSceneDetails {
            id: agg.id,
            details: details.clone(),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    test_support::replay_events(&mut agg, event.unwrap());
    assert_eq!(agg.details.scene_number, Some(10));
}

#[test]
fn test_update_scene_details_idempotency() {
    let agg = create_scene();
    let result = agg.handle(
        UpdateSceneDetails {
            id: agg.id,
            details: agg.details.clone(),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        SceneError::ValidationError(ref m) if m.contains("unchanged")
    ));
}

#[test]
fn test_update_scene_details_wrong_version() {
    let agg = create_scene();
    let result = agg.handle(
        UpdateSceneDetails {
            id: agg.id,
            details: SceneDetails {
                scene_number: Some(99),
                ..Default::default()
            },
            project_id: Some(project_id()),
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        SceneError::VersionMismatch {
            expected: AggregateVersion(99),
            actual: AggregateVersion::INITIAL,
        }
    ));
}

/// All five mutating scene commands must reject a stale version with the
/// typed `SceneError::VersionMismatch { expected, actual }` (issue #488) so
/// the write renders 409 `concurrency.version-mismatch` with the
/// `expected_version` / `current_version` extensions — not a generic
/// `domain.validation` 422.
#[test]
fn test_all_mutating_commands_reject_stale_version_as_version_mismatch() {
    let agg = create_scene();
    let stale = AggregateVersion(99);
    let character_id = Uuid::now_v7();
    let shooting_day_id = ShootingDayId::new();

    for result in [
        agg.handle(
            UpdateSceneDetails {
                id: agg.id,
                details: SceneDetails {
                    scene_number: Some(99),
                    ..Default::default()
                },
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        agg.handle(
            AssignCharacter {
                id: agg.id,
                character_id,
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        agg.handle(
            RemoveCharacter {
                id: agg.id,
                character_id,
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        agg.handle(
            ScheduleSceneOnShootingDay {
                id: agg.id,
                shooting_day_id,
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        agg.handle(
            UnscheduleSceneFromShootingDay {
                id: agg.id,
                shooting_day_id,
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
    ] {
        match result {
            Err(SceneError::VersionMismatch { expected, actual }) => {
                assert_eq!(expected, stale);
                assert_eq!(actual, AggregateVersion::INITIAL);
            }
            other => panic!("expected VersionMismatch, got {other:?}"),
        }
    }
}

#[test]
fn test_assign_character_success() {
    let mut agg = create_scene();
    let char_id = Uuid::now_v7();
    let events = agg
        .handle(
            AssignCharacter {
                id: agg.id,
                character_id: char_id,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.assigned_characters.len(), 1);
    assert_eq!(agg.assigned_characters[0], char_id);
}

#[test]
fn test_assign_character_conflict() {
    let mut agg = create_scene();
    let char_id = Uuid::now_v7();
    let events = agg
        .handle(
            AssignCharacter {
                id: agg.id,
                character_id: char_id,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let result = agg.handle(
        AssignCharacter {
            id: agg.id,
            character_id: char_id,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        SceneError::CharacterAlreadyAssigned
    ));
}

#[test]
fn test_remove_character_success() {
    let mut agg = create_scene();
    let char_id = Uuid::now_v7();
    let events = agg
        .handle(
            AssignCharacter {
                id: agg.id,
                character_id: char_id,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let events = agg
        .handle(
            RemoveCharacter {
                id: agg.id,
                character_id: char_id,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert!(agg.assigned_characters.is_empty());
    assert!(agg.assigned_characters.is_empty());
}

#[test]
fn test_remove_character_not_assigned() {
    let agg = create_scene();
    let result = agg.handle(
        RemoveCharacter {
            id: agg.id,
            character_id: Uuid::now_v7(),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        SceneError::ValidationError(ref m) if m.contains("not assigned")
    ));
}

#[test]
fn test_schedule_scene_double_schedule_is_state_idempotent() {
    let mut agg = create_scene();
    let day = ShootingDayId::new();
    let events = agg
        .handle(
            ScheduleSceneOnShootingDay {
                id: agg.id,
                shooting_day_id: day,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.shooting_day_ids, vec![day]);

    // The command service consults `is_state_idempotent` first: re-scheduling
    // an already-linked day is a no-op (ExecuteResult::Idempotent), not a
    // conflict — that is what lets a crashed AI schedule-apply retry converge
    // instead of stranding its idempotency mapping (issue #179).
    let cmd = ScheduleSceneOnShootingDay {
        id: agg.id,
        shooting_day_id: day,
        project_id: Some(project_id()),
        version: agg.version,
    };
    assert!(
        agg.is_state_idempotent(&cmd, make_ctx()),
        "an already-linked shooting day must be reported as state-idempotent"
    );

    // `handle` keeps its defensive rejection (unreachable through the command
    // service) so a direct call still emits no duplicate event.
    let result = agg.handle(cmd, make_ctx());
    assert!(matches!(
        result,
        Err(SceneError::AlreadyScheduled { shooting_day_id }) if shooting_day_id == day
    ));
    assert_eq!(agg.shooting_day_ids, vec![day]);

    // A *different* day is real work and must not be short-circuited — the
    // hook has to discriminate, not blanket-skip the command.
    let other_day = ShootingDayId::new();
    assert!(
        !agg.is_state_idempotent(
            &ScheduleSceneOnShootingDay {
                id: agg.id,
                shooting_day_id: other_day,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx()
        ),
        "an unlinked shooting day must still be scheduled"
    );
}

#[test]
fn test_unschedule_not_scheduled_rejected() {
    let agg = create_scene();
    let day = ShootingDayId::new();
    let result = agg.handle(
        UnscheduleSceneFromShootingDay {
            id: agg.id,
            shooting_day_id: day,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(
        result,
        Err(SceneError::NotScheduled { shooting_day_id }) if shooting_day_id == day
    ));
}

#[test]
fn test_unschedule_removes_link() {
    let mut agg = create_scene();
    let day = ShootingDayId::new();
    let events = agg
        .handle(
            ScheduleSceneOnShootingDay {
                id: agg.id,
                shooting_day_id: day,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let events = agg
        .handle(
            UnscheduleSceneFromShootingDay {
                id: agg.id,
                shooting_day_id: day,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert!(agg.shooting_day_ids.is_empty());
}

#[test]
fn test_summary_round_trips_through_update_guard() {
    let mut agg = create_scene();
    let summary = "A tense interrogation scene.".to_string();
    let events = agg
        .handle(
            UpdateSceneDetails {
                id: agg.id,
                details: SceneDetails {
                    summary: Some(summary.clone()),
                    ..agg.details.clone()
                },
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.details.summary.as_deref(), Some(summary.as_str()));

    // Replaying identical details (incl. summary) hits the "unchanged" guard.
    let unchanged = agg.handle(
        UpdateSceneDetails {
            id: agg.id,
            details: agg.details.clone(),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(
        unchanged,
        Err(SceneError::ValidationError(ref m)) if m.contains("unchanged")
    ));
}

#[test]
fn test_script_day_round_trips_through_update_guard() {
    let mut agg = create_scene();
    let script_day = "1. Spieltag".to_string();
    let events = agg
        .handle(
            UpdateSceneDetails {
                id: agg.id,
                details: SceneDetails {
                    script_day: Some(script_day.clone()),
                    ..agg.details.clone()
                },
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.details.script_day.as_deref(), Some(script_day.as_str()));

    // Replaying identical details (incl. script_day) hits the "unchanged" guard.
    let unchanged = agg.handle(
        UpdateSceneDetails {
            id: agg.id,
            details: agg.details.clone(),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(
        unchanged,
        Err(SceneError::ValidationError(ref m)) if m.contains("unchanged")
    ));
}

// ---------------------------------------------------------------------------
// Costume beats (issue #546)
// ---------------------------------------------------------------------------

/// Scene aggregate with one assigned character (the precondition for any
/// beat command).
fn scene_with_character() -> SceneAggregate {
    let mut agg = create_scene();
    let character_id = Uuid::now_v7();
    let event = agg.handle(
        AssignCharacter {
            id: agg.id,
            character_id,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    test_support::replay_events(&mut agg, event.unwrap());
    agg
}

fn add_beat(agg: &mut SceneAggregate, character_id: Uuid, costume_id: Uuid, note: Option<String>) {
    let event = agg
        .handle(
            AddCostumeBeat {
                id: agg.id,
                character_id,
                costume_id,
                note,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(agg, event);
}

#[test]
fn test_add_beat_computes_dense_order_per_character() {
    let mut agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    add_beat(
        &mut agg,
        character_id,
        Uuid::now_v7(),
        Some("Mantel".into()),
    );
    add_beat(&mut agg, character_id, Uuid::now_v7(), Some("ohne".into()));
    assert_eq!(agg.costume_beats.len(), 2);
    assert_eq!(agg.costume_beats[0].order, 0);
    assert_eq!(agg.costume_beats[1].order, 1);
    assert_eq!(agg.costume_beats[0].note.as_deref(), Some("Mantel"));
}

#[test]
fn test_add_beat_for_character_not_in_scene_rejected() {
    let agg = scene_with_character();
    let stranger = Uuid::now_v7();
    let result = agg.handle(
        AddCostumeBeat {
            id: agg.id,
            character_id: stranger,
            costume_id: Uuid::now_v7(),
            note: None,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    match result {
        Err(SceneError::CharacterNotInScene { character_id }) => {
            assert_eq!(character_id, stranger);
        }
        _ => panic!("Expected CharacterNotInScene"),
    }
}

#[test]
fn test_add_beat_rejects_stale_version() {
    let agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    let result = agg.handle(
        AddCostumeBeat {
            id: agg.id,
            character_id,
            costume_id: Uuid::now_v7(),
            note: None,
            project_id: Some(project_id()),
            version: AggregateVersion::INITIAL, // stale: agg.version is INITIAL.next()
        },
        make_ctx(),
    );
    assert!(matches!(result, Err(SceneError::VersionMismatch { .. })));
}

#[test]
fn test_consecutive_identical_beat_guard() {
    let mut agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    let costume = Uuid::now_v7();
    add_beat(&mut agg, character_id, costume, None);
    let result = agg.handle(
        AddCostumeBeat {
            id: agg.id,
            character_id,
            costume_id: costume,
            note: None,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(result, Err(SceneError::ValidationError(_))));
}

#[test]
fn test_on_change_two_costumes_same_character_allowed() {
    let mut agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    // The guard only fires on identical consecutive costumes, not on a change.
    assert_eq!(agg.costume_beats.len(), 2);
}

#[test]
fn test_update_beat_edits_in_place_and_never_renumbers() {
    let mut agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    let new_costume = Uuid::now_v7();
    let event = agg
        .handle(
            UpdateCostumeBeat {
                id: agg.id,
                character_id,
                order: 0,
                costume_id: new_costume,
                note: Some("geändert".into()),
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, event);
    assert_eq!(agg.costume_beats[0].costume_id, new_costume);
    assert_eq!(agg.costume_beats[0].order, 0);
}

#[test]
fn test_update_beat_not_found() {
    let agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    let result = agg.handle(
        UpdateCostumeBeat {
            id: agg.id,
            character_id,
            order: 3,
            costume_id: Uuid::now_v7(),
            note: None,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    match result {
        Err(SceneError::BeatNotFound {
            character_id: c,
            order,
        }) => {
            assert_eq!(c, character_id);
            assert_eq!(order, 3);
        }
        _ => panic!("Expected BeatNotFound"),
    }
}

#[test]
fn test_remove_middle_beat_keeps_surviving_orders_untouched() {
    let mut agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    let event = agg
        .handle(
            RemoveCostumeBeat {
                id: agg.id,
                character_id,
                order: Some(1),
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, event);
    // 0 and 2 survive untouched — no renumbering.
    let mut orders: Vec<u32> = agg.costume_beats.iter().map(|b| b.order).collect();
    orders.sort_unstable();
    assert_eq!(orders, vec![0, 2]);
    // Next add continues at max + 1 = 3.
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    assert!(agg.costume_beats.iter().any(|b| b.order == 3));
}

#[test]
fn test_remove_beat_not_found() {
    let agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    let result = agg.handle(
        RemoveCostumeBeat {
            id: agg.id,
            character_id,
            order: Some(0),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(result, Err(SceneError::BeatNotFound { .. })));
}

#[test]
fn test_clear_all_beats_of_character() {
    let mut agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    let event = agg
        .handle(
            RemoveCostumeBeat {
                id: agg.id,
                character_id,
                order: None,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, event);
    assert!(agg.costume_beats.is_empty());
}

#[test]
fn test_clear_all_with_no_beats_is_a_validation_error() {
    let agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    let result = agg.handle(
        RemoveCostumeBeat {
            id: agg.id,
            character_id,
            order: None,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    // Surfaced as the dedicated 422 `scene.beat-not-found` code
    // (`NoCostumeBeats`), not the generic `scene.validation` — a client
    // can tell "nothing to clear" apart from a real validation failure
    // (issue #546, CodeRabbit review).
    assert!(matches!(result, Err(SceneError::NoCostumeBeats { .. })));
}

#[test]
fn test_version_chain_advances_one_event_per_beat_command() {
    let mut agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    let v0 = agg.version;
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    assert_eq!(agg.version, v0.next());
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    assert_eq!(agg.version, v0.next().next());
}

#[test]
fn test_legacy_scene_without_beats_replays_with_empty_beats() {
    let mut agg = SceneAggregate::default();
    let event = SceneAggregate::default()
        .handle(
            CreateScene {
                id: Uuid::now_v7(),
                episode_id: EpisodeId::new(),
                project_id: Some(project_id()),
                details: SceneDetails::default(),
                source: SceneSource::Manual,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, event);
    assert!(agg.costume_beats.is_empty());
}

#[test]
fn test_beat_events_round_trip_through_serde() {
    let event = SceneEvent::CostumeBeatAdded {
        id: Uuid::now_v7(),
        character_id: Uuid::now_v7(),
        costume_id: Uuid::now_v7(),
        order: 1,
        note: Some("nach dem Telefonat".into()),
        version: AggregateVersion::INITIAL.next(),
    };
    let json = serde_json::to_string(&event).unwrap();
    let back: SceneEvent = serde_json::from_str(&json).unwrap();
    assert_eq!(back, event);
}

#[test]
fn test_remove_character_clears_beats_first() {
    let mut agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);
    add_beat(&mut agg, character_id, Uuid::now_v7(), None);

    let events = agg
        .handle(
            RemoveCharacter {
                id: agg.id,
                character_id,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();

    // Two events, versions advancing in order: clear, then remove.
    assert_eq!(events.len(), 2);
    match (&events[0], &events[1]) {
        (
            SceneEvent::CostumeBeatsCleared { version: v0, .. },
            SceneEvent::CharacterRemoved { version: v1, .. },
        ) => {
            assert_eq!(*v0, agg.version.next());
            assert_eq!(*v1, agg.version.next().next());
        }
        _ => panic!("Expected CostumeBeatsCleared then CharacterRemoved"),
    }

    test_support::replay_events(&mut agg, events.clone());
    assert!(agg.costume_beats.is_empty(), "no orphan beats may survive");
    assert!(!agg.assigned_characters.contains(&character_id));
}

#[test]
fn test_remove_character_without_beats_emits_one_event() {
    let agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    let events = agg
        .handle(
            RemoveCharacter {
                id: agg.id,
                character_id,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1);
    assert!(matches!(events[0], SceneEvent::CharacterRemoved { .. }));
}

#[test]
fn test_clear_all_without_beats_is_beat_not_found_code() {
    let agg = scene_with_character();
    let character_id = agg.assigned_characters[0];
    let result = agg.handle(
        RemoveCostumeBeat {
            id: agg.id,
            character_id,
            order: None,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    match result {
        Err(SceneError::NoCostumeBeats { character_id: c }) => assert_eq!(c, character_id),
        _ => panic!("Expected NoCostumeBeats"),
    }
}
