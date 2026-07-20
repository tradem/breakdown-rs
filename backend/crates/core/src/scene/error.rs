// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Scene errors.

use thiserror::Error;

use crate::shared::ShootingDayId;

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

    #[error("Scene is already scheduled on shooting day {shooting_day_id}")]
    AlreadyScheduled { shooting_day_id: ShootingDayId },

    #[error("Scene is not scheduled on shooting day {shooting_day_id}")]
    NotScheduled { shooting_day_id: ShootingDayId },
}
