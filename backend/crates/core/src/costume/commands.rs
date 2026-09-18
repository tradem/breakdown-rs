// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Costume commands.

use uuid::Uuid;

use super::events::CostumeDetail;
use crate::shared::{AggregateVersion, SeasonId, SeriesId};

/// Create a costume.
///
/// `season_id` is the optional **repertoire** season (issue #453): the season
/// whose costume stream the costume should appear in while unassigned. A
/// costume may sit in several seasons' repertoires over its lifetime (main
/// characters reuse costumes across seasons), so this is one binding among
/// possibly many — not an ownership. The API edge resolves `series_id` for the
/// audit trail from the season projection; the aggregate itself stays
/// scope-free apart from the emitted event's `season_id` (read-model
/// repertoire row).
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateCostume {
    pub id: Uuid,
    pub season_id: Option<SeasonId>,
    /// Audit metadata (`EventMetadata`), resolved at the API edge from the
    /// repertoire season's projection.
    pub series_id: Option<SeriesId>,
}
/// Update the costume's free-form notes.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// costume projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateCostumeNotes {
    pub id: Uuid,
    pub notes: String,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}
/// Bind the costume to a character.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// character projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AssignCostumeToCharacter {
    pub id: Uuid,
    pub character_id: Uuid,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}
/// Unbind the costume from its character.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// costume projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UnassignCostume {
    pub id: Uuid,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}
/// Add a detail entry to the costume.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// costume projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AddDetail {
    pub id: Uuid,
    pub detail: CostumeDetail,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}
/// Remove a detail entry from the costume.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// costume projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemoveDetail {
    pub id: Uuid,
    pub detail_id: Uuid,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}
/// Link a photo to the costume.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// costume projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct LinkPhoto {
    pub id: Uuid,
    pub photo_id: Uuid,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}
/// Unlink a photo from the costume.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// costume projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UnlinkPhoto {
    pub id: Uuid,
    pub photo_id: Uuid,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateCostume {
    fn command_name() -> &'static str {
        "CreateCostume"
    }
}
impl kameo_es::CommandName for UpdateCostumeNotes {
    fn command_name() -> &'static str {
        "UpdateCostumeNotes"
    }
}
impl kameo_es::CommandName for AssignCostumeToCharacter {
    fn command_name() -> &'static str {
        "AssignCostumeToCharacter"
    }
}
impl kameo_es::CommandName for UnassignCostume {
    fn command_name() -> &'static str {
        "UnassignCostume"
    }
}
impl kameo_es::CommandName for AddDetail {
    fn command_name() -> &'static str {
        "AddDetail"
    }
}
impl kameo_es::CommandName for RemoveDetail {
    fn command_name() -> &'static str {
        "RemoveDetail"
    }
}
impl kameo_es::CommandName for LinkPhoto {
    fn command_name() -> &'static str {
        "LinkPhoto"
    }
}
impl kameo_es::CommandName for UnlinkPhoto {
    fn command_name() -> &'static str {
        "UnlinkPhoto"
    }
}
