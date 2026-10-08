// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Episode context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, BlockId, ProjectId};

/// Complete episode read model.
///
/// `updated_at` is sourced from the timestamp of the last applied `EpisodeEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct EpisodeView {
    pub id: Uuid,
    pub block_id: BlockId,
    /// The tenant-level production container this episode belongs to (`project_id`
    /// on the wire, issue #599).
    pub project_id: ProjectId,
    pub number: i32,
    pub name: Option<String>,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
