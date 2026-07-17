// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Block aggregate using `kameo_es` event-sourced actor pattern.

use chrono::NaiveDate;
use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, SeasonId, SeriesId};

use super::commands::{CreateBlock, UpdateBlockTimeSpan};
use super::error::BlockError;
use super::events::BlockEvent;

/// State persisted by the Block aggregate.
///
/// A Block is scoped to exactly one `SeasonId` and groups Episodes. Its
/// `series_id` is denormalized (immutable for the Block's lifetime) so the
/// series-global `(series_id, number)` numbering unique index can be enforced
/// directly in the projection.
#[derive(Debug, Clone, Default)]
pub struct BlockAggregate {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub series_id: SeriesId,
    pub number: i32,
    pub start_date: Option<NaiveDate>,
    pub end_date: Option<NaiveDate>,
    pub version: AggregateVersion,
}

impl Entity for BlockAggregate {
    type ID = Uuid;
    type Event = BlockEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "block"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for BlockAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            BlockEvent::BlockCreated {
                id,
                season_id,
                series_id,
                number,
                start_date,
                end_date,
                version,
            } => {
                self.id = id;
                self.season_id = season_id;
                self.series_id = series_id;
                self.number = number;
                self.start_date = start_date;
                self.end_date = end_date;
                self.version = version;
            }
            BlockEvent::BlockTimeSpanUpdated {
                start_date,
                end_date,
                version,
                ..
            } => {
                self.start_date = start_date;
                self.end_date = end_date;
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
impl Command<CreateBlock> for BlockAggregate {
    type Error = BlockError;
    fn handle(
        &self,
        cmd: CreateBlock,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        Ok(vec![BlockEvent::BlockCreated {
            id: cmd.id,
            season_id: cmd.season_id,
            series_id: cmd.series_id,
            number: cmd.number,
            start_date: cmd.start_date,
            end_date: cmd.end_date,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<UpdateBlockTimeSpan> for BlockAggregate {
    type Error = BlockError;
    fn handle(
        &self,
        cmd: UpdateBlockTimeSpan,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(BlockError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![BlockEvent::BlockTimeSpanUpdated {
            id: self.id,
            start_date: cmd.start_date,
            end_date: cmd.end_date,
            version: new_version,
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
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
} // mod tests
