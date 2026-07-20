// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Season aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, SeriesId};

use super::commands::{CreateSeason, RenameSeason};
use super::error::SeasonError;
use super::events::SeasonEvent;

/// State persisted by the Season aggregate.
///
/// A Season is scoped to exactly one `SeriesId`. It does NOT own per-Block or
/// per-Episode containment; that is derived from events in the read model.
#[derive(Debug, Clone, Default)]
pub struct SeasonAggregate {
    pub id: Uuid,
    pub series_id: SeriesId,
    pub number: i32,
    pub title: Option<String>,
    pub version: AggregateVersion,
}

impl Entity for SeasonAggregate {
    type ID = Uuid;
    type Event = SeasonEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "season"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for SeasonAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            SeasonEvent::SeasonCreated {
                id,
                series_id,
                number,
                title,
                version,
            } => {
                self.id = id;
                self.series_id = series_id;
                self.number = number;
                self.title = title;
                self.version = version;
            }
            SeasonEvent::SeasonRenamed { title, version, .. } => {
                self.title = title;
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
impl Command<CreateSeason> for SeasonAggregate {
    type Error = SeasonError;
    fn handle(
        &self,
        cmd: CreateSeason,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // Series-global numbering uniqueness is enforced by a Postgres unique
        // index on (series_id, number) in the projection, NOT here (CQRS
        // write/read split — the aggregate cannot read its siblings).
        Ok(vec![SeasonEvent::SeasonCreated {
            id: cmd.id,
            series_id: cmd.series_id,
            number: cmd.number,
            title: cmd.title,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<RenameSeason> for SeasonAggregate {
    type Error = SeasonError;
    fn handle(
        &self,
        cmd: RenameSeason,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SeasonError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if cmd.title == self.title {
            return Err(SeasonError::ValidationError(
                "Season title unchanged".into(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![SeasonEvent::SeasonRenamed {
            id: self.id,
            title: cmd.title,
            version: new_version,
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
#[path = "aggregate_test.rs"]
mod tests;
