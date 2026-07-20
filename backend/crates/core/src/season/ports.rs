// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the Season context.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, SeriesId};

use super::commands::{CreateSeason, RenameSeason};
use super::views::SeasonView;

/// Async write port for the `SeasonAggregate`.
#[allow(async_fn_in_trait)]
pub trait SeasonCommands: Send + Sync {
    /// Create a new season aggregate.
    async fn create(&self, cmd: CreateSeason) -> Result<(Uuid, AggregateVersion), DomainError>;
    /// Rename a season (optional title).
    async fn rename(&self, cmd: RenameSeason) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `SeasonView` projections.
#[allow(async_fn_in_trait)]
pub trait SeasonRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<SeasonView, DomainError>;
    /// List seasons of a series, ordered by number.
    async fn list_by_series(
        &self,
        series_id: SeriesId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<SeasonView>, DomainError>;
    /// Look up a season by its series-global number (for the 409 pre-check).
    async fn find_by_series_and_number(
        &self,
        series_id: SeriesId,
        number: i32,
    ) -> Result<Option<SeasonView>, DomainError>;
}
