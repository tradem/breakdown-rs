// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use thiserror::Error;

use crate::shared::AggregateVersion;

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum SettingsError {
    #[error("credential provider must not be empty")]
    EmptyProvider,
    #[error("vault key reference must not be empty")]
    EmptyVaultKey,
    #[error("credential provider cannot change during rotation")]
    ProviderMismatch,
    #[error("credential binding not found")]
    NotFound,
    #[error("credential binding is already revoked")]
    AlreadyRevoked,
    #[error("settings version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
