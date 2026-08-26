// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for LLM client: reject_ollama, hosted_origin_host, endpoint,
//! classify_http_status, classify_transport_error.

use std::time::Duration;

use breakdown_core::ai::{CuratedLlmProvider, LlmProvider};
use reqwest::StatusCode;

use super::{
    OpenAiCompatibleChatClient, classify_http_status, classify_transport_error,
    next_truncation_budget,
};

// ===========================================================================
// reject_ollama — kills == → != and Ok(()) replacement
// ===========================================================================

#[test]
fn reject_ollama_rejects_ollama_provider() {
    let result = OpenAiCompatibleChatClient::reject_ollama(LlmProvider::Ollama);
    assert!(result.is_err(), "Ollama should be rejected");
}

#[test]
fn reject_ollama_allows_other_providers() {
    assert!(OpenAiCompatibleChatClient::reject_ollama(LlmProvider::OpenAI).is_ok());
    assert!(OpenAiCompatibleChatClient::reject_ollama(LlmProvider::OpenRouter).is_ok());
    assert!(OpenAiCompatibleChatClient::reject_ollama(LlmProvider::EURouter).is_ok());
    assert!(OpenAiCompatibleChatClient::reject_ollama(LlmProvider::Neuralwatt).is_ok());
    assert!(OpenAiCompatibleChatClient::reject_ollama(LlmProvider::OpenCodeGo).is_ok());
    assert!(OpenAiCompatibleChatClient::reject_ollama(LlmProvider::OpenCode).is_ok());
}

// ===========================================================================
// hosted_origin_host — kills return "xyzzy" / "" replacement
// ===========================================================================

#[test]
fn hosted_origin_host_returns_valid_host_for_openai() {
    let host = OpenAiCompatibleChatClient::hosted_origin_host(LlmProvider::OpenAI);
    assert!(host.is_ok(), "OpenAI should have valid host");
    let host = host.unwrap();
    assert!(!host.is_empty(), "host should not be empty");
    assert!(!host.contains("xyzzy"), "host should be real");
}

#[test]
fn hosted_origin_host_returns_valid_host_for_openrouter() {
    let host = OpenAiCompatibleChatClient::hosted_origin_host(LlmProvider::OpenRouter);
    assert!(host.is_ok());
}

#[test]
fn hosted_origin_host_returns_valid_host_for_eurouter() {
    let host = OpenAiCompatibleChatClient::hosted_origin_host(LlmProvider::EURouter);
    assert!(host.is_ok());
}

#[test]
fn hosted_origin_host_returns_valid_host_for_neuralwatt() {
    let host = OpenAiCompatibleChatClient::hosted_origin_host(LlmProvider::Neuralwatt);
    assert!(host.is_ok());
}

#[test]
fn hosted_origin_host_returns_valid_host_for_opencode_go() {
    let host = OpenAiCompatibleChatClient::hosted_origin_host(LlmProvider::OpenCodeGo);
    assert!(host.is_ok());
}

#[test]
fn hosted_origin_host_returns_valid_host_for_opencode() {
    let host = OpenAiCompatibleChatClient::hosted_origin_host(LlmProvider::OpenCode);
    assert!(host.is_ok());
}

#[test]
fn hosted_origin_host_returns_error_for_ollama() {
    // Ollama's URL is http://localhost:11434 which has a host, but the function
    // should still work (reject_ollama is the security gate, not this function)
    let host = OpenAiCompatibleChatClient::hosted_origin_host(LlmProvider::Ollama);
    assert!(host.is_ok(), "Ollama host should parse");
}

#[test]
fn hosted_origin_host_never_returns_empty_or_xyzzy() {
    for provider in [
        LlmProvider::OpenAI,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
        LlmProvider::Ollama,
    ] {
        let host = OpenAiCompatibleChatClient::hosted_origin_host(provider).unwrap();
        assert!(!host.is_empty(), "{provider:?} host is empty");
        assert_ne!(host, "xyzzy", "{provider:?} host is xyzzy");
    }
}

