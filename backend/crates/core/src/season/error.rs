// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Season errors.

use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum SeasonError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Season not found: {id}")]
    NotFound { id: uuid::Uuid },
}
