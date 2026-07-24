// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kwaipilot/kat-coder-air-v2.5 (openrouter)

//! SceneShoot domain errors.

use thiserror::Error;
use uuid::Uuid;

use crate::shared::{AggregateVersion, PhotoId, SceneShootId, SceneShootStatus};

#[derive(Error, Debug, Clone, PartialEq)]
pub enum SceneShootError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("SceneShoot not found: {id}")]
    NotFound { id: SceneShootId },

    #[error("A SceneShoot already exists for this (scene, shooting_day) pair")]
    PairAlreadyExists,

    #[error("Version mismatch on SceneShoot {entity}: expected {expected:?}, current {actual:?}")]
    VersionMismatch {
        entity: String,
        expected: AggregateVersion,
        actual: AggregateVersion,
    },

    #[error("Planned order is frozen because execution data has been recorded on this SceneShoot")]
    PlannedOrderFrozen,

    #[error("Note not found: {note_id}")]
    NoteNotFound { note_id: Uuid },

    #[error("Continuity photo {photo_id} is already linked to this SceneShoot")]
    AlreadyLinked { photo_id: PhotoId },

    #[error("SceneShoot is already started with a different start_dt")]
    AlreadyStarted,

    #[error("SceneShoot is in a terminal state ({status:?}) and cannot be mutated")]
    TerminalState { status: SceneShootStatus },
}
