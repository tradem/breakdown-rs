// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Calculation errors.

use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum CalculationError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Item not found: {id}")]
    ItemNotFound { id: uuid::Uuid },

    #[error("Calculation not found: {id}")]
    NotFound { id: uuid::Uuid },
}
