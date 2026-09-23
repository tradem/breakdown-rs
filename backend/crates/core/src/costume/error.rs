// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)

//! Costume errors.

use thiserror::Error;

use crate::shared::AggregateVersion;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum CostumeError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Costume not found: {id}")]
    NotFound { id: uuid::Uuid },

    #[error("Costume is already assigned to character {assigned_to}")]
    AlreadyAssigned { assigned_to: uuid::Uuid },

    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
