// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Character domain commands.

use uuid::Uuid;

use super::category::CharacterCategory;
use super::events::{CharacterMeasurements, ContactInfo};
use crate::shared::{AggregateVersion, SeasonId};

/// Create a new character role with an externally supplied UUIDv7 id.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateCharacter {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub name: String,
    pub category: CharacterCategory,
}

/// Update physical measurements as a God-Command payload.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateMeasurements {
    pub id: Uuid,
    pub measurements: CharacterMeasurements,
    pub version: AggregateVersion,
}

/// Update contact information as a God-Command payload.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateContactInfo {
    pub id: Uuid,
    pub contact_info: ContactInfo,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateCharacter {
    fn command_name() -> &'static str {
        "CreateCharacter"
    }
}

impl kameo_es::CommandName for UpdateMeasurements {
    fn command_name() -> &'static str {
        "UpdateMeasurements"
    }
}

impl kameo_es::CommandName for UpdateContactInfo {
    fn command_name() -> &'static str {
        "UpdateContactInfo"
    }
}
