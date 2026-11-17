// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the Block context.

use uuid::Uuid;

use super::commands::{CreateBlock, UpdateBlockTimeSpan};
use super::views::BlockView;
use crate::error::DomainError;
use crate::shared::{AggregateVersion, ProjectId, SeasonId, UserId};
/// Async write port for the `BlockAggregate`.
#[allow(async_fn_in_trait)]
pub trait BlockCommands: Send + Sync {
    /// Create a new block aggregate.
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateBlock,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;
    /// Update the block's (optional) time span.
    async fn update_time_span(
        &self,
        actor: UserId,
        cmd: UpdateBlockTimeSpan,
    ) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `BlockView` projections.
#[allow(async_fn_in_trait)]
pub trait BlockRepository: Send + Sync {
    /// Read one block projection row.
    ///
    /// Declared as an explicit `impl Future + Send` (rather than the bare
    /// `async fn` the rest of this trait uses) because the cfg-gated AI-import
    /// fixture route awaits it from a handler generic over `Ports`, and axum's
    /// `Handler` requires that future to be `Send` — an `async fn` in a trait
    /// does not imply a `Send` future, so a generic caller cannot prove it.
    /// `async fn` implementations still satisfy this signature.
    fn find_by_id(
        &self,
        id: Uuid,
    ) -> impl std::future::Future<Output = Result<BlockView, DomainError>> + Send;
    /// List blocks of a season, ordered by number.
    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<BlockView>, DomainError>;
    /// Look up a block by its project-global number (for the 409 pre-check).
    async fn find_by_project_and_number(
        &self,
        project_id: ProjectId,
        number: i32,
    ) -> Result<Option<BlockView>, DomainError>;
}
