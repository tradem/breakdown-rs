// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Block errors.

use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum BlockError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Block not found: {id}")]
    NotFound { id: uuid::Uuid },
}
