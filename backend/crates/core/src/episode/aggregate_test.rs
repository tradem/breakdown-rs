// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;
use test_support::make_ctx;

fn create_episode() -> EpisodeAggregate {
    let cmd = CreateEpisode {
        id: Uuid::now_v7(),
        block_id: BlockId::new(),
        series_id: SeriesId::new(),
        number: 1,
        name: Some("Pilot".into()),
    };
    let events = EpisodeAggregate::default().handle(cmd, make_ctx()).unwrap();
    let mut agg = EpisodeAggregate::default();
    test_support::replay_events(&mut agg, events);
    agg
}

#[test]
fn test_create_episode_success() {
    let block_id = BlockId::new();
    let series_id = SeriesId::new();
    let cmd = CreateEpisode {
        id: Uuid::now_v7(),
        block_id,
        series_id,
        number: 2,
        name: Some("Finale".into()),
    };
    let result = EpisodeAggregate::default().handle(cmd, make_ctx());
    assert!(result.is_ok());
    match result.unwrap().into_iter().next().unwrap() {
        EpisodeEvent::EpisodeCreated {
            id,
            block_id: bid,
            series_id: sid,
            number,
            name,
            version,
        } => {
            assert_ne!(id, Uuid::nil());
            assert_eq!(bid, block_id);
            assert_eq!(sid, series_id);
            assert_eq!(number, 2);
            assert_eq!(name, Some("Finale".into()));
            assert_eq!(version, AggregateVersion::INITIAL);
        }
        _ => panic!("Expected EpisodeCreated"),
    }
}

#[test]
fn test_create_episode_without_name() {
    let cmd = CreateEpisode {
        id: Uuid::now_v7(),
        block_id: BlockId::new(),
        series_id: SeriesId::new(),
        number: 3,
        name: None,
    };
    let events = EpisodeAggregate::default().handle(cmd, make_ctx()).unwrap();
    match events.into_iter().next().unwrap() {
        EpisodeEvent::EpisodeCreated { name, .. } => assert_eq!(name, None),
        _ => panic!("Expected EpisodeCreated"),
    }
}

#[test]
fn test_rename_episode_success() {
    let mut agg = create_episode();
    let event = agg
        .handle(
            RenameEpisode {
                id: agg.id,
                name: Some("Renamed".into()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, event);
    assert_eq!(agg.name, Some("Renamed".into()));
    assert_eq!(agg.version, AggregateVersion(2));
}

#[test]
fn test_rename_episode_idempotency() {
    let agg = create_episode();
    let result = agg.handle(
        RenameEpisode {
            id: agg.id,
            name: agg.name.clone(),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        EpisodeError::ValidationError(ref m) if m.contains("unchanged")
    ));
}

#[test]
fn test_rename_episode_wrong_version() {
    let agg = create_episode();
    let result = agg.handle(
        RenameEpisode {
            id: agg.id,
            name: Some("X".into()),
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        EpisodeError::ValidationError(ref m) if m.contains("version mismatch")
    ));
}

/// Verify that apply() actually mutates aggregate state — catches mutants
/// that replace the `apply` body with `()`.
#[test]
fn test_apply_updates_state() {
    use kameo_es::Metadata;
    let mut agg = EpisodeAggregate::default();
    let id = Uuid::now_v7();
    agg.apply(
        EpisodeEvent::EpisodeCreated {
            id,
            block_id: BlockId::new(),
            series_id: SeriesId::new(),
            number: 5,
            name: Some("Liese".into()),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    assert_eq!(
        agg.name,
        Some("Liese".into()),
        "apply() should set the name"
    );
    assert_eq!(agg.id, id);
    assert_eq!(agg.number, 5);
    assert_eq!(agg.version, AggregateVersion::INITIAL);
}

/// Verify that RenameEpisode checks `!=` (not `==`) so passing the same
/// name correctly returns an idempotency error.
#[test]
fn test_rename_uses_not_equal() {
    use kameo_es::Metadata;
    let mut agg = EpisodeAggregate::default();
    let id = Uuid::now_v7();
    agg.apply(
        EpisodeEvent::EpisodeCreated {
            id,
            block_id: BlockId::new(),
            series_id: SeriesId::new(),
            number: 1,
            name: Some("A".into()),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    agg.apply(
        EpisodeEvent::EpisodeRenamed {
            id,
            name: Some("B".into()),
            version: AggregateVersion(2),
        },
        Metadata::default(),
    );
    let result = agg.handle(
        RenameEpisode {
            id,
            name: Some("B".into()),
            version: AggregateVersion(2),
        },
        make_ctx(),
    );
    assert!(
        result.is_err(),
        "identical name should be rejected (idempotency check)"
    );
}
