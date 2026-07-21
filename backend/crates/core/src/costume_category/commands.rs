// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! CostumeCategory commands.

use uuid::Uuid;

use crate::shared::{AggregateVersion, LexicalSortKey, SeasonId};

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateCostumeCategory {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub name: String,
    pub order_key: LexicalSortKey,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenameCostumeCategory {
    pub id: Uuid,
    pub name: String,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ReorderCostumeCategory {
    pub id: Uuid,
    pub order_key: LexicalSortKey,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ArchiveCostumeCategory {
    pub id: Uuid,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateCostumeCategory {
    fn command_name() -> &'static str {
        "CreateCostumeCategory"
    }
}
impl kameo_es::CommandName for RenameCostumeCategory {
    fn command_name() -> &'static str {
        "RenameCostumeCategory"
    }
}
impl kameo_es::CommandName for ReorderCostumeCategory {
    fn command_name() -> &'static str {
        "ReorderCostumeCategory"
    }
}
impl kameo_es::CommandName for ArchiveCostumeCategory {
    fn command_name() -> &'static str {
        "ArchiveCostumeCategory"
    }
}
