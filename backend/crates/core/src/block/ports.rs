// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the Block context.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, SeasonId, SeriesId};

use super::commands::{CreateBlock, UpdateBlockTimeSpan};
use super::views::BlockView;

/// Async write port for the `BlockAggregate`.
#[allow(async_fn_in_trait)]
pub trait BlockCommands: Send + Sync {
    /// Create a new block aggregate.
    async fn create(&self, cmd: CreateBlock) -> Result<(Uuid, AggregateVersion), DomainError>;
    /// Update the block's (optional) time span.
    async fn update_time_span(
        &self,
        cmd: UpdateBlockTimeSpan,
    ) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `BlockView` projections.
#[allow(async_fn_in_trait)]
pub trait BlockRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<BlockView, DomainError>;
    /// List blocks of a season, ordered by number.
    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<BlockView>, DomainError>;
    /// Look up a block by its series-global number (for the 409 pre-check).
    async fn find_by_series_and_number(
        &self,
        series_id: SeriesId,
        number: i32,
    ) -> Result<Option<BlockView>, DomainError>;
}
