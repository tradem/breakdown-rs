use super::*;
use test_support::make_ctx;

fn create_season() -> SeasonAggregate {
    let cmd = CreateSeason {
        id: Uuid::now_v7(),
        series_id: SeriesId::new(),
        number: 1,
        title: Some("Spring Run".into()),
    };
    let events = SeasonAggregate::default().handle(cmd, make_ctx()).unwrap();
    let mut agg = SeasonAggregate::default();
    test_support::replay_events(&mut agg, events);
    agg
}

#[test]
fn test_create_season_success() {
    let series_id = SeriesId::new();
    let cmd = CreateSeason {
        id: Uuid::now_v7(),
        series_id,
        number: 2,
        title: Some("Autumn Run".into()),
    };
    let result = SeasonAggregate::default().handle(cmd, make_ctx());
    assert!(result.is_ok());
    match result.unwrap().into_iter().next().unwrap() {
        SeasonEvent::SeasonCreated {
            id,
            series_id: sid,
            number,
            title,
            version,
        } => {
            assert_ne!(id, Uuid::nil());
            assert_eq!(sid, series_id);
            assert_eq!(number, 2);
            assert_eq!(title, Some("Autumn Run".into()));
            assert_eq!(version, AggregateVersion::INITIAL);
        }
        _ => panic!("Expected SeasonCreated"),
    }
}

#[test]
fn test_create_season_without_title() {
    let cmd = CreateSeason {
        id: Uuid::now_v7(),
        series_id: SeriesId::new(),
        number: 3,
        title: None,
    };
    let events = SeasonAggregate::default().handle(cmd, make_ctx()).unwrap();
    match events.into_iter().next().unwrap() {
        SeasonEvent::SeasonCreated { title, .. } => assert_eq!(title, None),
        _ => panic!("Expected SeasonCreated"),
    }
}

#[test]
fn test_rename_season_success() {
    let mut agg = create_season();
    let event = agg
        .handle(
            RenameSeason {
                id: agg.id,
                title: Some("Renamed".into()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, event);
    assert_eq!(agg.title, Some("Renamed".into()));
    assert_eq!(agg.version, AggregateVersion(2));
}

#[test]
fn test_rename_season_idempotency() {
    let agg = create_season();
    let result = agg.handle(
        RenameSeason {
            id: agg.id,
            title: agg.title.clone(),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        SeasonError::ValidationError(ref m) if m.contains("unchanged")
    ));
}

#[test]
fn test_rename_season_wrong_version() {
    let agg = create_season();
    let result = agg.handle(
        RenameSeason {
            id: agg.id,
            title: Some("X".into()),
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        SeasonError::ValidationError(ref m) if m.contains("version mismatch")
    ));
}

/// Verify that apply() actually mutates aggregate state — catches mutants
/// that replace the `apply` body with `()`.
#[test]
fn test_apply_updates_state() {
    use kameo_es::Metadata;
    let mut agg = SeasonAggregate::default();
    let id = Uuid::now_v7();
    let series_id = SeriesId::new();
    agg.apply(
        SeasonEvent::SeasonCreated {
            id,
            series_id,
            number: 7,
            title: Some("Liese".into()),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    assert_eq!(
        agg.title,
        Some("Liese".into()),
        "apply() should set the title"
    );
    assert_eq!(agg.id, id, "apply() should set the id");
    assert_eq!(agg.number, 7);
    assert_eq!(agg.series_id, series_id);
    assert_eq!(agg.version, AggregateVersion::INITIAL);
}

/// Verify that RenameSeason checks `!=` (not `==`) so passing the same
/// title correctly returns an idempotency error.
#[test]
fn test_rename_uses_not_equal() {
    use kameo_es::Metadata;
    let mut agg = SeasonAggregate::default();
    let id = Uuid::now_v7();
    agg.apply(
        SeasonEvent::SeasonCreated {
            id,
            series_id: SeriesId::new(),
            number: 1,
            title: Some("A".into()),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    agg.apply(
        SeasonEvent::SeasonRenamed {
            id,
            title: Some("B".into()),
            version: AggregateVersion(2),
        },
        Metadata::default(),
    );
    let result = agg.handle(
        RenameSeason {
            id,
            title: Some("B".into()),
            version: AggregateVersion(2),
        },
        make_ctx(),
    );
    assert!(
        result.is_err(),
        "identical title should be rejected (idempotency check)"
    );
}
