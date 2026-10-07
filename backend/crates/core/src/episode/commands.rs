// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Episode domain commands.

use uuid::Uuid;

use crate::shared::{AggregateVersion, BlockId, ProjectId};

/// Create a new episode within a block.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateEpisode {
    pub id: Uuid,
    pub block_id: BlockId,
    /// Denormalized project reference (immutable for an Episode).
    #[schema(rename = "series_id")]
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: ProjectId,
    pub number: i32,
    pub name: Option<String>,
}

/// Rename an episode (optional name may be cleared by passing `None`).
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// episode projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenameEpisode {
    pub id: Uuid,
    pub name: Option<String>,
    #[schema(rename = "series_id")]
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateEpisode {
    fn command_name() -> &'static str {
        "CreateEpisode"
    }
}

impl kameo_es::CommandName for RenameEpisode {
    fn command_name() -> &'static str {
        "RenameEpisode"
    }
}
