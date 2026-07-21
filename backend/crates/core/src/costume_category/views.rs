// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the CostumeCategory context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, LexicalSortKey, SeasonId};

/// Complete costume-category read model (season-scoped vocabulary entry).
///
/// `updated_at` is sourced from the timestamp of the last applied
/// `CostumeCategoryEvent` (ADR-004 + ADR-015).
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CostumeCategoryView {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub name: String,
    pub order_key: LexicalSortKey,
    pub archived: bool,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
