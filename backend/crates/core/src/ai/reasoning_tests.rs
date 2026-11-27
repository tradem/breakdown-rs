// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Reasoning-effort vocabulary and capability tests.
//!
//! Every assertion here is a fact read from a provider catalogue on 2026-11-20,
//! re-read on **2026-11-26** for issue #1007 (the eurouter rows were re-read on
//! 2026-11-21 for issue #950; see the module docs for the three shapes). The
//! `curated_model_ids` cross-check that catches a *forgotten* model lives in
//! `infra`, where both lists are visible.

use super::{
    ReasoningEffort, ReasoningEffortChoice, supported_reasoning_efforts, supports_reasoning_effort,
};
use crate::ai::ports::LlmProvider;

#[test]
fn wire_values_are_the_provider_spelling() {
    assert_eq!(ReasoningEffort::Minimal.as_str(), "minimal");
    assert_eq!(ReasoningEffort::Low.as_str(), "low");
    assert_eq!(ReasoningEffort::Medium.as_str(), "medium");
    assert_eq!(ReasoningEffort::High.as_str(), "high");
    // `ALL` is the ascending order the API surface and the picker rely on.
    assert_eq!(
        ReasoningEffort::ALL,
        [
            ReasoningEffort::Minimal,
            ReasoningEffort::Low,
            ReasoningEffort::Medium,
            ReasoningEffort::High,
        ]
    );
}

#[test]
fn neuralwatt_offers_all_four_efforts_on_its_curated_models() {
    // `capabilities.reasoning_effort: true` plus `reasoning.accepted_efforts`
    // including `minimal` on every curated Neuralwatt model.
    for model in [
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
    ] {
        assert_eq!(
            supported_reasoning_efforts(LlmProvider::Neuralwatt, model),
            Some(ReasoningEffort::ALL.as_slice()),
            "{model} is curated on Neuralwatt and declares all four efforts"
        );
    }
}

#[test]
fn eurouter_offers_no_minimal_because_its_catalogue_does_not_declare_it() {
    // `supported_parameters` names the parameter but not its domain, so only the
    // values every OpenRouter-shaped provider accepts are offered.
    let efforts = supported_reasoning_efforts(LlmProvider::EURouter, "mistral-small-4")
        .expect("mistral-small-4 lists reasoning_effort");
    assert!(efforts.contains(&ReasoningEffort::Low));
    assert!(efforts.contains(&ReasoningEffort::Medium));
    assert!(efforts.contains(&ReasoningEffort::High));
    assert!(
        !efforts.contains(&ReasoningEffort::Minimal),
        "minimal is not declared by the OpenRouter-shaped catalogues"
    );
}

/// The mistake this module exists to prevent: `mistral-large-3` does **not**
/// advertise `reasoning_effort` (only `mistral-large-4` and `mistral-small-4`
/// do), so offering it would send an undeclared parameter. Issue #950 rotated it
/// out of the curated eurouter set, but persisted `AiConfig` records still
/// reference it — an absent pair must stay absent, never inherit a sibling's
/// values.
#[test]
fn mistral_large_3_offers_nothing() {
    assert_eq!(
        supported_reasoning_efforts(LlmProvider::EURouter, "mistral-large-3"),
        None
    );
    assert!(!supports_reasoning_effort(
        LlmProvider::EURouter,
        "mistral-large-3",
        ReasoningEffort::Low
    ));
}

/// The #950 successor: the curated eurouter recommendation declares the
/// parameter, so the picker of the DEFAULT configuration is not empty.
#[test]
fn mistral_large_4_offers_low_medium_high() {
    assert_eq!(
        supported_reasoning_efforts(LlmProvider::EURouter, "mistral-large-4"),
        Some(
            &[
                ReasoningEffort::Low,
                ReasoningEffort::Medium,
                ReasoningEffort::High
            ][..]
        )
    );
    assert!(supports_reasoning_effort(
        LlmProvider::EURouter,
        "mistral-large-4",
        ReasoningEffort::Low
    ));
    // `minimal` is OpenAI-specific and not declared by the eurouter catalogue.
    assert!(!supports_reasoning_effort(
        LlmProvider::EURouter,
        "mistral-large-4",
        ReasoningEffort::Minimal
    ));
}

