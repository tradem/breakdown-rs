// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Events and the import-provenance source discriminator for `ShootingDay`.

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EpisodeId, LexicalSortKey, ShootingDayId};

/// Provenance discriminator for how a `ShootingDay` came into existence.
///
/// `Manual` is the user-created path. `AiExtracted` reserves the shape for the
/// future AI call-sheet extraction increment; retrofitting this onto already
/// persisted events would be impossible, so the field exists from day one.
///
/// Serialized as an externally-tagged enum, e.g. `{"Manual":null}` or
/// `{"AiExtracted":{"document_id":...,"external_ref":...,"confidence":...}}`,
/// which maps directly onto the `source JSONB` projection column.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, utoipa::ToSchema)]
pub enum ShootingDaySource {
    Manual,
    AiExtracted {
        document_id: Uuid,
        external_ref: Option<String>,
        confidence: f32,
    },
}

/// Events emitted by the `ShootingDayAggregate`.
///
/// Every event carries `id` and `version` (`AggregateVersion::INITIAL` on
/// creation, then `prev + 1`) so the read model and optimistic-locking can
/// track it without re-deriving from the stream.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ShootingDayEvent {
    ShootingDayCreated {
        id: ShootingDayId,
        episode_id: EpisodeId,
        label: Option<String>,
        order_key: LexicalSortKey,
        date: Option<NaiveDate>,
        source: ShootingDaySource,
        version: AggregateVersion,
    },
    ShootingDayRenamed {
        id: ShootingDayId,
        label: Option<String>,
        version: AggregateVersion,
    },
    ShootingDayRescheduled {
        id: ShootingDayId,
        date: Option<NaiveDate>,
        version: AggregateVersion,
    },
    ShootingDayReordered {
        id: ShootingDayId,
        order_key: LexicalSortKey,
        version: AggregateVersion,
    },
    ShootingDayArchived {
        id: ShootingDayId,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for ShootingDayEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::ShootingDayCreated { .. } => "ShootingDayCreated",
            Self::ShootingDayRenamed { .. } => "ShootingDayRenamed",
            Self::ShootingDayRescheduled { .. } => "ShootingDayRescheduled",
            Self::ShootingDayReordered { .. } => "ShootingDayReordered",
            Self::ShootingDayArchived { .. } => "ShootingDayArchived",
        }
    }
}
