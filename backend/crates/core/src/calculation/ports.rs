// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the Calculation context.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, ProjectId};

use super::commands::{
    AddCalculationItem, CreateCalculation, MarkItemAsPaid, MarkItemAsUnpaid, RemoveCalculationItem,
    UpdateCalculationItem, UpdateHeaderInfo,
};
use super::views::CalculationView;

/// Async write port for the `CalculationAggregate`.
#[allow(async_fn_in_trait)]
pub trait CalculationCommands: Send + Sync {
    async fn create(&self, cmd: CreateCalculation)
    -> Result<(Uuid, AggregateVersion), DomainError>;
    async fn update_header(&self, cmd: UpdateHeaderInfo) -> Result<AggregateVersion, DomainError>;
    async fn add_item(&self, cmd: AddCalculationItem) -> Result<AggregateVersion, DomainError>;
    async fn update_item(
        &self,
        cmd: UpdateCalculationItem,
    ) -> Result<AggregateVersion, DomainError>;
    async fn remove_item(
        &self,
        cmd: RemoveCalculationItem,
    ) -> Result<AggregateVersion, DomainError>;
    async fn mark_item_paid(&self, cmd: MarkItemAsPaid) -> Result<AggregateVersion, DomainError>;
    async fn mark_item_unpaid(
        &self,
        cmd: MarkItemAsUnpaid,
    ) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `CalculationView` projections.
#[allow(async_fn_in_trait)]
pub trait CalculationRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<CalculationView, DomainError>;
    async fn list_by_project(
        &self,
        project_id: ProjectId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CalculationView>, DomainError>;
    /// Fetch a calculation with all child items.
    async fn calculation_with_items(&self, id: Uuid) -> Result<CalculationView, DomainError>;
}
