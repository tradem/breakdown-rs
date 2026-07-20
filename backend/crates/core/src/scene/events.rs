// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Scene events.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EpisodeId, ShootingDayId};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default, utoipa::ToSchema)]
pub struct SceneDetails {
    pub scene_number: Option<u32>,
    pub location: Option<String>,
    pub mood: Option<String>,
    pub is_schedule_set: bool,
    /// Free-form scene description/prose summary.
    pub summary: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum SceneEvent {
    SceneCreated {
        id: Uuid,
        episode_id: EpisodeId,
        details: SceneDetails,
        assigned_characters: Vec<Uuid>,
        version: AggregateVersion,
    },
    SceneDetailsUpdated {
        id: Uuid,
        details: SceneDetails,
        version: AggregateVersion,
    },
    CharacterAssigned {
        id: Uuid,
        character_id: Uuid,
        version: AggregateVersion,
    },
    CharacterRemoved {
        id: Uuid,
        character_id: Uuid,
        version: AggregateVersion,
    },
    /// A `ShootingDay` was linked to this Scene (scene owns the collection).
    ShootingDayScheduled {
        id: Uuid,
        shooting_day_id: ShootingDayId,
        version: AggregateVersion,
    },
    /// A `ShootingDay` link was removed from this Scene.
    ShootingDayUnscheduled {
        id: Uuid,
        shooting_day_id: ShootingDayId,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for SceneEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::SceneCreated { .. } => "SceneCreated",
            Self::SceneDetailsUpdated { .. } => "SceneDetailsUpdated",
            Self::CharacterAssigned { .. } => "CharacterAssigned",
            Self::CharacterRemoved { .. } => "CharacterRemoved",
            Self::ShootingDayScheduled { .. } => "ShootingDayScheduled",
            Self::ShootingDayUnscheduled { .. } => "ShootingDayUnscheduled",
        }
    }
}
