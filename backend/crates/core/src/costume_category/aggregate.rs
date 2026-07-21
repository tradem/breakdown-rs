// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! CostumeCategory aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, CostumeCategoryId, LexicalSortKey, SeasonId};

use super::commands::*;
use super::error::CostumeCategoryError;
use super::events::CostumeCategoryEvent;

/// State persisted by the CostumeCategory aggregate.
///
/// A CostumeCategory is scoped to exactly one `Season` (matching `Character`).
/// It has no knowledge of which `CostumeDetail`s reference it; deletion is
/// modelled as a terminal soft-archive (`archived = true`).
#[derive(Debug, Clone)]
pub struct CostumeCategoryAggregate {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub name: String,
    pub order_key: LexicalSortKey,
    pub archived: bool,
    pub version: AggregateVersion,
}

impl Default for CostumeCategoryAggregate {
    fn default() -> Self {
        Self {
            id: Uuid::nil(),
            season_id: SeasonId::default(),
            name: String::new(),
            order_key: LexicalSortKey::from_static("0"),
            archived: false,
            version: AggregateVersion::default(),
        }
    }
}

impl Entity for CostumeCategoryAggregate {
    type ID = Uuid;
    type Event = CostumeCategoryEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "costume_category"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for CostumeCategoryAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            CostumeCategoryEvent::CostumeCategoryCreated {
                id,
                season_id,
                name,
                order_key,
                version,
            } => {
                self.id = id;
                self.season_id = season_id;
                self.name = name;
                self.order_key = order_key;
                self.archived = false;
                self.version = version;
            }
            CostumeCategoryEvent::CostumeCategoryRenamed { name, version, .. } => {
                self.name = name;
                self.version = version;
            }
            CostumeCategoryEvent::CostumeCategoryReordered {
                order_key, version, ..
            } => {
                self.order_key = order_key;
                self.version = version;
            }
            CostumeCategoryEvent::CostumeCategoryArchived { version, .. } => {
                self.archived = true;
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
impl Command<CreateCostumeCategory> for CostumeCategoryAggregate {
    type Error = CostumeCategoryError;
    fn handle(
        &self,
        cmd: CreateCostumeCategory,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.name.trim().is_empty() {
            return Err(CostumeCategoryError::ValidationError(
                "CostumeCategory name must not be empty".into(),
            ));
        }
        Ok(vec![CostumeCategoryEvent::CostumeCategoryCreated {
            id: cmd.id,
            season_id: cmd.season_id,
            name: cmd.name,
            order_key: cmd.order_key,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<RenameCostumeCategory> for CostumeCategoryAggregate {
    type Error = CostumeCategoryError;
    fn handle(
        &self,
        cmd: RenameCostumeCategory,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.archived {
            return Err(CostumeCategoryError::ArchivedCannotBeMutated {
                id: CostumeCategoryId(self.id),
            });
        }
        if cmd.version != self.version {
            return Err(CostumeCategoryError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if cmd.name.trim().is_empty() {
            return Err(CostumeCategoryError::ValidationError(
                "CostumeCategory name must not be empty".into(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![CostumeCategoryEvent::CostumeCategoryRenamed {
            id: self.id,
            name: cmd.name,
            version: new_version,
        }])
    }
}

impl Command<ReorderCostumeCategory> for CostumeCategoryAggregate {
    type Error = CostumeCategoryError;
    fn handle(
        &self,
        cmd: ReorderCostumeCategory,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.archived {
            return Err(CostumeCategoryError::ArchivedCannotBeMutated {
                id: CostumeCategoryId(self.id),
            });
        }
        if cmd.version != self.version {
            return Err(CostumeCategoryError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        let new_version = self.version.next();
        Ok(vec![CostumeCategoryEvent::CostumeCategoryReordered {
            id: self.id,
            order_key: cmd.order_key,
            version: new_version,
        }])
    }
}

impl Command<ArchiveCostumeCategory> for CostumeCategoryAggregate {
    type Error = CostumeCategoryError;
    fn handle(
        &self,
        cmd: ArchiveCostumeCategory,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeCategoryError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        // Idempotent-reject: a category that is already archived stays archived
        // and emits no further event.
        if self.archived {
            return Err(CostumeCategoryError::ArchivedCannotBeMutated {
                id: CostumeCategoryId(self.id),
            });
        }
        let new_version = self.version.next();
        Ok(vec![CostumeCategoryEvent::CostumeCategoryArchived {
            id: self.id,
            version: new_version,
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
#[path = "aggregate_test.rs"]
mod tests;
