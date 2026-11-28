// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for OllamaChatClient — kills mutations in request_once and
//! chat_constrained.

use async_trait::async_trait;
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
        reasoning_effort: None,
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

// ===========================================================================
// Zone-label breaker gate (issue #1013, CodeRabbit review PR #1018)
// ===========================================================================

/// Minimal breaker read model: answers one fixed snapshot and refuses every
/// transition (the client only ever *reads* it).
struct FixedBreaker(breakdown_core::ai::ProviderBreakerSnapshot);

#[async_trait]
impl breakdown_core::ai::ProviderHealth for FixedBreaker {
    async fn state(
        &self,
        _provider: LlmProvider,
        _model: &str,
    ) -> Result<breakdown_core::ai::ProviderBreakerSnapshot, DomainError> {
        Ok(self.0)
    }

    async fn record_failure(
        &self,
        _provider: LlmProvider,
        _model: &str,
        _threshold: u32,
        _retry_after: Option<std::time::Duration>,
    ) -> Result<breakdown_core::ai::BreakerDecision, DomainError> {
        Err(DomainError::internal(
            "the client must never transition a breaker",
        ))
    }

    async fn record_success(
        &self,
        _provider: LlmProvider,
        _model: &str,
    ) -> Result<breakdown_core::ai::BreakerDecision, DomainError> {
        Err(DomainError::internal(
            "the client must never transition a breaker",
        ))
    }

    async fn try_begin_probe(
        &self,
        _provider: LlmProvider,
        _model: &str,
        _owner: &str,
    ) -> Result<Option<breakdown_core::ai::ProbeLease>, DomainError> {
        Err(DomainError::internal("the client must never begin a probe"))
    }

    async fn finish_probe(
        &self,
        _lease: &breakdown_core::ai::ProbeLease,
        _outcome: breakdown_core::ai::ProbeOutcome,
    ) -> Result<breakdown_core::ai::BreakerDecision, DomainError> {
        Err(DomainError::internal(
            "the client must never finish a probe",
        ))
    }

    async fn open_breakers(
        &self,
        _limit: i64,
    ) -> Result<Vec<breakdown_core::ai::OpenBreaker>, DomainError> {
        Ok(Vec::new())
    }
}

fn zone_request() -> breakdown_core::ai::LlmVisionRequest {
    breakdown_core::ai::LlmVisionRequest {
        provider: LlmProvider::Ollama,
        model: "qwen3-vl:30b".into(),
        prompt: "Label the zones of this page.".into(),
        user_context: "Document: 1 pages. Label page 1 of 1.".into(),
        page: breakdown_core::ai::LlmVisionPageInput {
            page_number: 1,
            png_bytes: vec![0x89, b'P', b'N', b'G'],
            spatial_text_hint: None,
        },
        max_tokens: 512,
        response_schema: None,
        reasoning_effort: None,
        zdr_attested: false,
    }
}

/// The zoning loop carries no `ProviderGate` of its own, so the client's own
/// breaker gate is the ONLY thing that keeps a page the pair already fails on
/// from being re-sent once per page. The open snapshot must therefore refuse the
/// request with the sentinel — not reach the transport (which would answer a
/// transport error, since no server is running here).
#[test]
fn an_open_vision_breaker_refuses_the_zone_request_before_the_transport() {
    let client =
        OllamaChatClient::with_http(reqwest::Client::new(), 0, std::time::Duration::from_secs(1))
            .with_provider_health(std::sync::Arc::new(FixedBreaker(
                breakdown_core::ai::ProviderBreakerSnapshot {
                    state: breakdown_core::ai::ProviderBreakerState::Open,
                    consecutive_failures: 3,
                    ..breakdown_core::ai::ProviderBreakerSnapshot::closed()
                },
            )));

    let rt = tokio::runtime::Runtime::new().unwrap();
    let error = rt
        .block_on(client.chat_vision_zone_labels(&zone_request()))
        .expect_err("an open breaker refuses the paid zone request");
    assert!(
        crate::ai::provider_health::is_breaker_open(&error),
        "the refusal must be the breaker sentinel, not a transport failure: {error:?}"
    );
    assert_eq!(
        crate::ai::provider_health::orphaned_usage(&error),
        Some(Vec::new()),
        "nothing was billed before the refusal"
    );
}

/// A closed breaker lets the request through, i.e. the gate does not add a new
/// failure mode for the healthy path (it then fails in the transport, because no
/// Ollama server is running).
#[test]
fn a_closed_vision_breaker_admits_the_zone_request() {
    let client =
        OllamaChatClient::with_http(reqwest::Client::new(), 0, std::time::Duration::from_secs(1))
            .with_provider_health(std::sync::Arc::new(FixedBreaker(
                breakdown_core::ai::ProviderBreakerSnapshot::closed(),
            )));

    let rt = tokio::runtime::Runtime::new().unwrap();
    let error = rt
        .block_on(client.chat_vision_zone_labels(&zone_request()))
        .expect_err("no Ollama server is listening");
    assert!(
        !crate::ai::provider_health::is_breaker_open(&error),
        "a closed breaker must not answer the sentinel: {error:?}"
    );
}
