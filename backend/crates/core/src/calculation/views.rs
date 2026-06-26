// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Calculation context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

use super::events::CalculationHeader;

/// Read-model item for a calculation line.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CalculationItemView {
    pub id: Uuid,
    pub name: String,
    #[schema(value_type = String)]
    pub quantity: rust_decimal::Decimal,
    #[schema(value_type = String)]
    pub unit_price: rust_decimal::Decimal,
    pub is_paid: bool,
}

/// Complete calculation read model, optionally populated with child items.
///
/// `updated_at` is sourced from the timestamp of the last applied `CalculationEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CalculationView {
    pub id: Uuid,
    pub project_id: ProjectId,
    pub header: CalculationHeader,
    pub items: Vec<CalculationItemView>,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
