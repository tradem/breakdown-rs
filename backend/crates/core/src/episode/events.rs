// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Episode domain events.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, BlockId, ProjectId};

/// Events emitted by the `EpisodeAggregate`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum EpisodeEvent {
    EpisodeCreated {
        id: Uuid,
        block_id: BlockId,
        /// Denormalized from `block_id` (the project reference is immutable for
        /// an Episode, so write-once is safe) — needed directly for the
        /// project-global numbering unique index (ADR: decision 3).
        ///
        /// `#[serde(rename = "series_id")]` pins the persisted key (issue #591,
        /// layer 2): stored `EpisodeCreated` events already use `project_id` and
        /// ADR-002 forbids rewriting history.
        #[serde(rename = "series_id")]
        project_id: ProjectId,
        number: i32,
        name: Option<String>,
        version: AggregateVersion,
    },
    EpisodeRenamed {
        id: Uuid,
        name: Option<String>,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for EpisodeEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::EpisodeCreated { .. } => "EpisodeCreated",
            Self::EpisodeRenamed { .. } => "EpisodeRenamed",
        }
    }
}
