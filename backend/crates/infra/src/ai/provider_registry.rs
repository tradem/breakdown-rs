// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

//! Centralized curated `LlmProvider` metadata.
//!
//! A single metadata source prevents provider-list and provider-parser drift
//! when a provider is added or changed. Both the API provider listing and the
//! provider-key parsing resolve from this registry.

use breakdown_core::ai::{LlmProvider, ModelInfo, ReasoningEffort};

/// Curated metadata for one LLM provider.
#[derive(Debug, Clone, Copy)]
pub struct ProviderEntry {
    /// The canonical `LlmProvider` variant.
    pub variant: LlmProvider,
    /// The canonical lowercase path key (e.g. `"openai"`, `"opencode-go"`).
    pub key: &'static str,
    /// Supported aliases that resolve to the same provider (API contract).
    /// The canonical `key` is always accepted; aliases are additional names.
    pub aliases: &'static [&'static str],
}

/// Exhaustive registry of curated providers. Adding a new `LlmProvider`
/// variant requires exactly one entry here and a matching arm in the core
/// `as_str` match — no other files need to change.
pub const PROVIDER_REGISTRY: &[ProviderEntry] = &[
    ProviderEntry {
        variant: LlmProvider::OpenAI,
        key: "openai",
        aliases: &[],
    },
    ProviderEntry {
        variant: LlmProvider::Gemini,
        key: "gemini",
        aliases: &["google"],
    },
    ProviderEntry {
        variant: LlmProvider::OpenRouter,
        key: "openrouter",
        aliases: &[],
    },
    ProviderEntry {
        variant: LlmProvider::EURouter,
        key: "eurouter",
        aliases: &["openrouter_eu", "openrouter-eu"],
    },
    // Issue #968: the EU pay-as-you-go vision fallbacks of ADR-041 `D2`.
    ProviderEntry {
        variant: LlmProvider::Scaleway,
        key: "scaleway",
        aliases: &[],
    },
    ProviderEntry {
        variant: LlmProvider::Ovhcloud,
        key: "ovhcloud",
        aliases: &["ovh"],
    },
    ProviderEntry {
        variant: LlmProvider::Nebius,
        key: "nebius",
        aliases: &["token-factory", "token_factory"],
    },
    ProviderEntry {
        variant: LlmProvider::Neuralwatt,
        key: "neuralwatt",
        aliases: &[],
    },
    ProviderEntry {
        variant: LlmProvider::OpenCodeGo,
        key: "opencode-go",
        aliases: &["opencode_go"],
    },
    ProviderEntry {
        variant: LlmProvider::OpenCode,
        key: "opencode",
        aliases: &[],
    },
    ProviderEntry {
        variant: LlmProvider::Ollama,
        key: "ollama",
        aliases: &[],
    },
];

/// Provider info for the `/ai-import/providers` endpoint response.
#[derive(Debug, Clone)]
pub struct ProviderInfo {
    pub variant: LlmProvider,
    pub key: String,
}

/// List all curated providers in display order.
pub fn list_providers() -> Vec<ProviderInfo> {
    PROVIDER_REGISTRY
        .iter()
        .map(|entry| ProviderInfo {
            variant: entry.variant,
            key: entry.key.to_owned(),
        })
        .collect()
}

/// Resolve a user-supplied provider key or alias to its canonical
/// `LlmProvider` variant. Returns `None` if the value is not recognized.
pub fn resolve_provider(value: &str) -> Option<LlmProvider> {
    for entry in PROVIDER_REGISTRY {
        if entry.key == value {
            return Some(entry.variant);
        }
        for alias in entry.aliases {
            if *alias == value {
                return Some(entry.variant);
            }
        }
    }
    None
}

