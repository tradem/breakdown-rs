// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Costume commands.

use uuid::Uuid;

use super::events::CostumeDetail;
use crate::shared::{AggregateVersion, ProjectId};

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateCostume {
    pub id: Uuid,
    pub project_id: ProjectId,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateCostumeNotes {
    pub id: Uuid,
    pub notes: String,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AssignCostumeToCharacter {
    pub id: Uuid,
    pub character_id: Uuid,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UnassignCostume {
    pub id: Uuid,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AddDetail {
    pub id: Uuid,
    pub detail: CostumeDetail,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemoveDetail {
    pub id: Uuid,
    pub detail_id: Uuid,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct LinkPhoto {
    pub id: Uuid,
    pub photo_id: Uuid,
    pub version: AggregateVersion,
}
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UnlinkPhoto {
    pub id: Uuid,
    pub photo_id: Uuid,
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
