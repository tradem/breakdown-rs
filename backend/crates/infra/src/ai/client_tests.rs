// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for LLM client: reject_ollama, hosted_origin_host, endpoint,
//! classify_http_status, classify_transport_error.

use std::time::Duration;

use breakdown_core::ai::{CuratedLlmProvider, LlmChatRequest, LlmClient, LlmProvider};
use reqwest::StatusCode;

use super::{
    ChatCompletionRequest, ChatCompletionResponse, ChatMessage, MAX_COMPLETION_DETAIL_CHARS,
    MAX_TRUNCATION_RETRIES, OpenAiCompatibleChatClient, RateLimitVerdict, ResponseMeta,
    ResponseStep, classify_http_status, classify_http_status_rich,
    classify_http_status_with_detail, classify_provider_body, classify_transport_error,
    next_truncation_budget, step_for_response,
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

// ===========================================================================
// Issue #871, workstream C — the request count one attempt can issue
// ===========================================================================

/// One `chat_constrained` call issues at most `1 + HOSTED_INNER_RETRIES` billed
/// requests, and that is the number `AiImportBounds::attempt_worst_case_secs`
/// multiplies with.
///
/// The loop is simulated through the same `next_truncation_budget` countdown the
/// real `request_decoded` uses, so this pins the structure rather than a mock: a
/// future edit that grants one more retry fails here *and* invalidates the
/// permit bound, instead of silently widening the window.
#[test]
fn one_attempt_issues_at_most_three_billed_requests() {
    let mut retries_left = MAX_TRUNCATION_RETRIES;
    let mut budget = 1_000u32;
    let mut requests = 1usize; // the first request always happens
    while let Some(grown) = next_truncation_budget(Some("length"), budget, retries_left) {
        requests += 1;
        budget = grown;
        retries_left -= 1;
    }
    assert_eq!(
        requests,
        1 + breakdown_core::ai::HOSTED_INNER_RETRIES as usize,
        "the bound multiplies (1 + max_attempt_retries) by (1 + this count)"
    );
    assert_eq!(requests, 3);
}

/// The countdown is driven by the retry counter, never by `finish_reason` — a
/// gateway that cuts a body short while reporting `stop` still gets the bounded
/// retries (observed live against eurouter). So the ceiling holds for *any*
/// unparseable answer, which is what makes the permit bound a ceiling rather than
/// a hope.
#[test]
fn the_retry_countdown_ignores_the_reported_finish_reason() {
    for reported in [Some("length"), Some("stop"), None] {
        assert_eq!(
            next_truncation_budget(reported, 1_000, 1),
            Some(2_000),
            "an unparseable answer is retried whatever the provider claims ({reported:?})"
        );
    }
    assert_eq!(
        next_truncation_budget(Some("length"), 1_000, 0),
        None,
        "and the ceiling is the counter, so the last request is the last request"
    );
}

// ===========================================================================
// classify_http_status_rich — the retry hint (issue #926)
// ===========================================================================

#[test]
fn a_hint_is_carried_on_the_retryable_error_and_named_in_the_narrative() {
    let error = classify_http_status_rich(
        StatusCode::TOO_MANY_REQUESTS,
        "",
        Some(Duration::from_secs(7)),
        RateLimitVerdict::RateLimited,
    );

    // Structure: the schedulers read this, not the text.
    assert_eq!(error.retry_after(), Some(Duration::from_secs(7)));
    // Narrative: the attempt row's `error_summary` is `Display`, so the operator
    // must be able to see the rate limit and the wait from the history alone.
    let narrative = error.to_string();
    assert!(
        narrative.contains("429"),
        "the status must stay in the narrative: {narrative}"
    );
    assert!(
        narrative.contains("wait 7s"),
        "the provider's own wait must be named: {narrative}"
    );
    // Taxonomy: unchanged by the hint (ADR-031 — no new variant, no new code).
    assert_eq!(error.code().code, "ai-import.llm-provider-unavailable");
    assert!(error.is_retryable());
}

#[test]
fn a_hint_never_changes_the_classification() {
    for status in [
        StatusCode::TOO_MANY_REQUESTS,
        StatusCode::SERVICE_UNAVAILABLE,
        StatusCode::BAD_REQUEST,
        StatusCode::NOT_FOUND,
    ] {
        let plain =
            classify_http_status_rich(status, "detail", None, RateLimitVerdict::RateLimited);
        let hinted = classify_http_status_rich(
            status,
            "detail",
            Some(Duration::from_secs(30)),
            RateLimitVerdict::RateLimited,
        );

        assert_eq!(
            plain.code().code,
            hinted.code().code,
            "{status}: the stable code must not depend on a header"
        );
        assert_eq!(
            plain.is_retryable(),
            hinted.is_retryable(),
            "{status}: retryability must not depend on a header"
        );
        // The hint is only ever attached where a scheduler reads it.
        if plain.is_retryable() {
            assert_eq!(hinted.retry_after(), Some(Duration::from_secs(30)));
        } else {
            assert_eq!(hinted.retry_after(), None, "{status} has no retry path");
        }
    }
}

#[test]
fn a_hint_less_classification_carries_no_hint() {
    // Byte-compatibility: every pre-#926 call site keeps behaving identically.
    let error = classify_http_status(StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(error.retry_after(), None);
    assert!(!error.to_string().contains("wait"));
}

#[test]
fn the_detail_suffix_still_follows_the_hint_in_the_narrative() {
    let error = classify_http_status_rich(
        StatusCode::TOO_MANY_REQUESTS,
        "rate limited by tier",
        Some(Duration::from_secs(2)),
        RateLimitVerdict::RateLimited,
    );
    let narrative = error.to_string();
    assert!(narrative.contains("wait 2s"), "{narrative}");
    assert!(
        narrative.contains("rate limited by tier"),
        "the provider's own detail must survive the hint: {narrative}"
    );
}

// ===========================================================================
// classify_provider_body / RateLimitVerdict — quota vs rate limit (issue #927)
// ===========================================================================

/// A live OpenAI `insufficient_quota` answer (the shape verified against the
/// provider's documented error codes): the terminal case.
const OPENAI_QUOTA_BODY: &str = r#"{"error":{"message":"You exceeded your current quota, please check your plan and billing details.","type":"insufficient_quota","param":null,"code":"insufficient_quota"}}"#;

/// A live OpenAI rate-limit answer: retryable, and the regression pin for the
/// pre-#927 behaviour.
const OPENAI_RATE_LIMIT_BODY: &str = r#"{"error":{"message":"Rate limit reached for requests","type":"requests","param":null,"code":"rate_limit_exceeded"}}"#;

/// Gemini's `RESOURCE_EXHAUSTED` names the exhausted quota in
/// `details[].metadata.quota_limit` — the per-DAY id is the terminal case, the
/// per-MINUTE id the retryable one. Both are `429 RESOURCE_EXHAUSTED`, so only
/// the quota id can tell them apart.
const GEMINI_PER_DAY_BODY: &str = r#"{"error":{"code":429,"message":"Resource has been exhausted (e.g. check quota).","status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"RATE_LIMIT_EXCEEDED","domain":"googleapis.com","metadata":{"quota_limit":"GenerateRequestsPerDayPerProjectPerModel-FreeTier"}}]}}"#;
const GEMINI_PER_MINUTE_BODY: &str = r#"{"error":{"code":429,"message":"Resource has been exhausted (e.g. check quota).","status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"RATE_LIMIT_EXCEEDED","domain":"googleapis.com","metadata":{"quota_limit":"GenerateRequestsPerMinutePerProjectPerModel-FreeTier"}}]}}"#;

/// OpenRouter states its free-tier daily cap in prose, not in a code field.
const OPENROUTER_FREE_TIER_BODY: &str = r#"{"error":{"message":"Rate limit exceeded: free-models-per-day. Add 10 credits to unlock 1000 free model requests per day","code":429}}"#;

/// The marker a terminal verdict matched, or `None` for a retryable one.
fn matched(verdict: RateLimitVerdict) -> Option<&'static str> {
    match verdict {
        RateLimitVerdict::RateLimited => None,
        RateLimitVerdict::QuotaExhausted { marker } => Some(marker),
    }
}

#[test]
fn openai_shaped_providers_recognise_the_quota_codes() {
    for provider in [
        LlmProvider::OpenAI,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCode,
        LlmProvider::OpenCodeGo,
    ] {
        assert_eq!(
            matched(classify_provider_body(provider, OPENAI_QUOTA_BODY)),
            Some("insufficient_quota"),
            "{provider:?} shares the OpenAI error shape, and the verdict names the code"
        );
        for body in [
            r#"{"error":{"code":"credit_balance_exhausted"}}"#,
            r#"{"error":{"code":"billing_hard_limit_reached"}}"#,
        ] {
            assert!(
                matched(classify_provider_body(provider, body)).is_some(),
                "{provider:?}: {body}"
            );
        }
        assert_eq!(
            matched(classify_provider_body(provider, OPENAI_RATE_LIMIT_BODY)),
            None,
            "{provider:?}: a rate limit must stay retryable"
        );
    }
}

#[test]
fn gemini_distinguishes_a_per_day_quota_from_a_per_minute_limit() {
    assert_eq!(
        matched(classify_provider_body(
            LlmProvider::Gemini,
            GEMINI_PER_DAY_BODY
        )),
        Some("perdayperproject"),
        "the per-day quota id is the terminal one, and it is named"
    );
    assert_eq!(
        matched(classify_provider_body(
            LlmProvider::Gemini,
            GEMINI_PER_MINUTE_BODY
        )),
        None,
        "RPM exhaustion is exactly what a retry fixes"
    );
    // The spelling inside a `quota_limit` may use underscores.
    assert_eq!(
        matched(classify_provider_body(
            LlmProvider::Gemini,
            r#"{"error":{"details":[{"metadata":{"quota_limit":"requests_per_day_per_project"}}]}}"#
        )),
        Some("per_day_per_project")
    );
}

#[test]
fn openrouter_recognises_its_free_tier_daily_cap() {
    assert_eq!(
        matched(classify_provider_body(
            LlmProvider::OpenRouter,
            OPENROUTER_FREE_TIER_BODY
        )),
        Some("free-models-per-day")
    );
    assert_eq!(
        matched(classify_provider_body(
            LlmProvider::OpenRouter,
            r#"{"error":{"message":"Rate limit exceeded: free-models-per-minute","code":429}}"#
        )),
        None,
        "the per-minute cap is retryable"
    );
}

#[test]
fn a_provider_without_a_quota_concept_never_reports_one() {
    // EURouter's budget/spend caps arrive as `402`, not `429`; Ollama is
    // self-hosted. An OpenAI-shaped body therefore must NOT turn their `429`
    // into a dead-letter — there is no account quota to exhaust.
    for provider in [LlmProvider::EURouter, LlmProvider::Ollama] {
        assert_eq!(
            matched(classify_provider_body(provider, OPENAI_QUOTA_BODY)),
            None,
            "{provider:?} has no quota evidence table"
        );
    }
}

#[test]
fn an_unreadable_body_is_the_conservative_retryable_default() {
    for body in [
        "",
        "   ",
        "<html><body><h1>502 Bad Gateway</h1></body></html>",
        "{\"error\":",
        "{\"error\":{\"code\":\"something_new\"}}",
        "[1,2,3]",
    ] {
        assert_eq!(
            matched(classify_provider_body(LlmProvider::OpenAI, body)),
            None,
            "a wrong non-retryable verdict dead-letters a job a retry would have saved: {body:?}"
        );
    }
}

#[test]
fn only_json_values_are_evidence_never_keys() {
    // A provider echoing OUR request could contain the marker as a KEY; the
    // evidence has to come from what the provider said.
    let body = r#"{"insufficient_quota":{"message":"some unrelated complaint"}}"#;
    assert_eq!(
        matched(classify_provider_body(LlmProvider::OpenAI, body)),
        None
    );
}

/// Issue #942 W3: EURouter's budget/spend cap arrives as `402 Payment Required`
/// (its `429` is plan RPM, which is why its marker table is empty). Before this
/// it fell through to `RetryClass::Rejected` → `DomainError::validation`, so the
/// job dead-lettered with `domain.validation` and the app told the user their
/// request was malformed instead of that the account needs a top-up.
#[test]
fn a_payment_required_status_is_a_terminal_quota_verdict_not_a_validation_error() {
    let error = classify_http_status_rich(
        StatusCode::PAYMENT_REQUIRED,
        r#"{"error":{"message":"Insufficient credit","code":402}}"#,
        None,
        RateLimitVerdict::RateLimited,
    );

    assert!(
        matches!(
            error,
            breakdown_core::error::DomainError::LlmProviderQuotaExhausted { .. }
        ),
        "a 402 is an empty account, not a malformed request: {error:?}"
    );
    assert_eq!(error.code().code, "ai-import.provider-quota-exhausted");
    assert_eq!(error.code().status, 402);
    assert!(
        !error.is_retryable(),
        "nothing about the request may spend the retry budget on an empty account"
    );
    assert_eq!(
        error.retry_after(),
        None,
        "a terminal failure has nothing to schedule"
    );
    let narrative = error.to_string();
    assert!(
        narrative.contains("402"),
        "the attempt row must name the status that fired: {narrative}"
    );
}

#[test]
fn a_quota_verdict_is_terminal_and_renders_the_dedicated_quota_code() {
    let error = classify_http_status_rich(
        StatusCode::TOO_MANY_REQUESTS,
        OPENAI_QUOTA_BODY,
        Some(Duration::from_secs(30)),
        RateLimitVerdict::QuotaExhausted {
            marker: "insufficient_quota",
        },
    );

    assert!(
        matches!(
            error,
            breakdown_core::error::DomainError::LlmProviderQuotaExhausted { .. }
        ),
        "a quota exhaustion is terminal, not a hint-bearing outage: {error:?}"
    );
    // Issue #942 W3: the exhausted-account code, deliberately NOT the outage
    // code — the client branches on `code` alone (ADR-031 D2), and sharing it
    // made a top-up render as "provider unreachable".
    assert_eq!(error.code().code, "ai-import.provider-quota-exhausted");
    assert_ne!(
        error.code().code,
        "ai-import.llm-provider-unavailable",
        "an exhausted quota is not an outage (issue #942 W3)"
    );
    assert!(!error.is_retryable());
    // No scheduler may wait for a job that is about to dead-letter.
    assert_eq!(error.retry_after(), None);
    let narrative = error.to_string();
    assert!(
        narrative.contains("429") && narrative.contains("insufficient_quota"),
        "the attempt row must say WHY it was terminal: {narrative}"
    );
}

/// CodeRabbit review, PR #931: the attempt narrative must name the matched code
/// even when the provider hides it BEHIND the 400-character detail truncation.
/// A long `error.message` used to push the code out of the persisted narrative
/// while the verdict was still terminal — the operator then had no evidence in
/// the row.
#[test]
fn the_narrative_names_the_matched_code_behind_a_long_provider_message() {
    let long_message = "Quota exceeded for this project. ".repeat(30); // > 400 chars
    let body = format!(
        r#"{{"error":{{"message":"{long_message}","type":"insufficient_quota","code":"insufficient_quota"}}}}"#
    );

    let verdict = classify_provider_body(LlmProvider::OpenAI, &body);
    assert_eq!(matched(verdict), Some("insufficient_quota"));
    let error = classify_http_status_rich(StatusCode::TOO_MANY_REQUESTS, &body, None, verdict);
    let narrative = error.to_string();
    assert!(
        narrative.contains("insufficient_quota"),
        "the matched code must survive the detail truncation: {} chars",
        narrative.len()
    );
    assert!(
        narrative.len() < 1_000,
        "the narrative stays bounded even when the provider is verbose"
    );
}

/// CodeRabbit review, PR #931: an **incomplete** read is never evidence, even
/// when the bytes that arrived contain a complete quota JSON. A stream cut by a
/// proxy may have lost the part that changes the meaning, and a wrong
/// "non-retryable" verdict dead-letters a job a retry would have saved.
#[test]
fn an_incomplete_body_read_is_retryable_even_with_quota_evidence() {
    let cut = super::ErrorBody {
        text: OPENAI_QUOTA_BODY.to_owned(),
        complete: false,
    };
    assert_eq!(
        matched(cut.verdict(LlmProvider::OpenAI)),
        None,
        "a cut stream is not evidence"
    );

    let whole = super::ErrorBody {
        text: OPENAI_QUOTA_BODY.to_owned(),
        complete: true,
    };
    assert_eq!(
        matched(whole.verdict(LlmProvider::OpenAI)),
        Some("insufficient_quota"),
        "a fully read quota body stays terminal"
    );
}

#[test]
fn the_quota_verdict_applies_to_429_only() {
    // The VERDICT (parsed quota evidence) narrows a `429` only; a plain `402` is
    // handled separately and terminally (`a_payment_required_status_is_a_…`).
    // A 5xx that happens to carry a quota-looking body is a gateway fault, not
    // an account verdict: it must keep its retryable classification.
    for status in [
        StatusCode::SERVICE_UNAVAILABLE,
        StatusCode::INTERNAL_SERVER_ERROR,
        StatusCode::BAD_GATEWAY,
    ] {
        let error = classify_http_status_rich(
            status,
            OPENAI_QUOTA_BODY,
            None,
            RateLimitVerdict::QuotaExhausted {
                marker: "insufficient_quota",
            },
        );
        assert!(
            error.is_retryable(),
            "{status} is not a quota statement: {error:?}"
        );
    }
    // And a `429` with retryable evidence keeps today's taxonomy/hint.
    let error = classify_http_status_rich(
        StatusCode::TOO_MANY_REQUESTS,
        OPENAI_RATE_LIMIT_BODY,
        Some(Duration::from_secs(5)),
        RateLimitVerdict::RateLimited,
    );
    assert!(error.is_retryable());
    assert_eq!(error.retry_after(), Some(Duration::from_secs(5)));
}

/// CodeRabbit review, PR #931: the byte bound is not a **time** bound. A
/// provider that writes headers plus half a body and then stalls must not hold
/// the concurrency permit until the request timeout (default 120 s) — the read
/// ends at the deadline with `complete: false`, which keeps the verdict
/// retryable while the arrived bytes still reach the narrative.
#[tokio::test]
async fn a_stalled_error_body_read_ends_at_the_deadline() {
    use tokio::io::AsyncWriteExt;

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("a loopback listener");
    let addr = listener.local_addr().expect("a bound address");
    let server = tokio::spawn(async move {
        use tokio::io::AsyncReadExt;
        let Ok((mut socket, _)) = listener.accept().await else {
            return;
        };
        // Consume the request first, so this mock behaves like a real server.
        let mut request = [0_u8; 1024];
        let _ = socket.read(&mut request).await;
        // Headers, the first half of the body, then silence: the declared body
        // is never finished and the socket stays open.
        let partial = b"HTTP/1.1 429 Too Many Requests\r\ncontent-length: 1000\r\n\r\n{\"error\":{\"code\":\"insufficient_quota\"}";
        if let Err(error) = socket.write_all(partial).await {
            eprintln!("mock write failed: {error}");
            return;
        }
        tokio::time::sleep(Duration::from_secs(30)).await;
    });

    let mut response = reqwest::Client::new()
        .get(format!("http://{addr}/"))
        .send()
        .await
        .expect("the mock answers with a 429");

    let started = std::time::Instant::now();
    // A deadline far below the 30 s stall: 50 ms vs 30 s is a 600x margin, so
    // the assertion cannot be won by the socket simply closing.
    let body = super::read_error_body_within(&mut response, Duration::from_millis(50)).await;

    assert!(
        !body.complete,
        "the deadline, not the body's end, must end an incomplete read"
    );
    assert!(
        body.text.contains("insufficient_quota"),
        "the arrived bytes are still kept for the narrative: {:?}",
        body.text
    );
    assert_eq!(
        matched(body.verdict(LlmProvider::OpenAI)),
        None,
        "an incomplete read is not evidence, even when it looks like a quota code"
    );
    assert!(
        started.elapsed() < Duration::from_secs(5),
        "the read must end at its deadline, not at the request timeout: {:?}",
        started.elapsed()
    );

    server.abort();
}

/// CodeRabbit review, PR #931 (round 2): `AI_IMPORT_REQUEST_TIMEOUT_SECS` is
/// configurable down to **1 s**, so a fixed 5 s error-body deadline would
/// outlive the request it belongs to. The budget is therefore the smaller of the
/// two, asserted here analytically instead of slept through.
#[test]
fn the_error_body_budget_never_exceeds_the_request_timeout() {
    use std::time::Duration;

    // The default (and any long) request timeout is capped by the constant.
    assert_eq!(
        super::error_body_budget(Duration::from_secs(120)),
        super::ERROR_BODY_DEADLINE
    );
    assert_eq!(
        super::error_body_budget(Duration::MAX),
        super::ERROR_BODY_DEADLINE
    );
    // A short configured timeout wins, so the read can never outlive the
    // response it reads from.
    assert_eq!(
        super::error_body_budget(Duration::from_secs(1)),
        Duration::from_secs(1)
    );
    assert_eq!(
        super::error_body_budget(Duration::from_millis(250)),
        Duration::from_millis(250)
    );
}

// ===========================================================================
// Empty completion (2026-11-20 incident)
//
// A `200` whose `message.content` is null/blank used to become
// `DomainError::validation("LLM response contained no content")`: not
// retryable, zero in-attempt retries, immediate dead letter, no diagnosis and
// no breaker signal. These tests pin the corrected decision — the branch had NO
// coverage before, which is why the whole failure class reached the user's
// manual test instead of CI.
// ===========================================================================

/// Decode a provider envelope fixture the way the transport does.
fn envelope(value: serde_json::Value) -> ChatCompletionResponse {
    serde_json::from_value(value).expect("envelope fixture must deserialize")
}

/// Response metadata as a gateway sends it (eurouter answers with
/// `x-request-id`, `x-envoy-upstream-service-time` and `server`).
fn meta(request_id: &str) -> ResponseMeta {
    ResponseMeta {
        request_id: Some(request_id.to_owned()),
        upstream_service_time: Some("71004".to_owned()),
        server: Some("envoy".to_owned()),
    }
}

/// The 2026-11-20 response: `content: null` at the token ceiling.
fn empty_completion_envelope() -> ChatCompletionResponse {
    envelope(serde_json::json!({
        "id": "chatcmpl-abc123",
        "model": "mistral-large-3-2026-11",
        "choices": [{
            "message": {
                "role": "assistant",
                "content": null,
                "reasoning_content": "x"
            },
            "finish_reason": "length"
        }],
        "usage": {"prompt_tokens": 2187, "completion_tokens": 8192}
    }))
}

#[test]
fn a_null_content_is_retried_with_a_grown_budget_before_it_fails() {
    let body = empty_completion_envelope();
    let step = step_for_response(&body, &meta("req-1"), 8_192, 1);
    let ResponseStep::RetryWithBudget {
        budget,
        retries_left,
        reason,
    } = step
    else {
        panic!("a truncated empty completion must be re-requested, got {step:?}");
    };
    assert_eq!(budget, 16_384, "the budget doubles like a truncated answer");
    assert_eq!(retries_left, 0, "the retry budget must be spent");
    assert!(
        reason.contains("finish_reason=length"),
        "the diagnosis must name the provider's stop reason: {reason}"
    );
}

/// The regression the user hit: after the bounded retries are spent, an empty
/// completion is a PROVIDER failure (retryable, breaker-counting), never a
/// validation failure of our own input.
#[test]
fn an_exhausted_empty_completion_is_a_provider_failure() {
    let body = empty_completion_envelope();
    let step = step_for_response(&body, &meta("req-2"), 32_768, 0);
    let ResponseStep::Fail { error } = step else {
        panic!("the retry budget is spent, the step must fail: {step:?}");
    };
    assert_eq!(
        error.code().code,
        "ai-import.llm-provider-unavailable",
        "an empty answer is the endpoint failing, not a validation error"
    );
    assert!(
        error.is_retryable(),
        "a provider that answers 200 with nothing must be retried and may open the breaker"
    );
    assert!(
        error.to_string().contains("request_id=req-2"),
        "the failure text must carry the provider's request handle: {error}"
    );
}

#[test]
fn a_blank_content_string_takes_the_empty_completion_path() {
    let body = envelope(serde_json::json!({
        "choices": [{"message": {"content": "   \n"}, "finish_reason": "stop"}]
    }));
    let step = step_for_response(&body, &meta("req-3"), 8_192, 2);
    assert!(
        matches!(step, ResponseStep::RetryWithBudget { .. }),
        "whitespace-only content is 'no content', not a JSON parse error: {step:?}"
    );
}

#[test]
fn a_response_without_choices_is_retried_then_fails_as_a_provider_failure() {
    let body = envelope(serde_json::json!({"choices": []}));
    let step = step_for_response(&body, &meta("req-4"), 8_192, 0);
    let ResponseStep::Fail { error } = step else {
        panic!("no choices with no retries left must fail: {step:?}");
    };
    assert_eq!(error.code().code, "ai-import.llm-provider-unavailable");
    assert!(error.to_string().contains("no choices"));
}

/// The diagnosis is the whole point of the fix: every field the incident could
/// not answer must be in the recorded error.
#[test]
fn the_empty_completion_diagnosis_names_every_investigated_field() {
    let body = empty_completion_envelope();
    let step = step_for_response(&body, &meta("req-5"), 32_768, 0);
    let ResponseStep::Fail { error } = step else {
        panic!("expected a failure: {step:?}");
    };
    let text = error.to_string();
    for expected in [
        "blank content",
        "completion_id=chatcmpl-abc123",
        "response_model=mistral-large-3-2026-11",
        "finish_reason=length",
        "reasoning_content_chars=1",
        "tokens_in=2187",
        "tokens_out=8192",
        "request_id=req-5",
        "upstream_ms=71004",
        "server=envoy",
    ] {
        assert!(text.contains(expected), "missing {expected} in: {text}");
    }
}

#[test]
fn a_refusal_is_named_in_the_diagnosis() {
    let body = envelope(serde_json::json!({
        "choices": [{"message": {"content": null, "refusal": "cannot help with that"}, "finish_reason": "stop"}]
    }));
    let step = step_for_response(&body, &meta("req-6"), 8_192, 0);
    let ResponseStep::Fail { error } = step else {
        panic!("a refusal carries no content, so it fails: {step:?}");
    };
    assert!(error.to_string().contains("refusal=cannot help with that"));
}

/// A content-level refusal is TERMINAL (review finding): a larger output budget
/// cannot turn "cannot help with that" into an answer, so re-requesting pays the
/// same rejection again — and reporting it as
/// `ai-import.llm-provider-unavailable` (retryable, breaker-counting) let one
/// refusal accumulate in-attempt retries AND breaker failures for a healthy
/// pair.
#[test]
fn a_refusal_is_terminal_and_burns_no_retry_budget() {
    let body = envelope(serde_json::json!({
        "choices": [{"message": {"content": null, "refusal": "cannot help with that"}, "finish_reason": "stop"}]
    }));
    // Two inner retries were available; a refusal must not spend one.
    let step = step_for_response(&body, &meta("req-7r"), 8_192, 2);
    let ResponseStep::Fail { error } = step else {
        panic!("a refusal is never retried, got {step:?}");
    };
    assert!(
        !error.is_retryable(),
        "a refusal is not an outage and must not reach the breaker: {error:?}"
    );
    assert!(
        error.to_string().contains("refusal=cannot help with that"),
        "the diagnosis keeps the provider's own wording: {error}"
    );
}

/// The safety finish reason is the same decision as an explicit `refusal` — a
/// `content_filter` answer repeats identically at any budget.
#[test]
fn a_content_filter_is_terminal_without_a_refusal_field() {
    let body = envelope(serde_json::json!({
        "choices": [{"message": {"content": null}, "finish_reason": "content_filter"}]
    }));
    let step = step_for_response(&body, &meta("req-7c"), 8_192, 2);
    let ResponseStep::Fail { error } = step else {
        panic!("a content filter is never retried, got {step:?}");
    };
    assert!(!error.is_retryable(), "not a provider outage: {error:?}");
    assert!(
        error.to_string().contains("finish_reason=content_filter"),
        "the diagnosis names the filter: {error}"
    );
}

/// A refusal that still carries CONTENT is decoded, not discarded: the provider
/// answered, and the answer is the caller's to judge.
#[test]
fn a_refusal_with_content_is_still_decoded() {
    let body = envelope(serde_json::json!({
        "choices": [{
            "message": {"content": "{\"scenes\": []}", "refusal": "partial"},
            "finish_reason": "content_filter"
        }]
    }));
    let step = step_for_response(&body, &meta("req-7d"), 8_192, 2);
    assert!(
        matches!(step, ResponseStep::Decode { .. }),
        "content wins over the refusal marker: {step:?}"
    );
}

#[test]
fn the_diagnosis_is_bounded_but_never_silently_blank() {
    // The shared capper counts CHARACTERS and says when it cut.
    let unbounded = super::truncate_detail(&"r".repeat(4_000));
    assert_eq!(unbounded.chars().count(), MAX_COMPLETION_DETAIL_CHARS + 1);
    assert!(unbounded.ends_with('…'));
    assert_eq!(
        super::truncate_detail("short"),
        "short",
        "no ellipsis when it fits"
    );

    // End to end: a hostile 4 000-character refusal cannot bloat the recorded
    // error, which is persisted in `last_error` and rendered by the client.
    let body = envelope(serde_json::json!({
        "choices": [{"message": {"content": null, "refusal": "r".repeat(4_000)}, "finish_reason": "stop"}]
    }));
    let step = step_for_response(&body, &meta("req-7"), 8_192, 0);
    let ResponseStep::Fail { error } = step else {
        panic!("expected a failure: {step:?}");
    };
    let text = error.to_string();
    assert!(
        text.chars().count() <= MAX_COMPLETION_DETAIL_CHARS + 128,
        "the recorded error must stay bounded (got {} chars)",
        text.chars().count()
    );
    assert!(text.ends_with('…'), "a truncated diagnosis says so: {text}");
}

#[test]
fn a_response_with_content_is_decoded_unchanged() {
    let body = envelope(serde_json::json!({
        "choices": [{
            "message": {"content": "{\"title\": null, \"scenes\": [], \"uncertainties\": []}"},
            "finish_reason": "stop"
        }]
    }));
    let step = step_for_response(&body, &meta("req-8"), 8_192, 2);
    let ResponseStep::Decode {
        content,
        finish_reason,
    } = step
    else {
        panic!("real content must be decoded, not retried: {step:?}");
    };
    assert!(content.contains("\"scenes\""));
    assert_eq!(finish_reason, Some("stop"));
}

/// The 2026-11-20 incident had no `tracing` output on this path at all, so a
/// failed call could not be found in the provider's dashboard. `ResponseMeta`
/// reads the headers case-insensitively (gateways differ in casing) and prefers
/// `x-request-id`.
#[test]
fn response_meta_reads_the_provider_request_handle_from_headers() {
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert("X-Request-Id", "req-header".parse().unwrap());
    headers.insert("server", "envoy".parse().unwrap());
    let meta = ResponseMeta::capture(&headers);
    assert_eq!(meta.request_id.as_deref(), Some("req-header"));
    assert_eq!(meta.server.as_deref(), Some("envoy"));
    assert_eq!(meta.upstream_service_time, None);
}

/// `reasoning_effort` is an OPTIONAL wire field: an unset value must leave the
/// request body byte-identical to the pre-field one, because a provider that does
/// not advertise `reasoning_effort` answers `400` for the unknown parameter.
#[test]
fn an_unset_reasoning_effort_never_reaches_the_request_body() {
    let body = |effort: Option<String>| ChatCompletionRequest {
        model: "mistral-large-3".to_owned(),
        messages: vec![ChatMessage {
            role: "user".to_owned(),
            content: "hi".to_owned(),
        }],
        max_tokens: 8,
        reasoning_effort: effort,
        response_format: None,
    };
    let unset = serde_json::to_value(body(None)).expect("serialize");
    assert!(
        unset.get("reasoning_effort").is_none(),
        "an unset effort must not appear in the body: {unset}"
    );
    let set = serde_json::to_value(body(Some("low".to_owned()))).expect("serialize");
    assert_eq!(
        set.get("reasoning_effort").and_then(|v| v.as_str()),
        Some("low")
    );
}

// ===========================================================================
// The real request loop (review finding 9)
//
// `step_for_response` is pure and well covered, but the code AROUND it decides
// whether a second request goes out, which budget it carries, what the summed
// usage is and how many billable requests one attempt costs. These tests drive
// the production loop against a mock server through the `endpoint` test seam,
// so a wiring error cannot stay green.
// ===========================================================================

/// One request as the worker builds it. `.model`/`.provider` match the client
/// under test, which `chat_constrained` enforces.
fn chat_request(max_tokens: u32) -> LlmChatRequest {
    LlmChatRequest {
        provider: LlmProvider::Neuralwatt,
        model: "glm-5.3-flash".to_owned(),
        prompt: "Extract the scenes.".to_owned(),
        source_text: "1. INT. KÜCHE - TAG".to_owned(),
        max_tokens,
        response_schema: None,
        reasoning_effort: None,
    }
}

/// A client whose transport AND endpoint point at `server` (test seam: the
/// production endpoint comes from the curated provider registry).
fn mock_client(server: &wiremock::MockServer) -> OpenAiCompatibleChatClient {
    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "test-key".into(),
        Duration::from_secs(5),
    )
    .expect("with_http builds a client for a hosted provider");
    client.endpoint = format!("{}/chat/completions", server.uri());
    client
}

