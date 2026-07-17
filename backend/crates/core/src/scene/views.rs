// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Scene context.
//!
//! These views are reconstructed from PostgreSQL projection tables; clients must
//! never read from the aggregate directly (ADR-002 CQRS).

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, EpisodeId};

/// Complete scene read model.
///
/// `updated_at` is sourced from the timestamp of the last applied `SceneEvent`,
/// not from the UUIDv7 event id (ADR-004 + ADR-015).
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SceneView {
    pub id: Uuid,
    pub episode_id: EpisodeId,
    pub scene_number: Option<u32>,
    pub location: Option<String>,
    pub mood: Option<String>,
    pub is_schedule_set: bool,
    pub assigned_characters: Vec<Uuid>,
    /// Aggregate version of the last applied event; echo back in optimistic-locking commands.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
