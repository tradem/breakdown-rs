// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Scene commands.

use uuid::Uuid;

use super::events::SceneDetails;
use crate::shared::{AggregateVersion, ProjectId};

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateScene {
    pub id: Uuid,
    pub project_id: ProjectId,
    pub details: SceneDetails,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateSceneDetails {
    pub id: Uuid,
    pub details: SceneDetails,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AssignCharacter {
    pub id: Uuid,
    pub character_id: Uuid,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemoveCharacter {
    pub id: Uuid,
    pub character_id: Uuid,
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