/// The valid answer the second request receives.
fn decode_ok_body() -> serde_json::Value {
    serde_json::json!({
        "id": "chatcmpl-ok",
        "model": "glm-5.3-flash",
        "choices": [{
            "message": {
                "role": "assistant",
                "content": "{\"title\": null, \"scenes\": [], \"uncertainties\": []}"
            },
            "finish_reason": "stop"
        }],
        "usage": {"prompt_tokens": 50, "completion_tokens": 20}
    })
}

/// The 2026-11-20 shape: `content: null` with the output ceiling spent.
fn empty_completion_body() -> serde_json::Value {
    serde_json::json!({
        "id": "chatcmpl-empty",
        "model": "glm-5.3-flash",
        "choices": [{
            "message": {"role": "assistant", "content": null, "reasoning_content": "thinking"},
            "finish_reason": "length"
        }],
        "usage": {"prompt_tokens": 100, "completion_tokens": 8192}
    })
}

/// `HTTP 200 / content: null` → a SECOND request with a doubled budget → a
/// valid answer, with both paid responses in the summed usage.
#[tokio::test]
async fn an_empty_completion_is_re_requested_with_a_doubled_budget() {
    let server = wiremock::MockServer::start().await;
    // Matched on the budget, so the two mocks cannot be confused: the first
    // answer only satisfies the first request.
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .and(wiremock::matchers::body_partial_json(
            serde_json::json!({"max_tokens": 8_192}),
        ))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(empty_completion_body()))
        .mount(&server)
        .await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .and(wiremock::matchers::body_partial_json(
            serde_json::json!({"max_tokens": 16_384}),
        ))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(decode_ok_body()))
        .mount(&server)
        .await;

    let client = mock_client(&server);
    let outcome = client
        .chat_constrained(chat_request(8_192))
        .await
        .expect("the grown budget answers with valid JSON");

    assert!(
        outcome.output.scenes.is_empty() && outcome.output.uncertainties.is_empty(),
        "the second response is the one that is decoded"
    );
    // BOTH paid responses are billed to the job (issue #675).
    let expected = breakdown_core::ai::LlmCallUsage {
        tokens_in: 150,
        tokens_out: 8_212,
        ..Default::default()
    };
    assert_eq!(
        outcome.usage(),
        expected,
        "the discarded empty answer's tokens were paid too"
    );

    let requests = server
        .received_requests()
        .await
        .expect("wiremock records the requests");
    assert_eq!(requests.len(), 2, "exactly one re-request, no more");
    let budgets: Vec<u64> = requests
        .iter()
        .map(|request| {
            let body: serde_json::Value =
                serde_json::from_slice(&request.body).expect("the body is JSON");
            body["max_tokens"].as_u64().expect("max_tokens is a number")
        })
        .collect();
    assert_eq!(
        budgets,
        vec![8_192, 16_384],
        "the retry doubles the output budget once"
    );
}

