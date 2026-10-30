// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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

    /// The aggregate was deleted (issue #770): a deleted stream rejects every
    /// further command instead of appending events the projection can no longer
    /// apply.
    #[error("Scene({id}) was deleted")]
    Deleted { id: uuid::Uuid },
    #[error("Character is already assigned to this scene")]
    CharacterAlreadyAssigned,

    /// The character is not in the scene's `assigned_characters`, so it
    /// cannot hold a outfit beat (issue #546).
    #[error("Character {character_id} is not assigned to this scene")]
    CharacterNotInScene { character_id: uuid::Uuid },

    /// No outfit beat exists at `(character_id, order)` (issue #546).
    #[error("No outfit beat for character {character_id} at order {order}")]
    BeatNotFound {
        character_id: uuid::Uuid,
        order: u32,
    },

    /// A clear-all (`RemoveOutfitBeat.order = None`) targeted a character
    /// with no beats at all — surfaced as the dedicated 422
    /// `scene.beat-not-found` (issue #546, CodeRabbit review).
    #[error("Character {character_id} has no outfit beats in this scene")]
    NoOutfitBeats { character_id: uuid::Uuid },

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
