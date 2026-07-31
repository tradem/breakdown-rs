// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Character domain commands.

use uuid::Uuid;

use super::category::CharacterCategory;
use super::events::{CharacterMeasurements, ContactInfo};
use crate::shared::{AggregateVersion, SeasonId, SeriesId};

/// Create a new character role with an externally supplied UUIDv7 id.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// season projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateCharacter {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub series_id: Option<SeriesId>,
    pub name: String,
    pub category: CharacterCategory,
}

/// Update physical measurements as a God-Command payload.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// character projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateMeasurements {
    pub id: Uuid,
    pub measurements: CharacterMeasurements,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Update contact information as a God-Command payload.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// character projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateContactInfo {
    pub id: Uuid,
    pub contact_info: ContactInfo,
    pub series_id: Option<SeriesId>,
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