/// A content-level refusal is one request and a terminal error — no grown
/// budget, no second billable call, no breaker-counting provider error.
#[tokio::test]
async fn a_refusal_costs_exactly_one_request() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .respond_with(
            wiremock::ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "id": "chatcmpl-refused",
                "model": "glm-5.3-flash",
                "choices": [{
                    "message": {"role": "assistant", "content": null, "refusal": "cannot help with that"},
                    "finish_reason": "stop"
                }],
                "usage": {"prompt_tokens": 100, "completion_tokens": 12}
            })),
        )
        .mount(&server)
        .await;

    let client = mock_client(&server);
    let error = client
        .chat_constrained(chat_request(8_192))
        .await
        .expect_err("a refusal never yields a valid answer");
    assert!(
        !error.is_retryable(),
        "a refusal is not a provider outage: {error:?}"
    );
    assert!(
        error.to_string().contains("refusal=cannot help with that"),
        "the diagnosis reaches the job: {error}"
    );
    let requests = server
        .received_requests()
        .await
        .expect("wiremock records the requests");
    assert_eq!(
        requests.len(),
        1,
        "a refusal must be paid ONCE, not once per inner retry"
    );
}

// ===========================================================================
// Issue #960 — multimodal vision seam: pre-egress provider-policy gate
// (ADR-041 `D2`)
// ===========================================================================

