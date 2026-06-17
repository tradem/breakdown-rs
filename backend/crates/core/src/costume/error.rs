// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Costume errors.

use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum CostumeError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Costume not found: {id}")]
    NotFound { id: uuid::Uuid },

    #[error("Costume is already assigned to character {assigned_to}")]
    AlreadyAssigned { assigned_to: uuid::Uuid },
}
