// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Block domain commands.

use chrono::NaiveDate;
use uuid::Uuid;

use crate::shared::{AggregateVersion, SeasonId, SeriesId};

/// Create a new block within a season.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateBlock {
    pub id: Uuid,
    pub season_id: SeasonId,
    /// Denormalized series reference (immutable for a Block).
    pub series_id: SeriesId,
    pub number: i32,
    #[schema(value_type = String)]
    pub start_date: Option<NaiveDate>,
    #[schema(value_type = String)]
    pub end_date: Option<NaiveDate>,
}

/// Update a block's (optional) time span.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateBlockTimeSpan {
    pub id: Uuid,
    #[schema(value_type = String)]
    pub start_date: Option<NaiveDate>,
    #[schema(value_type = String)]
    pub end_date: Option<NaiveDate>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateBlock {
    fn command_name() -> &'static str {
        "CreateBlock"
    }
}

impl kameo_es::CommandName for UpdateBlockTimeSpan {
    fn command_name() -> &'static str {
        "UpdateBlockTimeSpan"
    }
}
