// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Reasoning-effort vocabulary and per-model capability (2026-11-20
//! output-budget investigation).
//!
//! Why this lives in `core`: the `AiConfig` aggregate must reject an effort the
//! configured pair cannot honour, and `core` cannot depend on `infra`. The same
//! reasoning already puts `curated_decision_model_ids`/`is_decision_capable`
//! here, with `infra` re-exporting them.
//!
//! **Every entry below is read from the provider's own catalogue, never
//! guessed.** The three sources disagree in shape, which is exactly why the
//! accepted VALUES are per-model rather than one global list:
//!
//! | Provider | Where the capability is published |
//! |---|---|
//! | Neuralwatt | `metadata.capabilities.reasoning_effort` + `metadata.reasoning.supported_efforts` |
//! | EURouter, OpenRouter | `supported_parameters` (contains `reasoning_effort`) |
//! | OpenCode / OpenCode-Go | `capabilities.reasoning.effort[]` |
//! | OpenAI, Gemini | not published per model — **unverified, so not offered** |
//!
//! A pair absent from [`supported_reasoning_efforts`] is deliberately
//! unsupported: sending an undeclared parameter is answered with `400`, so an
//! unverified model gets no picker value and `422` on the API instead of a
//! surprise at import time.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::ports::LlmProvider;

/// Provider-side `reasoning_effort` a caller may request.
///
/// Deliberately a closed set with wire-stable names: a free-form string would let
/// a typo reach a provider that answers `400` on every call of that
/// configuration. The provider-specific extras (`max`, `xhigh`, `none`) are not
/// modelled — every use case here is *reducing* effort, and the common
/// denominator of the three catalogues is `low`/`medium`/`high`/`minimal`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "lowercase")]
pub enum ReasoningEffort {
    /// Least thinking. Measured to cut `glm-5.3-flash` output by 85 %.
    Minimal,
    Low,
    Medium,
    High,
}

impl ReasoningEffort {
    /// The wire value sent as `reasoning_effort`.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Minimal => "minimal",
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
        }
    }

    /// Every variant, in ascending order — used for the API surface and tests.
    pub const ALL: [Self; 4] = [Self::Minimal, Self::Low, Self::Medium, Self::High];
}

/// What a configuration stores: an explicit level, or "let the system decide".
///
/// Deliberately a VALUE rather than `Option<ReasoningEffort>` (2026-11-20
/// investigation). The generated Dart client omits `null` fields, so a
/// nullable field can be set but never cleared from the app — the level would be
/// a one-way door. `Auto` travels as the string `"auto"` and therefore says
/// "no explicit level" unambiguously in both directions.
///
/// `Auto` means: the curated profile for this `(provider, model)` if one
/// applies, otherwise the provider's own default. It is spelled "Auto" rather
/// than "provider default" for exactly that reason.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ReasoningEffortChoice {
    /// No explicit level — the curated profile, else the provider's own default.
    #[default]
    Auto,
    Minimal,
    Low,
    Medium,
    High,
}

impl ReasoningEffortChoice {
    /// The explicit level, or `None` for [`Self::Auto`].
    pub const fn effort(self) -> Option<ReasoningEffort> {
        match self {
            Self::Auto => None,
            Self::Minimal => Some(ReasoningEffort::Minimal),
            Self::Low => Some(ReasoningEffort::Low),
            Self::Medium => Some(ReasoningEffort::Medium),
            Self::High => Some(ReasoningEffort::High),
        }
    }

    /// Every choice, `Auto` first — the order the picker renders.
    pub const ALL: [Self; 5] = [
        Self::Auto,
        Self::Minimal,
        Self::Low,
        Self::Medium,
        Self::High,
    ];
}

impl From<ReasoningEffort> for ReasoningEffortChoice {
    fn from(effort: ReasoningEffort) -> Self {
        match effort {
            ReasoningEffort::Minimal => Self::Minimal,
            ReasoningEffort::Low => Self::Low,
            ReasoningEffort::Medium => Self::Medium,
            ReasoningEffort::High => Self::High,
        }
    }
}