/// Curated assistant model IDs per provider, refreshed against the live
/// catalogs at the time of issue #675. Previously curated (now rotated-out)
/// legacy model IDs stay in [`default_allowlist`] and the `ai_model_pricing`
/// seed migration so existing persisted `AiConfig` records remain valid.
///
/// Issue #950 rotated eurouter's recommendation off `mistral-large-3` — the only
/// curated eurouter model whose `supported_parameters` carries no
/// `reasoning_effort`, so the effort picker of the #949 stack stayed empty on
/// exactly the config a new deployment creates. `mistral-large-4` declares it
/// and is the recommendation since; `mistral-large-3` stays in
/// `default_allowlist`.
///
/// Issue #1007 re-checked every list on **2026-11-26 (UTC)** against
/// `https://openrouter.ai/api/v1/models` (+ `?output_modalities=decisions`),
/// `https://api.eurouter.ai/api/v1/models` (+ the same decision filter),
/// `https://api.neuralwatt.com/v1/models`, `https://opencode.ai/zen/go/v1/models`,
/// `https://opencode.ai/zen/v1/models`,
/// `https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/models`,
/// `https://models.dev/api.json` (OpenAI/Gemini/Scaleway/Nebius cross-check) and
/// `https://ollama.com/library/qwen3.5`. `opencode` and `opencode-go` keep
/// SEPARATE arms because their live catalogues differ: the Go gateway no longer
/// lists `minimax-m2.7` while it is the only one of the two that still offers
/// `mimo-v2.6-pro`. OpenAI/Gemini/Scaleway/Nebius answer `401`/`403` anonymously,
/// so their entries come from the official model docs plus models.dev.
/// ADR-041 `D2` is untouched: Scaleway/OVHcloud/Nebius and every egress policy
/// are unchanged.
///
/// Single source for the models endpoint; a new `LlmProvider` variant must
/// be added here and to the exhaustive `as_str` match in core.
pub fn curated_model_ids(provider: LlmProvider) -> &'static [&'static str] {
    match provider {
        LlmProvider::OpenAI => &["gpt-6-luna", "gpt-6.1-terra", "gpt-5.6-luna"],
        LlmProvider::Gemini => &[
            "gemini-3.8-flash",
            "gemini-3.6-flash",
            "gemini-3.5-flash-lite",
            "gemini-3.1-pro-preview",
            "gemini-2.5-flash",
            "gemini-2.5-pro",
        ],
        LlmProvider::OpenRouter => &[
            "openai/gpt-6-luna",
            "openai/gpt-5-mini",
            "deepseek/deepseek-v4-flash",
            "deepseek/deepseek-v4.1-flash",
            "nvidia/nemotron-3.5-lightning:free",
        ],
        LlmProvider::EURouter => &[
            "mistral-large-4",
            "mistral-small-4",
            // The structured-output-capable successor of the `deepseek-v4-flash`
            // the live catalogue no longer lists — deliberately not the older
            // `deepseek-v4-flash-0731` nor the namespaced
            // `deepseek/deepseek-v4.1-flash`.
            "deepseek-v4.1-flash-1017",
            "deepseek-v4-pro",
            "mistral-medium-3.5",
        ],
        // Issue #968, verified 2026-11-25. Both IDs are documented as
        // VISION-capable by Scaleway itself (`mistral-small-3.2-24b-instruct-2506`
        // is the model of the vision how-to example; `qwen3.5-397b-a17b` is the
        // documented video/vision model) and both carry Apache-2.0 weights.
        // Catalogue: .../reference-content/supported-models/, vision example:
        // .../how-to/query-vision-models/.
        LlmProvider::Scaleway => &["qwen3.5-397b-a17b", "mistral-small-3.2-24b-instruct-2506"],
        // Issue #968, verified 2026-11-25 against the LIVE
        // `GET https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/models`
        // response (anonymous) and the AI Endpoints catalogue page: both are
        // listed with the `Vision` capability tag and their USD rates.
        // `Qwen2.5-VL-72B-Instruct` is deliberately NOT curated — the catalogue
        // marks it "Being retired".
        LlmProvider::Ovhcloud => &["qwen3-vl-30b-a3b", "Mistral-Small-3.2-24B-Instruct-2506"],
        // Issue #968, verified 2026-11-25 against models.dev's `nebius` feed
        // (the same public catalogue this workspace already consumes as its
        // pricing fallback): both IDs are listed there with multimodal
        // (`attachment: true`) input. Token Factory's own `/v1/models` requires
        // a paid key, so the live-catalog check is a deployment-time task (see
        // `.github/instructions/ai-import.instructions.md`). The Qwen family is
        // Apache-2.0; the DeepSeek release is MIT.
        LlmProvider::Nebius => &["Qwen/Qwen3.8-27B", "deepseek-ai/DeepSeek-V4.1-Flash-1017"],
        // `deepseek-v4-flash`, `glm-5.3-fast`, `glm-5.3-short`, `kimi-k3`,
        // `kimi-k3-fast` and `kimi-k3-flex` left the live catalogue on
        // 2026-11-26 and are replaced by the six flex/successor ids below.
        // `nw-*`, `mammoth-1`, `gemma-4-31b`, `mimo-*` and
        // `deepseek-v4.1-flash-speed` are deliberately NOT curated (issue #1007).
        LlmProvider::Neuralwatt => &[
            "deepseek-v4.1-flash",
            "deepseek-v4.1-flash-flex",
            "glm-5.3",
            "glm-5.3-flex",
            "glm-5.3-flash",
            "glm-5.3-flash-flex",
            "kimi-k3.1-pro",
            "kimi-k3.1-pro-flex",
            "qwen3.6-35b",
            "qwen3.6-35b-fast",
            "qwen3.6-35b-flex",
            "qwen-3.8-27b",
            "qwen-3.8-27b-flex",
        ],
        // Separate arms on purpose (issue #1007): the two catalogues differ. The
        // Go gateway no longer lists `minimax-m2.7`; `mimo-v2.6-pro` is Go-only.
        LlmProvider::OpenCodeGo => &[
            "deepseek-v4.1-flash",
            "deepseek-v4-pro",
            "glm-5.3",
            "glm-5.3-flash",
            "kimi-k3.1-pro",
            "kimi-k3",
            "kimi-k2.7-code",
            "minimax-m3",
            "mimo-v2.6-pro",
            "grok-4.7",
        ],
        LlmProvider::OpenCode => &[
            "deepseek-v4.1-flash",
            "deepseek-v4-pro",
            "glm-5.3",
            "glm-5.3-flash",
            "kimi-k3.1-pro",
            "kimi-k3",
            "kimi-k2.7-code",
            "minimax-m3",
            "minimax-m2.7",
            "grok-4.7",
        ],
        LlmProvider::Ollama => &["qwen3.5:9b", "qwen3:8b", "llama3.2", "qwen2.5-coder:7b"],
        // LlmProvider is #[non_exhaustive]; future variants get an empty
        // list so the registry stays backward-compatible without a catch-all.
        _ => &[],
    }
}

