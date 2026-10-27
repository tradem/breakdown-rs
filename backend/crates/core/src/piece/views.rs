// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Flat read-model DTOs for the Piece (fundus) context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::photo::views::PhotoVariantView;
use crate::shared::{AggregateVersion, CostumeCategoryId};

/// Description element of a piece (e.g. belt, hat, shoes).
///
/// Pure description: the category lives on the piece
/// (`PieceView.category_id`), never on the detail.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct PieceDetailView {
    pub id: Uuid,
    /// Free-form per-detail micro-title (e.g. "Rote Lederjacke").
    pub subject: Option<String>,
    /// The description.
    pub text: String,
}

/// Linked photo reference for a piece, enriched with variant metadata.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct PiecePhotoView {
    pub id: Uuid,
    /// MIME type of the uploaded original (e.g. `image/jpeg`).
    pub content_type: String,
    /// Size of the re-encoded original in bytes.
    pub size_bytes: u64,
    /// Generation status and size of each variant.
    pub variants: Vec<PhotoVariantView>,
}

/// Complete piece read model, optionally populated with child details/photos.
///
/// `photos` merges the piece's directly linked photos with the photos linked
/// to any outfit containing this piece (fitting photos are usually taken at
/// outfit level), deduplicated by photo id.
///
/// `updated_at` is sourced from the timestamp of the last applied `PieceEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct PieceView {
    pub id: Uuid,
    /// Required, non-blank display name.
    pub name: String,
    /// The piece's single category reference. `None` = uncategorised.
    pub category_id: Option<CostumeCategoryId>,
    /// Denormalised category name, resolved by the projector at write time;
    /// `None` on a projection miss (dangling reference, best-effort).
    pub category_name: Option<String>,
    pub notes: String,
    pub details: Vec<PieceDetailView>,
    pub photos: Vec<PiecePhotoView>,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
    /// The piece's season repertoire, populated from `projection_piece_season`.
    /// Ordered by season id (deterministic). Empty for a piece not yet filed
    /// into any season.
    pub season_ids: Vec<Uuid>,
}
