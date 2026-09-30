// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

//! Costume events.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, CostumeCategoryId};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct CostumeDetail {
    pub id: Uuid,
    /// Free-form per-detail micro-title (e.g. "Rote Lederjacke"). Optional.
    #[serde(default)]
    pub subject: Option<String>,
    /// **Legacy field (issue #543).** The category moved to the costume
    /// aggregate (`CostumeCategorySet`); details are pure description now.
    /// The field stays on the event payload with `serde(default)` so old
    /// events replay: the aggregate and the projector derive the costume's
    /// category from it (first-wins rule). Newly added details carry `None`.
    #[serde(default)]
    pub category_id: Option<CostumeCategoryId>,
    /// The description (unchanged meaning — never reinterpreted from `subject`).
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum CostumeEvent {
    CostumeCreated {
        id: Uuid,
        character_id: Option<Uuid>,
        /// Repertoire season (issue #453): the season whose costume stream the
        /// costume appears in while unassigned. Old events (pre-#453) lack the
        /// field; `serde(default)` keeps them replayable as `None`.
        #[serde(default)]
        season_id: Option<Uuid>,
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
    DetailUpdated {
        id: Uuid,
        /// The **full** detail after the change, not a patch (issue #544).
        /// A patch would leave the field merging to the client and turn an
        /// emptied `subject` into an ambiguity (intent or accident); the
        /// full detail is unambiguous and the projector already upserts on
        /// `(costume_id, detail_id)`.
        detail: CostumeDetail,
        version: AggregateVersion,
    },
    DetailRemoved {
        id: Uuid,
        detail_id: Uuid,
        version: AggregateVersion,
    },
    /// The costume's single category was set or cleared (issue #543).
    /// `category_id: None` clears the binding.
    CostumeCategorySet {
        id: Uuid,
        category_id: Option<CostumeCategoryId>,
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
            Self::DetailUpdated { .. } => "DetailUpdated",
            Self::DetailRemoved { .. } => "DetailRemoved",
            Self::CostumeCategorySet { .. } => "CostumeCategorySet",
            Self::PhotoLinked { .. } => "PhotoLinked",
            Self::PhotoUnlinked { .. } => "PhotoUnlinked",
        }
    }
}
