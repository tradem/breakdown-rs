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
/// Single source for the models endpoint; a new `LlmProvider` variant must
/// be added here and to the exhaustive `as_str` match in core.
pub fn curated_model_ids(provider: LlmProvider) -> &'static [&'static str] {
    match provider {
        LlmProvider::OpenAI => &["gpt-5.6-luna", "gpt-5.6-terra", "gpt-4.1-mini"],
        LlmProvider::Gemini => &[
            "gemini-3.6-flash",
            "gemini-3.5-flash-lite",
            "gemini-3.1-pro-preview",
            "gemini-2.5-flash",
            "gemini-2.5-pro",
        ],
        LlmProvider::OpenRouter => &[
            "openai/gpt-5-mini",
            "deepseek/deepseek-v4-flash",
            "deepseek/deepseek-v4.1-flash",
            "nvidia/nemotron-3.5-lightning:free",
        ],
        LlmProvider::EURouter => &[
            "mistral-large-3",
            "mistral-small-4",
            "deepseek-v4-flash",
            "deepseek-v4-pro",
            "mistral-medium-3.5",
        ],
        LlmProvider::Neuralwatt => &[
            "deepseek-v4.1-flash",
            "deepseek-v4-flash",
            "glm-5.3",
            "glm-5.3-fast",
            "glm-5.3-flex",
            "glm-5.3-flash",
            "glm-5.3-short",
            "kimi-k3",
            "kimi-k3-fast",
            "kimi-k3-flex",
            "qwen3.6-35b",
            "qwen3.6-35b-fast",
            "qwen-3.8-27b",
        ],
        LlmProvider::OpenCodeGo | LlmProvider::OpenCode => &[
            "deepseek-v4-pro",
            "deepseek-v4-flash",
            "glm-5.2",
            "glm-5.3",
            "kimi-k3",
            "kimi-k2.7-code",
            "minimax-m3",
            "minimax-m2.7",
            "mimo-v2.6-pro",
            "grok-4.5",
            "grok-4.6",
        ],
        LlmProvider::Ollama => &["qwen3:8b", "llama3.2", "qwen2.5-coder:7b"],
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
        LlmProvider::EURouter => Some("mistral-large-3"),
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

        // `mistral-large-3` declares no effort → the picker offers nothing, and
        // the user cannot configure a value the provider would reject.
        let large3 = curated_models(LlmProvider::EURouter)
            .into_iter()
            .find(|model| model.id == "mistral-large-3")
            .expect("mistral-large-3 is still curated");
        assert!(
            large3.supported_reasoning_efforts.is_empty(),
            "mistral-large-3 must offer no effort: {:?}",
            large3.supported_reasoning_efforts
        );

        // A provider whose catalogue publishes nothing offers nothing at all.
        assert!(
            curated_models(LlmProvider::OpenAI)
                .iter()
                .all(|model| model.supported_reasoning_efforts.is_empty())
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
        // send a parameter the model does not declare.
        assert_eq!(
            default_reasoning_effort(LlmProvider::EURouter, "mistral-large-3"),
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
            vec!["clef-flash", "metis"]
        );
        assert!(!curated_decision_models(LlmProvider::OpenRouter).is_empty());
        // Non-decision providers expose no decision models at all.
        assert!(curated_decision_models(LlmProvider::OpenAI).is_empty());
        assert!(curated_decision_models(LlmProvider::Ollama).is_empty());
        // Never recommended — the slot is optional.
        for model in curated_decision_models(LlmProvider::OpenRouter) {
            assert!(!model.recommended);
        }
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
