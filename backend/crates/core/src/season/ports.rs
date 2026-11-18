// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the Season context.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, ProjectId, UserId};

use super::commands::{ArchiveSeason, CreateSeason, RenameSeason};
use super::views::SeasonView;

/// Async write port for the `SeasonAggregate`.
#[allow(async_fn_in_trait)]
pub trait SeasonCommands: Send + Sync {
    /// Create a new season aggregate.
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateSeason,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;
    /// Rename a season (optional title).
    async fn rename(
        &self,
        actor: UserId,
        cmd: RenameSeason,
    ) -> Result<AggregateVersion, DomainError>;
    /// Archive a season (terminal lifecycle state).
    async fn archive(
        &self,
        actor: UserId,
        cmd: ArchiveSeason,
    ) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `SeasonView` projections.
#[allow(async_fn_in_trait)]
pub trait SeasonRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<SeasonView, DomainError>;
    /// List all seasons, ordered by number (deterministic `id` tiebreak).
    ///
    /// Archived seasons are excluded unless `include_archived` is set
    /// (issue #533 default-off read model).
    async fn list_all(
        &self,
        include_archived: bool,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<SeasonView>, DomainError>;
    /// List seasons of a project, ordered by number.
    ///
    /// Archived seasons are excluded unless `include_archived` is set
    /// (issue #533 default-off read model).
    async fn list_by_project(
        &self,
        project_id: ProjectId,
        include_archived: bool,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<SeasonView>, DomainError>;
    /// Look up a season by its project-global number (for the 409 pre-check).
    async fn find_by_project_and_number(
        &self,
        project_id: ProjectId,
        number: i32,
    ) -> Result<Option<SeasonView>, DomainError>;
}
