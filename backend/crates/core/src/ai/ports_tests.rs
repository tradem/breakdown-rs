// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use uuid::Uuid;

use super::{AggregateVersion, AiImportMapping, CURATED_PROVIDERS, DocumentKind, LlmProvider};

// ===========================================================================
// P3.3 — LlmClient-Port-Defaults
// ===========================================================================

// --- LlmProvider::as_str (kills return "" / "xyzzy") ---------------------

#[test]
fn llm_provider_as_str_matches_variant_name() {
    assert_eq!(LlmProvider::OpenAI.as_str(), "openai");
    assert_eq!(LlmProvider::OpenRouter.as_str(), "openrouter");
    assert_eq!(LlmProvider::EURouter.as_str(), "eurouter");
    assert_eq!(LlmProvider::Neuralwatt.as_str(), "neuralwatt");
    assert_eq!(LlmProvider::OpenCodeGo.as_str(), "opencode-go");
    assert_eq!(LlmProvider::OpenCode.as_str(), "opencode");
    assert_eq!(LlmProvider::Ollama.as_str(), "ollama");
}

#[test]
fn llm_provider_as_str_never_empty() {
    for provider in CURATED_PROVIDERS {
        assert!(!provider.as_str().is_empty(), "{provider:?} returns empty");
    }
}

#[test]
fn llm_provider_as_str_never_xyzzy() {
    for provider in CURATED_PROVIDERS {
        assert_ne!(
            provider.as_str(),
            "xyzzy",
            "{provider:?} returns wrong value"
        );
    }
}

// --- LlmProvider::curated_base_url_key (kills return "" / "xyzzy") --------

#[test]
fn llm_provider_curated_base_url_key_matches_as_str() {
    for provider in CURATED_PROVIDERS {
        assert_eq!(
            provider.curated_base_url_key(),
            provider.as_str(),
            "curated_base_url_key should match as_str for {provider:?}"
        );
    }
}

// --- LlmProvider::is_local (kills return false / true) --------------------

#[test]
fn only_ollama_is_local() {
    for provider in CURATED_PROVIDERS {
        let expected = provider == LlmProvider::Ollama;
        assert_eq!(
            provider.is_local(),
            expected,
            "{provider:?}.is_local() should be {expected}"
        );
    }
}

#[test]
fn openai_is_not_local() {
    assert!(!LlmProvider::OpenAI.is_local());
}

#[test]
fn ollama_is_local() {
    assert!(LlmProvider::Ollama.is_local());
}

// --- AiImportMapping::is_reserved (kills == → !=, return false/true) ------

#[test]
fn mapping_is_reserved_when_version_is_zero() {
    let mapping = AiImportMapping {
        preview_id: super::AiImportJobId::new(),
        draft_ref: "scene-1".into(),
        aggregate_kind: "scene".into(),
        aggregate_id: Uuid::now_v7(),
        aggregate_version: AggregateVersion(0),
    };
    assert!(
        mapping.is_reserved(),
        "RESERVED_VERSION (0) should be reserved"
    );
}

#[test]
fn mapping_is_not_reserved_after_confirmation() {
    let mapping = AiImportMapping {
        preview_id: super::AiImportJobId::new(),
        draft_ref: "scene-1".into(),
        aggregate_kind: "scene".into(),
        aggregate_id: Uuid::now_v7(),
        aggregate_version: AggregateVersion::INITIAL,
    };
    assert!(
        !mapping.is_reserved(),
        "non-zero version should not be reserved"
    );
}

#[test]
fn mapping_is_not_reserved_for_high_version() {
    let mapping = AiImportMapping {
        preview_id: super::AiImportJobId::new(),
        draft_ref: "scene-1".into(),
        aggregate_kind: "scene".into(),
        aggregate_id: Uuid::now_v7(),
        aggregate_version: AggregateVersion(999),
    };
    assert!(!mapping.is_reserved());
}

#[test]
fn mapping_reservation_creates_reserved_mapping() {
    let preview_id = super::AiImportJobId::new();
    let aggregate_id = Uuid::now_v7();
    let mapping =
        AiImportMapping::reservation(preview_id, "scene-1".into(), "scene".into(), aggregate_id);
    assert!(mapping.is_reserved());
    assert_eq!(mapping.aggregate_id, aggregate_id);
    assert_eq!(mapping.aggregate_version, AggregateVersion(0));
}

// --- CURATED_PROVIDERS constant -------------------------------------------

#[test]
fn curated_providers_has_seven_entries() {
    assert_eq!(CURATED_PROVIDERS.len(), 7);
}

#[test]
fn curated_providers_contains_all_variants() {
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::OpenAI));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::OpenRouter));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::EURouter));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::Neuralwatt));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::OpenCodeGo));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::OpenCode));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::Ollama));
}

// --- DocumentKind::as_str (kills return "" / "xyzzy") ---------------------

#[test]
fn document_kind_as_str_matches_variant() {
    assert_eq!(DocumentKind::Script.as_str(), "script");
    assert_eq!(DocumentKind::Schedule.as_str(), "schedule");
}

// --- AiImportMapping::RESERVED_VERSION ------------------------------------

#[test]
fn reserved_version_is_zero() {
    assert_eq!(AiImportMapping::RESERVED_VERSION, AggregateVersion(0));
}
