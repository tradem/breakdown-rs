// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)

//! Character domain errors.

use thiserror::Error;

use crate::shared::AggregateVersion;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum CharacterError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Entity not found: {id}")]
    NotFound { id: uuid::Uuid },

    /// The aggregate was deleted (issue #770): a deleted stream rejects every
    /// further command instead of appending events the projection can no longer
    /// apply.
    #[error("Character({id}) was deleted")]
    Deleted { id: uuid::Uuid },
    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
