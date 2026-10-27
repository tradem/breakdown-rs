// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Piece aggregate errors.

use thiserror::Error;
use uuid::Uuid;

use crate::shared::AggregateVersion;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum PieceError {
    /// The piece name is empty or whitespace-only. A fundus item without a
    /// name is unreachable for the wardrobe crew, so this is a hard rejection
    /// (422 `piece.validation`) rather than a silent `None`.
    #[error("Piece name must not be empty")]
    EmptyName,

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Piece not found: {id}")]
    NotFound { id: Uuid },

    /// The piece exists, but the addressed detail does not. A dedicated
    /// variant so the HTTP edge can answer 404 `piece-detail.not-found` and a
    /// client can tell "the detail is gone" apart from a validation failure.
    #[error("Piece detail not found: {id}")]
    DetailNotFound { id: Uuid },

    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
