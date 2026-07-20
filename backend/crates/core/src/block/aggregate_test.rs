use super::*;
use chrono::NaiveDate;
use test_support::make_ctx;

fn make_block() -> BlockAggregate {
    let cmd = CreateBlock {
        id: Uuid::now_v7(),
        season_id: SeasonId::new(),
        series_id: SeriesId::new(),
        number: 1,
        start_date: None,
        end_date: None,
    };
    let events = BlockAggregate::default().handle(cmd, make_ctx()).unwrap();
    let mut agg = BlockAggregate::default();
    test_support::replay_events(&mut agg, events);
    agg
}

#[test]
fn test_create_block_without_span() {
    let season_id = SeasonId::new();
    let series_id = SeriesId::new();
    let cmd = CreateBlock {
        id: Uuid::now_v7(),
        season_id,
        series_id,
        number: 2,
        start_date: None,
        end_date: None,
    };
    let events = BlockAggregate::default().handle(cmd, make_ctx()).unwrap();
    match events.into_iter().next().unwrap() {
        BlockEvent::BlockCreated {
            id,
            season_id: sid,
            series_id: serid,
            number,
            start_date,
            end_date,
            version,
        } => {
            assert_ne!(id, Uuid::nil());
            assert_eq!(sid, season_id);
            assert_eq!(serid, series_id);
            assert_eq!(number, 2);
            assert_eq!(start_date, None);
            assert_eq!(end_date, None);
            assert_eq!(version, AggregateVersion::INITIAL);
        }
        _ => panic!("Expected BlockCreated"),
    }
}

#[test]
fn test_create_block_with_span() {
    let d1 = NaiveDate::from_ymd_opt(2024, 3, 1).unwrap();
    let d2 = NaiveDate::from_ymd_opt(2024, 3, 31).unwrap();
    let cmd = CreateBlock {
        id: Uuid::now_v7(),
        season_id: SeasonId::new(),
        series_id: SeriesId::new(),
        number: 3,
        start_date: Some(d1),
        end_date: Some(d2),
    };
    let events = BlockAggregate::default().handle(cmd, make_ctx()).unwrap();
    match events.into_iter().next().unwrap() {
        BlockEvent::BlockCreated {
            start_date,
            end_date,
            ..
        } => {
            assert_eq!(start_date, Some(d1));
            assert_eq!(end_date, Some(d2));
        }
        _ => panic!("Expected BlockCreated"),
    }
}

#[test]
fn test_update_block_time_span_success() {
    let mut agg = make_block();
    let d1 = NaiveDate::from_ymd_opt(2024, 5, 1).unwrap();
    let d2 = NaiveDate::from_ymd_opt(2024, 5, 15).unwrap();
    let event = agg
        .handle(
            UpdateBlockTimeSpan {
                id: agg.id,
                start_date: Some(d1),
                end_date: Some(d2),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, event);
    assert_eq!(agg.start_date, Some(d1));
    assert_eq!(agg.end_date, Some(d2));
    assert_eq!(agg.version, AggregateVersion(2));
}

#[test]
fn test_update_block_time_span_wrong_version() {
    let agg = make_block();
    let result = agg.handle(
        UpdateBlockTimeSpan {
            id: agg.id,
            start_date: None,
            end_date: None,
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        BlockError::ValidationError(ref m) if m.contains("version mismatch")
    ));
}

/// Verify that apply() actually mutates aggregate state — catches mutants
/// that replace the `apply` body with `()`.
#[test]
fn test_apply_updates_state() {
    use kameo_es::Metadata;
    let mut agg = BlockAggregate::default();
    let id = Uuid::now_v7();
    let d1 = NaiveDate::from_ymd_opt(2024, 1, 1).unwrap();
    agg.apply(
        BlockEvent::BlockCreated {
            id,
            season_id: SeasonId::new(),
            series_id: SeriesId::new(),
            number: 4,
            start_date: Some(d1),
            end_date: None,
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    assert_eq!(agg.number, 4, "apply() should set the number");
    assert_eq!(agg.id, id);
    assert_eq!(agg.start_date, Some(d1));
    assert_eq!(agg.version, AggregateVersion::INITIAL);
}