/// Curated image-generation model IDs per provider (issue #675, preparing
/// for #673). Empty for text-only providers. Seeded in `ai_model_pricing`
/// with their image rates so #673 can consume them directly.
pub fn curated_image_model_ids(provider: LlmProvider) -> &'static [&'static str] {
    match provider {
        LlmProvider::Gemini => &[
            "gemini-3.1-flash-image",
            "gemini-3.1-flash-lite-image",
            "gemini-3-pro-image",
            "gemini-2.5-flash-image",
        ],
        LlmProvider::OpenAI => &["gpt-image-2", "gpt-image-1"],
        _ => &[],
    }
}

/// The provider's recommended default model for a new AI-config creation
/// (issue #471). Must be one of the provider's [`curated_model_ids`]; the
/// `curated_models` endpoint flags it `recommended: true`. `None` for
/// uncurated/unknown variants.
pub fn recommended_model(provider: LlmProvider) -> Option<&'static str> {
    match provider {
        LlmProvider::OpenAI => Some("gpt-5.6-luna"),
        LlmProvider::Gemini => Some("gemini-3.6-flash"),
        LlmProvider::OpenRouter => Some("openai/gpt-5-mini"),
        // Issue #950: the recommendation must be the model that declares
        // `reasoning_effort` (see `the_eurouter_recommendation_publishes_an_effort`).
        LlmProvider::EURouter => Some("mistral-large-4"),
        // Issue #968: the vision-capable flagship of each fallback, because the
        // reason these providers exist is page-image schedule extraction
        // (ADR-041 `D2`); a text-only recommendation would leave the very
        // fallback path that a flapping EURouter needs unusable.
        LlmProvider::Scaleway => Some("qwen3.5-397b-a17b"),
        LlmProvider::Ovhcloud => Some("qwen3-vl-30b-a3b"),
        // `zdr_attested` still has to be set on the AI config before this
        // provider may carry page images — the gate reads the attestation, not
        // this recommendation.
        LlmProvider::Nebius => Some("Qwen/Qwen3.8-27B"),
        LlmProvider::Neuralwatt => Some("glm-5.3"),
        LlmProvider::OpenCodeGo | LlmProvider::OpenCode => Some("glm-5.3"),
        LlmProvider::Ollama => Some("qwen3:8b"),
        // LlmProvider is #[non_exhaustive]; unknown variants have no
        // curated recommendation.
        _ => None,
    }
}

/// Curated **Decision Model** IDs per provider (issue #722). Pure re-export
/// of the core catalog so the decision-models endpoint and the aggregate
/// validation share one source; a non-decision provider yields an empty list.
pub fn curated_decision_model_ids(provider: LlmProvider) -> &'static [&'static str] {
    breakdown_core::ai::curated_decision_model_ids(provider)
}

/// Whether `provider` natively hosts Decision Models (issue #736). Pure
/// re-export of the core predicate, so the `GET /ai-import/providers`
/// capability flag the client's Decision provider picker filters on and the
/// decision-models route's 422 rejection are decided by the SAME source —
/// the client no longer mirrors the set as a hardcoded allowlist.
pub fn is_decision_capable(provider: LlmProvider) -> bool {
    breakdown_core::ai::is_decision_capable(provider)
}

