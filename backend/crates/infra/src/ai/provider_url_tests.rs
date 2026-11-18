// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for CuratedProviderUrls::base_url — kills deletion of match arms
//! and replacement with "" or "xyzzy".

use breakdown_core::ai::{CuratedLlmProvider, LlmProvider};

use super::CuratedProviderUrls;

// ===========================================================================
// CuratedProviderUrls::base_url — kills return "" / "xyzzy" and arm deletion
// ===========================================================================

#[test]
fn openai_base_url_is_https() {
    let url = CuratedProviderUrls::base_url(LlmProvider::OpenAI);
    assert!(
        url.starts_with("https://"),
        "OpenAI URL should be HTTPS: {url}"
    );
    assert!(
        url.contains("openai"),
        "OpenAI URL should contain 'openai': {url}"
    );
    assert!(!url.is_empty(), "URL should not be empty");
    assert_ne!(url, "xyzzy", "URL should not be xyzzy");
}

#[test]
fn openrouter_base_url_is_https() {
    let url = CuratedProviderUrls::base_url(LlmProvider::OpenRouter);
    assert!(
        url.starts_with("https://"),
        "OpenRouter URL should be HTTPS: {url}"
    );
    assert!(
        url.contains("openrouter"),
        "OpenRouter URL should contain 'openrouter': {url}"
    );
}

#[test]
fn eurouter_base_url_is_https() {
    let url = CuratedProviderUrls::base_url(LlmProvider::EURouter);
    assert!(
        url.starts_with("https://"),
        "EURouter URL should be HTTPS: {url}"
    );
}

#[test]
fn neuralwatt_base_url_is_https() {
    let url = CuratedProviderUrls::base_url(LlmProvider::Neuralwatt);
    assert!(
        url.starts_with("https://"),
        "Neuralwatt URL should be HTTPS: {url}"
    );
    assert!(
        url.contains("neuralwatt"),
        "Neuralwatt URL should contain 'neuralwatt': {url}"
    );
}

#[test]
fn opencode_go_base_url_is_https() {
    let url = CuratedProviderUrls::base_url(LlmProvider::OpenCodeGo);
    assert!(
        url.starts_with("https://"),
        "OpenCodeGo URL should be HTTPS: {url}"
    );
}

#[test]
fn opencode_base_url_is_https() {
    let url = CuratedProviderUrls::base_url(LlmProvider::OpenCode);
    assert!(
        url.starts_with("https://"),
        "OpenCode URL should be HTTPS: {url}"
    );
}

#[test]
fn ollama_base_url_is_http() {
    let url = CuratedProviderUrls::base_url(LlmProvider::Ollama);
    assert!(
        url.starts_with("http://"),
        "Ollama URL should be HTTP (local): {url}"
    );
}

// ===========================================================================
// All providers have non-empty, unique URLs
// ===========================================================================

#[test]
fn all_providers_have_non_empty_urls() {
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
        let url = CuratedProviderUrls::base_url(provider);
        assert!(!url.is_empty(), "{provider:?} has empty URL");
        assert_ne!(url, "xyzzy", "{provider:?} has placeholder URL");
    }
}

#[test]
fn all_hosted_providers_are_https() {
    let hosted = [
        LlmProvider::OpenAI,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
    ];

    for provider in hosted {
        let url = CuratedProviderUrls::base_url(provider);
        assert!(
            url.starts_with("https://"),
            "{provider:?} should be HTTPS but got: {url}"
        );
    }
}

#[test]
fn ollama_is_only_http_provider() {
    let url = CuratedProviderUrls::base_url(LlmProvider::Ollama);
    assert!(
        url.starts_with("http://"),
        "Ollama should be HTTP for local dev"
    );
}

// ===========================================================================
// URLs are valid (parseable)
// ===========================================================================

#[test]
fn all_urls_are_valid() {
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
        let url = CuratedProviderUrls::base_url(provider);
        let parsed = reqwest::Url::parse(url);
        assert!(
            parsed.is_ok(),
            "{provider:?} URL failed to parse: {url} — {parsed:?}"
        );
    }
}
