// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Season context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, SeriesId};

/// Complete season read model.
///
/// `updated_at` is sourced from the timestamp of the last applied `SeasonEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SeasonView {
    pub id: Uuid,
    pub series_id: SeriesId,
    pub number: i32,
    pub title: Option<String>,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
