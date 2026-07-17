// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the Episode context.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, BlockId, SeriesId};

use super::commands::{CreateEpisode, RenameEpisode};
use super::views::EpisodeView;

/// Async write port for the `EpisodeAggregate`.
#[allow(async_fn_in_trait)]
pub trait EpisodeCommands: Send + Sync {
    /// Create a new episode aggregate.
    async fn create(&self, cmd: CreateEpisode) -> Result<(Uuid, AggregateVersion), DomainError>;
    /// Rename an episode (optional name).
    async fn rename(&self, cmd: RenameEpisode) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `EpisodeView` projections.
#[allow(async_fn_in_trait)]
pub trait EpisodeRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<EpisodeView, DomainError>;
    /// List episodes of a block, ordered by number.
    async fn list_by_block(
        &self,
        block_id: BlockId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<EpisodeView>, DomainError>;
    /// List episodes of a series, ordered by number.
    async fn list_by_series(
        &self,
        series_id: SeriesId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<EpisodeView>, DomainError>;
    /// Look up an episode by its series-global number (for the 409 pre-check).
    async fn find_by_series_and_number(
        &self,
        series_id: SeriesId,
        number: i32,
    ) -> Result<Option<EpisodeView>, DomainError>;
}
