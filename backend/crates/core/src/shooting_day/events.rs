// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Events and the import-provenance source discriminator for `ShootingDay`.

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EpisodeId, LexicalSortKey, ShootingDayId};

/// Provenance discriminator for how a `ShootingDay` came into existence.
///
/// `Manual` is the user-created path. `AiExtracted` marks a day created by the
/// AI schedule import, carrying the import `document_id` (the AI job id), an
/// optional `external_ref` and the extraction `confidence`.
///
/// `confidence` is `Option<f32>` (issue #517): the import has no per-model or
/// per-row confidence value, so the apply records `None` — the former
/// hard-coded `1.0` was a misleading constant. Persisted events with a plain
/// numeric value (pre-change apply) deserialize losslessly as `Some(...)`.
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
        confidence: Option<f32>,
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
    /// The shooting day has been wrapped (finalised).
    ///
    /// Once wrapped, the Soll-Ist-Vergleich report is considered authoritative.
    /// Wrapping is idempotent and does not prevent archiving.
    ShootingDayWrapped {
        id: ShootingDayId,
        wrapped_at: DateTime<Utc>,
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
            Self::ShootingDayWrapped { .. } => "ShootingDayWrapped",
        }
    }
}