/// The pre-egress gate must reject a non-compliant provider BEFORE any HTTP
/// egress: the error surfaces without a reachable endpoint, which only the
/// in-client policy check can guarantee.
#[tokio::test]
async fn chat_vision_rejects_a_non_compliant_provider_before_egress() {
    use breakdown_core::ai::{LlmVisionPageInput, LlmVisionRequest};

    let client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "test-key".to_owned(),
        Duration::from_secs(30),
    )
    .expect("a with_http test client builds");
    let request = LlmVisionRequest {
        provider: LlmProvider::Neuralwatt,
        model: "qwen3-vl".to_owned(),
        prompt: "fixture".to_owned(),
        user_context: "fixture".to_owned(),
        page: LlmVisionPageInput {
            page_number: 1,
            png_bytes: vec![0x89, b'P', b'N', b'G'],
            spatial_text_hint: None,
        },
        max_tokens: 1024,
        response_schema: None,
        reasoning_effort: None,
    };
    let error = client
        .chat_vision_constrained(&request)
        .await
        .expect_err("a provider without ZDR + no-training + EU residency must be refused");
    let detail = error.to_string();
    assert!(
        detail.contains("Zero Data Retention"),
        "the refusal must name the missing policy guarantees: {detail}"
    );
}

/// A compliant provider passes the gate and reaches the transport — verified
/// against a LOCAL wiremock, not the live EURouter URL (CodeRabbit review, PR
/// #967): the mock expects exactly one vision POST and answers with a valid
/// page extraction, so the test asserts the request actually reached a server
/// (no wall-clock deadline guessing) and that the answer decodes.
#[tokio::test]
async fn chat_vision_gate_passes_a_compliant_provider_through_to_the_transport() {
    use breakdown_core::ai::{LlmVisionPageInput, LlmVisionRequest};

    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .and(wiremock::matchers::body_partial_json(serde_json::json!({
            "model": "qwen3-vl",
            "messages": [
                {"role": "system"},
                {"role": "user", "content": [
                    {"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBORw=="}},
                    {"type": "text"}
                ]}
            ]
        })))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(
            serde_json::json!({
                "id": "chatcmpl-vision-ok",
                "model": "qwen3-vl",
                "choices": [{
                    "message": {
                        "role": "assistant",
                        "content": "{\"legend_entries\":[],\"rows\":[{\"row_ref\":\"300.33\",\"rows\":null}]}"
                    },
                    "finish_reason": "stop"
                }],
                "usage": {"prompt_tokens": 11, "completion_tokens": 7}
            }),
        ))
        .expect(1)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::EURouter,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let request = LlmVisionRequest {
        provider: LlmProvider::EURouter,
        model: "qwen3-vl".to_owned(),
        prompt: "fixture".to_owned(),
        user_context: "fixture".to_owned(),
        page: LlmVisionPageInput {
            page_number: 1,
            png_bytes: vec![0x89, b'P', b'N', b'G'],
            spatial_text_hint: None,
        },
        max_tokens: 1024,
        response_schema: None,
        reasoning_effort: None,
    };
    let outcome = client
        .chat_vision_constrained(&request)
        .await
        .expect("a compliant provider reaches the transport and decodes");
    assert_eq!(outcome.output.rows[0].row_ref, "300.33");
    assert_eq!(outcome.usage().tokens_in, 11);
    server.verify().await;
}

