// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Commands for the `ShootingDay` aggregate.

use chrono::NaiveDate;

use crate::shared::{AggregateVersion, EpisodeId, LexicalSortKey, SeriesId, ShootingDayId};

use super::events::ShootingDaySource;

/// Create a shooting day within an episode.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// episode projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateShootingDay {
    pub id: ShootingDayId,
    pub episode_id: EpisodeId,
    pub series_id: Option<SeriesId>,
    pub label: Option<String>,
    pub order_key: LexicalSortKey,
    pub date: Option<NaiveDate>,
    pub source: ShootingDaySource,
}

/// Rename a shooting day.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// shooting-day projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenameShootingDay {
    pub id: ShootingDayId,
    /// New free-form label. `None` clears the label.
    pub label: Option<String>,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Reschedule a shooting day.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// shooting-day projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RescheduleShootingDay {
    pub id: ShootingDayId,
    /// New calendar date. `None` unschedules the day (planning only).
    pub date: Option<NaiveDate>,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Reorder a shooting day.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// shooting-day projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ReorderShootingDay {
    pub id: ShootingDayId,
    /// New canonical ordering key. Computed by the caller (e.g. midpoint of
    /// two sibling keys); the aggregate validates its format only.
    pub order_key: LexicalSortKey,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Archive a shooting day.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// shooting-day projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ArchiveShootingDay {
    pub id: ShootingDayId,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateShootingDay {
    fn command_name() -> &'static str {
        "CreateShootingDay"
    }
}
impl kameo_es::CommandName for RenameShootingDay {
    fn command_name() -> &'static str {
        "RenameShootingDay"
    }
}
impl kameo_es::CommandName for RescheduleShootingDay {
    fn command_name() -> &'static str {
        "RescheduleShootingDay"
    }
}
impl kameo_es::CommandName for ReorderShootingDay {
    fn command_name() -> &'static str {
        "ReorderShootingDay"
    }
}
impl kameo_es::CommandName for ArchiveShootingDay {
    fn command_name() -> &'static str {
        "ArchiveShootingDay"
    }
}

/// Wrap (finalise) a shooting day.
///
/// Idempotent: re-dispatching on an already-wrapped day emits no event.
/// Wrapping does not prevent archiving.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// shooting-day projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct WrapShootingDay {
    pub id: ShootingDayId,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for WrapShootingDay {
    fn command_name() -> &'static str {
        "WrapShootingDay"
    }
}
