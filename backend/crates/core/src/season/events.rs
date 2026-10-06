// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Season domain events.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, SeriesId};

/// Events emitted by the `SeasonAggregate`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum SeasonEvent {
    SeasonCreated {
        id: Uuid,
        series_id: SeriesId,
        number: i32,
        title: Option<String>,
        version: AggregateVersion,
    },
    SeasonRenamed {
        id: Uuid,
        title: Option<String>,
        version: AggregateVersion,
    },
    /// The season is finished being produced (terminal lifecycle state).
    ///
    /// The season's number stays reserved (the (series_id, number) unique
    /// index is untouched by design, issue #533) and its inventory (blocks,
    /// episodes, shooting days) stays readable — only the season itself is
    /// locked against further mutation.
    SeasonArchived { id: Uuid, version: AggregateVersion },
}

impl kameo_es::EventType for SeasonEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::SeasonCreated { .. } => "SeasonCreated",
            Self::SeasonRenamed { .. } => "SeasonRenamed",
            Self::SeasonArchived { .. } => "SeasonArchived",
        }
    }
}
