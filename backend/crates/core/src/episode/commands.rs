// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Episode domain commands.

use uuid::Uuid;

use crate::shared::{AggregateVersion, BlockId, SeriesId};

/// Create a new episode within a block.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateEpisode {
    pub id: Uuid,
    pub block_id: BlockId,
    /// Denormalized series reference (immutable for an Episode).
    pub series_id: SeriesId,
    pub number: i32,
    pub name: Option<String>,
}

/// Rename an episode (optional name may be cleared by passing `None`).
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// episode projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenameEpisode {
    pub id: Uuid,
    pub name: Option<String>,
    pub series_id: Option<SeriesId>,
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
