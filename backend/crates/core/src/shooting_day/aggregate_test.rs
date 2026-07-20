// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;
use crate::shared::LexicalSortKey;
use crate::shooting_day::views::ShootingDayView;
use test_support::make_ctx;

fn create_day(order_key: &str) -> ShootingDayAggregate {
    let agg = ShootingDayAggregate::default();
    let id = ShootingDayId::new();
    let episode_id = EpisodeId::new();
    let events = agg
        .handle(
            CreateShootingDay {
                id,
                episode_id,
                label: Some("Tag 1".into()),
                order_key: LexicalSortKey::new(order_key).unwrap(),
                date: None,
                source: ShootingDaySource::Manual,
            },
            make_ctx(),
        )
        .unwrap();
    let mut applied = ShootingDayAggregate::default();
    test_support::replay_events(&mut applied, events);
    applied
}

#[test]
fn test_create_shooting_day_success() {
    let result = ShootingDayAggregate::default().handle(
        CreateShootingDay {
            id: ShootingDayId::new(),
            episode_id: EpisodeId::new(),
            label: Some("Tag 1".into()),
            order_key: LexicalSortKey::new("a").unwrap(),
            date: Some(chrono::NaiveDate::from_ymd_opt(2026, 1, 2).unwrap()),
            source: ShootingDaySource::Manual,
        },
        make_ctx(),
    );
    assert!(result.is_ok());
    let events = result.unwrap();
    assert_eq!(events.len(), 1);
    match events.into_iter().next().unwrap() {
        ShootingDayEvent::ShootingDayCreated {
            version, ..
        } => {
            assert_eq!(version, AggregateVersion::INITIAL);
        }
        _ => panic!("Expected ShootingDayCreated"),
    }
}

#[test]
fn test_rename_preserves_order_key() {
    let mut agg = create_day("a");
    let before = agg.order_key.clone();
    let events = agg
        .handle(
            RenameShootingDay {
                id: agg.id,
                label: Some("Renamed".into()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.label.as_deref(), Some("Renamed"));
    assert_eq!(agg.order_key, before, "rename must not alter order_key");
}

#[test]
fn test_reschedule_sets_and_clears_date() {
    let mut agg = create_day("a");
    let date = chrono::NaiveDate::from_ymd_opt(2026, 3, 4).unwrap();
    let events = agg
        .handle(
            RescheduleShootingDay {
                id: agg.id,
                date: Some(date),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.date, Some(date));

    let events = agg
        .handle(
            RescheduleShootingDay {
                id: agg.id,
                date: None,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.date, None, "reschedule to None unschedules the day");
}

#[test]
fn test_reorder_with_midpoint_emits_single_event_between_siblings() {
    let agg = create_day("a");
    let a = LexicalSortKey::new("a").unwrap();
    let b = LexicalSortKey::new("b").unwrap();
    let mid = LexicalSortKey::midpoint(&a, &b).unwrap();
    assert!(a < mid && mid < b, "midpoint invariant violated");

    let events = agg
        .handle(
            ReorderShootingDay {
                id: agg.id,
                order_key: mid.clone(),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1, "reorder must emit exactly one event");
    match events.into_iter().next().unwrap() {
        ShootingDayEvent::ShootingDayReordered { order_key, .. } => {
            assert_eq!(order_key, mid);
            assert!(a < order_key && order_key < b);
        }
        other => panic!("expected ShootingDayReordered, got {other:?}"),
    }
}

#[test]
fn test_archive_is_terminal_and_blocks_mutations() {
    let mut agg = create_day("a");
    let events = agg
        .handle(
            ArchiveShootingDay {
                id: agg.id,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1);
    test_support::replay_events(&mut agg, events);
    assert!(agg.archived, "archive must flip the flag");

    // Subsequent mutations must be rejected.
    assert!(matches!(
        agg.handle(
            RenameShootingDay {
                id: agg.id,
                label: Some("x".into()),
                version: agg.version,
            },
            make_ctx(),
        ),
        Err(ShootingDayError::ArchivedCannotBeMutated { .. })
    ));
    assert!(matches!(
        agg.handle(
            RescheduleShootingDay {
                id: agg.id,
                date: None,
                version: agg.version,
            },
            make_ctx(),
        ),
        Err(ShootingDayError::ArchivedCannotBeMutated { .. })
    ));
    assert!(matches!(
        agg.handle(
            ReorderShootingDay {
                id: agg.id,
                order_key: LexicalSortKey::new("z").unwrap(),
                version: agg.version,
            },
            make_ctx(),
        ),
        Err(ShootingDayError::ArchivedCannotBeMutated { .. })
    ));

    // Re-archiving an already-archived day is an idempotent-reject.
    assert!(matches!(
        agg.handle(
            ArchiveShootingDay {
                id: agg.id,
                version: agg.version,
            },
            make_ctx(),
        ),
        Err(ShootingDayError::ArchivedCannotBeMutated { .. })
    ));
}

#[test]
fn test_version_mismatch_rejected() {
    let agg = create_day("a");
    let wrong = AggregateVersion(agg.version.0 + 5);
    assert!(matches!(
        agg.handle(
            RenameShootingDay {
                id: agg.id,
                label: Some("x".into()),
                version: wrong,
            },
            make_ctx(),
        ),
        Err(ShootingDayError::VersionMismatch { .. })
    ));
}

#[test]
fn test_view_shape_round_trips_source() {
    // Ensures the view + source discriminator serialise cleanly (used by the
    // JSONB projection and OpenAPI schema).
    let manual = ShootingDayView {
        id: ShootingDayId::new(),
        episode_id: EpisodeId::new(),
        label: None,
        order_key: LexicalSortKey::new("a").unwrap(),
        date: None,
        source: ShootingDaySource::Manual,
        archived: false,
        version: AggregateVersion::INITIAL,
        updated_at: chrono::Utc::now(),
    };
    let json = serde_json::to_string(&manual).unwrap();
    assert!(json.contains("\"source\":{\"Manual\":null}") || json.contains("Manual"));

    let ai = ShootingDayView {
        source: ShootingDaySource::AiExtracted {
            document_id: uuid::Uuid::now_v7(),
            external_ref: Some("call-sheet-1".into()),
            confidence: 0.92,
        },
        ..manual
    };
    let json = serde_json::to_string(&ai).unwrap();
    assert!(json.contains("AiExtracted"));
}
