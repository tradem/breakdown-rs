// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Character domain events.

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

/// Payload for measurement fields updated as a God-Command.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct CharacterMeasurements {
    pub shoe_size: Option<Decimal>,
    pub hat_size: Option<Decimal>,
    pub height: Option<Decimal>,
    pub weight: Option<Decimal>,
    pub chest: Option<Decimal>,
    pub waist: Option<Decimal>,
    pub hips: Option<Decimal>,
}

/// Payload for contact information updated as a God-Command.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ContactInfo {
    pub phone: Option<String>,
    pub email: Option<String>,
}

/// Events emitted by the Character aggregate.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum CharacterEvent {
    CharacterCreated {
        id: Uuid,
        project_id: ProjectId,
        name: String,
        is_extra: bool,
        is_main_character: bool,
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