#[test]
fn opencode_glm_does_not_offer_medium() {
    // `capabilities.reasoning.effort: ["low", "high", "max"]`.
    let efforts = supported_reasoning_efforts(LlmProvider::OpenCode, "glm-5.3")
        .expect("opencode glm-5.3 declares an effort list");
    assert_eq!(efforts, &[ReasoningEffort::Low, ReasoningEffort::High]);
    assert!(supports_reasoning_effort(
        LlmProvider::OpenCode,
        "glm-5.3",
        ReasoningEffort::Low
    ));
    assert!(
        !supports_reasoning_effort(LlmProvider::OpenCode, "glm-5.3", ReasoningEffort::Medium),
        "medium would be a 400 on this endpoint"
    );
    // The Go gateway publishes the same list.
    assert_eq!(
        supported_reasoning_efforts(LlmProvider::OpenCodeGo, "glm-5.3"),
        Some(efforts)
    );
}

#[test]
fn opencode_grok_offers_medium() {
    // `capabilities.reasoning.effort: ["low", "medium", "high", "xhigh"]`.
    assert!(supports_reasoning_effort(
        LlmProvider::OpenCode,
        "grok-4.7",
        ReasoningEffort::Medium
    ));
    assert!(supports_reasoning_effort(
        LlmProvider::OpenCodeGo,
        "grok-4.7",
        ReasoningEffort::Medium
    ));
}

/// `deepseek-v4-pro` advertises `high` (plus the unmodelled `max`) and nothing
/// else. Offering `low`/`medium` would be a `400` on every call — the exact
/// failure mode the closed enum exists to prevent.
#[test]
fn both_opencode_endpoints_offer_only_high_for_deepseek_v4_pro() {
    for provider in [LlmProvider::OpenCodeGo, LlmProvider::OpenCode] {
        let efforts = supported_reasoning_efforts(provider, "deepseek-v4-pro")
            .expect("deepseek-v4-pro declares an effort list");
        assert_eq!(efforts, &[ReasoningEffort::High]);
        assert!(supports_reasoning_effort(
            provider,
            "deepseek-v4-pro",
            ReasoningEffort::High
        ));
        assert!(!supports_reasoning_effort(
            provider,
            "deepseek-v4-pro",
            ReasoningEffort::Low
        ));
        assert!(!supports_reasoning_effort(
            provider,
            "deepseek-v4-pro",
            ReasoningEffort::Medium
        ));
    }
}

/// The provider-specific difference issue #1007 exists for: the Go gateway
/// advertises only the provider-only `max` for `kimi-k3`, while the OpenCode
/// endpoint advertises `low|high|max` for the SAME model id. Neither may
/// inherit the other's set.
#[test]
fn opencode_go_and_opencode_disagree_about_kimi_k3() {
    assert_eq!(
        supported_reasoning_efforts(LlmProvider::OpenCodeGo, "kimi-k3"),
        None,
        "the Go gateway exposes no representable effort for kimi-k3"
    );
    assert_eq!(
        supported_reasoning_efforts(LlmProvider::OpenCode, "kimi-k3"),
        Some(&[ReasoningEffort::Low, ReasoningEffort::High][..])
    );
}

/// Curated models whose live metadata declares no representable effort (a
/// provider-only `max`, an empty list, or no parameter at all). Never an empty
/// `Some(&[])`, never a borrowed sibling set.
#[test]
fn curated_pairs_without_a_representable_effort_stay_unresolved() {
    for (provider, model) in [
        // Go: only the provider-only `max`.
        (LlmProvider::OpenCodeGo, "kimi-k3"),
        (LlmProvider::OpenCodeGo, "kimi-k2.7-code"),
        (LlmProvider::OpenCodeGo, "minimax-m3"),
        (LlmProvider::OpenCodeGo, "mimo-v2.6-pro"),
        // OpenCode: no `mimo-v2.6-pro` arm here, `kimi-k3` IS offered above.
        (LlmProvider::OpenCode, "kimi-k2.7-code"),
        (LlmProvider::OpenCode, "minimax-m3"),
        (LlmProvider::OpenCode, "minimax-m2.7"),
    ] {
        assert_eq!(
            supported_reasoning_efforts(provider, model),
            None,
            "{provider:?}/{model} must expose no representable effort"
        );
    }
}

