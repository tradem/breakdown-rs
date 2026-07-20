// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! The `ShootingDay` event-sourced aggregate.

use chrono::NaiveDate;
use kameo_es::{Apply, Command, Context, Entity, Metadata};

use crate::shared::{AggregateVersion, EpisodeId, LexicalSortKey, ShootingDayId};

use super::commands::{
    ArchiveShootingDay, CreateShootingDay, ReorderShootingDay, RenameShootingDay,
    RescheduleShootingDay,
};
use super::error::ShootingDayError;
use super::events::{ShootingDayEvent, ShootingDaySource};

/// State persisted by the `ShootingDay` aggregate.
///
/// A `ShootingDay` is scoped to exactly one `Episode` (its parent in the
/// `Series → Season → Block → Episode → ShootingDay` leaf). It has no
/// knowledge of which `Scene`s reference it; the `Scene` aggregate owns that
/// link. Deletion is modelled as a terminal soft-archive (`archived = true`).
#[derive(Debug, Clone)]
pub struct ShootingDayAggregate {
    pub id: ShootingDayId,
    pub episode_id: EpisodeId,
    pub label: Option<String>,
    pub order_key: LexicalSortKey,
    pub date: Option<NaiveDate>,
    pub source: ShootingDaySource,
    pub archived: bool,
    pub version: AggregateVersion,
}

impl Default for ShootingDayAggregate {
    fn default() -> Self {
        Self {
            id: ShootingDayId::default(),
            episode_id: EpisodeId::default(),
            label: None,
            order_key: LexicalSortKey::from_static("0"),
            date: None,
            source: ShootingDaySource::Manual,
            archived: false,
            version: AggregateVersion::default(),
        }
    }
}

impl Entity for ShootingDayAggregate {
    type ID = ShootingDayId;
    type Event = ShootingDayEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "shooting_day"
    }
}

impl Apply for ShootingDayAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            ShootingDayEvent::ShootingDayCreated {
                id,
                episode_id,
                label,
                order_key,
                date,
                source,
                version,
            } => {
                self.id = id;
                self.episode_id = episode_id;
                self.label = label;
                self.order_key = order_key;
                self.date = date;
                self.source = source;
                self.archived = false;
                self.version = version;
            }
            ShootingDayEvent::ShootingDayRenamed { label, version, .. } => {
                self.label = label;
                self.version = version;
            }
            ShootingDayEvent::ShootingDayRescheduled { date, version, .. } => {
                self.date = date;
                self.version = version;
            }
            ShootingDayEvent::ShootingDayReordered { order_key, version, .. } => {
                self.order_key = order_key;
                self.version = version;
            }
            ShootingDayEvent::ShootingDayArchived { version, .. } => {
                self.archived = true;
                self.version = version;
            }
        }
    }
}

impl Command<CreateShootingDay> for ShootingDayAggregate {
    type Error = ShootingDayError;
    fn handle(
        &self,
        cmd: CreateShootingDay,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        Ok(vec![ShootingDayEvent::ShootingDayCreated {
            id: cmd.id,
            episode_id: cmd.episode_id,
            label: cmd.label,
            order_key: cmd.order_key,
            date: cmd.date,
            source: cmd.source,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<RenameShootingDay> for ShootingDayAggregate {
    type Error = ShootingDayError;
    fn handle(
        &self,
        cmd: RenameShootingDay,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.archived {
            return Err(ShootingDayError::ArchivedCannotBeMutated { id: self.id });
        }
        if cmd.version != self.version {
            return Err(ShootingDayError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        let new_version = self.version.next();
        Ok(vec![ShootingDayEvent::ShootingDayRenamed {
            id: self.id,
            label: cmd.label,
            version: new_version,
        }])
    }
}

impl Command<RescheduleShootingDay> for ShootingDayAggregate {
    type Error = ShootingDayError;
    fn handle(
        &self,
        cmd: RescheduleShootingDay,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.archived {
            return Err(ShootingDayError::ArchivedCannotBeMutated { id: self.id });
        }
        if cmd.version != self.version {
            return Err(ShootingDayError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        let new_version = self.version.next();
        Ok(vec![ShootingDayEvent::ShootingDayRescheduled {
            id: self.id,
            date: cmd.date,
            version: new_version,
        }])
    }
}

impl Command<ReorderShootingDay> for ShootingDayAggregate {
    type Error = ShootingDayError;
    fn handle(
        &self,
        cmd: ReorderShootingDay,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.archived {
            return Err(ShootingDayError::ArchivedCannotBeMutated { id: self.id });
        }
        if cmd.version != self.version {
            return Err(ShootingDayError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        let new_version = self.version.next();
        Ok(vec![ShootingDayEvent::ShootingDayReordered {
            id: self.id,
            order_key: cmd.order_key,
            version: new_version,
        }])
    }
}

impl Command<ArchiveShootingDay> for ShootingDayAggregate {
    type Error = ShootingDayError;
    fn handle(
        &self,
        cmd: ArchiveShootingDay,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(ShootingDayError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        // Idempotent-reject: a day that is already archived stays archived and
        // emits no further event.
        if self.archived {
            return Err(ShootingDayError::ArchivedCannotBeMutated { id: self.id });
        }
        let new_version = self.version.next();
        Ok(vec![ShootingDayEvent::ShootingDayArchived {
            id: self.id,
            version: new_version,
        }])
    }
}

#[cfg(test)]
#[path = "aggregate_test.rs"]
mod tests;
