// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Scene commands.

use uuid::Uuid;

use super::events::{SceneDetails, SceneSource, default_scene_source};
use crate::shared::{AggregateVersion, EpisodeId, ProjectId, ShootingDayId};

/// Create a scene within an episode.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// episode projection, never queried again by the command adapter.
///
/// `source` records the scene's provenance: the REST handler passes `Manual`,
/// the AI script-apply worker passes `AiExtracted` with the import job id and
/// the draft ref issued for this scene (issue #517). Defaults to `Manual` on
/// wire inputs that omit it.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateScene {
    pub id: Uuid,
    pub episode_id: EpisodeId,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub details: SceneDetails,
    #[serde(default = "default_scene_source")]
    pub source: SceneSource,
}

/// Update a scene's details.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateSceneDetails {
    pub id: Uuid,
    pub details: SceneDetails,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Assign a character to a scene.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AssignCharacter {
    pub id: Uuid,
    pub character_id: Uuid,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Remove a character from a scene.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemoveCharacter {
    pub id: Uuid,
    pub character_id: Uuid,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Add a costume beat: “character C wears costume K in this scene”.
///
/// The beat's `order` is computed by the aggregate (`max + 1` per character,
/// `0` when none exist) — never client-supplied: a client-chosen order is a
/// race. The character must already be in `assigned_characters`.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AddCostumeBeat {
    pub id: Uuid,
    pub character_id: Uuid,
    pub costume_id: Uuid,
    /// Optional free-text cue for the wardrobe crew ("nach dem Telefonat").
    pub note: Option<String>,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Update a costume beat in place, addressing it by `(character_id, order)`.
///
/// Never changes `order` (reordering is remove + add, which keeps the event
/// history legible); `BeatNotFound` if no beat exists at that position.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateCostumeBeat {
    pub id: Uuid,
    pub character_id: Uuid,
    pub order: u32,
    pub costume_id: Uuid,
    pub note: Option<String>,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Remove costume beats of a character: `Some(order)` removes exactly that
/// beat, `None` removes all beats of the character (= “no costume in this
/// scene”, the first-class empty state).
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemoveCostumeBeat {
    pub id: Uuid,
    pub character_id: Uuid,
    pub order: Option<u32>,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateScene {
    fn command_name() -> &'static str {
        "CreateScene"
    }
}
impl kameo_es::CommandName for UpdateSceneDetails {
    fn command_name() -> &'static str {
        "UpdateSceneDetails"
    }
}
impl kameo_es::CommandName for AssignCharacter {
    fn command_name() -> &'static str {
        "AssignCharacter"
    }
}
impl kameo_es::CommandName for RemoveCharacter {
    fn command_name() -> &'static str {
        "RemoveCharacter"
    }
}
impl kameo_es::CommandName for AddCostumeBeat {
    fn command_name() -> &'static str {
        "AddCostumeBeat"
    }
}
impl kameo_es::CommandName for UpdateCostumeBeat {
    fn command_name() -> &'static str {
        "UpdateCostumeBeat"
    }
}
impl kameo_es::CommandName for RemoveCostumeBeat {
    fn command_name() -> &'static str {
        "RemoveCostumeBeat"
    }
}

/// Schedule a scene on a shooting day.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// shooting-day projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ScheduleSceneOnShootingDay {
    pub id: Uuid,
    pub shooting_day_id: ShootingDayId,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

/// Unschedule a scene from a shooting day.
///
/// `project_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `project_id`); it is resolved at the API edge from the
/// shooting-day projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UnscheduleSceneFromShootingDay {
    pub id: Uuid,
    pub shooting_day_id: ShootingDayId,
    // wire name pinned: layer 3 (OpenAPI field rename) is a breaking ADR-021 change, deferred
    pub project_id: Option<ProjectId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for ScheduleSceneOnShootingDay {
    fn command_name() -> &'static str {
        "ScheduleSceneOnShootingDay"
    }
}
impl kameo_es::CommandName for UnscheduleSceneFromShootingDay {
    fn command_name() -> &'static str {
        "UnscheduleSceneFromShootingDay"
    }
}
