// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Costume events.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct CostumeDetail {
    pub id: Uuid,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum CostumeEvent {
    CostumeCreated {
        id: Uuid,
        project_id: ProjectId,
        character_id: Option<Uuid>,
        notes: String,
        details: Vec<CostumeDetail>,
        photos: Vec<Uuid>,
        version: AggregateVersion,
    },
    CostumeNotesUpdated {
        id: Uuid,
        notes: String,
        version: AggregateVersion,
    },
    CostumeAssignedToCharacter {
        id: Uuid,
        character_id: Uuid,
        version: AggregateVersion,
    },
    CostumeUnassigned {
        id: Uuid,
        version: AggregateVersion,
    },
    DetailAdded {
        id: Uuid,
        detail: CostumeDetail,
        version: AggregateVersion,
    },
    DetailRemoved {
        id: Uuid,
        detail_id: Uuid,
        version: AggregateVersion,
    },
    PhotoLinked {
        id: Uuid,
        photo_id: Uuid,
        version: AggregateVersion,
    },
    PhotoUnlinked {
        id: Uuid,
        photo_id: Uuid,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for CostumeEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::CostumeCreated { .. } => "CostumeCreated",
            Self::CostumeNotesUpdated { .. } => "CostumeNotesUpdated",
            Self::CostumeAssignedToCharacter { .. } => "CostumeAssignedToCharacter",
            Self::CostumeUnassigned { .. } => "CostumeUnassigned",
            Self::DetailAdded { .. } => "DetailAdded",
            Self::DetailRemoved { .. } => "DetailRemoved",
            Self::PhotoLinked { .. } => "PhotoLinked",
            Self::PhotoUnlinked { .. } => "PhotoUnlinked",
        }
    }
}
