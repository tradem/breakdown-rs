// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)

//! Episode errors.

use thiserror::Error;

use crate::shared::AggregateVersion;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum EpisodeError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Episode not found: {id}")]
    NotFound { id: uuid::Uuid },

    /// The aggregate was deleted (issue #770): a deleted stream rejects every
    /// further command instead of appending events the projection can no longer
    /// apply.
    #[error("Episode({id}) was deleted")]
    Deleted { id: uuid::Uuid },
    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
