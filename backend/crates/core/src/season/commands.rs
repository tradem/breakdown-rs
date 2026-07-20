// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Season domain commands.

use uuid::Uuid;

use crate::shared::{AggregateVersion, SeriesId};

/// Create a new season in a series.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateSeason {
    pub id: Uuid,
    pub series_id: SeriesId,
    pub number: i32,
    pub title: Option<String>,
}

/// Rename a season (optional title may be cleared by passing `None`).
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenameSeason {
    pub id: Uuid,
    pub title: Option<String>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateSeason {
    fn command_name() -> &'static str {
        "CreateSeason"
    }
}

impl kameo_es::CommandName for RenameSeason {
    fn command_name() -> &'static str {
        "RenameSeason"
    }
}
