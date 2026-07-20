// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Costume aggregate.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::AggregateVersion;

use super::commands::*;
use super::error::CostumeError;
use super::events::*;

/// State persisted by the Costume aggregate.
#[derive(Debug, Clone, Default)]
pub struct CostumeAggregate {
    pub id: Uuid,
    pub character_id: Option<Uuid>,
    pub notes: String,
    pub details: Vec<CostumeDetail>,
    pub photos: Vec<Uuid>,
    pub version: AggregateVersion,
}

impl Entity for CostumeAggregate {
    type ID = Uuid;
    type Event = CostumeEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "costume"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for CostumeAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            CostumeEvent::CostumeCreated {
                id,
                character_id,
                notes,
                details,
                photos,
                version,
            } => {
                self.id = id;
                self.character_id = character_id;
                self.notes = notes;
                self.details = details;
                self.photos = photos;
                self.version = version;
            }
            CostumeEvent::CostumeNotesUpdated { notes, version, .. } => {
                self.notes = notes;
                self.version = version;
            }
            CostumeEvent::CostumeAssignedToCharacter {
                character_id,
                version,
                ..
            } => {
                self.character_id = Some(character_id);
                self.version = version;
            }
            CostumeEvent::CostumeUnassigned { version, .. } => {
                self.character_id = None;
                self.version = version;
            }
            CostumeEvent::DetailAdded {
                detail, version, ..
            } => {
                self.details.push(detail);
                self.version = version;
            }
            CostumeEvent::DetailRemoved {
                detail_id, version, ..
            } => {
                self.details.retain(|d| d.id != detail_id);
                self.version = version;
            }
            CostumeEvent::PhotoLinked {
                photo_id, version, ..
            } => {
                if !self.photos.contains(&photo_id) {
                    self.photos.push(photo_id);
                }
                self.version = version;
            }
            CostumeEvent::PhotoUnlinked {
                photo_id, version, ..
            } => {
                self.photos.retain(|&id| id != photo_id);
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
impl Command<CreateCostume> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: CreateCostume,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        Ok(vec![CostumeEvent::CostumeCreated {
            id: cmd.id,
            character_id: None,
            notes: String::new(),
            details: Vec::new(),
            photos: Vec::new(),
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<UpdateCostumeNotes> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: UpdateCostumeNotes,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if cmd.notes == self.notes {
            return Err(CostumeError::ValidationError("Notes unchanged".into()));
        }
        Ok(vec![CostumeEvent::CostumeNotesUpdated {
            id: self.id,
            notes: cmd.notes,
            version: self.version.next(),
        }])
    }
}

impl Command<AssignCostumeToCharacter> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: AssignCostumeToCharacter,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if let Some(assigned_to) = self.character_id {
            if assigned_to != cmd.character_id {
                return Err(CostumeError::AlreadyAssigned { assigned_to });
            }
            return Err(CostumeError::ValidationError(
                "Costume already assigned to this character".into(),
            ));
        }
        Ok(vec![CostumeEvent::CostumeAssignedToCharacter {
            id: self.id,
            character_id: cmd.character_id,
            version: self.version.next(),
        }])
    }
}

impl Command<UnassignCostume> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: UnassignCostume,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if self.character_id.is_none() {
            return Err(CostumeError::ValidationError(
                "Costume is not currently assigned".into(),
            ));
        }
        Ok(vec![CostumeEvent::CostumeUnassigned {
            id: self.id,
            version: self.version.next(),
        }])
    }
}

impl Command<AddDetail> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: AddDetail,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        Ok(vec![CostumeEvent::DetailAdded {
            id: self.id,
            detail: cmd.detail,
            version: self.version.next(),
        }])
    }
}

impl Command<RemoveDetail> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: RemoveDetail,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.details.iter().any(|d| d.id == cmd.detail_id) {
            return Err(CostumeError::ValidationError("Detail not found".into()));
        }
        Ok(vec![CostumeEvent::DetailRemoved {
            id: self.id,
            detail_id: cmd.detail_id,
            version: self.version.next(),
        }])
    }
}

impl Command<LinkPhoto> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: LinkPhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if self.photos.contains(&cmd.photo_id) {
            return Err(CostumeError::ValidationError("Photo already linked".into()));
        }
        Ok(vec![CostumeEvent::PhotoLinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: self.version.next(),
        }])
    }
}

impl Command<UnlinkPhoto> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: UnlinkPhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.photos.contains(&cmd.photo_id) {
            return Err(CostumeError::ValidationError("Photo is not linked".into()));
        }
        Ok(vec![CostumeEvent::PhotoUnlinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: self.version.next(),
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
#[path = "aggregate_test.rs"]
mod tests;