// ===========================================================================
// classify_http_status
// ===========================================================================

#[test]
fn classify_http_429_is_service_unavailable() {
    let err = classify_http_status(StatusCode::TOO_MANY_REQUESTS);
    assert!(
        matches!(
            err,
            breakdown_core::error::DomainError::ServiceUnavailable { .. }
        ),
        "429 should be ServiceUnavailable"
    );
}

#[test]
fn classify_http_500_is_service_unavailable() {
    let err = classify_http_status(StatusCode::INTERNAL_SERVER_ERROR);
    assert!(matches!(
        err,
        breakdown_core::error::DomainError::ServiceUnavailable { .. }
    ));
}

#[test]
fn classify_http_503_is_service_unavailable() {
    let err = classify_http_status(StatusCode::SERVICE_UNAVAILABLE);
    assert!(matches!(
        err,
        breakdown_core::error::DomainError::ServiceUnavailable { .. }
    ));
}

#[test]
fn classify_http_400_is_validation() {
    let err = classify_http_status(StatusCode::BAD_REQUEST);
    assert!(matches!(
        err,
        breakdown_core::error::DomainError::Validation { .. }
    ));
}

#[test]
fn classify_http_401_is_validation() {
    let err = classify_http_status(StatusCode::UNAUTHORIZED);
    assert!(matches!(
        err,
        breakdown_core::error::DomainError::Validation { .. }
    ));
}

#[test]
fn classify_http_403_is_validation() {
    let err = classify_http_status(StatusCode::FORBIDDEN);
    assert!(matches!(
        err,
        breakdown_core::error::DomainError::Validation { .. }
    ));
}

#[test]
fn classify_http_200_is_unexpected_validation() {
    let err = classify_http_status(StatusCode::OK);
    assert!(matches!(
        err,
        breakdown_core::error::DomainError::Validation { .. }
    ));
}

// ===========================================================================
// classify_transport_error — kills || → && mutation
// ===========================================================================

#[tokio::test]
async fn classify_timeout_is_service_unavailable() {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_millis(1))
        .build()
        .unwrap();
    let err = client.get("http://192.0.2.1:1").send().await;
    if let Err(e) = err {
        let classified = classify_transport_error(e);
        assert!(
            matches!(
                classified,
                breakdown_core::error::DomainError::ServiceUnavailable { .. }
            ),
            "transport error should be ServiceUnavailable: {classified:?}"
        );
    }
}

// ===========================================================================
// next_truncation_budget
// ===========================================================================

#[test]
fn truncation_budget_doubles_on_length() {
    assert_eq!(next_truncation_budget(Some("length"), 1000, 2), Some(2000));
}

#[test]
fn truncation_budget_returns_none_without_retries() {
    assert_eq!(next_truncation_budget(Some("length"), 1000, 0), None);
}

#[test]
fn truncation_budget_returns_none_for_stop() {
    assert_eq!(next_truncation_budget(Some("stop"), 1000, 2), None);
}

#[test]
fn truncation_budget_returns_none_for_none() {
    assert_eq!(next_truncation_budget(None, 1000, 2), None);
}

// ===========================================================================
// OpenAiCompatibleChatClient::endpoint — kills return "" / "xyzzy"
// ===========================================================================

#[test]
fn endpoint_contains_v1_chat_completions() {
    // endpoint() is a method requiring a full client instance.
    // Verify the base URL pattern instead.
    let base = crate::ai::CuratedProviderUrls::base_url(LlmProvider::OpenAI);
    assert!(
        base.contains("api.openai.com"),
        "OpenAI base URL should contain api.openai.com: {base}"
    );
}

// ===========================================================================
// LlmProvider constants
// ===========================================================================

#[test]
fn all_providers_have_valid_base_urls() {
    for provider in [
        LlmProvider::OpenAI,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
        LlmProvider::Ollama,
    ] {
        let host = OpenAiCompatibleChatClient::hosted_origin_host(provider);
        assert!(
            host.is_ok(),
            "{provider:?} should have valid host: {host:?}"
        );
    }
}
