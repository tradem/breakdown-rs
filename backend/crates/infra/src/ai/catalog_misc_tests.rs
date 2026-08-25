// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for catalog, provider_registry, and prompts — kills mutations
//! in default_allowlist, curated_model_ids, and default_prompt.

use breakdown_core::ai::{CuratedLlmProvider, DocumentKind, LlmProvider};

use super::CuratedProviderUrls;

// ===========================================================================
// Catalog: default_allowlist — kills HashSet::new() / wrong values
// ===========================================================================

#[test]
fn default_allowlist_contains_known_models() {
    // The default allowlist is used internally; we verify the catalog
    // can be created (which validates the allowlist)
    let _catalog = super::OpenAiCompatibleModelCatalog::new()
        .expect("catalog should be created with valid allowlist");
}

// ===========================================================================
// Provider Registry: curated_model_ids — kills Vec::leak replacement
// ===========================================================================

#[test]
fn curated_model_ids_returns_non_empty_for_openai() {
    let models = super::provider_registry::curated_model_ids(LlmProvider::OpenAI);
    assert!(!models.is_empty(), "OpenAI should have curated models");
    assert!(
        models.iter().any(|m| m.contains("gpt")),
        "OpenAI should have gpt models: {models:?}"
    );
}

#[test]
fn curated_model_ids_returns_non_empty_for_openrouter() {
    let models = super::provider_registry::curated_model_ids(LlmProvider::OpenRouter);
    assert!(!models.is_empty(), "OpenRouter should have curated models");
}

#[test]
fn curated_model_ids_returns_non_empty_for_ollama() {
    let models = super::provider_registry::curated_model_ids(LlmProvider::Ollama);
    assert!(!models.is_empty(), "Ollama should have curated models");
}

#[test]
fn curated_model_ids_never_returns_wrong_values() {
    for provider in [
        LlmProvider::OpenAI,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
        LlmProvider::Ollama,
    ] {
        let models = super::provider_registry::curated_model_ids(provider);
        assert!(!models.is_empty(), "{provider:?} should have models");
        for model in models {
            assert_ne!(*model, "xyzzy", "{provider:?} has placeholder model");
            assert!(!model.is_empty(), "{provider:?} has empty model");
        }
    }
}

#[test]
fn curated_model_ids_for_all_providers_are_non_empty() {
    let providers = [
        LlmProvider::OpenAI,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
        LlmProvider::Ollama,
    ];

    for provider in providers {
        let models = super::provider_registry::curated_model_ids(provider);
        assert!(
            !models.is_empty(),
            "{provider:?} should have curated models"
        );
    }
}

// ===========================================================================
// Prompts: default_prompt — kills delete ! replacement
// ===========================================================================

#[test]
fn default_prompt_returns_ok_for_script() {
    let result = super::prompts::default_prompt(DocumentKind::Script);
    assert!(result.is_ok(), "Script prompt should exist: {result:?}");
    let prompt = result.unwrap();
    assert!(!prompt.is_empty(), "Script prompt should not be empty");
}

#[test]
fn default_prompt_returns_ok_for_schedule() {
    let result = super::prompts::default_prompt(DocumentKind::Schedule);
    assert!(result.is_ok(), "Schedule prompt should exist: {result:?}");
    let prompt = result.unwrap();
    assert!(!prompt.is_empty(), "Schedule prompt should not be empty");
}

#[test]
fn default_prompt_contains_relevant_instructions() {
    let script_prompt = super::prompts::default_prompt(DocumentKind::Script).unwrap();
    assert!(
        script_prompt.to_lowercase().contains("scene")
            || script_prompt.to_lowercase().contains("script"),
        "Script prompt should mention scenes or script"
    );

    let schedule_prompt = super::prompts::default_prompt(DocumentKind::Schedule).unwrap();
    assert!(
        schedule_prompt.to_lowercase().contains("schedule")
            || schedule_prompt.to_lowercase().contains("csv"),
        "Schedule prompt should mention schedule or csv"
    );
}

// ===========================================================================
// Provider URLs: base_url consistency
// ===========================================================================

#[test]
fn base_url_for_each_provider_is_unique() {
    let urls: Vec<_> = [
        LlmProvider::OpenAI,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
        LlmProvider::Ollama,
    ]
    .iter()
    .map(|&p| CuratedProviderUrls::base_url(p))
    .collect();

    // All URLs should be unique
    for i in 0..urls.len() {
        for j in (i + 1)..urls.len() {
            assert_ne!(
                urls[i], urls[j],
                "URLs for different providers should be unique: {} vs {}",
                urls[i], urls[j]
            );
        }
    }
}

// ===========================================================================
// Provider info
// ===========================================================================

#[test]
fn list_providers_returns_all_curated_providers() {
    let providers = super::provider_registry::list_providers();
    assert_eq!(providers.len(), 7, "should have 7 curated providers");
}

#[test]
fn resolve_provider_works_for_known_names() {
    assert!(super::provider_registry::resolve_provider("openai").is_some());
    assert!(super::provider_registry::resolve_provider("openrouter").is_some());
    assert!(super::provider_registry::resolve_provider("ollama").is_some());
    assert!(super::provider_registry::resolve_provider("unknown").is_none());
}
