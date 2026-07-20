// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Errors for the `ShootingDay` aggregate.

use thiserror::Error;

use crate::shared::{AggregateVersion, LexicalSortKey, ShootingDayId};

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum ShootingDayError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("ShootingDay({id}) not found")]
    NotFound { id: ShootingDayId },

    #[error("ShootingDay({id}) is archived and cannot be mutated")]
    ArchivedCannotBeMutated { id: ShootingDayId },

    #[error("order key {0} already exists for this episode")]
    DuplicateOrderKey(LexicalSortKey),

    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