/// Build `ModelInfo` list for a provider's curated **decision models**
/// (issue #722). No `recommended` flag — a decision model is an optional
/// capability slot, not a default choice.
pub fn curated_decision_models(provider: LlmProvider) -> Vec<ModelInfo> {
    curated_decision_model_ids(provider)
        .iter()
        .map(|id| ModelInfo {
            id: (*id).to_owned(),
            display_name: None,
            provider,
            recommended: false,
            pricing: None,
            // A decision/image slot is not an extraction target: no effort is
            // offered for it.
            supported_reasoning_efforts: Vec::new(),
        })
        .collect()
}

/// Build `ModelInfo` list for a provider's curated **image-generation
/// models** (issue #732, serving the `curated_image_model_ids` catalog
/// prepared by #675). No `recommended` flag — the image model is an
/// optional capability slot, like the decision model. A text-only provider
/// (e.g. eurorouter, neuralwatt) yields an empty list — the honest signal
/// the image picker collapses to "— none —" on.
pub fn curated_image_models(provider: LlmProvider) -> Vec<ModelInfo> {
    curated_image_model_ids(provider)
        .iter()
        .map(|id| ModelInfo {
            id: (*id).to_owned(),
            display_name: None,
            provider,
            recommended: false,
            pricing: None,
            // A decision/image slot is not an extraction target: no effort is
            // offered for it.
            supported_reasoning_efforts: Vec::new(),
        })
        .collect()
}

/// Build `ModelInfo` list for a provider from the curated model IDs.
pub fn curated_models(provider: LlmProvider) -> Vec<ModelInfo> {
    let recommended = recommended_model(provider);
    curated_model_ids(provider)
        .iter()
        .map(|id| ModelInfo {
            id: (*id).to_owned(),
            display_name: None,
            provider,
            recommended: Some(*id) == recommended,
            pricing: None,
            supported_reasoning_efforts: breakdown_core::ai::supported_reasoning_efforts(
                provider, id,
            )
            .map(<[breakdown_core::ai::ReasoningEffort]>::to_vec)
            .unwrap_or_default(),
        })
        .collect()
}