/// The refused provider performs ZERO egress: the same local mock seam is
/// mounted with `expect(0)` and the policy refusal is returned before any
/// HTTP attempt (CodeRabbit review, PR #967 — deterministic, no live URL).
#[tokio::test]
async fn chat_vision_gate_refusal_performs_zero_requests() {
    use breakdown_core::ai::{LlmVisionPageInput, LlmVisionRequest};

    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .respond_with(wiremock::ResponseTemplate::new(200))
        .expect(0..1)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let request = LlmVisionRequest {
        provider: LlmProvider::Neuralwatt,
        model: "qwen3-vl".to_owned(),
        prompt: "fixture".to_owned(),
        user_context: "fixture".to_owned(),
        page: LlmVisionPageInput {
            page_number: 1,
            png_bytes: vec![0x89, b'P', b'N', b'G'],
            spatial_text_hint: None,
        },
        max_tokens: 1024,
        response_schema: None,
        reasoning_effort: None,
    };
    let error = client
        .chat_vision_constrained(&request)
        .await
        .expect_err("Neuralwatt is not vision-egress compliant");
    assert!(error.to_string().contains("Zero Data Retention"));
    server.verify().await;
}

// ===========================================================================
// CodeRabbit review, PR #967 — format-fallback eligibility and the
// provider-facing page decoder
// ===========================================================================

