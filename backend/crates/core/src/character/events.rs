// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Character domain events.

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use super::category::CharacterCategory;
use crate::shared::{AggregateVersion, SeasonId};

/// Payload for measurement fields updated as a God-Command.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default, ToSchema)]
pub struct CharacterMeasurements {
    #[schema(value_type = String)]
    pub shoe_size: Option<Decimal>,
    #[schema(value_type = String)]
    pub hat_size: Option<Decimal>,
    #[schema(value_type = String)]
    pub height: Option<Decimal>,
    #[schema(value_type = String)]
    pub weight: Option<Decimal>,
    #[schema(value_type = String)]
    pub chest: Option<Decimal>,
    #[schema(value_type = String)]
    pub waist: Option<Decimal>,
    #[schema(value_type = String)]
    pub hips: Option<Decimal>,
}

/// Payload for contact information updated as a God-Command.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default, ToSchema)]
pub struct ContactInfo {
    pub phone: Option<String>,
    pub email: Option<String>,
}

/// Events emitted by the Character aggregate.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum CharacterEvent {
    CharacterCreated {
        id: Uuid,
        season_id: SeasonId,
        name: String,
        category: CharacterCategory,
        measurements: CharacterMeasurements,
        contact_info: ContactInfo,
        version: AggregateVersion,
    },
    MeasurementsUpdated {
        id: Uuid,
        measurements: CharacterMeasurements,
        version: AggregateVersion,
    },
    ContactInfoUpdated {
        id: Uuid,
        contact_info: ContactInfo,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for CharacterEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::CharacterCreated { .. } => "CharacterCreated",
            Self::MeasurementsUpdated { .. } => "MeasurementsUpdated",
            Self::ContactInfoUpdated { .. } => "ContactInfoUpdated",
        }
    }
}
