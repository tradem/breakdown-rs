// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)

//! Block errors.

use thiserror::Error;

use crate::shared::AggregateVersion;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum BlockError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Block not found: {id}")]
    NotFound { id: uuid::Uuid },

    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
