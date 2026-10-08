// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Season domain commands.

use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

/// Create a new season in a project.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateSeason {
    pub id: Uuid,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: ProjectId,
    pub number: i32,
    pub title: Option<String>,
}

/// Rename a season (optional title may be cleared by passing `None`).
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// season projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenameSeason {
    pub id: Uuid,
    pub title: Option<String>,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateSeason {
    fn command_name() -> &'static str {
        "CreateSeason"
    }
}

/// Archive a season (terminal lifecycle state).
///
/// An archived season keeps its number reserved and its inventory readable;
/// active write commands (`RenameSeason`) are rejected once archived. The
/// flip side of the repertoire lifecycle (issue #534): costume bindings stay
/// historically valid while active membership ends.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// season projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ArchiveSeason {
    pub id: Uuid,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for RenameSeason {
    fn command_name() -> &'static str {
        "RenameSeason"
    }
}

impl kameo_es::CommandName for ArchiveSeason {
    fn command_name() -> &'static str {
        "ArchiveSeason"
    }
}
