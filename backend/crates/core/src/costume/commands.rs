// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Costume commands.

use uuid::Uuid;

use super::events::CostumeDetail;
use crate::shared::{AggregateVersion, CostumeCategoryId, SeasonId, SeriesId};

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
/// Add the costume to a season's **repertoire** (issue #534).
///
/// The wardrobe lifecycle carries a costume from one season into the next,
/// so the repertoire is real aggregate state (`seasons: Vec<SeasonId>`).
/// Idempotent: adding a season already in the list is a state-based no-op
/// that emits no event (issue #515 lesson, same pattern as
/// `SetCostumeCategory`). `series_id` is carried for the `EventMetadata`
/// audit trail (the audit projector keys on `series_id`); it is resolved at
/// the API edge from the **target** season's projection, never queried again
/// by the command adapter. The target season's existence and
/// not-archived state are pre-checked at the API edge (404
/// `season.not-found` / 409 `season.archived`) — the aggregate cannot
/// validate cross-aggregate state.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AddCostumeToSeason {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}
/// Remove the costume from a season's repertoire (issue #534).
///
/// Idempotent: removing a season that is not in the list emits no event.
/// An empty repertoire is legitimate — the authz scope then falls back to
/// the character's season. `series_id` is carried for the `EventMetadata`
/// audit trail, resolved at the API edge from the target season's
/// projection.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemoveCostumeFromSeason {
    pub id: Uuid,
    pub season_id: SeasonId,
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
/// Update an existing detail entry in place (issue #544).
///
/// The command carries the **full** detail, not a patch: a patch-merge would
/// leave the field merging to the client and make an emptied `subject`
/// ambiguous (cleared on purpose vs. lost). The `detail.id` must match a
/// detail already in the aggregate state — otherwise the command fails with
/// `CostumeError::DetailNotFound` **without** emitting an event, which is the
/// validation the event store models correctly.
///
/// `series_id` is carried for the `EventMetadata` audit trail; it is resolved
/// at the API edge from the costume projection, never queried again by the
/// command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateCostumeDetail {
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
/// Set (or clear) the costume's single category (issue #543).
///
/// A costume belongs to exactly one season vocabulary `CostumeCategory` (n:1);
/// `None` clears the binding. `series_id` is carried for the `EventMetadata`
/// audit trail (the audit projector keys on `series_id`); it is resolved at
/// the API edge from the **category's** season projection (or, when clearing,
/// from the costume projection), never queried again by the command adapter.
/// The season-scope invariant (`category.season_id ∈ repertoire ∪
/// season(character)`) is enforced as an API-edge pre-check (409
/// `costume-category.season-mismatch`) — the scope-free aggregate cannot and
/// must not validate it.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct SetCostumeCategory {
    pub id: Uuid,
    pub category_id: Option<CostumeCategoryId>,
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
impl kameo_es::CommandName for AddCostumeToSeason {
    fn command_name() -> &'static str {
        "AddCostumeToSeason"
    }
}
impl kameo_es::CommandName for RemoveCostumeFromSeason {
    fn command_name() -> &'static str {
        "RemoveCostumeFromSeason"
    }
}
impl kameo_es::CommandName for AddDetail {
    fn command_name() -> &'static str {
        "AddDetail"
    }
}
impl kameo_es::CommandName for UpdateCostumeDetail {
    fn command_name() -> &'static str {
        "UpdateCostumeDetail"
    }
}
impl kameo_es::CommandName for RemoveDetail {
    fn command_name() -> &'static str {
        "RemoveDetail"
    }
}
impl kameo_es::CommandName for SetCostumeCategory {
    fn command_name() -> &'static str {
        "SetCostumeCategory"
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
