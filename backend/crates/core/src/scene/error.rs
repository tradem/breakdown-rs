// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)

//! Scene errors.

use thiserror::Error;

use crate::shared::{AggregateVersion, ShootingDayId};

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum SceneError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Character not found: {id}")]
    CharacterNotFound { id: uuid::Uuid },

    #[error("Scene not found: {id}")]
    NotFound { id: uuid::Uuid },

    #[error("Character is already assigned to this scene")]
    CharacterAlreadyAssigned,

    /// The character is not in the scene's `assigned_characters`, so it
    /// cannot hold a costume beat (issue #546).
    #[error("Character {character_id} is not assigned to this scene")]
    CharacterNotInScene { character_id: uuid::Uuid },

    /// No costume beat exists at `(character_id, order)` (issue #546).
    #[error("No costume beat for character {character_id} at order {order}")]
    BeatNotFound {
        character_id: uuid::Uuid,
        order: u32,
    },

    #[error("Scene is already scheduled on shooting day {shooting_day_id}")]
    AlreadyScheduled { shooting_day_id: ShootingDayId },

    #[error("Scene is not scheduled on shooting day {shooting_day_id}")]
    NotScheduled { shooting_day_id: ShootingDayId },

    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
