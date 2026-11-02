// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! Unit tests for the Decision API adapter (issue #722).

use super::{DecisionWireResponse, decision_endpoint};
use crate::ai::decision_client::HttpDecisionClient;
use breakdown_core::ai::{
    DecisionClient, DecisionRequest, LlmProvider, noul, question_keys, score5,
};
use serde_json::json;
use std::time::Duration;

fn request(provider: LlmProvider, model: &str) -> DecisionRequest {
    let mut questions = std::collections::BTreeMap::new();
    questions.insert(
        question_keys::CHARACTERS_COMPLETE.to_owned(),
        noul("characters complete?"),
    );
    questions.insert(
        question_keys::SCENE_METADATA_ACCURACY.to_owned(),
        score5("metadata accuracy?"),
    );
    DecisionRequest {
        provider,
        model: model.to_owned(),
        state: json!({"kind": "script_chunk", "heading": "1 I/T - OP"}),
        questions,
    }
}

/// The endpoint registry covers exactly the three curated decision providers.
#[test]
fn decision_endpoints_are_curated() {
    assert_eq!(
        decision_endpoint(LlmProvider::Neuralwatt),
        Some("https://api.neuralwatt.com/v1/systemone")
    );
    assert_eq!(
        decision_endpoint(LlmProvider::EURouter),
        // The System One surface — NOT `/api/v1/decisions`, which 404s (see the
        // `decision_endpoint` doc: that path produced `scoring_failed` on
        // every row of a live import).
        Some("https://api.eurouter.ai/api/v1/systemone")
    );
    assert_eq!(
        decision_endpoint(LlmProvider::OpenRouter),
        Some("https://openrouter.ai/api/alpha/decisions")
    );
    // Non-decision providers have none.
    assert_eq!(decision_endpoint(LlmProvider::OpenAI), None);
    assert_eq!(decision_endpoint(LlmProvider::Ollama), None);
}

#[tokio::test]
async fn rejects_non_decision_providers() {
    let error =
        HttpDecisionClient::new(LlmProvider::OpenAI, "k".to_owned(), Duration::from_secs(1))
            .await
            .err();
    assert!(error.is_some(), "OpenAI must be rejected (fail closed)");
    let error =
        HttpDecisionClient::new(LlmProvider::Ollama, "k".to_owned(), Duration::from_secs(1))
            .await
            .err();
    assert!(error.is_some(), "Ollama must be rejected (fail closed)");
}

#[tokio::test]
async fn rejects_empty_api_key() {
    let error = HttpDecisionClient::new(
        LlmProvider::Neuralwatt,
        "  ".to_owned(),
        Duration::from_secs(1),
    )
    .await
    .err();
    assert!(error.is_some(), "an empty decision key must be rejected");
}

#[tokio::test]
async fn provider_mismatch_fails_closed() {
    let http = reqwest::Client::new();
    let client = HttpDecisionClient::with_http(
        http,
        LlmProvider::Neuralwatt,
        "k".into(),
        Duration::from_secs(1),
    )
    .unwrap();
    // A EURouter request against a Neuralwatt client must be rejected before
    // any network activity.
    let error = client
        .decide(request(LlmProvider::EURouter, "clef-flash"))
        .await
        .err();
    assert!(error.is_some(), "provider mismatch must fail closed");
}

/// The adapter must forward the provider's error body through
/// `classify_http_status_with_detail`. Without this test a revert to the
/// detail-less `classify_http_status(status)` keeps every other test green,
/// because the forwarding happens only on the wire path (CodeRabbit review,
/// PR #806) — hence the `endpoint` seam on `with_http` clients.
#[tokio::test]
async fn non_2xx_response_forwards_the_provider_body() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .respond_with(
            wiremock::ResponseTemplate::new(503).set_body_string("unknown property: rubric"),
        )
        .mount(&server)
        .await;

    let mut client = HttpDecisionClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "k".into(),
        Duration::from_secs(5),
    )
    .expect("a decision-capable provider builds a client");
    client.endpoint = server.uri();

    let error = client
        .decide(request(LlmProvider::Neuralwatt, "clef-flash"))
        .await
        .err()
        .expect("a 503 response must fail");
    // 503 keeps its retryable class …
    assert!(
        matches!(
            error,
            breakdown_core::error::DomainError::ServiceUnavailable { .. }
        ),
        "503 must stay ServiceUnavailable, got {error:?}"
    );
    // … and the provider's own message reaches the caller instead of a bare
    // "HTTP 503".
    assert!(
        error.to_string().contains("unknown property: rubric"),
        "the provider body must be forwarded, got: {error}"
    );
}

/// The forwarded detail is bounded: the read stops at `MAX_ERROR_DETAIL_BYTES`
/// and the message keeps at most 400 characters of it, so a chatty body cannot
/// flood the log or the error surface.
#[tokio::test]
async fn non_2xx_response_detail_is_bounded() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .respond_with(wiremock::ResponseTemplate::new(400).set_body_string("x".repeat(8 * 1024)))
        .mount(&server)
        .await;

    let mut client = HttpDecisionClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "k".into(),
        Duration::from_secs(5),
    )
    .expect("a decision-capable provider builds a client");
    client.endpoint = server.uri();

    let error = client
        .decide(request(LlmProvider::Neuralwatt, "clef-flash"))
        .await
        .err()
        .expect("a 400 response must fail");
    let message = error.to_string();
    let detail = message
        .split_once(" \u{2014} ")
        .map(|(_, d)| d)
        .expect("the detail must be appended after the separator");
    assert_eq!(
        detail.chars().count(),
        400,
        "the detail must be truncated to 400 characters, got {}",
        detail.chars().count()
    );
}

#[test]
fn parses_answers_and_usage_leniently() {
    // Wire-shape test: the adapter's envelope parser maps the response
    // leniently (missing usage → zeros) and `decide` filters unknown answer
    // names before they reach the outcome (network path covered by the
    // integration suite's wire tests).
    let body = json!({
        "answers": {
            question_keys::CHARACTERS_COMPLETE: {"noul": 0.87},
            question_keys::SCENE_METADATA_ACCURACY: {"score": [0.0, 0.1, 0.2, 0.3, 0.4]},
            "unknown_question": {"noul": 0.5}
        },
        "usage": {"input_tokens": 123, "millijoules": 45}
    });
    let wire: DecisionWireResponse = serde_json::from_value(body).unwrap();
    assert_eq!(wire.answers.len(), 3);
    let usage = wire.usage.unwrap_or_default();
    assert_eq!(usage.input_tokens, 123);
    assert_eq!(usage.millijoules, 45);
    // A response without a usage object degrades to zeros — never a
    // fabricated value.
    let bare: DecisionWireResponse = serde_json::from_value(json!({"answers": {}})).unwrap();
    assert!(bare.usage.is_none());
    assert!(bare.answers.is_empty());
}
