// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Flat read-model DTOs for the Character context.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, EpisodeId, SeasonId};

use super::category::CharacterCategory;
use super::events::{CharacterMeasurements, ContactInfo};

/// Complete character read model.
///
/// `updated_at` is sourced from the timestamp of the last applied `CharacterEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CharacterView {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub name: String,
    pub category: CharacterCategory,
    pub measurements: CharacterMeasurements,
    pub contact: ContactInfo,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}

/// One appearance of a character in a scene (issue #621): the scene reference
/// in script order plus the character's own outfit beats in that scene.
///
/// Backs `GET /v1/characters/{id}/appearances` — the role extract ("Ring
/// binder per role"): every scene the character appears in, in `scene_number`
/// order, with the outfit(s) that character wears there.
#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
pub struct CharacterAppearanceView {
    pub scene_id: Uuid,
    pub episode_id: EpisodeId,
    /// Script-order scene number; `None` for scenes not yet numbered.
    pub scene_number: Option<u32>,
    /// Scene synopsis (the scene projection's `summary`), for the extract row.
    pub synopsis: Option<String>,
    /// The character's outfit beats in this scene, ordered by `order`.
    /// Empty when the character has no outfit beat in the scene yet.
    #[serde(default)]
    pub outfits: Vec<AppearanceOutfitView>,
}

/// One outfit beat of a character within one scene (issue #621): the
/// character-scoped slice of `projection_scene_outfit_assignment`, enriched by
/// join with `projection_outfit` for the look's name and variant lineage.
#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
pub struct AppearanceOutfitView {
    pub outfit_id: Uuid,
    pub outfit_name: Option<String>,
    pub variant_of: Option<Uuid>,
    /// Dense, zero-based, unique per character within this scene.
    pub order: u32,
    /// Optional free-text cue for the wardrobe crew.
    pub note: Option<String>,
}
