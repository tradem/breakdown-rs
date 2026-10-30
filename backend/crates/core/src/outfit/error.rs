// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Outfit aggregate errors.

use thiserror::Error;
use uuid::Uuid;

use crate::shared::AggregateVersion;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum OutfitError {
    /// The outfit name is empty or whitespace-only (422 `outfit.validation`).
    #[error("Outfit name must not be empty")]
    EmptyName,

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Outfit not found: {id}")]
    NotFound { id: Uuid },

    /// The aggregate was deleted (issue #770): a deleted stream rejects every
    /// further command instead of appending events the projection can no longer
    /// apply.
    #[error("Outfit({id}) was deleted")]
    Deleted { id: Uuid },
    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
