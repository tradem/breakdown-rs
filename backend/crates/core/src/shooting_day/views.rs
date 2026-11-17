// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Read-model view for a `ShootingDay`.

use jiff::Timestamp;
use serde::Serialize;
use utoipa::ToSchema;

use super::events::ShootingDaySource;
use crate::shared::{AggregateVersion, EpisodeId, LexicalSortKey, ShootingDayId};
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
    pub date: Option<jiff::civil::Date>,
    pub source: ShootingDaySource,
    pub archived: bool,
    /// When this shooting day was wrapped (finalised). `None` means open.
    pub wrapped_at: Option<Timestamp>,
    /// Aggregate version of the last applied event; echo back in optimistic-locking commands.
    pub version: AggregateVersion,
    pub updated_at: Timestamp,
}
