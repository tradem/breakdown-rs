// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Centralized curated `LlmProvider` metadata.
//!
//! A single metadata source prevents provider-list and provider-parser drift
//! when a provider is added or changed. Both the API provider listing and the
//! provider-key parsing resolve from this registry.

use breakdown_core::ai::{LlmProvider, ModelInfo};

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

/// Curated model IDs per provider. Single source for the models endpoint;
/// a new `LlmProvider` variant must be added here and to the exhaustive
/// `as_str` match in core.
pub fn curated_model_ids(provider: LlmProvider) -> &'static [&'static str] {
    match provider {
        LlmProvider::OpenAI => &["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"],
        LlmProvider::OpenRouter => &[
            "openai/gpt-4o-mini",
            "openai/gpt-4o",
            "meta-llama/llama-3.1-8b-instruct:free",
        ],
        LlmProvider::EURouter => &["mistral-large-3", "mistral-small-3.1", "deepseek-v4-flash"],
        LlmProvider::Neuralwatt => &[
            "deepseek-v4-flash",
            "glm-5.2",
            "glm-5.2-fast",
            "kimi-k2.7-code",
            "kimi-k3",
            "qwen3.6-35b",
        ],
        LlmProvider::OpenCodeGo | LlmProvider::OpenCode => &[
            "deepseek-v4-pro",
            "deepseek-v4-flash",
            "glm-5.2",
            "glm-5.1",
            "kimi-k3",
            "kimi-k2.7-code",
            "kimi-k2.6",
            "minimax-m3",
            "minimax-m2.7",
            "mimo-v2.5",
            "grok-4.5",
        ],
        LlmProvider::Ollama => &["llama3.1:8b", "qwen2.5:7b"],
        // LlmProvider is #[non_exhaustive]; future variants get an empty
        // list so the registry stays backward-compatible without a catch-all.
        _ => &[],
    }
}

/// Build `ModelInfo` list for a provider from the curated model IDs.
pub fn curated_models(provider: LlmProvider) -> Vec<ModelInfo> {
    curated_model_ids(provider)
        .iter()
        .map(|id| ModelInfo {
            id: (*id).to_owned(),
            display_name: None,
            provider,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn aliases_do_not_shadow_canonical_keys() {
        // If an alias collides with a canonical key of another provider, the
        // canonical key wins (checked first in resolve_provider).
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
}
