// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Commands for the `ShootingDay` aggregate.

use chrono::NaiveDate;

use crate::shared::{AggregateVersion, EpisodeId, LexicalSortKey, ShootingDayId};

use super::events::ShootingDaySource;

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateShootingDay {
    pub id: ShootingDayId,
    pub episode_id: EpisodeId,
    pub label: Option<String>,
    pub order_key: LexicalSortKey,
    pub date: Option<NaiveDate>,
    pub source: ShootingDaySource,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenameShootingDay {
    pub id: ShootingDayId,
    /// New free-form label. `None` clears the label.
    pub label: Option<String>,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RescheduleShootingDay {
    pub id: ShootingDayId,
    /// New calendar date. `None` unschedules the day (planning only).
    pub date: Option<NaiveDate>,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ReorderShootingDay {
    pub id: ShootingDayId,
    /// New canonical ordering key. Computed by the caller (e.g. midpoint of
    /// two sibling keys); the aggregate validates its format only.
    pub order_key: LexicalSortKey,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ArchiveShootingDay {
    pub id: ShootingDayId,
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
