// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! The `Outfit` aggregate — a character's composed look.
//!
//! Aggregate-local invariants: non-blank name, version fence, deduplicated
//! insertion-ordered `piece_ids`, state-based no-ops for add-existing /
//! remove-absent / rename-identical. Cross-aggregate facts (character exists,
//! season not archived, piece exists) are API-edge pre-checks — the aggregate
//! never queries a projection or another stream.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EventMetadata};

use super::commands::*;
use super::error::OutfitError;
use super::events::*;

/// State persisted by the `Outfit` aggregate.
#[derive(Debug, Clone, Default)]
pub struct OutfitAggregate {
    pub id: Uuid,
    /// Mandatory character binding — an outfit always belongs to exactly one
    /// character, whose season provides the outfit's scope.
    pub character_id: Uuid,
    /// Required, non-blank look name.
    pub name: String,
    /// Insertion-ordered, deduplicated pieces. Layering is permitted: several
    /// pieces of the same category may coexist.
    pub piece_ids: Vec<Uuid>,
    /// `Some(source)` when this outfit was forked via `CreateOutfitVariant`.
    /// Never mutated afterwards.
    pub variant_of: Option<Uuid>,
    pub photos: Vec<Uuid>,
    pub notes: String,
    /// Set by the terminal `OutfitDeleted` event: a deleted
    /// aggregate rejects every further command (issue #770 — a delete
    /// must not leave a stream that still accepts mutations).
    pub deleted: bool,
    pub version: AggregateVersion,
}

/// Trim a name and reject the blank case (422 `outfit.validation`).
fn normalize_name(raw: &str) -> Result<String, OutfitError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(OutfitError::EmptyName);
    }
    Ok(trimmed.to_string())
}

/// Collapse duplicates, preserving first-occurrence order.
fn dedup_pieces(piece_ids: Vec<Uuid>) -> Vec<Uuid> {
    let mut out: Vec<Uuid> = Vec::with_capacity(piece_ids.len());
    for piece_id in piece_ids {
        if !out.contains(&piece_id) {
            out.push(piece_id);
        }
    }
    out
}

impl Entity for OutfitAggregate {
    type ID = Uuid;
    type Event = OutfitEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "outfit"
    }
}