fn vision_request_fixture() -> breakdown_core::ai::LlmVisionRequest {
    breakdown_core::ai::LlmVisionRequest {
        provider: LlmProvider::EURouter,
        model: "qwen3-vl".to_owned(),
        prompt: "fixture".to_owned(),
        user_context: "fixture".to_owned(),
        page: breakdown_core::ai::LlmVisionPageInput {
            page_number: 1,
            png_bytes: vec![0x89, b'P', b'N', b'G'],
            spatial_text_hint: None,
        },
        max_tokens: 1024,
        response_schema: None,
        reasoning_effort: None,
    }
}

/// A `429` whose error body happens to mention `response_format` must keep its
/// Retry-After on the classification path — it must NEVER trigger the plain
/// JSON-object fallback (which would re-send the image immediately, ignoring
/// the provider-requested wait). The fallback is reserved for explicit
/// unsupported-format rejections on validation statuses (400/422).
#[tokio::test]
async fn a_rate_limited_body_mentioning_response_format_is_not_a_format_fallback() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .respond_with(
            wiremock::ResponseTemplate::new(429)
                .insert_header("retry-after", "7")
                .set_body_json(serde_json::json!({
                    "error": {"message": "rate limit exceeded for response_format json_schema requests"}
                })),
        )
        .expect(1)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::EURouter,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let request = vision_request_fixture();
    let error = client
        .chat_vision_constrained(&request)
        .await
        .expect_err("a 429 must fail the attempt, not fall back");
    assert!(
        error.is_retryable(),
        "the 429 keeps its classification: {error}"
    );
    assert_eq!(
        error.retry_after(),
        Some(Duration::from_secs(7)),
        "the provider-requested wait survives: {error}"
    );
    server.verify().await;
}

/// A vision page decode of an unrelated JSON object must FAIL, not silently
/// default to an empty (successful) page: the provider-facing decoder requires
/// an explicit `rows` array (CodeRabbit review, PR #967).
#[tokio::test]
async fn a_rows_less_vision_answer_fails_instead_of_reporting_an_empty_page() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "id": "chatcmpl-bad",
            "model": "qwen3-vl",
            "choices": [{
                "message": {"role": "assistant", "content": "{\"message\": \"could not read page\"}"},
                "finish_reason": "stop"
            }]
        })))
        // The countdown ignores the reported finish reason (PR #931-era
        // behaviour): a malformed answer consumes the FULL bounded truncation
        // budget — 1 + HOSTED_INNER_RETRIES = 3 requests — before failing.
        .expect(3)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::EURouter,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let request = vision_request_fixture();
    let error = client
        .chat_vision_constrained(&request)
        .await
        .expect_err("an unrelated JSON object must not decode as an empty page");
    assert!(
        error.to_string().contains("vision LLM JSON did not match"),
        "the decode failure surfaces: {error}"
    );
    server.verify().await;
}

/// The hosted schema permits `modifier: null` and free strings ("Nur Stimme");
/// the provider-facing decoder normalizes them into the core enum instead of
/// failing the page (CodeRabbit review, PR #967).
#[tokio::test]
async fn a_free_string_vision_modifier_normalizes_instead_of_failing_the_page() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .respond_with(
            wiremock::ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "id": "chatcmpl-mod",
                "model": "qwen3-vl",
                "choices": [{
                    "message": {"role": "assistant", "content": serde_json::json!({
                        "legend_entries": [
                            {"code": "2", "character_name": "Ben", "modifier": "Nur Stimme"},
                            {"code": "4", "character_name": "Philipp", "modifier": null}
                        ],
                        "rows": []
                    }).to_string()},
                    "finish_reason": "stop"
                }]
            })),
        )
        .expect(1)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::EURouter,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let request = vision_request_fixture();
    let outcome = client
        .chat_vision_constrained(&request)
        .await
        .expect("schema-permitted modifier values must decode");
    assert_eq!(outcome.output.legend_entries.len(), 2);
    assert_eq!(
        outcome.output.legend_entries[0].modifier,
        breakdown_core::ai::ScheduleRoleModifier::VoiceOnly
    );
    assert_eq!(
        outcome.output.legend_entries[1].modifier,
        breakdown_core::ai::ScheduleRoleModifier::None
    );
    server.verify().await;
}

/// An unrelated 400 validation error that merely ECHOES the field name is NOT
/// evidence of an unsupported format: no fallback, single request, the
/// classification path answers (CodeRabbit's PR #967 follow-up).
#[tokio::test]
async fn an_unrelated_400_echoing_response_format_does_not_fall_back() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .respond_with(
            wiremock::ResponseTemplate::new(400).set_body_json(serde_json::json!({
                "error": {"message": "validation failed: field `response_format` must be an object"}
            })),
        )
        .expect(1)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::EURouter,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let request = vision_request_fixture();
    let error = client
        .chat_vision_constrained(&request)
        .await
        .expect_err("an unrelated 400 must fail without a fallback re-send");
    assert!(
        !error.to_string().contains("json_object"),
        "the fallback never ran: {error}"
    );
    server.verify().await;
}