/// Every effort declared by `(provider, model)`, or `None` when the pair does
/// not accept a `reasoning_effort` at all.
///
/// `Some(&[])` never occurs: a pair that accepts the field accepts at least one
/// value, and an empty slice would be an unreadable state for callers and the
/// picker.
pub fn supported_reasoning_efforts(
    provider: LlmProvider,
    model: &str,
) -> Option<&'static [ReasoningEffort]> {
    use ReasoningEffort::{High, Low, Medium, Minimal};
    /// The three values every catalogue that publishes the parameter accepts.
    /// `minimal` is OpenAI-specific and not declared by the others, so it is not
    /// offered for them.
    const BROAD: &[ReasoningEffort] = &[Low, Medium, High];
    /// Neuralwatt declares `accepted_efforts` per model and every curated one
    /// includes `minimal`.
    const ALL: &[ReasoningEffort] = &[Minimal, Low, Medium, High];
    /// OpenCode's `capabilities.reasoning.effort[]` for its GLM and Kimi
    /// endpoints is `[low, high, max]` — **no `medium`**.
    const LOW_HIGH: &[ReasoningEffort] = &[Low, High];

    match (provider, model) {
        // --- Neuralwatt: `capabilities.reasoning_effort: true` on all thirteen
        // curated models, `accepted_efforts` including `minimal` on each. ---
        (LlmProvider::Neuralwatt, "deepseek-v4.1-flash" | "deepseek-v4-flash")
        | (
            LlmProvider::Neuralwatt,
            "glm-5.3" | "glm-5.3-fast" | "glm-5.3-flex" | "glm-5.3-flash" | "glm-5.3-short",
        ) => Some(ALL),
        (LlmProvider::Neuralwatt, "kimi-k3" | "kimi-k3-fast" | "kimi-k3-flex") => Some(ALL),
        (LlmProvider::Neuralwatt, "qwen3.6-35b" | "qwen3.6-35b-fast" | "qwen-3.8-27b") => Some(ALL),

        // --- EURouter: `supported_parameters` contains `reasoning_effort` for
        // these three, and for nothing else curated. `mistral-large-3` is
        // deliberately absent: its list has no `reasoning_effort`. ---
        (LlmProvider::EURouter, "mistral-small-4" | "mistral-medium-3.5" | "deepseek-v4-pro") => {
            Some(BROAD)
        }

        // --- OpenRouter: same `supported_parameters` shape. ---
        (
            LlmProvider::OpenRouter,
            "openai/gpt-5-mini" | "deepseek/deepseek-v4-flash" | "deepseek/deepseek-v4.1-flash",
        ) => Some(BROAD),

        // --- OpenCode / -Go: explicit `capabilities.reasoning.effort[]`. ---
        (
            LlmProvider::OpenCodeGo | LlmProvider::OpenCode,
            "glm-5.2" | "glm-5.3" | "kimi-k3" | "minimax-m3" | "mimo-v2.6-pro",
        ) => Some(LOW_HIGH),
        (
            LlmProvider::OpenCodeGo | LlmProvider::OpenCode,
            "grok-4.5" | "grok-4.6" | "kimi-k2.7-code" | "minimax-m2.7",
        ) => Some(BROAD),

        // Everything else — OpenAI and Gemini publish no per-model parameter
        // metadata (unverified), Ollama has a different API, and a rotated-out
        // legacy id is not something to offer.
        _ => None,
    }
}

/// Whether `effort` may be requested for `(provider, model)`.
pub fn supports_reasoning_effort(
    provider: LlmProvider,
    model: &str,
    effort: ReasoningEffort,
) -> bool {
    supported_reasoning_efforts(provider, model).is_some_and(|efforts| efforts.contains(&effort))
}

#[cfg(test)]
#[path = "reasoning_tests.rs"]
mod reasoning_tests;
