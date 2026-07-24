// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Flat read-model DTOs for the SceneShoot context.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{
    AggregateVersion, LexicalSortKey, PhotoId, SceneShootId, SceneShootStatus, ShootingDayId,
};

/// Complete scene-shoot read model.
///
/// `updated_at` is sourced from the timestamp of the last applied
/// `SceneShootEvent`, not from the UUIDv7 event id.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SceneShootView {
    pub id: SceneShootId,
    pub scene_id: Uuid,
    pub shooting_day_id: ShootingDayId,
    pub planned_order: LexicalSortKey,
    pub actual_order: Option<LexicalSortKey>,
    pub status: SceneShootStatus,
    pub start_dt: Option<DateTime<Utc>>,
    pub end_dt: Option<DateTime<Utc>>,
    pub notes: Vec<SerializedNote>,
    pub continuity_photo_ids: Vec<PhotoId>,
    /// Aggregate version of the last applied event; echo back in optimistic-locking commands.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}

/// A note as exposed in the read model (flattened for JSON serialisation).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct SerializedNote {
    pub id: Uuid,
    pub body: String,
}

// ---------------------------------------------------------------------------
// Report DTOs
// ---------------------------------------------------------------------------

/// A single row in the Dispo (planned / Soll) report.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct DispoRow {
    pub planned_order: LexicalSortKey,
    pub scene_id: Uuid,
    pub scene_number: Option<u32>,
    pub script_day: Option<String>,
    pub location: Option<String>,
    pub mood: Option<String>,
    pub summary: Option<String>,
}

/// A single row in the Shoot Day (execution / Ist) report.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ShootDayRow {
    pub actual_order: Option<LexicalSortKey>,
    pub scene_id: Uuid,
    pub scene_number: Option<u32>,
    pub script_day: Option<String>,
    pub location: Option<String>,
    pub status: SceneShootStatus,
    pub start_dt: Option<DateTime<Utc>>,
    pub end_dt: Option<DateTime<Utc>>,
    pub notes: Vec<SerializedNote>,
    pub continuity_photo_ids: Vec<PhotoId>,
}

/// The Soll-Ist-Vergleich diff report for a single scene.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SollIstDiffRow {
    pub scene_id: Uuid,
    pub scene_number: Option<u32>,
    pub script_day: Option<String>,
    pub location: Option<String>,
    pub planned_order: Option<LexicalSortKey>,
    pub actual_order: Option<LexicalSortKey>,
    /// `true` when `actual_order` differs from `planned_order`.
    pub moved: bool,
    /// `true` when planned but without execution data.
    pub missing: bool,
    /// `true` when status is `Skipped`.
    pub skipped: bool,
    /// `true` when the same scene_id has a `Shot` record on another day.
    pub reshot_candidate: bool,
}

/// The overall Soll-Ist report.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SollIstReport {
    pub rows: Vec<SollIstDiffRow>,
    pub is_final: bool,
}
