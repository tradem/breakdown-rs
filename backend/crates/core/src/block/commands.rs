// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Block domain commands.

use chrono::NaiveDate;
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId, SeasonId};

/// Create a new block within a season.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateBlock {
    pub id: Uuid,
    pub season_id: SeasonId,
    /// Denormalized project reference (immutable for a Block).
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: ProjectId,
    pub number: i32,
    // value_type must carry `Option` nullability (issue #423) — a bare
    // `value_type = String` override drops `Option`'s nullable flag.
    #[schema(value_type = Option<String>)]
    pub start_date: Option<NaiveDate>,
    #[schema(value_type = Option<String>)]
    pub end_date: Option<NaiveDate>,
}

/// Update a block's (optional) time span.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// block projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateBlockTimeSpan {
    pub id: Uuid,
    #[schema(value_type = Option<String>)]
    pub start_date: Option<NaiveDate>,
    #[schema(value_type = Option<String>)]
    pub end_date: Option<NaiveDate>,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
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
