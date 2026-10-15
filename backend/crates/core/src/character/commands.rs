// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Character domain commands.

use uuid::Uuid;

use super::category::CharacterCategory;
use super::events::{CharacterMeasurements, ContactInfo};
use crate::shared::{AggregateVersion, ProjectId, SeasonId};

/// Create a new character role with an externally supplied UUIDv7 id.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// season projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateCharacter {
    pub id: Uuid,
    pub season_id: SeasonId,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub name: String,
    pub category: CharacterCategory,
}

/// Update physical measurements as a God-Command payload.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// character projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateMeasurements {
    pub id: Uuid,
    pub measurements: CharacterMeasurements,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Update contact information as a God-Command payload.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// character projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateContactInfo {
    pub id: Uuid,
    pub contact_info: ContactInfo,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Change the role type of a Character (issue #678): the manual correction
/// path for a wrong import classification (#677). Metadata correction only —
/// no repertoire/appearance recomputation, consumers read the *current*
/// category from the projection.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateCharacterCategory {
    pub id: Uuid,
    pub project_id: Option<ProjectId>,
    pub category: CharacterCategory,
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

impl kameo_es::CommandName for UpdateCharacterCategory {
    fn command_name() -> &'static str {
        "UpdateCharacterCategory"
    }
}
