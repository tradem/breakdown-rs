// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Scene commands.

use uuid::Uuid;

use super::events::SceneDetails;
use crate::shared::{AggregateVersion, EpisodeId, SeriesId, ShootingDayId};

/// Create a scene within an episode.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// episode projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateScene {
    pub id: Uuid,
    pub episode_id: EpisodeId,
    pub series_id: Option<SeriesId>,
    pub details: SceneDetails,
}

/// Update a scene's details.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateSceneDetails {
    pub id: Uuid,
    pub details: SceneDetails,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Assign a character to a scene.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AssignCharacter {
    pub id: Uuid,
    pub character_id: Uuid,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Remove a character from a scene.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemoveCharacter {
    pub id: Uuid,
    pub character_id: Uuid,
    pub series_id: Option<SeriesId>,
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

/// Schedule a scene on a shooting day.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// shooting-day projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ScheduleSceneOnShootingDay {
    pub id: Uuid,
    pub shooting_day_id: ShootingDayId,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Unschedule a scene from a shooting day.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// shooting-day projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UnscheduleSceneFromShootingDay {
    pub id: Uuid,
    pub shooting_day_id: ShootingDayId,
    pub series_id: Option<SeriesId>,
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
