// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Scene context.
//!
//! These views are reconstructed from PostgreSQL projection tables; clients must
//! never read from the aggregate directly (ADR-002 CQRS).

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::scene::events::SceneSource;
use crate::shared::{AggregateVersion, EpisodeId, ShootingDayId};

/// Complete scene read model.
///
/// `updated_at` is sourced from the timestamp of the last applied `SceneEvent`,
/// not from the UUIDv7 event id (ADR-004 + ADR-015).
#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
pub struct SceneView {
    pub id: Uuid,
    pub episode_id: EpisodeId,
    pub scene_number: Option<u32>,
    pub location: Option<String>,
    pub mood: Option<String>,
    pub is_schedule_set: bool,
    pub summary: Option<String>,
    /// Fictional script-chronology day (e.g. "1. Spieltag"), distinct
    /// from the calendar `ShootingDay.date`.
    pub script_day: Option<String>,
    /// Shooting days this scene is scheduled on.
    pub shooting_day_ids: Vec<ShootingDayId>,
    pub assigned_characters: Vec<Uuid>,
    /// Ordered costume beats per (character, order) — the scene-side casting
    /// relation (issue #546). Additive on the wire; empty for scenes without
    /// beats.
    #[serde(default)]
    pub costume_beats: Vec<SceneCostumeBeatView>,
    /// Provenance discriminator (EU AI Act transparency, issue #517).
    /// `Some(AiExtracted)` marks AI-imported scenes; `Some(Manual)` is the
    /// user-created path; `None` is only produced by clients that do not know
    /// the field (legacy caches). Serde-`default`-backed and additive on the
    /// wire (ADR-021 D3/MINOR).
    pub source: Option<SceneSource>,
    /// Aggregate version of the last applied event; echo back in optimistic-locking commands.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}

/// One costume beat of a scene, enriched by the query layer: character and
/// costume identity resolved by join (`projection_character`,
/// `projection_costume`); a projection miss yields `None`, never an error
/// (audit/derived metadata never blocks reads, issue #546).
#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
pub struct SceneCostumeBeatView {
    pub character_id: Uuid,
    pub character_name: Option<String>,
    pub costume_id: Uuid,
    pub costume_category_id: Option<Uuid>,
    pub costume_category_name: Option<String>,
    /// Dense, zero-based, unique per character within this scene.
    pub order: u32,
    /// Optional free-text cue for the wardrobe crew.
    pub note: Option<String>,
}
