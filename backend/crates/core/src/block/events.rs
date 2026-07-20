// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Block domain events.

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, SeasonId, SeriesId};

/// Events emitted by the `BlockAggregate`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum BlockEvent {
    BlockCreated {
        id: Uuid,
        season_id: SeasonId,
        /// Denormalized from `season_id` (`Series` reference is immutable for a
        /// Block, so write-once is safe) — needed directly for the series-
        /// global numbering unique index (ADR: decision 3, parity with Episode).
        series_id: SeriesId,
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
