// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Costume context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::photo::views::PhotoVariantView;
use crate::shared::{AggregateVersion, CostumeCategoryId};

/// Detailed costume element (e.g. belt, hat, shoes).
///
/// Pure description since issue #543: the category lives on the costume
/// (`CostumeView.category_id`), not on the detail. `subject` + `text` remain.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CostumeDetailView {
    pub id: Uuid,
    /// Free-form per-detail micro-title (e.g. "Rote Lederjacke").
    pub subject: Option<String>,
    /// The description (unchanged meaning).
    pub text: String,
}

/// Linked photo reference for a costume, enriched with variant metadata.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CostumePhotoView {
    pub id: Uuid,
    /// MIME type of the uploaded original (e.g. `image/jpeg`).
    pub content_type: String,
    /// Size of the re-encoded original in bytes.
    pub size_bytes: u64,
    /// Generation status and size of each variant.
    pub variants: Vec<PhotoVariantView>,
}

/// Complete costume read model, optionally populated with child details/photos.
///
/// `updated_at` is sourced from the timestamp of the last applied `CostumeEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CostumeView {
    pub id: Uuid,
    pub character_id: Option<Uuid>,
    /// The costume's single category (issue #543): reference into the
    /// season-scoped vocabulary. `None` = uncategorised. A cross-aggregate
    /// reference like `character_id` — no scope column, resolved by join in
    /// the read model.
    pub category_id: Option<CostumeCategoryId>,
    /// Denormalised category name, resolved by the projector at write time;
    /// `None` on a projection miss (dangling reference, best-effort).
    pub category_name: Option<String>,
    pub notes: String,
    pub details: Vec<CostumeDetailView>,
    pub photos: Vec<CostumePhotoView>,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
    /// The costume's season **repertoire** (issue #534): the seasons whose
    /// costume streams the costume stands in, populated from
    /// `projection_costume_season` by the enrich path. Ordered by
    /// `season_id` (deterministic). Empty for a costume without a
    /// repertoire binding — its scope then falls back to the character's
    /// season.
    pub season_ids: Vec<Uuid>,
}