/// Issue #1007 rotated these out of curation; their mappings went with them so
/// a stale id cannot silently keep an effort set nobody verified any more.
#[test]
fn rotated_out_neuralwatt_ids_are_no_longer_mapped() {
    for model in [
        "deepseek-v4-flash",
        "glm-5.3-fast",
        "glm-5.3-short",
        "kimi-k3",
        "kimi-k3-fast",
        "kimi-k3-flex",
    ] {
        assert_eq!(
            supported_reasoning_efforts(LlmProvider::Neuralwatt, model),
            None,
            "{model} left the Neuralwatt catalogue on 2026-11-26"
        );
    }
}

/// `openai/gpt-6-luna` joined OpenRouter's curated set with the same
/// `supported_parameters` shape as its siblings.
#[test]
fn openrouter_gpt_6_luna_offers_low_medium_high() {
    assert_eq!(
        supported_reasoning_efforts(LlmProvider::OpenRouter, "openai/gpt-6-luna"),
        Some(
            &[
                ReasoningEffort::Low,
                ReasoningEffort::Medium,
                ReasoningEffort::High
            ][..]
        )
    );
}

/// Eurouter's structured-output successor of the rotated-out
/// `deepseek-v4-flash`.
#[test]
fn eurouter_deepseek_v4_1_flash_1017_offers_low_medium_high() {
    assert_eq!(
        supported_reasoning_efforts(LlmProvider::EURouter, "deepseek-v4.1-flash-1017"),
        Some(
            &[
                ReasoningEffort::Low,
                ReasoningEffort::Medium,
                ReasoningEffort::High
            ][..]
        )
    );
    // The rotated-out id it replaced stays unresolved rather than borrowing it.
    assert_eq!(
        supported_reasoning_efforts(LlmProvider::EURouter, "deepseek-v4-flash"),
        None
    );
}

#[test]
fn unverified_providers_offer_nothing() {
    // OpenAI and Gemini publish no per-model parameter metadata; Ollama speaks a
    // different API. An unverified pair must never be offered — a `400` on every
    // call of that configuration is the failure mode this avoids.
    for (provider, model) in [
        (LlmProvider::OpenAI, "gpt-5.6-luna"),
        (LlmProvider::Gemini, "gemini-3.6-flash"),
        (LlmProvider::Ollama, "qwen3:8b"),
        (
            LlmProvider::OpenRouter,
            "nvidia/nemotron-3.5-lightning:free",
        ),
    ] {
        assert_eq!(
            supported_reasoning_efforts(provider, model),
            None,
            "{provider:?}/{model} must not be offered"
        );
    }
}

#[test]
fn a_supported_pair_never_yields_an_empty_set() {
    // `Some(&[])` would be an unreadable state for the picker ("supported, but
    // nothing to choose") — see the function docs.
    for provider in [
        LlmProvider::OpenAI,
        LlmProvider::Gemini,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
        LlmProvider::Ollama,
    ] {
        for model in [
            "gpt-5.6-luna",
            "gemini-3.6-flash",
            "openai/gpt-5-mini",
            "mistral-large-4",
            "mistral-large-3",
            "mistral-small-4",
            "glm-5.3-flash",
            "glm-5.3",
            "nw-flash",
        ] {
            if let Some(efforts) = supported_reasoning_efforts(provider, model) {
                assert!(
                    !efforts.is_empty(),
                    "{provider:?}/{model} advertises an empty effort set"
                );
            }
        }
    }
}

/// `Auto` is a value on the wire, never a `null`: the generated Dart client omits
/// null fields, so a nullable setting could be set but never cleared.
#[test]
fn auto_is_a_wire_value_and_resolves_to_no_explicit_level() {
    assert_eq!(
        ReasoningEffortChoice::default(),
        ReasoningEffortChoice::Auto
    );
    assert_eq!(ReasoningEffortChoice::Auto.effort(), None);
    assert_eq!(
        ReasoningEffortChoice::Low.effort(),
        Some(ReasoningEffort::Low)
    );
    assert_eq!(
        serde_json::to_string(&ReasoningEffortChoice::Auto).expect("serialize"),
        "\"auto\""
    );
    assert_eq!(
        serde_json::from_str::<ReasoningEffortChoice>("\"low\"").expect("deserialize"),
        ReasoningEffortChoice::Low
    );
    // Every real level round-trips through its effort and back.
    for choice in ReasoningEffortChoice::ALL {
        if let Some(effort) = choice.effort() {
            assert_eq!(ReasoningEffortChoice::from(effort), choice);
        }
    }
}
