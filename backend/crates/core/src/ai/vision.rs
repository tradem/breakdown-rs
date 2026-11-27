// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Vision (page-image) model catalogue (issue #1013).
//!
//! The AI configuration names the pair that carries **page images** in a slot
//! separate from the text assistant pair (`vision_provider`, `vision_model`,
//! `vision_vault_key_id`). This module is the pure domain half of that
//! capability: which models a provider is known to accept images with, and
//! whether a named model is acceptable for a provider at all.
//!
//! It is deliberately NOT the image-generation catalogue
//! (`provider_registry::curated_image_model_ids`, #673): a diffusion model
//! produces pictures, a vision model *reads* them. Overloading one list for
//! both would offer a text-blind generator to the page extractor.
//!
//! **Two different questions, two different answers.**
//!
//! * [`curated_vision_model_ids`] answers "which models may the vision picker
//!   offer?" — it is a *short* list of models this workspace has verified as
//!   image-capable (ADR-041 `D2.1`), and it is empty for a provider whose
//!   catalogue cannot be verified from here.
//! * [`is_vision_model_acceptable`] answers "may this configuration SAVE the
//!   model it names?" — an empty catalogue means "nothing to check against"
//!   (a local `ollama` tag, an unverified reseller), so the operator's choice
//!   is accepted; the runtime egress gate still decides whether the provider
//!   may receive an image at all.
//!
//! Conflating the two would either hide every local model from the picker or
//! reject a legitimate local tag at save time, so they are separate functions
//! on purpose.

use super::ports::LlmProvider;

/// Curated **vision** model IDs per provider (issue #1013).
///
/// Verified against each provider's own published catalogue on **2026-11-25**
/// (ADR-041 `D2.1`); the notes below are the verification evidence and must be
/// updated together with the list:
///
/// * **Scaleway** — both IDs are documented as vision-capable in Scaleway's
///   own reference (`.../how-to/query-vision-models/`).
/// * **OVHcloud** — both carry the `Vision` capability tag in the LIVE
///   `GET /v1/models` response. `Qwen2.5-VL-72B-Instruct` is deliberately not
///   curated: the catalogue marks it "Being retired".
/// * **Nebius** — both are listed in models.dev's `nebius` feed with
///   multimodal (`attachment: true`) input; Token Factory's own `/v1/models`
///   needs a paid key, so the live check is a deployment task (see
///   `.github/instructions/ai-import.instructions.md`).
///
/// Deliberately EMPTY elsewhere:
///
/// * `eurouter` is a reseller fronting many upstreams — a per-model vision
///   claim cannot be verified from here, and the nightly vision smoke gives it
///   no paid page call for exactly that reason. An operator who knows their
///   upstream may still name a model (see [`is_vision_model_acceptable`]).
/// * `ollama` tags are deployment-local: the catalogue this workspace ships
///   cannot know which of them were pulled with vision weights.
/// * `openai`, `gemini` and `openrouter` fail the ADR-041 `D2` egress gate, so
///   offering them here would be a lie — the aggregate refuses the slot before
///   a model ID is ever considered.
#[must_use]
pub fn curated_vision_model_ids(provider: LlmProvider) -> &'static [&'static str] {
    match provider {
        LlmProvider::Scaleway => &["qwen3.5-397b-a17b", "mistral-small-3.2-24b-instruct-2506"],
        LlmProvider::Ovhcloud => &["qwen3-vl-30b-a3b", "Mistral-Small-3.2-24B-Instruct-2506"],
        LlmProvider::Nebius => &["Qwen/Qwen3.8-27B", "deepseek-ai/DeepSeek-V4.1-Flash-1017"],
        // LlmProvider is #[non_exhaustive]; an unlisted variant has no verified
        // vision catalogue, which is NOT the same as "cannot carry images" —
        // that question is answered by `vision_egress_policy`.
        _ => &[],
    }
}

/// Whether `provider` publishes a curated vision catalogue at all.
///
/// `false` means "this workspace cannot verify which models see" — the picker
/// serves an empty list and the aggregate accepts whatever the operator names.
#[must_use]
pub fn has_curated_vision_models(provider: LlmProvider) -> bool {
    !curated_vision_model_ids(provider).is_empty()
}

/// Whether `model` is one of `provider`'s curated vision models.
///
/// Exact match, like [`super::decision::is_curated_decision_model`]: a
/// provider's model IDs are case-sensitive (`Mistral-Small-3.2-24B-Instruct-2506`
/// vs `mistral-small-3.2-24b-instruct-2506` are DIFFERENT ids on different
/// providers), so a case-insensitive comparison would accept an ID the
/// provider will answer with `404`.
#[must_use]
pub fn is_curated_vision_model(provider: LlmProvider, model: &str) -> bool {
    curated_vision_model_ids(provider).contains(&model)
}

/// Whether a configuration may SAVE `(provider, model)` as its vision slot
/// (issue #1013).
///
/// A provider with a curated catalogue must name one of its models; a provider
/// without one accepts any non-empty ID, because there is nothing to check
/// against and the operator's own catalogue (a local `ollama` tag, a reseller
/// upstream) is the authority. The egress gate is a separate, unconditional
/// check — this predicate never widens it.
#[must_use]
pub fn is_vision_model_acceptable(provider: LlmProvider, model: &str) -> bool {
    if !has_curated_vision_models(provider) {
        return true;
    }
    is_curated_vision_model(provider, model)
}

#[cfg(test)]
#[path = "vision_tests.rs"]
mod vision_tests;
