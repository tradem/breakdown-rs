// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Outfit events.
//!
//! An `Outfit` is a composed look worn by **one** character: it aggregates
//! `0..n` fundus `Piece`s (layering is explicitly allowed, including several
//! pieces of the same category) and is what scenes cast onto a character's
//! beats. See OpenSpec change `separate-piece-and-outfit-domain`.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::AggregateVersion;

/// All state transitions of the `Outfit` aggregate.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum OutfitEvent {
    /// A new outfit was created for a character. `piece_ids` may be empty
    /// (an empty shell establishes a named look before the garments exist).
    OutfitCreated {
        id: Uuid,
        /// Mandatory: an outfit always belongs to exactly one character.
        character_id: Uuid,
        /// Required, non-blank look name ("Alltagslook Tag 1", "OP", "KHK").
        name: String,
        /// Insertion-ordered, deduplicated.
        piece_ids: Vec<Uuid>,
        photos: Vec<Uuid>,
        notes: String,
        version: AggregateVersion,
    },
    /// A **copy-on-write** variant of an existing outfit was created as an
    /// independent stream. The source's data (character, pieces, notes) is
    /// resolved at the API edge and carried in the event — the aggregate never
    /// reads the source.
    OutfitVariantCreated {
        id: Uuid,
        source_outfit_id: Uuid,
        character_id: Uuid,
        name: String,
        piece_ids: Vec<Uuid>,
        photos: Vec<Uuid>,
        notes: String,
        version: AggregateVersion,
    },
    /// The outfit was renamed (non-blank).
    OutfitRenamed {
        id: Uuid,
        name: String,
        version: AggregateVersion,
    },
    /// Free-form notes were replaced.
    OutfitNotesUpdated {
        id: Uuid,
        notes: String,
        version: AggregateVersion,
    },
    /// A piece was added to the outfit. `position` is aggregate-computed
    /// (current length) so the projector never has to recompute ordering.
    OutfitPieceAdded {
        id: Uuid,
        piece_id: Uuid,
        position: u32,
        version: AggregateVersion,
    },
    /// A piece was removed from the outfit (surviving positions are not
    /// renumbered — the ordering is presentation-only).
    OutfitPieceRemoved {
        id: Uuid,
        piece_id: Uuid,
        version: AggregateVersion,
    },
    /// A photo (usually a fitting photo) was linked to the outfit.
    OutfitPhotoLinked {
        id: Uuid,
        photo_id: Uuid,
        version: AggregateVersion,
    },
    /// A photo link was removed from the outfit.
    OutfitPhotoUnlinked {
        id: Uuid,
        photo_id: Uuid,
        version: AggregateVersion,
    },
    /// The Outfit was deleted (issue #770, dev data reset). The projector
    /// removes the row; the stream keeps its history and the audit row.
    OutfitDeleted { id: Uuid, version: AggregateVersion },
}

impl kameo_es::EventType for OutfitEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::OutfitCreated { .. } => "OutfitCreated",
            Self::OutfitVariantCreated { .. } => "OutfitVariantCreated",
            Self::OutfitRenamed { .. } => "OutfitRenamed",
            Self::OutfitNotesUpdated { .. } => "OutfitNotesUpdated",
            Self::OutfitPieceAdded { .. } => "OutfitPieceAdded",
            Self::OutfitPieceRemoved { .. } => "OutfitPieceRemoved",
            Self::OutfitPhotoLinked { .. } => "OutfitPhotoLinked",
            Self::OutfitPhotoUnlinked { .. } => "OutfitPhotoUnlinked",
            Self::OutfitDeleted { .. } => "OutfitDeleted",
        }
    }
}
