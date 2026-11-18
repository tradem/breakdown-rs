// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Piece events.
//!
//! A `Piece` is a single garment in the wardrobe **fundus** (Kleidungsstück).
//! It is deliberately character-free: the character binding lives on the
//! `Outfit` aggregate (`crate::outfit`), which composes `0..n` pieces into a
//! look. See OpenSpec change `separate-piece-and-outfit-domain`.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, CostumeCategoryId};

/// Pure-description element of a piece (e.g. "Knöpfe vorne").
///
/// Since the clean cut there is **no** `category_id` on a detail: the single
/// category is `Piece.category_id` (`PieceCategorySet`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct PieceDetail {
    pub id: Uuid,
    /// Free-form per-detail micro-title (e.g. "Rote Lederjacke"). Optional.
    #[serde(default)]
    pub subject: Option<String>,
    /// The description (never reinterpreted as `subject`).
    pub text: String,
}

/// All state transitions of the `Piece` aggregate.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum PieceEvent {
    /// A new fundus piece was catalogued.
    PieceCreated {
        id: Uuid,
        /// Required, non-blank display name ("Rote Lederjacke").
        name: String,
        /// The piece's single category (n:1 vocabulary reference), if set at
        /// creation time.
        #[serde(default)]
        category_id: Option<CostumeCategoryId>,
        /// Optional initial repertoire season. `None` = not yet filed into a
        /// season; the repertoire is maintained by `PieceAddedToSeason`.
        #[serde(default)]
        season_id: Option<Uuid>,
        notes: String,
        details: Vec<PieceDetail>,
        photos: Vec<Uuid>,
        version: AggregateVersion,
    },
    /// The piece was renamed (non-blank; names are not unique).
    PieceRenamed {
        id: Uuid,
        name: String,
        version: AggregateVersion,
    },
    /// Free-form notes were replaced.
    PieceNotesUpdated {
        id: Uuid,
        notes: String,
        version: AggregateVersion,
    },
    /// The piece was added to a season's **repertoire** (m:n over its life).
    PieceAddedToSeason {
        id: Uuid,
        season_id: Uuid,
        version: AggregateVersion,
    },
    /// The piece was removed from a season's repertoire.
    PieceRemovedFromSeason {
        id: Uuid,
        season_id: Uuid,
        version: AggregateVersion,
    },
    /// A description detail was appended.
    PieceDetailAdded {
        id: Uuid,
        detail: PieceDetail,
        version: AggregateVersion,
    },
    /// A detail was replaced in place (the **full** detail, not a patch).
    PieceDetailUpdated {
        id: Uuid,
        detail: PieceDetail,
        version: AggregateVersion,
    },
    /// A detail was removed.
    PieceDetailRemoved {
        id: Uuid,
        detail_id: Uuid,
        version: AggregateVersion,
    },
    /// The piece's single category was set or cleared (`None` clears).
    PieceCategorySet {
        id: Uuid,
        category_id: Option<CostumeCategoryId>,
        version: AggregateVersion,
    },
    /// A photo was linked to the piece (direct Anprobe photo).
    PiecePhotoLinked {
        id: Uuid,
        photo_id: Uuid,
        version: AggregateVersion,
    },
    /// A photo link was removed from the piece.
    PiecePhotoUnlinked {
        id: Uuid,
        photo_id: Uuid,
        version: AggregateVersion,
    },
    /// The Piece was deleted (issue #770, dev data reset). The projector
    /// removes the row; the stream keeps its history and the audit row.
    PieceDeleted { id: Uuid, version: AggregateVersion },
}

impl kameo_es::EventType for PieceEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::PieceCreated { .. } => "PieceCreated",
            Self::PieceRenamed { .. } => "PieceRenamed",
            Self::PieceNotesUpdated { .. } => "PieceNotesUpdated",
            Self::PieceAddedToSeason { .. } => "PieceAddedToSeason",
            Self::PieceRemovedFromSeason { .. } => "PieceRemovedFromSeason",
            Self::PieceDetailAdded { .. } => "PieceDetailAdded",
            Self::PieceDetailUpdated { .. } => "PieceDetailUpdated",
            Self::PieceDetailRemoved { .. } => "PieceDetailRemoved",
            Self::PieceCategorySet { .. } => "PieceCategorySet",
            Self::PiecePhotoLinked { .. } => "PiecePhotoLinked",
            Self::PiecePhotoUnlinked { .. } => "PiecePhotoUnlinked",
            Self::PieceDeleted { .. } => "PieceDeleted",
        }
    }
}
