// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Block domain events.

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId, SeasonId};

/// Events emitted by the `BlockAggregate`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum BlockEvent {
    BlockCreated {
        id: Uuid,
        season_id: SeasonId,
        /// Denormalized from `season_id` (the project reference is immutable for
        /// a Block, so write-once is safe) — needed directly for the
        /// project-global numbering unique index (ADR: decision 3, parity with
        /// Episode).
        ///
        /// `#[serde(rename = "series_id")]` pins the persisted key (issue #591,
        /// layer 2): stored `BlockCreated` events already use `project_id` and
        /// ADR-002 forbids rewriting history.
        #[serde(rename = "series_id")]
        project_id: ProjectId,
        number: i32,
        start_date: Option<NaiveDate>,
        end_date: Option<NaiveDate>,
        version: AggregateVersion,
    },
    BlockTimeSpanUpdated {
        id: Uuid,
        start_date: Option<NaiveDate>,
        end_date: Option<NaiveDate>,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for BlockEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::BlockCreated { .. } => "BlockCreated",
            Self::BlockTimeSpanUpdated { .. } => "BlockTimeSpanUpdated",
        }
    }
}