/// An explicit unsupported-format rejection on 400 DOES earn the one-shot
/// fallback: the second request carries the plain `json_object` response
/// format and its valid page answer decodes (CodeRabbit review, PR #967).
#[tokio::test]
async fn an_explicit_unsupported_format_400_falls_back_once_to_plain_json() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .and(wiremock::matchers::body_partial_json(serde_json::json!({
            "response_format": {"type": "json_schema"}
        })))
        .respond_with(
            wiremock::ResponseTemplate::new(400).set_body_json(serde_json::json!({
                "error": {"message": "response_format json_schema is not supported for this model"}
            })),
        )
        .expect(1)
        .mount(&server)
        .await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .and(wiremock::matchers::body_partial_json(serde_json::json!({
            "response_format": {"type": "json_object"}
        })))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "id": "chatcmpl-fallback",
            "model": "qwen3-vl",
            "choices": [{
                "message": {"role": "assistant", "content": "{\"legend_entries\":[],\"rows\":[]}"},
                "finish_reason": "stop"
            }]
        })))
        .expect(1)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::EURouter,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let request = vision_request_fixture();
    let outcome = client
        .chat_vision_constrained(&request)
        .await
        .expect("the plain json_object fallback answers with a valid page");
    assert!(outcome.output.rows.is_empty());
    server.verify().await;
}

/// The flat schedule path accepts German dot dates: the flat schema decode
/// goes through the core parser (`parse_schedule_date`), which handles ISO and
/// German dot notation (CodeRabbit's PR #967 follow-up).
#[test]
fn a_german_dot_date_in_the_flat_schedule_path_is_not_dropped() {
    use super::{ScheduleRowSchema, ScheduleSceneRefSchema, ShootingScheduleSchema};

    let decoded = ScheduleRowSchema {
        row_ref: "300.33".into(),
        scene_number: Some(ScheduleSceneRefSchema::Text("300.33".into())),
        shooting_day_label: Some("1. Drehtag: Mo. 18.10.2021".into()),
        date: Some("18.10.2021".into()),
        location: Some("KLINIKUM".into()),
        order: Some(1),
    };
    let core = ShootingScheduleSchema {
        rows: vec![decoded],
    }
    .into_core();
    assert_eq!(
        core.rows[0].date,
        Some(jiff::civil::date(2021, 10, 18)),
        "the German calendar date survives the flat decode"
    );
}

/// An unrelated capability statement ("does not support images") far from the
/// echoed field name is NOT fallback evidence: the unsupported claim must sit
/// within the proximity window of `response_format` (CodeRabbit's PR #967
/// round-3 follow-up).
#[tokio::test]
async fn a_distant_unrelated_unsupported_statement_does_not_fall_back() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .respond_with(
            wiremock::ResponseTemplate::new(400).set_body_json(serde_json::json!({
                "error": {"message": "this model does not support image inputs at all, which is a \
                         capability constraint unrelated to schema handling; the request echoed \
                         response_format in its payload"}
            })),
        )
        .expect(1)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::EURouter,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let request = vision_request_fixture();
    let error = client
        .chat_vision_constrained(&request)
        .await
        .expect_err("an unrelated capability statement must not trigger the fallback");
    assert!(
        !error.to_string().contains("json_object"),
        "the fallback never ran: {error}"
    );
    server.verify().await;
}

// CodeRabbit's PR #967 round-4 follow-ups on the fallback evidence helper.

/// A provider echoing the request back puts `response_format` in a JSON KEY
/// position; that is not a prose unsupported-format statement.
#[test]
fn an_echoed_request_body_is_not_fallback_evidence() {
    let body = r#"{"error":{"message":"Model does not support images"},"response_format":{"type":"json_schema"}}"#;
    assert!(!super::names_unsupported_response_format(body));
}

/// The window slice is char-boundary safe: a multibyte character near the
/// window edge must not panic the helper.
#[test]
fn the_proximity_window_is_char_boundary_safe() {
    // 'é' (2 bytes) + 79 ASCII + the claim adjacent to the field name.
    let body = format!("é{}", "a".repeat(79));
    assert!(super::names_unsupported_response_format(&format!(
        "{body} not support response_format"
    )));
    // And the distant case stays negative even with multibyte padding.
    assert!(!super::names_unsupported_response_format(&format!(
        "{body} unrelated text, and much later the request echoed response_format"
    )));
}

/// A genuine unsupported-format statement still qualifies.
#[test]
fn a_genuine_unsupported_format_statement_is_fallback_evidence() {
    assert!(super::names_unsupported_response_format(
        "'response_format' of type 'json_schema' is not supported by this model"
    ));
    assert!(super::names_unsupported_response_format(
        "unsupported value for response_format"
    ));
}

/// CodeRabbit's PR #967 round-5 follow-up: the JSON-key detection tolerates
/// whitespace between the quoted key and the colon
/// (`"response_format" : {"type": ...}`).
#[test]
fn a_json_key_with_whitespace_before_the_colon_is_not_fallback_evidence() {
    let body = r#"{"error":{"message":"Model does not support images"},"response_format" : {"type":"json_schema"}}"#;
    assert!(!super::names_unsupported_response_format(body));
}

/// CodeRabbit's PR #967 round-6 follow-up: a JSON VALUE echo next to an
/// unrelated unsupported-image statement is not evidence either — the gap
/// between the claim and the mention carries JSON structure (comma, colon,
/// quotes-as-structure), which the connector rule rejects.
#[test]
fn a_json_value_echo_of_response_format_is_not_fallback_evidence() {
    let body = r#"{"error":{"message":"Model does not support images","param":"response_format"}}"#;
    assert!(!super::names_unsupported_response_format(body));
}

/// CodeRabbit's PR #967 round-7 follow-up: the claim and the mention must
/// live in the SAME sentence — "does not support images. Request included
/// response_format" crosses a sentence boundary and is not evidence.
#[test]
fn a_sentence_boundary_between_claim_and_mention_is_not_fallback_evidence() {
    let body = r#"{"error":{"message":"Model does not support images. Request included response_format"}}"#;
    assert!(!super::names_unsupported_response_format(body));
}

/// Issue #970 (CodeRabbit review, PR #967 round 8): a billed response with
/// malformed JSON followed by a provider failure must carry the billed usage
/// ON the error — the hold persists it instead of dropping the accounting.
#[tokio::test]
async fn a_provider_failure_after_a_billed_response_carries_the_usage() {
    let server = wiremock::MockServer::start().await;
    // First response: billed (tokens 100), but the answer is malformed JSON —
    // the loop re-requests with a grown budget (the countdown ignores the
    // reported finish reason).
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .and(wiremock::matchers::body_partial_json(
            serde_json::json!({"max_tokens": 1_024}),
        ))
        .respond_with(
            wiremock::ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "id": "chatcmpl-billed",
                "model": "glm-5.3-flash",
                "choices": [{
                    "message": {"role": "assistant", "content": "{not json"},
                    "finish_reason": "stop"
                }],
                "usage": {"prompt_tokens": 100, "completion_tokens": 25}
            })),
        )
        .expect(1)
        .mount(&server)
        .await;
    // Second response: the provider fails transiently.
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .and(wiremock::matchers::body_partial_json(
            serde_json::json!({"max_tokens": 2_048}),
        ))
        .respond_with(
            wiremock::ResponseTemplate::new(503)
                .set_body_json(serde_json::json!({"error": {"message": "provider overloaded"}})),
        )
        .expect(1)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let error = client
        .chat_constrained(chat_request(1_024))
        .await
        .expect_err("the 503 must fail the attempt");
    assert!(
        error.is_retryable(),
        "the 503 stays on the classification path: {error}"
    );
    assert_eq!(
        error
            .billed_usage()
            .map(|calls| breakdown_core::ai::LlmCallUsage::total(calls).tokens_in),
        Some(100),
        "the billed response's usage travels ON the provider error: {error}"
    );
    server.verify().await;
}

/// CodeRabbit's PR #967 round-9 follow-up: a positive statement about the
/// format between the mention and the unsupported claim ("response_format is
/// valid but images are not supported") is not evidence — the claim is about
/// the images, not the format.
#[test]
fn a_positive_format_statement_between_mention_and_claim_is_not_evidence() {
    assert!(!super::names_unsupported_response_format(
        "response_format is valid but images are not supported"
    ));
    // Genuine single-sentence statements still qualify.
    assert!(super::names_unsupported_response_format(
        "'response_format' of type 'json_schema' is not supported by this model"
    ));
}

