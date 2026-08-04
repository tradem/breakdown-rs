// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use thiserror::Error;

use crate::shared::AggregateVersion;

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum AiConfigError {
    #[error("AI provider must be selected")]
    EmptyProvider,
    #[error("AI assistant model must not be empty")]
    EmptyModel,
    #[error("AI prompt must not be empty")]
    EmptyPrompt,
    #[error("AI vault key reference must not be empty")]
    EmptyVaultKey,
    #[error("AI provider cannot change for an existing configuration")]
    ProviderMismatch,
    #[error("AI configuration not found")]
    NotFound,
    #[error("AI configuration is already revoked")]
    AlreadyRevoked,
    #[error("AI configuration version mismatch: expected {expected:?}, actual {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
