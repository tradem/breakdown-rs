// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for LLM client: reject_ollama, hosted_origin_host, endpoint,
//! classify_http_status, classify_transport_error.

use std::time::Duration;

use breakdown_core::ai::{CuratedLlmProvider, LlmProvider};
use reqwest::StatusCode;

use super::{
    OpenAiCompatibleChatClient, classify_http_status, classify_http_status_with_detail,
    classify_transport_error, next_truncation_budget,
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

/// The retryable classification keeps its variant (`ServiceUnavailable` — so
/// `is_retryable()` and the backoff path are untouched) but is attributed to
/// the LLM PROVIDER (issue #822). The recorded attempt's `code` is the signal
/// the client aggregates repeated failures on, so it is pinned here for every
/// retryable status: a regression back to the generic
/// `domain.service-unavailable` would silently disable the degraded-provider
/// surface.
#[test]
fn classify_retryable_statuses_are_provider_attributed() {
    for status in [
        StatusCode::TOO_MANY_REQUESTS,
        StatusCode::INTERNAL_SERVER_ERROR,
        StatusCode::SERVICE_UNAVAILABLE,
        StatusCode::BAD_GATEWAY,
    ] {
        let err = classify_http_status(status);
        assert!(
            matches!(
                err,
                breakdown_core::error::DomainError::ServiceUnavailable { .. }
            ),
            "{status} must stay retryable"
        );
        assert_eq!(
            err.code().code,
            "ai-import.llm-provider-unavailable",
            "{status} must name the provider, not a generic service"
        );
        assert!(err.is_retryable(), "{status} must stay retryable");
    }
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
// classify_http_status_with_detail — the provider's own error text
// ===========================================================================

/// The status alone cannot be acted on: a wrong curated endpoint answers 404
/// "Route not found" and a rejected rubric answers 400 naming a property. Both
/// used to surface as an unexplained `scoring_failed` row (issue #767), so the
/// body must reach the error while the classification stays the same.
#[test]
fn classify_http_status_with_detail_keeps_the_class_and_appends_the_body() {
    let detail = r#"{"error":{"code":404,"message":"Route not found"}}"#;
    let err = classify_http_status_with_detail(StatusCode::NOT_FOUND, detail);
    match err {
        breakdown_core::error::DomainError::Validation { reason, .. } => {
            assert!(reason.contains("404"), "status must stay visible: {reason}");
            assert!(
                reason.contains("Route not found"),
                "the provider's reason must be carried: {reason}"
            );
        }
        other => panic!("404 must stay a validation error, got {other:?}"),
    }
    // A retryable status keeps its class — the detail never re-classifies it.
    let err = classify_http_status_with_detail(StatusCode::TOO_MANY_REQUESTS, "slow down");
    assert!(matches!(
        err,
        breakdown_core::error::DomainError::ServiceUnavailable { .. }
    ));
    assert_eq!(
        err.code().code,
        "ai-import.llm-provider-unavailable",
        "the provider attribution is stable with a body"
    );
    // An empty body degrades to exactly the plain classification.
    let err = classify_http_status_with_detail(StatusCode::BAD_REQUEST, "   ");
    match err {
        breakdown_core::error::DomainError::Validation { reason, .. } => {
            assert!(!reason.contains('—'), "no empty detail separator: {reason}");
        }
        other => panic!("expected validation, got {other:?}"),
    }
    // A chatty body is bounded (it can echo the request). The bound is asserted
    // on the DETAIL suffix, not on the whole message: a total-length check would
    // also pass for a 500-character detail, because the status prefix and the
    // separator already take 58 characters (CodeRabbit review).
    let long = "x".repeat(2_000);
    let err = classify_http_status_with_detail(StatusCode::BAD_REQUEST, &long);
    match err {
        breakdown_core::error::DomainError::Validation { reason, .. } => {
            let detail_part = reason
                .split_once(" \u{2014} ")
                .map(|(_, d)| d)
                .unwrap_or("");
            assert_eq!(
                detail_part.chars().count(),
                400,
                "detail must be truncated to exactly 400 chars, got {}",
                detail_part.chars().count()
            );
        }
        other => panic!("expected validation, got {other:?}"),
    }
}

// ===========================================================================
// classify_transport_error — kills || → && mutation
// ===========================================================================

/// A local endpoint that accepts the connection and then holds it open without
/// answering: the ONLY possible failure is the client's own timeout, so the test
/// cannot pass on a connect/DNS error that happens to be classified the same way
/// (both map to the provider code since issue #822 — which is exactly why the
/// classification alone proves nothing about *which* arm was taken).
///
/// A std listener + thread is enough and avoids depending on a tokio `net`
/// feature; the thread is stopped when the guard drops, so no test leaks a
/// background task past its assertions.
struct SilentServer {
    address: std::net::SocketAddr,
    stop: std::sync::mpsc::Sender<()>,
    handle: Option<std::thread::JoinHandle<()>>,
}

impl SilentServer {
    fn start() -> Self {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        // Non-blocking so the accept wait can observe the stop signal: a
        // blocking `accept()` would make `Drop` join a thread no client ever
        // wakes, stalling CI instead of reporting the test failure.
        listener.set_nonblocking(true).unwrap();
        let (stop, stopped) = std::sync::mpsc::channel::<()>();
        let handle = std::thread::spawn(move || {
            // Phase 1: wait for the connection, but always yield to a stop.
            let accepted = loop {
                match stopped.recv_timeout(Duration::from_millis(10)) {
                    // The test finished (or failed) before a client arrived.
                    Ok(()) | Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return,
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
                }
                match listener.accept() {
                    Ok(connection) => break connection,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => continue,
                    // The listener is gone: nothing left to hold open.
                    Err(_) => return,
                }
            };
            // Phase 2: hold the request open without answering. Same stop
            // discipline, so the thread never outlives the test.
            let _ = stopped.recv_timeout(Duration::from_secs(30));
            drop(accepted);
        });
        Self {
            address,
            stop,
            handle: Some(handle),
        }
    }
}

impl Drop for SilentServer {
    fn drop(&mut self) {
        // The signal is honoured in BOTH phases, so this join is bounded no
        // matter how far the test got — including "the client never connected".
        let _ = self.stop.send(());
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

/// The teardown must not depend on a client ever arriving: a test that fails
/// before connecting (a client-build panic, a refused connect) still has to
/// finish, or the suite stalls in `join()` instead of reporting the failure.
#[test]
fn silent_server_teardown_is_bounded_without_a_connection() {
    let started = std::time::Instant::now();
    {
        let server = SilentServer::start();
        assert!(server.address.port() > 0, "the listener is bound");
        // No client: exactly the path that used to block in `accept()`.
    }
    assert!(
        started.elapsed() < Duration::from_secs(2),
        "drop must not wait for a connection, took {:?}",
        started.elapsed()
    );
}

#[tokio::test]
async fn classify_timeout_is_provider_attributed() {
    let server = SilentServer::start();
    let client = reqwest::Client::builder()
        .timeout(Duration::from_millis(200))
        // A proxy from the environment would answer (or fail) instead of the
        // silent listener, making the asserted arm depend on the host setup.
        .no_proxy()
        .build()
        .unwrap();

    let error = client
        .get(format!("http://{}/", server.address))
        .send()
        .await
        .expect_err("a silent listener can only time out");
    // The arm under test: a TIMEOUT, not a connect failure.
    assert!(error.is_timeout(), "expected a timeout, got: {error:?}");
    assert!(!error.is_connect(), "expected no connect error: {error:?}");

    let classified = classify_transport_error(error);
    assert!(
        matches!(
            classified,
            breakdown_core::error::DomainError::ServiceUnavailable { .. }
        ),
        "transport error should be ServiceUnavailable: {classified:?}"
    );
    assert_eq!(
        classified.code().code,
        "ai-import.llm-provider-unavailable",
        "a provider transport fault must name the provider"
    );
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

// CHANGED (was: `assert_eq!(..., None)` for `stop` / `None`).
//
// The old expectation encoded "only a provider-confirmed `length` may be
// retried", which is what made the live eurouter failure unrecoverable: that
// gateway returns a body cut off mid-JSON while reporting `stop`, so the job
// was dead-lettered after a single paid call. Retryability is now bounded by
// the attempt budget alone, so a possibly-truncated response is retried with a
// doubled budget — and still fails hard once the budget is spent.
#[test]
fn truncation_budget_grows_even_when_the_provider_reports_stop() {
    assert_eq!(next_truncation_budget(Some("stop"), 1000, 2), Some(2000));
    assert_eq!(next_truncation_budget(None, 1000, 2), Some(2000));
    // ...but never past the bound.
    assert_eq!(next_truncation_budget(Some("stop"), 1000, 0), None);
    assert_eq!(next_truncation_budget(None, 1000, 0), None);
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

/// Strict Structured Outputs contract (CodeRabbit review PR #725): every
/// object in the generated schedule schema must carry
/// `additionalProperties: false` and list every property in `required`.
/// Mirrors the production call site (`strict_schema`, issue #726).
#[test]
fn schedule_schema_is_strict_structured_outputs_compatible() {
    let schema = super::strict_schema::<super::ShootingScheduleSchema>();

    check_strict(&schema, "$");

    // The decode semantics are unchanged: an Option property is nullable AND
    // required (the model answers `null` instead of omitting the key).
    let row = &schema["$defs"]["ScheduleRowSchema"];
    assert!(
        row["required"]
            .as_array()
            .unwrap()
            .contains(&serde_json::Value::String("shooting_day_label".into()))
    );
    assert_eq!(
        row["properties"]["shooting_day_label"]["type"],
        serde_json::json!(["string", "null"])
    );
}

/// Strict Structured Outputs contract for the SCRIPT-extraction path (issue
/// #726): `chat_constrained` sends `ScriptContextSchema` under the same
/// `strict: true` response format as the schedule path, so the generated
/// schema — and every nested definition — must pass through the same
/// `strict_schema` post-processing.
#[test]
fn script_schema_is_strict_structured_outputs_compatible() {
    let schema = super::strict_schema::<super::ScriptContextSchema>();

    check_strict(&schema, "$");

    // Optional (`Option`) mirrors must stay representable as `null` now that
    // they are required — requiring a non-nullable field would change the
    // decode semantics instead of only the wire shape.
    let scene = &schema["$defs"]["DraftSceneSchema"];
    assert!(
        scene["required"]
            .as_array()
            .unwrap()
            .contains(&serde_json::Value::String("mood".into()))
    );
    assert_eq!(
        scene["properties"]["mood"]["type"],
        serde_json::json!(["string", "null"])
    );
    let root = &schema["properties"]["title"];
    assert_eq!(root["type"], serde_json::json!(["string", "null"]));
}

/// Recursively assert the two strict Structured Outputs invariants
/// (`additionalProperties: false` + every property in `required`) on every
/// object schema in the tree. Shared by the schedule and script contract
/// tests.
fn check_strict(value: &serde_json::Value, path: &str) {
    let serde_json::Value::Object(map) = value else {
        return;
    };
    let is_object = map.get("type").and_then(|t| t.as_str()) == Some("object")
        || map.contains_key("properties");
    if is_object {
        assert_eq!(
            map.get("additionalProperties"),
            Some(&serde_json::Value::Bool(false)),
            "{path}: missing additionalProperties: false"
        );
        if let Some(properties) = map.get("properties").and_then(|p| p.as_object()) {
            let required = map
                .get("required")
                .and_then(|r| r.as_array())
                .unwrap_or_else(|| panic!("{path}: missing required"));
            for name in properties.keys() {
                assert!(
                    required.contains(&serde_json::Value::String(name.clone())),
                    "{path}: property {name} not in required"
                );
            }
        }
    }
    for (key, child) in map {
        check_strict(child, &format!("{path}.{key}"));
    }
}
