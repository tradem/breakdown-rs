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
        /// `#[serde(rename = "series_id")]` pins the **persisted** key and stays
        /// that way: stored `BlockCreated` events already use `series_id`,
        /// ADR-002 forbids rewriting history, and `projection_audit.event_key` is
        /// derived from the re-serialized payload. Issue #599 renamed every *other*
        /// spelling but deliberately left this one.
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
