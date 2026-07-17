// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Block context.

use chrono::{DateTime, NaiveDate, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, SeasonId, SeriesId};

/// Complete block read model.
///
/// `updated_at` is sourced from the timestamp of the last applied `BlockEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct BlockView {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub series_id: SeriesId,
    pub number: i32,
    #[schema(value_type = String)]
    pub start_date: Option<NaiveDate>,
    #[schema(value_type = String)]
    pub end_date: Option<NaiveDate>,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
