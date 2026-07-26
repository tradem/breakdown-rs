// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Events emitted by the `SceneShootAggregate`.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{
    AggregateVersion, LexicalSortKey, PhotoId, SceneShootId, SceneShootStatus, ShootingDayId,
    UserId,
};

/// A single mutable, audited note on a `SceneShoot`.
///
/// Notes carry an id (UUIDv7), body, and optional author claim from the
/// `CurrentUser`. The event stream is the authoritative audit log.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SceneShootNote {
    pub id: Uuid,
    pub body: String,
    pub author: Option<UserId>,
}

/// Events emitted by the `SceneShootAggregate`.
///
/// Every event carries `id` and `version` (`AggregateVersion::INITIAL` on
/// creation, then `prev + 1`) so the read model and optimistic-locking can
/// track it without re-deriving from the stream.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum SceneShootEvent {
    /// A scene shoot has been planned (Dispo creation).
    SceneShootPlanned {
        id: SceneShootId,
        scene_id: Uuid,
        shooting_day_id: ShootingDayId,
        planned_order: LexicalSortKey,
        status: SceneShootStatus,
        version: AggregateVersion,
    },
    /// The planned order has been re-set (only while no execution data exists).
    SceneShootReplanned {
        id: SceneShootId,
        planned_order: LexicalSortKey,
        version: AggregateVersion,
    },
    /// Execution has started for this scene shoot.
    SceneShootStarted {
        id: SceneShootId,
        start_dt: DateTime<Utc>,
        version: AggregateVersion,
    },
    /// The actual (Ist) order has been set or replaced.
    SceneShootActualOrderSet {
        id: SceneShootId,
        actual_order: LexicalSortKey,
        version: AggregateVersion,
    },
    /// The scene shoot has finished.
    SceneShootFinished {
        id: SceneShootId,
        end_dt: DateTime<Utc>,
        version: AggregateVersion,
    },
    /// The scene shoot has been skipped.
    SceneShootSkipped {
        id: SceneShootId,
        version: AggregateVersion,
    },
    /// A note was added to this scene shoot.
    ShootDayNoteAdded {
        id: SceneShootId,
        note_id: Uuid,
        body: String,
        author: Option<UserId>,
        version: AggregateVersion,
    },
    /// An existing note was updated.
    ShootDayNoteUpdated {
        id: SceneShootId,
        note_id: Uuid,
        body: String,
        version: AggregateVersion,
    },
    /// A note was removed.
    ShootDayNoteRemoved {
        id: SceneShootId,
        note_id: Uuid,
        version: AggregateVersion,
    },
    /// A continuity photo was linked to this scene shoot.
    ContinuityPhotoLinked {
        id: SceneShootId,
        photo_id: PhotoId,
        version: AggregateVersion,
    },
    /// A continuity photo was unlinked from this scene shoot.
    ContinuityPhotoUnlinked {
        id: SceneShootId,
        photo_id: PhotoId,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for SceneShootEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::SceneShootPlanned { .. } => "SceneShootPlanned",
            Self::SceneShootReplanned { .. } => "SceneShootReplanned",
            Self::SceneShootStarted { .. } => "SceneShootStarted",
            Self::SceneShootActualOrderSet { .. } => "SceneShootActualOrderSet",
            Self::SceneShootFinished { .. } => "SceneShootFinished",
            Self::SceneShootSkipped { .. } => "SceneShootSkipped",
            Self::ShootDayNoteAdded { .. } => "ShootDayNoteAdded",
            Self::ShootDayNoteUpdated { .. } => "ShootDayNoteUpdated",
            Self::ShootDayNoteRemoved { .. } => "ShootDayNoteRemoved",
            Self::ContinuityPhotoLinked { .. } => "ContinuityPhotoLinked",
            Self::ContinuityPhotoUnlinked { .. } => "ContinuityPhotoUnlinked",
        }
    }
}
