// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kwaipilot/kat-coder-air-v2.5 (openrouter)

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
