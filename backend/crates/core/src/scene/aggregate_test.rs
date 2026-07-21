// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;
use test_support::make_ctx;

fn create_scene() -> SceneAggregate {
    let episode_id = EpisodeId::new();
    let details = SceneDetails {
        scene_number: Some(1),
        location: Some("Studio A".to_string()),
        mood: Some("IN".to_string()),
        is_schedule_set: false,
        summary: None,
    };
    let events = SceneAggregate::default().handle(
        CreateScene {
            id: Uuid::now_v7(),
            episode_id,
            details: details.clone(),
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
                details,
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
    };
    let result = SceneAggregate::default().handle(
        CreateScene {
            id: Uuid::now_v7(),
            episode_id,
            details,
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
    };
    let event = agg.handle(
        UpdateSceneDetails {
            id: agg.id,
            details: details.clone(),
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
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        SceneError::ValidationError(ref m) if m.contains("version mismatch")
    ));
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
fn test_schedule_scene_double_schedule_rejected() {
    let mut agg = create_scene();
    let day = ShootingDayId::new();
    let events = agg
        .handle(
            ScheduleSceneOnShootingDay {
                id: agg.id,
                shooting_day_id: day,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.shooting_day_ids, vec![day]);

    // Second schedule of the same day must be rejected (no duplicate event).
    let result = agg.handle(
        ScheduleSceneOnShootingDay {
            id: agg.id,
            shooting_day_id: day,
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(
        result,
        Err(SceneError::AlreadyScheduled { shooting_day_id }) if shooting_day_id == day
    ));
    assert_eq!(agg.shooting_day_ids, vec![day]);
}

#[test]
fn test_unschedule_not_scheduled_rejected() {
    let agg = create_scene();
    let day = ShootingDayId::new();
    let result = agg.handle(
        UnscheduleSceneFromShootingDay {
            id: agg.id,
            shooting_day_id: day,
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
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(
        unchanged,
        Err(SceneError::ValidationError(ref m)) if m.contains("unchanged")
    ));
}
