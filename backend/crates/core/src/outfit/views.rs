// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Flat read-model DTOs for the Outfit context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::photo::views::PhotoVariantView;
use crate::shared::AggregateVersion;

/// One piece inside an outfit, in presentation order.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct OutfitPieceView {
    pub piece_id: Uuid,
    /// Piece display name; `None` on a projection miss (best-effort, never an
    /// error — a dangling reference must not fail the outfit read).
    pub name: Option<String>,
    pub category_id: Option<Uuid>,
    pub category_name: Option<String>,
    /// Insertion position (ascending presentation order).
    pub position: i32,
}

/// Linked photo reference for an outfit, enriched with variant metadata.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct OutfitPhotoView {
    pub id: Uuid,
    pub content_type: String,
    pub size_bytes: u64,
    pub variants: Vec<PhotoVariantView>,
}

/// Complete outfit read model.
///
/// `season_id` and `character_name` are resolved by the read model through the
/// character join (`projection_outfit.character_id → projection_character`);
/// both are `None` on a projection miss and never block the read.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct OutfitView {
    pub id: Uuid,
    pub character_id: Uuid,
    pub character_name: Option<String>,
    pub season_id: Option<Uuid>,
    /// Required, non-blank look name.
    pub name: String,
    /// `Some(source_outfit_id)` when this outfit was forked as a variant.
    pub variant_of: Option<Uuid>,
    /// Insertion-ordered piece references (parallel to `pieces`).
    pub piece_ids: Vec<Uuid>,
    pub pieces: Vec<OutfitPieceView>,
    pub notes: String,
    pub photos: Vec<OutfitPhotoView>,
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
