// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Calculation commands.

use uuid::Uuid;

use super::events::{CalculationHeader, CalculationItem};
use crate::shared::{AggregateVersion, ProjectId};

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateCalculation {
    pub id: Uuid,
    pub project_id: ProjectId,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateHeaderInfo {
    pub id: Uuid,
    pub header: CalculationHeader,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AddCalculationItem {
    pub id: Uuid,
    pub item: CalculationItem,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateCalculationItem {
    pub id: Uuid,
    pub item: CalculationItem,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemoveCalculationItem {
    pub id: Uuid,
    pub item_id: Uuid,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct MarkItemAsPaid {
    pub id: Uuid,
    pub item_id: Uuid,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct MarkItemAsUnpaid {
    pub id: Uuid,
    pub item_id: Uuid,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateCalculation {
    fn command_name() -> &'static str {
        "CreateCalculation"
    }
}
impl kameo_es::CommandName for UpdateHeaderInfo {
    fn command_name() -> &'static str {
        "UpdateHeaderInfo"
    }
}
impl kameo_es::CommandName for AddCalculationItem {
    fn command_name() -> &'static str {
        "AddCalculationItem"
    }
}
impl kameo_es::CommandName for UpdateCalculationItem {
    fn command_name() -> &'static str {
        "UpdateCalculationItem"
    }
}
impl kameo_es::CommandName for RemoveCalculationItem {
    fn command_name() -> &'static str {
        "RemoveCalculationItem"
    }
}
impl kameo_es::CommandName for MarkItemAsPaid {
    fn command_name() -> &'static str {
        "MarkItemAsPaid"
    }
}
impl kameo_es::CommandName for MarkItemAsUnpaid {
    fn command_name() -> &'static str {
        "MarkItemAsUnpaid"
    }
}