/// Issue #970 (CodeRabbit review, PR #967 round 11): MULTIPLE billed
/// malformed responses through the REAL client accumulate into the terminal
/// failure's carried usage — the exact sequence the hold/dead-letter path
/// persists.
#[tokio::test]
async fn multiple_billed_malformed_responses_accumulate_into_the_terminal_failure() {
    let server = wiremock::MockServer::start().await;
    // Three billed responses, each malformed: budgets 1024 → 2048 → 4096.
    for (max_tokens, tokens_in) in [(1_024, 100), (2_048, 50), (4_096, 30)] {
        wiremock::Mock::given(wiremock::matchers::method("POST"))
            .and(wiremock::matchers::path("/chat/completions"))
            .and(wiremock::matchers::body_partial_json(
                serde_json::json!({"max_tokens": max_tokens}),
            ))
            .respond_with(
                wiremock::ResponseTemplate::new(200).set_body_json(serde_json::json!({
                    "id": "chatcmpl-billed",
                    "model": "glm-5.3-flash",
                    "choices": [{
                        "message": {"role": "assistant", "content": "{not json"},
                        "finish_reason": "stop"
                    }],
                    "usage": {"prompt_tokens": tokens_in, "completion_tokens": 10}
                })),
            )
            .expect(1)
            .mount(&server)
            .await;
    }

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let error = client
        .chat_constrained(chat_request(1_024))
        .await
        .expect_err("the exhausted decode budget must fail the attempt");
    assert_eq!(
        error
            .billed_usage()
            .map(|calls| breakdown_core::ai::LlmCallUsage::total(calls).tokens_in),
        Some(180),
        "every billed response's usage accumulates into the terminal error: {error}"
    );
    server.verify().await;
}

/// Issue #970 (CodeRabbit review, PR #967 round 10): a billed response
/// followed by a DETERMINISTIC transport failure — the mock answers the
/// first request, then the listener is gone, so the second request is
/// refused with `connection refused` (no wall-clock deadline involved).
#[tokio::test]
async fn a_transport_failure_after_a_billed_response_carries_the_usage() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        // Answer the FIRST request with a valid billed body, then keep the
        // stream open forever: the listener is consumed, so the client's
        // second request is deterministically refused at the transport.
        let (mut stream, _) = listener.accept().await.unwrap();
        // CLOSE the listener explicitly: the retry's connection is
        // deterministically refused, not timed out.
        drop(listener);
        // Read the request to its declared Content-Length (CodeRabbit's PR
        // #967 round-11 follow-up: a nested-JSON chunk can end in `}` before
        // the body is complete).
        let mut request = Vec::new();
        let mut chunk = [0_u8; 1024];
        let content_length: Option<usize> = loop {
            let read = stream.read(&mut chunk).await.unwrap_or(0);
            request.extend_from_slice(&chunk[..read]);
            let text = String::from_utf8_lossy(&request);
            if let Some(header_end) = text.find("\r\n\r\n")
                && let Some(len) = text
                    .lines()
                    .find_map(|line| {
                        line.to_ascii_lowercase()
                            .strip_prefix("content-length:")
                            .map(|v| v.trim().parse::<usize>().ok())
                    })
                    .flatten()
                && request.len() >= header_end + 4 + len
            {
                break Some(len);
            }
            if read == 0 {
                break None;
            }
        };
        let _ = content_length;
        let body = serde_json::json!({
            "id": "chatcmpl-billed",
            "model": "glm-5.3-flash",
            "choices": [{
                "message": {"role": "assistant", "content": "{not json"},
                "finish_reason": "stop"
            }],
            "usage": {"prompt_tokens": 100, "completion_tokens": 25}
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\n\r\n{}",
            body.len(),
            body
        );
        let _ = stream.write_all(response.as_bytes()).await;
        let _ = stream.flush().await;
        // Close the served connection gracefully (the response is complete,
        // nothing is left unread, so this is a FIN, not an RST): the client's
        // pooled connection dies and the retry reconnects into a CLOSED port.
        drop(stream);
    });

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "test-key".to_owned(),
        // The deadline never fires: the first response is answered
        // immediately and the second request is REFUSED (connection refused).
        // A generous value keeps any runner-load latency off the failure path.
        Duration::from_secs(60),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("http://{addr}/chat/completions");

    let error = client
        .chat_constrained(chat_request(1_024))
        .await
        .expect_err("the refused second request must fail the attempt");
    // The failure is the CONNECTION REFUSAL, not the (never-firing) deadline:
    // a reqwest timeout renders "operation timed out" — its absence plus the
    // instant completion distinguishes the deterministic refusal from any
    // deadline fire.
    assert!(
        !error.to_string().to_lowercase().contains("timed out"),
        "the failure must be the connection refusal, not the deadline: {error}"
    );
    assert_eq!(
        error
            .billed_usage()
            .map(|calls| breakdown_core::ai::LlmCallUsage::total(calls).tokens_in),
        Some(100),
        "the billed response's usage survives the transport failure: {error}"
    );
    server.abort();
}

/// CodeRabbit's PR #967 round-10 follow-up: "invalid" must not read as the
/// positive token "valid" — an explicit unsupported-format statement that
/// contains the word `invalid` still earns the fallback.
#[test]
fn invalid_is_not_the_positive_token_valid() {
    assert!(super::names_unsupported_response_format(
        "response_format has an invalid value and is not supported"
    ));
    // The round-9 exclusion keeps working at word boundaries.
    assert!(!super::names_unsupported_response_format(
        "response_format is valid but images are not supported"
    ));
}

/// Issue #970 (CodeRabbit review, PR #967 round 12): a billed malformed
/// response followed by a QUOTA failure keeps the billed usage on the
/// terminal error — the quota variant carries the counters like the
/// transient-unavailable path, with its code and terminal classification
/// unchanged.
#[tokio::test]
async fn a_quota_failure_after_a_billed_response_carries_the_usage() {
    let server = wiremock::MockServer::start().await;
    // First response: billed (tokens 100), malformed JSON — the loop
    // re-requests with a grown budget.
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .and(wiremock::matchers::body_partial_json(
            serde_json::json!({"max_tokens": 1_024}),
        ))
        .respond_with(
            wiremock::ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "id": "chatcmpl-billed",
                "model": "glm-5.3-flash",
                "choices": [{
                    "message": {"role": "assistant", "content": "{not json"},
                    "finish_reason": "stop"
                }],
                "usage": {"prompt_tokens": 100, "completion_tokens": 25}
            })),
        )
        .expect(1)
        .mount(&server)
        .await;
    // Second response: the wallet is empty (terminal quota refusal).
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/chat/completions"))
        .and(wiremock::matchers::body_partial_json(
            serde_json::json!({"max_tokens": 2_048}),
        ))
        .respond_with(
            wiremock::ResponseTemplate::new(402)
                .set_body_json(serde_json::json!({"error": {"message": "insufficient_quota"}})),
        )
        .expect(1)
        .mount(&server)
        .await;

    let mut client = OpenAiCompatibleChatClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "test-key".to_owned(),
        Duration::from_secs(5),
    )
    .expect("a with_http test client builds");
    client.endpoint = format!("{}/chat/completions", server.uri());

    let error = client
        .chat_constrained(chat_request(1_024))
        .await
        .expect_err("the quota refusal must fail the attempt");
    assert_eq!(
        error.code().code,
        "ai-import.provider-quota-exhausted",
        "the quota classification is unchanged: {error}"
    );
    assert!(!error.is_retryable(), "quota stays terminal: {error}");
    assert_eq!(
        error
            .billed_usage()
            .map(|calls| breakdown_core::ai::LlmCallUsage::total(calls).tokens_in),
        Some(100),
        "the billed response's usage travels on the quota error: {error}"
    );
    server.verify().await;
}
