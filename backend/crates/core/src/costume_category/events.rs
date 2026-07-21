// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! CostumeCategory events.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, LexicalSortKey, SeasonId};

/// Events emitted by the `CostumeCategoryAggregate`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum CostumeCategoryEvent {
    /// A new category was created in a Season's vocabulary.
    CostumeCategoryCreated {
        id: Uuid,
        season_id: SeasonId,
        name: String,
        order_key: LexicalSortKey,
        version: AggregateVersion,
    },
    /// The (display) name changed. Order and scope are untouched.
    CostumeCategoryRenamed {
        id: Uuid,
        name: String,
        version: AggregateVersion,
    },
    /// The ordering key changed (single move between two siblings).
    CostumeCategoryReordered {
        id: Uuid,
        order_key: LexicalSortKey,
        version: AggregateVersion,
    },
    /// Soft-archive (terminal). Historical `CostumeDetail` references survive.
    CostumeCategoryArchived { id: Uuid, version: AggregateVersion },
}

impl kameo_es::EventType for CostumeCategoryEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::CostumeCategoryCreated { .. } => "CostumeCategoryCreated",
            Self::CostumeCategoryRenamed { .. } => "CostumeCategoryRenamed",
            Self::CostumeCategoryReordered { .. } => "CostumeCategoryReordered",
            Self::CostumeCategoryArchived { .. } => "CostumeCategoryArchived",
        }
    }
}
