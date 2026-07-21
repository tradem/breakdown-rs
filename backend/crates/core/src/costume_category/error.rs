// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! CostumeCategory errors.

use thiserror::Error;

use crate::shared::{AggregateVersion, CostumeCategoryId};

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum CostumeCategoryError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("CostumeCategory({id}) is archived and cannot be mutated")]
    ArchivedCannotBeMutated { id: CostumeCategoryId },

    #[error("version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
