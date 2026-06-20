// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Scene errors.

use thiserror::Error;

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
}
