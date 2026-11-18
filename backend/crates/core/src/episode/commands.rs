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

/// Delete an episode (issue #770 — dev data reset).
///
/// This is the undo path for an AI script import: the reset tooling removes the
/// aggregates an import created through **real domain commands** instead of
/// truncating projections behind the event store's back (AGENTS.md §1).
///
/// There is deliberately **no HTTP route** and no port method for it (issue
/// #770: a delete endpoint is a footgun); the `reset-dev-data` maintenance
/// binary is the only dispatcher. It deletes children first — an episode delete
/// does not cascade to its scenes, because a projection-side cascade would
/// leave scene streams without a `SceneDeleted` event.
///
/// The ADR-036 `(project_id, number)` reservation claim is released by that
/// dispatcher after a successful append, so a later re-import may reuse the
/// number.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct DeleteEpisode {
    pub id: Uuid,
}

impl kameo_es::CommandName for DeleteEpisode {
    fn command_name() -> &'static str {
        "DeleteEpisode"
    }
}
