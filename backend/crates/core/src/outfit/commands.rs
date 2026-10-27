// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Outfit commands.
//!
//! An outfit belongs to exactly one character; its season scope is derived
//! from `character_id → Character.season_id` (read model), never stored on the
//! aggregate. `project_id` is carried for the `EventMetadata` audit trail and
//! resolved at the API edge (CQRS boundary).

use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

/// Create an outfit for a character.
///
/// `piece_ids` may be empty: named looks and fitting photos are routinely
/// established before the garments are catalogued. Duplicates are collapsed by
/// the aggregate (first occurrence wins). Character existence (404
/// `character.not-found`) and the archived-season state (409
/// `season.archived`) are API-edge pre-checks.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateOutfit {
    pub id: Uuid,
    pub character_id: Uuid,
    pub name: String,
    pub piece_ids: Vec<Uuid>,
    pub project_id: Option<ProjectId>,
}

/// Fork an existing outfit into an independent copy (copy-on-write variant).
///
/// The source's character, piece list and notes are resolved at the **API
/// edge** from `OutfitRepository` (the only legitimate read-model consumer)
/// and carried here; neither the aggregate nor the command adapter ever reads
/// the source stream or projection. Later edits to the variant never touch the
/// source — scenes referencing the original keep referenceing it.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateOutfitVariant {
    pub id: Uuid,
    pub source_outfit_id: Uuid,
    pub character_id: Uuid,
    pub name: String,
    pub piece_ids: Vec<Uuid>,
    pub notes: String,
    pub project_id: Option<ProjectId>,
}

/// Rename an outfit.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenameOutfit {
    pub id: Uuid,
    pub name: String,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Replace the outfit's free-form notes.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateOutfitNotes {
    pub id: Uuid,
    pub notes: String,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Add a piece to the outfit.
///
/// Layering is permitted: the outfit imposes no uniqueness on
/// `Piece.category_id`. Adding a piece the outfit already holds is a
/// state-based no-op (no event). Piece existence (404 `piece.not-found`) is an
/// API-edge pre-check.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AddPieceToOutfit {
    pub id: Uuid,
    pub piece_id: Uuid,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Remove a piece from the outfit. Removing an absent piece is a state-based
/// no-op (no event).
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemovePieceFromOutfit {
    pub id: Uuid,
    pub piece_id: Uuid,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Link a photo (usually a fitting photo) to the outfit.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct LinkOutfitPhoto {
    pub id: Uuid,
    pub photo_id: Uuid,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Unlink a photo from the outfit.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UnlinkOutfitPhoto {
    pub id: Uuid,
    pub photo_id: Uuid,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateOutfit {
    fn command_name() -> &'static str {
        "CreateOutfit"
    }
}
impl kameo_es::CommandName for CreateOutfitVariant {
    fn command_name() -> &'static str {
        "CreateOutfitVariant"
    }
}
impl kameo_es::CommandName for RenameOutfit {
    fn command_name() -> &'static str {
        "RenameOutfit"
    }
}
impl kameo_es::CommandName for UpdateOutfitNotes {
    fn command_name() -> &'static str {
        "UpdateOutfitNotes"
    }
}
impl kameo_es::CommandName for AddPieceToOutfit {
    fn command_name() -> &'static str {
        "AddPieceToOutfit"
    }
}
impl kameo_es::CommandName for RemovePieceFromOutfit {
    fn command_name() -> &'static str {
        "RemovePieceFromOutfit"
    }
}
impl kameo_es::CommandName for LinkOutfitPhoto {
    fn command_name() -> &'static str {
        "LinkOutfitPhoto"
    }
}
impl kameo_es::CommandName for UnlinkOutfitPhoto {
    fn command_name() -> &'static str {
        "UnlinkOutfitPhoto"
    }
}
