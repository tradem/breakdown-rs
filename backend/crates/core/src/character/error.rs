// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Character domain errors.

use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum CharacterError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Entity not found: {id}")]
    NotFound { id: uuid::Uuid },
}
