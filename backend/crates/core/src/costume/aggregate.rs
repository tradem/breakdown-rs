// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

//! Costume aggregate.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, CostumeCategoryId, EventMetadata};

use super::commands::*;
use super::error::CostumeError;
use super::events::*;

/// State persisted by the Costume aggregate.
#[derive(Debug, Clone, Default)]
pub struct CostumeAggregate {
    pub id: Uuid,
    pub character_id: Option<Uuid>,
    /// The costume's single category (issue #543): n:1 into the season-scoped
    /// `CostumeCategory` vocabulary. `None` = uncategorised. Legacy events
    /// (`CostumeCreated`/`DetailAdded` with categorized details) derive this
    /// state via the first-wins replay rule.
    pub category_id: Option<CostumeCategoryId>,
    pub notes: String,
    pub details: Vec<CostumeDetail>,
    pub photos: Vec<Uuid>,
    pub version: AggregateVersion,
}

/// Replay-derivation rule (issue #543): the first detail category in event
/// order (within one event: `detail_id` ASC) becomes the costume's category
/// while it has none. Deterministic: for contradictory detail categories the
/// one with the lowest `detail_id` wins. The projector executes the identical
/// rule so projection and aggregate never diverge on a replayed stream.
fn derive_category_id(details: &[CostumeDetail]) -> Option<CostumeCategoryId> {
    details
        .iter()
        .filter(|d| d.category_id.is_some())
        .min_by_key(|d| d.id)
        .and_then(|d| d.category_id)
}

impl Entity for CostumeAggregate {
    type ID = Uuid;
    type Event = CostumeEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "costume"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for CostumeAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            CostumeEvent::CostumeCreated {
                id,
                character_id,
                season_id: _,
                notes,
                details,
                photos,
                version,
            } => {
                self.id = id;
                self.character_id = character_id;
                self.category_id = derive_category_id(&details);
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
                // Replay-derivation (issue #543): adopt the detail's category
                // while the costume still has none (first-wins). Later
                // categorized details never overwrite an adopted category.
                if self.category_id.is_none() {
                    self.category_id = detail.category_id;
                }
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
            CostumeEvent::CostumeCategorySet {
                category_id,
                version,
                ..
            } => {
                self.category_id = category_id;
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
            season_id: cmd.season_id.map(|s| s.0),
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
            return Err(CostumeError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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
            return Err(CostumeError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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
            return Err(CostumeError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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
            return Err(CostumeError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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
            return Err(CostumeError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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
            return Err(CostumeError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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
            return Err(CostumeError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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

impl Command<SetCostumeCategory> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: SetCostumeCategory,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        // State-based no-op (issue #515 precedent): setting the category the
        // costume already carries (or clearing an already-empty one) emits no
        // event — re-dispatched commands are idempotent successes, and the
        // caller's version fence still matches. The season-scope invariant
        // (category season ∈ repertoire ∪ season(character)) is validated at
        // the API edge (409 costume-category.season-mismatch); the
        // scope-free aggregate cannot check it.
        if self.category_id == cmd.category_id {
            return Ok(vec![]);
        }
        Ok(vec![CostumeEvent::CostumeCategorySet {
            id: self.id,
            category_id: cmd.category_id,
            version: self.version.next(),
        }])
    }
}
