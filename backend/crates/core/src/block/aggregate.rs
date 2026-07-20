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
#[path = "aggregate_test.rs"]
mod tests;
