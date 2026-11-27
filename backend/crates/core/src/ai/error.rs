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
    /// Decision Model configuration (issue #722): the configured provider
    /// does not natively host decision models (only Neuralwatt, EURouter and
    /// OpenRouter are curated).
    #[error("provider does not host decision models")]
    DecisionProviderUnsupported,
    /// A decision model or vault key was set without a decision provider.
    #[error("decision model requires a decision provider")]
    DecisionProviderRequired,
    #[error("decision model must not be empty")]
    EmptyDecisionModel,
    /// The decision model is not in the provider's curated catalog.
    #[error("decision model is not curated for the provider")]
    DecisionModelUnknown,
    #[error("decision vault key reference must not be empty")]
    EmptyDecisionVaultKey,
    /// Vision slot (issue #1013): a vision model, provider or vault key was
    /// set without the other two. All-or-nothing, like the decision triple —
    /// the worker could not build a page-image client from half a slot.
    #[error("vision model requires a vision provider and vault key")]
    VisionProviderRequired,
    /// The configured vision provider cannot legally carry page images
    /// (ADR-041 `D2`: zero data retention, no training on inputs, EU data
    /// residency). Refused at save time so the refusal arrives before the
    /// first paid PDF page instead of on it.
    #[error("vision provider cannot carry page images")]
    VisionProviderUnsupported,
    #[error("vision model must not be empty")]
    EmptyVisionModel,
    #[error("vision vault key reference must not be empty")]
    EmptyVisionVaultKey,
    /// Same-key reuse rule (issue #722 precedent): a vision slot may reference
    /// the extraction key only when it names the SAME provider. A foreign
    /// provider's key would authenticate a client built for another endpoint.
    #[error("vision vault key cannot be reused across providers")]
    VisionVaultKeyMismatch,
    /// The vision model is not in the provider's curated vision catalogue
    /// (issue #1013). Only checked for a CHANGED model, so a catalogue rotation
    /// can never brick an unrelated edit of an existing configuration.
    #[error("vision model is not curated for the provider")]
    VisionModelUnknown,
    /// The configured assistant pair does not accept the requested
    /// `reasoning_effort` (2026-11-20 output-budget investigation): either the
    /// provider/model declares no such parameter at all, or it declares a
    /// different value set. Rejected while the error is still cheap — at save
    /// time, not on every import call.
    #[error("model does not accept the requested reasoning effort")]
    ReasoningEffortUnsupported,
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
