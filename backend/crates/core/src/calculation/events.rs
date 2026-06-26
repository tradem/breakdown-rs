// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Calculation events.

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize, ToSchema)]
pub struct CalculationHeader {
    pub subjects: Option<String>,
    pub sender_name: Option<String>,
    pub date: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct CalculationItem {
    pub id: Uuid,
    pub name: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    #[schema(value_type = String)]
    pub unit_price: Decimal,
    pub is_paid: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum CalculationEvent {
    CalculationCreated {
        id: Uuid,
        project_id: ProjectId,
        header: CalculationHeader,
        items: Vec<CalculationItem>,
        version: AggregateVersion,
    },
    HeaderInfoUpdated {
        id: Uuid,
        header: CalculationHeader,
        version: AggregateVersion,
    },
    CalculationItemAdded {
        id: Uuid,
        item: CalculationItem,
        version: AggregateVersion,
    },
    CalculationItemUpdated {
        id: Uuid,
        item: CalculationItem,
        version: AggregateVersion,
    },
    CalculationItemRemoved {
        id: Uuid,
        item_id: Uuid,
        version: AggregateVersion,
    },
    ItemMarkedAsPaid {
        id: Uuid,
        item_id: Uuid,
        version: AggregateVersion,
    },
    ItemMarkedAsUnpaid {
        id: Uuid,
        item_id: Uuid,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for CalculationEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::CalculationCreated { .. } => "CalculationCreated",
            Self::HeaderInfoUpdated { .. } => "HeaderInfoUpdated",
            Self::CalculationItemAdded { .. } => "CalculationItemAdded",
            Self::CalculationItemUpdated { .. } => "CalculationItemUpdated",
            Self::CalculationItemRemoved { .. } => "CalculationItemRemoved",
            Self::ItemMarkedAsPaid { .. } => "ItemMarkedAsPaid",
            Self::ItemMarkedAsUnpaid { .. } => "ItemMarkedAsUnpaid",
        }
    }
}
