// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Episode context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, BlockId, SeriesId};

/// Complete episode read model.
///
/// `updated_at` is sourced from the timestamp of the last applied `EpisodeEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct EpisodeView {
    pub id: Uuid,
    pub block_id: BlockId,
    pub series_id: SeriesId,
    pub number: i32,
    pub name: Option<String>,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
