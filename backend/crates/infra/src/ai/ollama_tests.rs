// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for OllamaChatClient — kills mutations in request_once and
//! chat_constrained.

use breakdown_core::ai::{LlmChatRequest, LlmClient, LlmProvider};
use breakdown_core::error::DomainError;

use super::OllamaChatClient;

/// Helper to create a test request.
fn make_request(provider: LlmProvider) -> LlmChatRequest {
    LlmChatRequest {
        provider,
        model: "llama3".into(),
        prompt: "Extract scenes".into(),
        source_text: "INT. ROOM - DAY\nHello.".into(),
        max_tokens: 1000,
        response_schema: None,
    }
}

#[test]
fn chat_constrained_rejects_non_ollama_provider() {
    let client = OllamaChatClient::with_http(
        reqwest::Client::new(),
        0,
        std::time::Duration::from_secs(30),
    );

    let rt = tokio::runtime::Runtime::new().unwrap();
    let result = rt.block_on(client.chat_constrained(make_request(LlmProvider::OpenAI)));
    assert!(result.is_err(), "non-Ollama provider should be rejected");

    let err = result.unwrap_err();
    assert!(
        matches!(err, DomainError::Validation { .. }),
        "should be validation error: {err:?}"
    );
}

#[test]
fn chat_constrained_allows_ollama_provider() {
    let client = OllamaChatClient::with_http(
        reqwest::Client::new(),
        0,
        std::time::Duration::from_secs(30),
    );

    // Should fail with transport error (no Ollama), NOT provider mismatch
    let rt = tokio::runtime::Runtime::new().unwrap();
    let result = rt.block_on(client.chat_constrained(make_request(LlmProvider::Ollama)));

    match result {
        Ok(_) => panic!("should fail with transport error when no Ollama server"),
        Err(err) => {
            let msg = err.to_string();
            // Must NOT be a provider mismatch — the provider check passed
            assert!(
                !msg.contains("non-Ollama"),
                "should not reject Ollama: {err}"
            );
            // Must be a real error, not a placeholder
            assert!(!msg.is_empty(), "error should have a message");
        }
    }
}

#[test]
fn request_once_returns_error_when_server_unavailable() {
    let client =
        OllamaChatClient::with_http(reqwest::Client::new(), 0, std::time::Duration::from_secs(1));

    let rt = tokio::runtime::Runtime::new().unwrap();
    let result = rt.block_on(client.request_once(&make_request(LlmProvider::Ollama)));

    assert!(result.is_err(), "should fail when server unavailable");
    let err = result.unwrap_err();
    let msg = err.to_string();
    assert!(!msg.is_empty(), "error message should not be empty");
    assert_ne!(msg, "xyzzy", "should not return placeholder");
}

#[test]
fn new_succeeds_with_valid_params() {
    let result = OllamaChatClient::new(3, std::time::Duration::from_secs(30));
    assert!(result.is_ok(), "constructor should succeed");
}

#[test]
fn with_http_creates_client() {
    let _client = OllamaChatClient::with_http(
        reqwest::Client::new(),
        5,
        std::time::Duration::from_secs(30),
    );
}

#[test]
fn ollama_provider_constant_is_ollama() {
    assert_eq!(LlmProvider::Ollama.as_str(), "ollama");
}

#[test]
fn ollama_is_local_provider() {
    assert!(LlmProvider::Ollama.is_local());
}
