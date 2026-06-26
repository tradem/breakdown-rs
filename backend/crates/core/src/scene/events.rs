// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Scene events.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default, utoipa::ToSchema)]
pub struct SceneDetails {
    pub scene_number: Option<u32>,
    pub location: Option<String>,
    pub mood: Option<String>,
    pub is_schedule_set: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum SceneEvent {
    SceneCreated {
        id: Uuid,
        project_id: ProjectId,
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
}

impl kameo_es::EventType for SceneEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::SceneCreated { .. } => "SceneCreated",
            Self::SceneDetailsUpdated { .. } => "SceneDetailsUpdated",
            Self::CharacterAssigned { .. } => "CharacterAssigned",
            Self::CharacterRemoved { .. } => "CharacterRemoved",
        }
    }
}
