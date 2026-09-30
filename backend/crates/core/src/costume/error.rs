// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
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

    /// The costume exists, but the addressed detail does not (issue #544).
    /// A dedicated variant — not a `ValidationError` string — so the HTTP
    /// edge can answer 404 `costume-detail.not-found` and the client can
    /// tell "the detail is gone" apart from a genuine validation failure.
    #[error("Costume detail not found: {id}")]
    DetailNotFound { id: uuid::Uuid },

    #[error("Costume is already assigned to character {assigned_to}")]
    AlreadyAssigned { assigned_to: uuid::Uuid },

    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
