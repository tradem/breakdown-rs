// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Read-model view for a `ShootingDay`.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;

use crate::shared::{AggregateVersion, EpisodeId, LexicalSortKey, ShootingDayId};

use super::events::ShootingDaySource;

/// Complete shooting-day read model.
///
/// `updated_at` is sourced from the timestamp of the last applied
/// `ShootingDayEvent`, not from the UUIDv7 event id.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ShootingDayView {
    pub id: ShootingDayId,
    pub episode_id: EpisodeId,
    pub label: Option<String>,
    pub order_key: LexicalSortKey,
    pub date: Option<chrono::NaiveDate>,
    pub source: ShootingDaySource,
    pub archived: bool,
    /// Aggregate version of the last applied event; echo back in optimistic-locking commands.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
