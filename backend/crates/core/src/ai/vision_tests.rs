// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use super::{
    curated_vision_model_ids, has_curated_vision_models, is_curated_vision_model,
    is_vision_model_acceptable,
};
use crate::ai::ports::LlmProvider;

#[test]
fn the_eu_vision_fallbacks_publish_their_verified_models() {
    // ADR-041 D2.1: these are the providers whose catalogue this workspace has
    // verified, and each entry is the evidence the picker relies on.
    assert_eq!(
        curated_vision_model_ids(LlmProvider::Ovhcloud),
        &["qwen3-vl-30b-a3b", "Mistral-Small-3.2-24B-Instruct-2506"]
    );
    assert_eq!(
        curated_vision_model_ids(LlmProvider::Scaleway),
        &["qwen3.5-397b-a17b", "mistral-small-3.2-24b-instruct-2506"]
    );
    assert_eq!(
        curated_vision_model_ids(LlmProvider::Nebius),
        &["Qwen/Qwen3.8-27B", "deepseek-ai/DeepSeek-V4.1-Flash-1017"]
    );
}

#[test]
fn a_non_compliant_provider_publishes_no_vision_catalogue() {
    // Offering a model on a provider the egress gate refuses would be a lie:
    // the slot could be configured but never used.
    for provider in [
        LlmProvider::OpenAI,
        LlmProvider::Gemini,
        LlmProvider::OpenRouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
    ] {
        assert!(
            !has_curated_vision_models(provider),
            "{} must not publish a vision catalogue",
            provider.as_str()
        );
    }
}

#[test]
fn model_ids_are_matched_exactly() {
    // A provider's IDs are case-sensitive: the OVHcloud spelling and the
    // Scaleway spelling are DIFFERENT ids on different providers.
    assert!(is_curated_vision_model(
        LlmProvider::Ovhcloud,
        "Mistral-Small-3.2-24B-Instruct-2506"
    ));
    assert!(!is_curated_vision_model(
        LlmProvider::Ovhcloud,
        "mistral-small-3.2-24b-instruct-2506"
    ));
    assert!(is_curated_vision_model(
        LlmProvider::Scaleway,
        "mistral-small-3.2-24b-instruct-2506"
    ));
}

#[test]
fn an_unverifiable_catalogue_accepts_the_operators_model() {
    // A local `ollama` tag and a reseller upstream cannot be verified from
    // here: the operator's own catalogue is the authority, so save-time
    // validation must not reject a model this module knows nothing about.
    assert!(is_vision_model_acceptable(
        LlmProvider::Ollama,
        "qwen3-vl:8b"
    ));
    assert!(is_vision_model_acceptable(
        LlmProvider::EURouter,
        "some-upstream-vl"
    ));
    // …while a VERIFIED catalogue still refuses an unknown id.
    assert!(!is_vision_model_acceptable(LlmProvider::Ovhcloud, "gpt-4o"));
    assert!(is_vision_model_acceptable(
        LlmProvider::Ovhcloud,
        "qwen3-vl-30b-a3b"
    ));
}