/// Curated reasoning-effort default for one `(provider, model)` pair, or `None`
/// to send no `reasoning_effort` field at all (the provider's own default).
///
/// **Only pairs with a MEASURED saving belong here.** The 2026-11-20 nightly
/// measured `glm-5.3-flash` dropping from 7 370 to 1 089 output tokens (25.3 s →
/// 4.4 s, −85 %/−82 %) when pinned to `low`; `deepseek-v4.1-flash` moved only
/// −15 %, because its provider default is already `high`. Anything unmeasured
/// stays `None`, i.e. exactly the behaviour every call had before this table
/// existed.
///
/// A **new** curated model therefore inherits "provider default" automatically —
/// the safe answer — and pinning an effort is a deliberate, evidence-backed edit
/// to this match (the test below refuses ids that are not curated).
///
/// **Which pairs may carry a value at all is verified against the provider's own
/// catalogue**, never assumed: Neuralwatt publishes
/// `capabilities.reasoning_effort` for all 13 curated models, eurouter and
/// OpenRouter list the parameter in `supported_parameters` per model, and
/// OpenCode publishes `capabilities.reasoning.effort[]`. A future edit must
/// respect two consequences:
/// - `eurouter/mistral-large-3` is **not** among them: its
///   `supported_parameters` carries no `reasoning_effort` (that is
///   `mistral-large-4` — an earlier draft of this comment mixed the two up), so
///   pinning an effort there would send a parameter the model does not declare.
///   Since #950 the id is no longer curated, but persisted `AiConfig` records
///   still reference it, so the pair must stay `None`-resolved rather than
///   falling into a default.
/// - `eurouter/mistral-large-4` **does** declare the parameter and is the
///   curated recommendation since #950 — declaring it is a capability, not a
///   measured saving, so it is deliberately still pinned to nothing (the
///   measurement is owed, see #950).
/// - the ACCEPTED VALUES differ per model (`opencode/glm-5.3` accepts
///   `low|high|max`, no `medium`), which is why the configurable path validates
///   against a per-model set instead of one global list.
pub fn default_reasoning_effort(provider: LlmProvider, model: &str) -> Option<ReasoningEffort> {
    match (provider, model) {
        // Measured 2026-11-20 (nightly run 44700866404): −85 % output tokens,
        // −82 % wall clock. The only pair whose saving is proven.
        (LlmProvider::Neuralwatt, "glm-5.3-flash") => Some(ReasoningEffort::Low),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The model list is what a client's effort picker reacts to, so it must
    /// carry the per-model capability — otherwise the picker would offer a level
    /// that the provider answers with `400`.
    #[test]
    fn the_curated_model_list_publishes_the_effort_capability() {
        let flash = curated_models(LlmProvider::Neuralwatt)
            .into_iter()
            .find(|model| model.id == "glm-5.3-flash")
            .expect("glm-5.3-flash is curated on Neuralwatt");
        assert_eq!(
            flash.supported_reasoning_efforts,
            breakdown_core::ai::ReasoningEffort::ALL.to_vec()
        );

        // `mistral-large-4` is the eurouter recommendation since #950 and DOES
        // declare `reasoning_effort`, so the picker offers the three values the
        // provider's catalogue publishes.
        let large4 = curated_models(LlmProvider::EURouter)
            .into_iter()
            .find(|model| model.id == "mistral-large-4")
            .expect("mistral-large-4 is the curated eurouter recommendation");
        assert_eq!(
            large4.supported_reasoning_efforts,
            vec![
                ReasoningEffort::Low,
                ReasoningEffort::Medium,
                ReasoningEffort::High,
            ],
            "mistral-large-4 must offer low|medium|high — the picker of the \
             recommended model must not be empty"
        );

        // A provider whose catalogue publishes nothing offers nothing at all.
        assert!(
            curated_models(LlmProvider::OpenAI)
                .iter()
                .all(|model| model.supported_reasoning_efforts.is_empty())
        );
    }

    /// Issue #950: eurouter's recommendation was the ONE curated model of its
    /// catalogue whose `supported_parameters` carries no `reasoning_effort`, so
    /// the effort picker stayed empty on exactly the config a new deployment
    /// creates. Rotating the recommendation back onto such a model is the
    /// regression this test refuses.
    #[test]
    fn the_eurouter_recommendation_publishes_an_effort() {
        let recommended =
            recommended_model(LlmProvider::EURouter).expect("eurouter designates a recommendation");
        let model = curated_models(LlmProvider::EURouter)
            .into_iter()
            .find(|model| model.id == recommended)
            .expect("the recommendation is curated");
        assert!(
            !model.supported_reasoning_efforts.is_empty(),
            "the eurouter recommendation {recommended} must publish its \
             reasoning efforts — a default without the knob leaves the picker empty"
        );
    }

    /// The forcing function behind "check every provider so nothing is
    /// forgotten": Neuralwatt publishes `capabilities.reasoning_effort` for
    /// EVERY model, so a newly curated Neuralwatt model must appear in core's
    /// effort table too. Adding one to `curated_model_ids` without declaring its
    /// efforts fails here instead of silently degrading that model to the
    /// provider default.
    #[test]
    fn every_curated_neuralwatt_model_declares_its_reasoning_efforts() {
        for model in curated_model_ids(LlmProvider::Neuralwatt) {
            assert!(
                breakdown_core::ai::supported_reasoning_efforts(LlmProvider::Neuralwatt, model)
                    .is_some(),
                "{model} is curated on Neuralwatt but missing from \
                 core::ai::supported_reasoning_efforts"
            );
        }
    }

    /// Only a CURATED pair may carry a pinned effort: a typo'd or rotated-out
    /// model id would silently pin nothing, and a model nobody curates is not a
    /// model the API can produce.
    #[test]
    fn pinned_reasoning_efforts_name_curated_models_only() {
        assert_eq!(
            default_reasoning_effort(LlmProvider::Neuralwatt, "glm-5.3-flash"),
            Some(ReasoningEffort::Low)
        );
        assert!(
            curated_model_ids(LlmProvider::Neuralwatt).contains(&"glm-5.3-flash"),
            "the pinned model must be curated"
        );
        // `eurouter/mistral-large-3` does NOT advertise `reasoning_effort` in its
        // `supported_parameters` (that is `mistral-large-4`), so pinning it would
        // send a parameter the model does not declare. It is rotated out of the
        // curated set since #950 but still referenced by persisted configs.
        assert_eq!(
            default_reasoning_effort(LlmProvider::EURouter, "mistral-large-3"),
            None
        );
        // Declaring the parameter is a capability, not a measured saving: the
        // #950 recommendation stays unpinned until a measurement exists.
        assert_eq!(
            default_reasoning_effort(LlmProvider::EURouter, "mistral-large-4"),
            None
        );
        // A misspelling must not silently pin an effort somewhere else.
        assert_eq!(
            default_reasoning_effort(LlmProvider::Neuralwatt, "glm-5.3-flashx"),
            None
        );
        assert_eq!(
            default_reasoning_effort(LlmProvider::OpenAI, "glm-5.3-flash"),
            None
        );
        // The default is "send nothing": every curated model without a measured
        // saving keeps the provider's own effort.
        assert_eq!(
            default_reasoning_effort(LlmProvider::Neuralwatt, "kimi-k3"),
            None
        );
        assert_eq!(
            default_reasoning_effort(LlmProvider::EURouter, "mistral-small-4"),
            None
        );
    }

    /// Issue #968: every new provider resolves from its canonical key AND its
    /// documented alias, and each one curates at least one model whose id is
    /// also on the catalog allowlist — a curated model outside the allowlist is
    /// refused at the catalog boundary, so the pair must agree.
    #[test]
    fn the_eu_vision_fallbacks_resolve_and_stay_inside_the_allowlist() {
        use crate::ai::catalog::OpenAiCompatibleModelCatalog;

        assert_eq!(resolve_provider("scaleway"), Some(LlmProvider::Scaleway));
        assert_eq!(resolve_provider("ovhcloud"), Some(LlmProvider::Ovhcloud));
        assert_eq!(resolve_provider("ovh"), Some(LlmProvider::Ovhcloud));
        assert_eq!(resolve_provider("nebius"), Some(LlmProvider::Nebius));
        assert_eq!(resolve_provider("token-factory"), Some(LlmProvider::Nebius));

        let catalog = OpenAiCompatibleModelCatalog::new()
            .unwrap_or_else(|error| panic!("catalog client must build: {error}"));
        for provider in [
            LlmProvider::Scaleway,
            LlmProvider::Ovhcloud,
            LlmProvider::Nebius,
        ] {
            let models = curated_model_ids(provider);
            assert!(
                !models.is_empty(),
                "{provider:?} must curate at least one vision model"
            );
            for model in models {
                assert!(
                    catalog.is_allowed(model),
                    "{provider:?}/{model} is curated but missing from the catalog allowlist"
                );
            }
            let recommended =
                recommended_model(provider).expect("the fallback designates a recommendation");
            assert!(models.contains(&recommended));
        }
    }

    #[test]
    fn curated_decision_models_match_the_core_catalog() {
        assert_eq!(
            curated_decision_models(LlmProvider::Neuralwatt)
                .iter()
                .map(|m| m.id.as_str())
                .collect::<Vec<_>>(),
            vec!["clef-flash", "clef"]
        );
        assert_eq!(
            curated_decision_models(LlmProvider::EURouter)
                .iter()
                .map(|m| m.id.as_str())
                .collect::<Vec<_>>(),
            vec!["clef-flash", "clef", "metis"]
        );
        assert_eq!(
            curated_decision_models(LlmProvider::OpenRouter)
                .iter()
                .map(|m| m.id.as_str())
                .collect::<Vec<_>>(),
            vec![
                "cloudflare/clef-flash",
                "cloudflare/clef",
                "typesafe/jev-1.14",
                "perplexity/pplx-decider-flash-v1.2",
                "liquid/d1.2",
            ]
        );
        // Non-decision providers expose no decision models at all.
        assert!(curated_decision_models(LlmProvider::OpenAI).is_empty());
        assert!(curated_decision_models(LlmProvider::Ollama).is_empty());
        // Never recommended — the slot is optional.
        for model in curated_decision_models(LlmProvider::OpenRouter) {
            assert!(!model.recommended);
        }
    }

    /// Issue #1007: the assistant catalogues are a reviewed artifact, so the
    /// exact ids AND their order are pinned here. `opencode` and `opencode-go`
    /// are asserted separately because their live catalogues differ — sharing one
    /// arm forced an incorrect common subset (`mimo-v2.6-pro` exists only on the
    /// Go gateway, `minimax-m2.7` only on OpenCode).
    #[test]
    fn curated_model_ids_match_the_binding_catalog() {
        assert_eq!(
            curated_model_ids(LlmProvider::OpenAI),
            &["gpt-6-luna", "gpt-6.1-terra", "gpt-5.6-luna"]
        );
        assert_eq!(
            curated_model_ids(LlmProvider::Gemini),
            &[
                "gemini-3.8-flash",
                "gemini-3.6-flash",
                "gemini-3.5-flash-lite",
                "gemini-3.1-pro-preview",
                "gemini-2.5-flash",
                "gemini-2.5-pro",
            ]
        );
        assert_eq!(
            curated_model_ids(LlmProvider::OpenRouter),
            &[
                "openai/gpt-6-luna",
                "openai/gpt-5-mini",
                "deepseek/deepseek-v4-flash",
                "deepseek/deepseek-v4.1-flash",
                "nvidia/nemotron-3.5-lightning:free",
            ]
        );
        assert_eq!(
            curated_model_ids(LlmProvider::EURouter),
            &[
                "mistral-large-4",
                "mistral-small-4",
                "deepseek-v4.1-flash-1017",
                "deepseek-v4-pro",
                "mistral-medium-3.5",
            ]
        );
        // ADR-041 `D2` vision fallbacks — unchanged by #1007.
        assert_eq!(
            curated_model_ids(LlmProvider::Scaleway),
            &["qwen3.5-397b-a17b", "mistral-small-3.2-24b-instruct-2506"]
        );
        assert_eq!(
            curated_model_ids(LlmProvider::Ovhcloud),
            &["qwen3-vl-30b-a3b", "Mistral-Small-3.2-24B-Instruct-2506"]
        );
        assert_eq!(
            curated_model_ids(LlmProvider::Nebius),
            &["Qwen/Qwen3.8-27B", "deepseek-ai/DeepSeek-V4.1-Flash-1017"]
        );
        assert_eq!(
            curated_model_ids(LlmProvider::Neuralwatt),
            &[
                "deepseek-v4.1-flash",
                "deepseek-v4.1-flash-flex",
                "glm-5.3",
                "glm-5.3-flex",
                "glm-5.3-flash",
                "glm-5.3-flash-flex",
                "kimi-k3.1-pro",
                "kimi-k3.1-pro-flex",
                "qwen3.6-35b",
                "qwen3.6-35b-fast",
                "qwen3.6-35b-flex",
                "qwen-3.8-27b",
                "qwen-3.8-27b-flex",
            ]
        );
        assert_eq!(
            curated_model_ids(LlmProvider::OpenCodeGo),
            &[
                "deepseek-v4.1-flash",
                "deepseek-v4-pro",
                "glm-5.3",
                "glm-5.3-flash",
                "kimi-k3.1-pro",
                "kimi-k3",
                "kimi-k2.7-code",
                "minimax-m3",
                "mimo-v2.6-pro",
                "grok-4.7",
            ]
        );
        assert_eq!(
            curated_model_ids(LlmProvider::OpenCode),
            &[
                "deepseek-v4.1-flash",
                "deepseek-v4-pro",
                "glm-5.3",
                "glm-5.3-flash",
                "kimi-k3.1-pro",
                "kimi-k3",
                "kimi-k2.7-code",
                "minimax-m3",
                "minimax-m2.7",
                "grok-4.7",
            ]
        );
        assert_eq!(
            curated_model_ids(LlmProvider::Ollama),
            &["qwen3.5:9b", "qwen3:8b", "llama3.2", "qwen2.5-coder:7b"]
        );

        // The two OpenCode arms must stay distinct — a future refactor back to
        // one shared arm is the regression this guards.
        assert_ne!(
            curated_model_ids(LlmProvider::OpenCodeGo),
            curated_model_ids(LlmProvider::OpenCode)
        );
    }

    #[test]
    fn decision_capability_matches_the_curated_decision_catalog() {
        // Issue #736: the capability flag the providers route serves and the
        // decision-models route's non-empty catalog are the same predicate
        // observed from two sides. Asserting the biconditional for EVERY
        // registered provider is what keeps a newly capable (or de-listed)
        // provider from being advertised by one route and rejected by the
        // other — the exact client-side drift the allowlist caused.
        for info in list_providers() {
            assert_eq!(
                is_decision_capable(info.variant),
                !curated_decision_model_ids(info.variant).is_empty(),
                "provider {} reports decision capability {:?} but curates {} decision models",
                info.key,
                is_decision_capable(info.variant),
                curated_decision_model_ids(info.variant).len(),
            );
        }
        // The concrete set the client used to hardcode: pinned here so the
        // wire flag cannot silently lose a capable provider.
        assert!(is_decision_capable(LlmProvider::Neuralwatt));
        assert!(is_decision_capable(LlmProvider::EURouter));
        assert!(is_decision_capable(LlmProvider::OpenRouter));
        assert!(!is_decision_capable(LlmProvider::OpenAI));
        assert!(!is_decision_capable(LlmProvider::Gemini));
        assert!(!is_decision_capable(LlmProvider::Ollama));
    }

    #[test]
    fn registry_covers_all_curated_providers() {
        let registry_variants: Vec<LlmProvider> =
            PROVIDER_REGISTRY.iter().map(|e| e.variant).collect();
        let curated: Vec<LlmProvider> = breakdown_core::ai::CURATED_PROVIDERS.to_vec();
        assert_eq!(registry_variants, curated);
    }

    #[test]
    fn resolve_canonical_keys() {
        for entry in PROVIDER_REGISTRY {
            assert_eq!(
                resolve_provider(entry.key),
                Some(entry.variant),
                "canonical key {} failed",
                entry.key
            );
        }
    }

    #[test]
    fn resolve_aliases() {
        assert_eq!(
            resolve_provider("openrouter_eu"),
            Some(LlmProvider::EURouter)
        );
        assert_eq!(
            resolve_provider("openrouter-eu"),
            Some(LlmProvider::EURouter)
        );
        assert_eq!(
            resolve_provider("opencode_go"),
            Some(LlmProvider::OpenCodeGo)
        );
        // opencode-go is the canonical key, not an alias
        assert_eq!(
            resolve_provider("opencode-go"),
            Some(LlmProvider::OpenCodeGo)
        );
    }

    #[test]
    fn resolve_unknown_returns_none() {
        assert_eq!(resolve_provider("not-a-provider"), None);
        assert_eq!(resolve_provider(""), None);
        assert_eq!(resolve_provider("OpenAI"), None); // case-sensitive
    }

    #[test]
    fn list_providers_matches_registry_order() {
        let providers = list_providers();
        assert_eq!(providers.len(), PROVIDER_REGISTRY.len());
        for (info, entry) in providers.iter().zip(PROVIDER_REGISTRY.iter()) {
            assert_eq!(info.variant, entry.variant);
            assert_eq!(info.key, entry.key);
        }
    }

    #[test]
    fn curated_models_covers_all_variants() {
        // Ensure every provider variant produces at least one model entry.
        for entry in PROVIDER_REGISTRY {
            let models = curated_models(entry.variant);
            assert!(
                !models.is_empty(),
                "curated_models returned empty for {:?}",
                entry.variant
            );
            for model in &models {
                assert_eq!(model.provider, entry.variant);
            }
        }
    }

    #[test]
    fn recommended_model_is_curated_per_provider() {
        // Issue #471: every curated provider must designate a recommendation
        // that is part of its curated model set, so the frontend can always
        // preselect a suggested model.
        for entry in PROVIDER_REGISTRY {
            let recommended = recommended_model(entry.variant)
                .unwrap_or_else(|| panic!("{} has no recommended model", entry.key));
            assert!(
                curated_model_ids(entry.variant).contains(&recommended),
                "recommended model {recommended} of {} is not curated",
                entry.key
            );
        }
    }

    #[test]
    fn curated_models_flags_exactly_one_recommended() {
        // Issue #471: the curated models endpoint flags exactly ONE model per
        // provider as `recommended` — the client keying for preselect.
        for entry in PROVIDER_REGISTRY {
            let models = curated_models(entry.variant);
            let recommended: Vec<&ModelInfo> = models.iter().filter(|m| m.recommended).collect();
            assert_eq!(
                recommended.len(),
                1,
                "{} must have exactly one recommended model",
                entry.key
            );
            assert_eq!(
                recommended[0].id,
                recommended_model(entry.variant)
                    .unwrap_or_else(|| { panic!("{} has no recommended model", entry.key) })
            );
        }
    }

    #[test]
    fn aliases_do_not_shadow_canonical_keys() {
        // resolve_provider scans entries in registry order and checks each
        // entry's key and aliases before the next entry. An alias on an
        // earlier entry would therefore shadow a later canonical key, so no
        // collision is allowed at all.
        for entry in PROVIDER_REGISTRY {
            for alias in entry.aliases {
                // The alias must not be a canonical key of a different entry.
                let other = PROVIDER_REGISTRY.iter().find(|e| e.key == *alias);
                assert!(
                    other.is_none(),
                    "alias `{}` of `{}` collides with canonical key of `{:?}`",
                    alias,
                    entry.key,
                    other.map(|e| e.variant)
                );
            }
        }
    }

    #[test]
    fn keys_and_aliases_are_unique() {
        let mut seen: Vec<&'static str> = Vec::new();
        for entry in PROVIDER_REGISTRY {
            for name in std::iter::once(&entry.key).chain(entry.aliases.iter()) {
                assert!(
                    !seen.contains(name),
                    "duplicate provider name `{name}` in registry"
                );
                seen.push(name);
            }
        }
    }

    #[test]
    fn registry_keys_match_core_as_str() {
        // Prevent drift: every registry key must equal the corresponding
        // LlmProvider::as_str() value.
        for entry in PROVIDER_REGISTRY {
            assert_eq!(
                entry.key,
                entry.variant.as_str(),
                "registry key `{}` does not match LlmProvider::as_str() `{}` for {:?}",
                entry.key,
                entry.variant.as_str(),
                entry.variant
            );
        }
    }
}
