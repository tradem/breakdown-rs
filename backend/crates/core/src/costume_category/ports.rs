// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the CostumeCategory context.
//!
//! `CostumeCategoryCommands` is the **write** seam (command-in) and
//! `CostumeCategoryRepository` is the **read** seam (flat views-out). No
//! event-store abstraction leaks into `core`; persistence is owned by the
//! `kameo_es` adapter in `infra`.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, SeasonId};

use super::commands::{
    ArchiveCostumeCategory, CreateCostumeCategory, ReorderCostumeCategory, RenameCostumeCategory,
};
use super::views::CostumeCategoryView;

/// Async write port for the `CostumeCategoryAggregate`.
#[allow(async_fn_in_trait)]
pub trait CostumeCategoryCommands: Send + Sync {
    /// Create a new costume category. Returns the generated UUIDv7 id and the
    /// initial aggregate version (`AggregateVersion::INITIAL`).
    async fn create(
        &self,
        cmd: CreateCostumeCategory,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;

    /// Rename an existing category (name only).
    async fn rename(
        &self,
        cmd: RenameCostumeCategory,
    ) -> Result<AggregateVersion, DomainError>;

    /// Move a category to a new ordering position (single key).
    async fn reorder(
        &self,
        cmd: ReorderCostumeCategory,
    ) -> Result<AggregateVersion, DomainError>;

    /// Soft-archive a category (terminal).
    async fn archive(
        &self,
        cmd: ArchiveCostumeCategory,
    ) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `CostumeCategoryView` projections.
#[allow(async_fn_in_trait)]
pub trait CostumeCategoryRepository: Send + Sync {
    /// List a Season's **non-archived** categories in canonical `order_key` order.
    /// Archived categories are hidden from picker queries (ADR: soft-archive).
    async fn list_by_season(
        &self,
        season_id: SeasonId,
    ) -> Result<Vec<CostumeCategoryView>, DomainError>;

    /// Count a Season's categories (regardless of `archived`). Used by the
    /// seeding saga as an idempotency guard.
    async fn count_for_season(&self, season_id: SeasonId) -> Result<i64, DomainError>;

    /// Fetch a single category by id (archived or not).
    async fn find_by_id(&self, id: Uuid) -> Result<CostumeCategoryView, DomainError>;
}
