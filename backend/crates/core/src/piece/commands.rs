// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Piece commands.
//!
//! A `Piece` is a garment in the wardrobe fundus: no `character_id`, a
//! required `name`, a single optional category and a season repertoire. The
//! character binding lives on `Outfit` (`crate::outfit`).
//!
//! Every command carries `project_id` for the `EventMetadata` audit trail; it
//! is resolved at the API edge and never queried again by the command adapter
//! (CQRS boundary, `AGENTS.md` §1).

use uuid::Uuid;

use super::events::PieceDetail;
use crate::shared::{AggregateVersion, CostumeCategoryId, ProjectId, SeasonId};

/// Catalogue a new fundus piece.
///
/// `name` is required (non-blank) — a garment without a name is unreachable
/// for the wardrobe crew. `season_id` is the optional **initial repertoire**
/// season; the repertoire is m:n over the piece's life and maintained by
/// [`AddPieceToSeason`] / [`RemovePieceFromSeason`]. `category_id` sets the
/// single category up front; the API edge pre-checks the season invariant
/// (`category.season_id ∈ repertoire`) before dispatch.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreatePiece {
    pub id: Uuid,
    pub name: String,
    pub category_id: Option<CostumeCategoryId>,
    pub season_id: Option<SeasonId>,
    pub project_id: Option<ProjectId>,
}

/// Rename a piece. Names are **not** unique within a season (two identical
/// garments are a legitimate fundus state).
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenamePiece {
    pub id: Uuid,
    pub name: String,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Replace the piece's free-form notes.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdatePieceNotes {
    pub id: Uuid,
    pub notes: String,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Add the piece to a season's **repertoire**. Idempotent: a season already in
/// the list is a state-based no-op that emits no event. The target season's
/// existence (404 `season.not-found`) and archived state (409
/// `season.archived`) are pre-checked at the API edge.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AddPieceToSeason {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Remove the piece from a season's repertoire. Idempotent: a season not in
/// the list emits no event. An empty repertoire is legitimate.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemovePieceFromSeason {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Append a description detail to the piece.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AddPieceDetail {
    pub id: Uuid,
    pub detail: PieceDetail,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Replace a detail in place.
///
/// The command carries the **full** detail, not a patch: a patch-merge would
/// leave field merging to the client and make an emptied `subject` ambiguous.
/// `detail.id` must match an existing detail, otherwise the command fails with
/// `PieceError::DetailNotFound` **without** emitting an event.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdatePieceDetail {
    pub id: Uuid,
    pub detail: PieceDetail,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Remove a description detail from the piece.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemovePieceDetail {
    pub id: Uuid,
    pub detail_id: Uuid,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Set (or clear, `None`) the piece's single category.
///
/// The season invariant (`category.season_id ∈ piece.seasons`) is an API-edge
/// pre-check (409 `costume-category.season-mismatch`) — the aggregate cannot
/// validate cross-aggregate state. Re-dispatching the value the piece already
/// carries is a state-based no-op.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct SetPieceCategory {
    pub id: Uuid,
    pub category_id: Option<CostumeCategoryId>,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Link a photo to the piece.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct LinkPiecePhoto {
    pub id: Uuid,
    pub photo_id: Uuid,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Unlink a photo from the piece.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UnlinkPiecePhoto {
    pub id: Uuid,
    pub photo_id: Uuid,
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreatePiece {
    fn command_name() -> &'static str {
        "CreatePiece"
    }
}
impl kameo_es::CommandName for RenamePiece {
    fn command_name() -> &'static str {
        "RenamePiece"
    }
}
impl kameo_es::CommandName for UpdatePieceNotes {
    fn command_name() -> &'static str {
        "UpdatePieceNotes"
    }
}
impl kameo_es::CommandName for AddPieceToSeason {
    fn command_name() -> &'static str {
        "AddPieceToSeason"
    }
}
impl kameo_es::CommandName for RemovePieceFromSeason {
    fn command_name() -> &'static str {
        "RemovePieceFromSeason"
    }
}
impl kameo_es::CommandName for AddPieceDetail {
    fn command_name() -> &'static str {
        "AddPieceDetail"
    }
}
impl kameo_es::CommandName for UpdatePieceDetail {
    fn command_name() -> &'static str {
        "UpdatePieceDetail"
    }
}
impl kameo_es::CommandName for RemovePieceDetail {
    fn command_name() -> &'static str {
        "RemovePieceDetail"
    }
}
impl kameo_es::CommandName for SetPieceCategory {
    fn command_name() -> &'static str {
        "SetPieceCategory"
    }
}
impl kameo_es::CommandName for LinkPiecePhoto {
    fn command_name() -> &'static str {
        "LinkPiecePhoto"
    }
}
impl kameo_es::CommandName for UnlinkPiecePhoto {
    fn command_name() -> &'static str {
        "UnlinkPiecePhoto"
    }
}

/// Delete a Piece (issue #770 — dev data reset).
///
/// The undo path for an AI script import: the reset tooling removes the
/// aggregates an import created through **real domain commands** instead of
/// truncating projections behind the event store's back (AGENTS.md §1).
///
/// There is deliberately **no HTTP route** and no port method (issue #770: a
/// delete endpoint is a footgun); the `reset-dev-data` maintenance binary is
/// the only dispatcher, and it deletes children first — a delete does not
/// cascade across aggregates, because a projection-side cascade would leave the
/// child streams without their own deleted event.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct DeletePiece {
    pub id: Uuid,
}

impl kameo_es::CommandName for DeletePiece {
    fn command_name() -> &'static str {
        "DeletePiece"
    }
}