impl Apply for OutfitAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            // Issue #770 (dev data reset): the delete carries no further state
            // change — the projector removes the projection row and the stream
            // keeps its history for the audit trail.
            OutfitEvent::OutfitDeleted { version, .. } => {
                self.deleted = true;
                self.version = version;
            }
            OutfitEvent::OutfitCreated {
                id,
                character_id,
                name,
                piece_ids,
                photos,
                notes,
                version,
            } => {
                self.id = id;
                self.character_id = character_id;
                self.name = name;
                self.piece_ids = piece_ids;
                self.variant_of = None;
                self.photos = photos;
                self.notes = notes;
                self.version = version;
            }
            OutfitEvent::OutfitVariantCreated {
                id,
                source_outfit_id,
                character_id,
                name,
                piece_ids,
                photos,
                notes,
                version,
            } => {
                self.id = id;
                self.character_id = character_id;
                self.name = name;
                self.piece_ids = piece_ids;
                self.variant_of = Some(source_outfit_id);
                self.photos = photos;
                self.notes = notes;
                self.version = version;
            }
            OutfitEvent::OutfitRenamed { name, version, .. } => {
                self.name = name;
                self.version = version;
            }
            OutfitEvent::OutfitNotesUpdated { notes, version, .. } => {
                self.notes = notes;
                self.version = version;
            }
            OutfitEvent::OutfitPieceAdded {
                piece_id, version, ..
            } => {
                if !self.piece_ids.contains(&piece_id) {
                    self.piece_ids.push(piece_id);
                }
                self.version = version;
            }
            OutfitEvent::OutfitPieceRemoved {
                piece_id, version, ..
            } => {
                self.piece_ids.retain(|id| *id != piece_id);
                self.version = version;
            }
            OutfitEvent::OutfitPhotoLinked {
                photo_id, version, ..
            } => {
                if !self.photos.contains(&photo_id) {
                    self.photos.push(photo_id);
                }
                self.version = version;
            }
            OutfitEvent::OutfitPhotoUnlinked {
                photo_id, version, ..
            } => {
                self.photos.retain(|&id| id != photo_id);
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): commands validate invariants and emit
// events. Aggregate state is mutated only through `Apply`.
impl Command<CreateOutfit> for OutfitAggregate {
    type Error = OutfitError;
    fn handle(
        &self,
        cmd: CreateOutfit,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.deleted {
            return Err(OutfitError::Deleted { id: self.id });
        }
        let name = normalize_name(&cmd.name)?;
        Ok(vec![OutfitEvent::OutfitCreated {
            id: cmd.id,
            character_id: cmd.character_id,
            name,
            piece_ids: dedup_pieces(cmd.piece_ids),
            photos: Vec::new(),
            notes: String::new(),
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<CreateOutfitVariant> for OutfitAggregate {
    type Error = OutfitError;
    fn handle(
        &self,
        cmd: CreateOutfitVariant,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.deleted {
            return Err(OutfitError::Deleted { id: self.id });
        }
        let name = normalize_name(&cmd.name)?;
        Ok(vec![OutfitEvent::OutfitVariantCreated {
            id: cmd.id,
            source_outfit_id: cmd.source_outfit_id,
            character_id: cmd.character_id,
            name,
            piece_ids: dedup_pieces(cmd.piece_ids),
            photos: Vec::new(),
            notes: cmd.notes,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<RenameOutfit> for OutfitAggregate {
    type Error = OutfitError;
    fn handle(
        &self,
        cmd: RenameOutfit,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.deleted {
            return Err(OutfitError::Deleted { id: self.id });
        }
        if cmd.version != self.version {
            return Err(OutfitError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        let name = normalize_name(&cmd.name)?;
        if name == self.name {
            return Ok(vec![]);
        }
        Ok(vec![OutfitEvent::OutfitRenamed {
            id: self.id,
            name,
            version: self.version.next(),
        }])
    }
}

impl Command<UpdateOutfitNotes> for OutfitAggregate {
    type Error = OutfitError;
    fn handle(
        &self,
        cmd: UpdateOutfitNotes,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.deleted {
            return Err(OutfitError::Deleted { id: self.id });
        }
        if cmd.version != self.version {
            return Err(OutfitError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if cmd.notes == self.notes {
            return Err(OutfitError::ValidationError("Notes unchanged".into()));
        }
        Ok(vec![OutfitEvent::OutfitNotesUpdated {
            id: self.id,
            notes: cmd.notes,
            version: self.version.next(),
        }])
    }
}

impl Command<AddPieceToOutfit> for OutfitAggregate {
    type Error = OutfitError;
    fn handle(
        &self,
        cmd: AddPieceToOutfit,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.deleted {
            return Err(OutfitError::Deleted { id: self.id });
        }
        if cmd.version != self.version {
            return Err(OutfitError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        // State-based no-op: the piece is already part of the look.
        if self.piece_ids.contains(&cmd.piece_id) {
            return Ok(vec![]);
        }
        // The projector writes `position` from the event so it never has to
        // derive ordering from projection state.
        let Ok(position) = u32::try_from(self.piece_ids.len()) else {
            return Err(OutfitError::ValidationError(
                "Outfit holds too many pieces".into(),
            ));
        };
        Ok(vec![OutfitEvent::OutfitPieceAdded {
            id: self.id,
            piece_id: cmd.piece_id,
            position,
            version: self.version.next(),
        }])
    }
}

impl Command<RemovePieceFromOutfit> for OutfitAggregate {
    type Error = OutfitError;
    fn handle(
        &self,
        cmd: RemovePieceFromOutfit,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.deleted {
            return Err(OutfitError::Deleted { id: self.id });
        }
        if cmd.version != self.version {
            return Err(OutfitError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if !self.piece_ids.contains(&cmd.piece_id) {
            return Ok(vec![]);
        }
        Ok(vec![OutfitEvent::OutfitPieceRemoved {
            id: self.id,
            piece_id: cmd.piece_id,
            version: self.version.next(),
        }])
    }
}

impl Command<LinkOutfitPhoto> for OutfitAggregate {
    type Error = OutfitError;
    fn handle(
        &self,
        cmd: LinkOutfitPhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.deleted {
            return Err(OutfitError::Deleted { id: self.id });
        }
        if cmd.version != self.version {
            return Err(OutfitError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if self.photos.contains(&cmd.photo_id) {
            return Ok(vec![]);
        }
        Ok(vec![OutfitEvent::OutfitPhotoLinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: self.version.next(),
        }])
    }
}

impl Command<UnlinkOutfitPhoto> for OutfitAggregate {
    type Error = OutfitError;
    fn handle(
        &self,
        cmd: UnlinkOutfitPhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.deleted {
            return Err(OutfitError::Deleted { id: self.id });
        }
        if cmd.version != self.version {
            return Err(OutfitError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if !self.photos.contains(&cmd.photo_id) {
            return Ok(vec![]);
        }
        Ok(vec![OutfitEvent::OutfitPhotoUnlinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: self.version.next(),
        }])
    }
}

// Issue #770 (dev data reset): the delete path for a Outfit. See
// `DeleteOutfit` for why it has no HTTP route and no port method.
impl Command<DeleteOutfit> for OutfitAggregate {
    type Error = OutfitError;
    fn handle(
        &self,
        cmd: DeleteOutfit,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // Idempotent: deleting an already-deleted aggregate is a no-op.
        if self.deleted {
            return Ok(vec![]);
        }
        // An absent aggregate replays to a default state; deleting it must not
        // fabricate a stream. A repeat delete on an existing aggregate is
        // idempotent at the projection (the DELETE matches nothing twice).
        if self.id.is_nil() {
            return Err(OutfitError::NotFound { id: cmd.id });
        }
        Ok(vec![OutfitEvent::OutfitDeleted {
            id: self.id,
            version: self.version.next(),
        }])
    }
}
