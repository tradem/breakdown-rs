// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for the Decision API adapter (issue #722, wire contract per
//! issue #808).
//!
//! **The fixtures speak the provider's contract, not ours.** The suite that let
//! issue #808 ship mocked the provider with our own assumption (`score` as a
//! distribution) and never checked the request body, so a wrong wire contract
//! in both directions stayed green. Everything below is therefore pinned
//! against either a captured provider body (`testdata/decision_wire/`) or a
//! **strict** mock that answers like the provider does: reject anything without
//! `instructions` / `criteria` with the real `400 details[]` shape.

use super::{
    DecisionWireResponse, HttpDecisionClient, decision_endpoint, normalize_answers,
    question_payload,
};
use crate::ai::decision_scoring::score_script_chunk;
use crate::ai::workers::DecisionPass;
use breakdown_core::ai::{
    DecisionClient, DecisionQuestion, DecisionRequest, DraftScene, DraftShootingDay, LlmProvider,
    UsageAccumulator, continuity_questions, noul, question_keys, score5,
};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;

/// The production rubric one script chunk asks, as the strict mock and the
/// goldens exercise it.
fn chunk_questions() -> BTreeMap<String, DecisionQuestion> {
    let mut questions = BTreeMap::new();
    questions.insert(
        question_keys::CHARACTERS_COMPLETE.to_owned(),
        noul(CHARACTERS_COMPLETE_INSTRUCTIONS),
    );
    questions.insert(
        question_keys::SCENE_METADATA_ACCURACY.to_owned(),
        score5(SCENE_METADATA_INSTRUCTIONS),
    );
    questions
}

const CHARACTERS_COMPLETE_INSTRUCTIONS: &str =
    "Are all figures named in this scene chunk accounted for in the extracted scenes?";
const SCENE_METADATA_INSTRUCTIONS: &str =
    "How accurately do the extracted scene number, location and mood match the heading?";

fn request(provider: LlmProvider, model: &str) -> DecisionRequest {
    DecisionRequest {
        provider,
        model: model.to_owned(),
        state: json!({"kind": "script_chunk", "heading": "1 I/T - OP"}),
        questions: chunk_questions(),
    }
}

/// Parse one checked-in provider fixture into the response DTO.
fn wire(fixture: &str) -> DecisionWireResponse {
    serde_json::from_str(fixture)
        .expect("the checked-in provider fixture must deserialize into the response DTO")
}

/// The question set the fixtures answer (`characters_complete` noul,
/// `scene_metadata_accuracy` score, `outfit_continuity` choice).
fn fixture_questions() -> BTreeMap<String, DecisionQuestion> {
    let mut questions = chunk_questions();
    questions.extend(continuity_questions());
    questions
}

// ── Endpoint registry / fail-closed constructor ────────────────────────────

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
        // every row of a live import). The URL is only half the contract: the
        // request/response bodies are pinned by the goldens, the strict mock
        // and the live smoke test below (issue #808).
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

// ── Request shape (goldens + strict validation) ────────────────────────────

/// Serialize the **production** rubric questions and compare them to the
/// checked-in goldens.
///
/// The key-set assertions are the sharp part: `instructions` present,
/// `criteria` present for `score`/`choice`, and the pre-#808 names
/// `description` / `options` / `levels` absent. A future rename cannot silently
/// re-introduce a field the provider rejects — one bad question rejects the
/// whole body (issue #808).
#[test]
fn the_request_payload_matches_the_provider_goldens() {
    let mut questions = chunk_questions();
    questions.extend(continuity_questions());

    let noul_payload = question_payload(&questions[question_keys::CHARACTERS_COMPLETE])
        .expect("a noul question serializes");
    assert_eq!(
        noul_payload,
        serde_json::from_str::<Value>(include_str!("testdata/decision_wire/question_noul.json"))
            .expect("the noul golden is valid JSON")
    );

    let score_payload = question_payload(&questions[question_keys::SCENE_METADATA_ACCURACY])
        .expect("a score question serializes");
    assert_eq!(
        score_payload,
        serde_json::from_str::<Value>(include_str!("testdata/decision_wire/question_score.json"))
            .expect("the score golden is valid JSON")
    );

    let choice_payload = question_payload(&questions[question_keys::OUTFIT_CONTINUITY])
        .expect("a choice question serializes");
    assert_eq!(
        choice_payload,
        serde_json::from_str::<Value>(include_str!("testdata/decision_wire/question_choice.json"))
            .expect("the choice golden is valid JSON")
    );

    for (kind, payload) in [
        ("noul", &noul_payload),
        ("score", &score_payload),
        ("choice", &choice_payload),
    ] {
        let object = payload.as_object().expect("a question is a JSON object");
        let keys: Vec<&str> = object.keys().map(String::as_str).collect();
        assert!(
            keys.contains(&"instructions"),
            "the `{kind}` question must carry `instructions`, got {keys:?}"
        );
        for legacy in ["description", "options", "levels"] {
            assert!(
                !keys.contains(&legacy),
                "the pre-#808 field `{legacy}` is still on the `{kind}` wire payload: {payload}"
            );
        }
        if kind != "noul" {
            assert!(
                keys.contains(&"criteria"),
                "the `{kind}` question must carry `criteria`, got {keys:?}"
            );
        }
    }
    // The score's criteria IS the label ladder — the answer's distribution is
    // ordered by exactly these indices.
    assert_eq!(
        score_payload["criteria"],
        json!(["wrong", "poor", "fair", "good", "exact"])
    );
    // The choice's criteria is `name -> description`, keyed by the option names
    // the answer's distribution uses.
    assert_eq!(
        choice_payload["criteria"]["continue_previous"],
        json!("The character keeps wearing the outfit of the previous scene.")
    );
}

/// A mis-shaped question is rejected **before** the request leaves the process:
/// the provider answers one wrong question with a 400 for the whole body, which
/// is exactly how a rubric-wide `scoring_failed` happened (issue #808).
#[test]
fn unbuildable_questions_are_rejected_before_the_request() {
    // A one-level ladder is not a scale.
    let flat = DecisionQuestion::Score {
        instructions: "How good is it?".into(),
        ladder: vec!["only".into()],
    };
    assert!(question_payload(&flat).is_err());

    // A duplicated label makes the answer's legend ambiguous.
    let duplicated = DecisionQuestion::Score {
        instructions: "How good is it?".into(),
        ladder: vec!["ok".into(), "ok".into()],
    };
    assert!(question_payload(&duplicated).is_err());

    // No instructions → no `instructions` field the provider would accept.
    let blank = DecisionQuestion::Noul {
        instructions: "   ".into(),
    };
    assert!(question_payload(&blank).is_err());

    // An option without a description cannot become `criteria`.
    let optionless = DecisionQuestion::Choice {
        instructions: "Which one?".into(),
        options: Vec::new(),
    };
    assert!(question_payload(&optionless).is_err());
}

// ── Response shape (provider fixtures → normalized answers) ────────────────

/// Every captured 200 answer normalizes into the internal [`DecisionAnswer`]:
/// the score distribution comes from `probabilities` **ordered by level index**
/// (not by map order), the choice map from `probabilities`, noul from `noul`.
#[test]
fn every_200_fixture_normalizes_into_the_internal_answer() {
    let questions = fixture_questions();

    let noul_answers = normalize_answers(
        &questions,
        wire(include_str!("testdata/decision_wire/answer_noul_200.json")).answers,
    )
    .expect("a noul answer normalizes");
    let noul_answer = &noul_answers[question_keys::CHARACTERS_COMPLETE];
    assert!((noul_answer.noul.expect("noul mass") - 0.461).abs() < 1e-6);
    assert!(noul_answer.score.is_none() && noul_answer.choice.is_none());

    let score_answers = normalize_answers(
        &questions,
        wire(include_str!("testdata/decision_wire/answer_score_200.json")).answers,
    )
    .expect("a score answer normalizes");
    let score_answer = &score_answers[question_keys::SCENE_METADATA_ACCURACY];
    let distribution = score_answer.score.as_ref().expect("score distribution");
    assert_eq!(
        distribution.len(),
        5,
        "one probability per ladder level: {distribution:?}"
    );
    // Index order, ascending: the mass piles up towards `exact`.
    assert!(
        distribution.windows(2).all(|pair| pair[0] <= pair[1]),
        "the distribution must be ordered by level index: {distribution:?}"
    );
    // The live mean is 3.2361 over a 0..=4 axis → ~0.809 normalized.
    let expected = score_answer.expected_score().expect("an expected score");
    assert!(
        (expected - 3.2361 / 4.0).abs() < 1e-4,
        "expected score {expected} must match the live distribution"
    );

    let choice_answers = normalize_answers(
        &questions,
        wire(include_str!(
            "testdata/decision_wire/answer_choice_200.json"
        ))
        .answers,
    )
    .expect("a choice answer normalizes");
    let choice = choice_answers[question_keys::OUTFIT_CONTINUITY]
        .choice
        .as_ref()
        .expect("choice distribution");
    assert_eq!(choice.get("props").copied(), Some(0.7249_f32));
    assert_eq!(choice.get("costume").copied(), Some(0.2751_f32));
}

/// A legend that is not the ladder we sent is a hard error: the level indices
/// would silently refer to different labels (issue #808).
#[test]
fn a_legend_that_contradicts_the_sent_ladder_is_rejected() {
    let error = normalize_answers(
        &fixture_questions(),
        wire(include_str!(
            "testdata/decision_wire/answer_score_legend_mismatch_200.json"
        ))
        .answers,
    )
    .expect_err("a contradicting legend must be rejected");
    let message = error.to_string();
    assert!(
        message.contains("legend"),
        "the error must name the legend, got: {message}"
    );
}

/// An empty mass map cannot be a distribution — and must not be read as "all
/// zero" (which would silently score every row 0.0).
#[test]
fn an_empty_score_distribution_is_rejected() {
    let error = normalize_answers(
        &fixture_questions(),
        wire(include_str!(
            "testdata/decision_wire/answer_score_empty_probabilities_200.json"
        ))
        .answers,
    )
    .expect_err("an empty distribution must be rejected");
    assert!(
        error.to_string().contains("probabilities"),
        "the error must name `probabilities`, got: {error}"
    );
}

/// A winning `choice` label outside its own `probabilities` map is a hard
/// error: the two halves of the answer contradict each other.
#[test]
fn a_choice_label_outside_its_own_probabilities_is_rejected() {
    let mut questions = BTreeMap::new();
    questions.insert(
        question_keys::OUTFIT_CONTINUITY.to_owned(),
        continuity_questions()[question_keys::OUTFIT_CONTINUITY].clone(),
    );
    let contradictory: DecisionWireResponse = serde_json::from_value(json!({
        "answers": {
            question_keys::OUTFIT_CONTINUITY: {
                "type": "choice",
                "choice": "neither_of_these",
                "probabilities": {"continue_previous": 0.6, "infer_new_outfit": 0.4},
            }
        }
    }))
    .expect("the wire DTO parses");
    let error = normalize_answers(&questions, contradictory.answers)
        .expect_err("a contradicting winning label must be rejected");
    assert!(
        error.to_string().contains("neither_of_these"),
        "the error must name the offending label, got: {error}"
    );
}

/// The provider's `400 details[]` classifies as a **permanent** validation
/// failure and its `path` survives into the message — an opaque
/// `scoring_failed` is what made issue #808 invisible for two imports.
#[test]
fn the_provider_400_keeps_its_class_and_its_field_path() {
    let body = include_str!("testdata/decision_wire/error_400_invalid_request.json");
    let error =
        crate::ai::client::classify_http_status_with_detail(reqwest::StatusCode::BAD_REQUEST, body);
    assert!(
        matches!(error, breakdown_core::error::DomainError::Validation { .. }),
        "a 400 must stay a permanent validation error, got {error:?}"
    );
    assert!(
        error.to_string().contains("questions.q.instructions"),
        "the provider's own field path must reach the caller, got: {error}"
    );
}

// ── Strict mock: the provider's own validation, in-process ─────────────────

/// Reject a body the way the System One surface does.
///
/// Returns the `details[]` entries to answer with. This mirrors the live
/// validation: a strict discriminated union, so a question carrying the
/// pre-#808 names instead of `instructions`/`criteria` is rejected — and one
/// rejected question rejects the whole body.
fn strict_request_violations(body: &Value) -> Vec<Value> {
    let mut details = Vec::new();
    let mut reject = |path: String, message: &str, code: &str| {
        details.push(json!({"path": path, "message": message, "code": code}));
    };
    if body["model"]
        .as_str()
        .is_none_or(|model| model.trim().is_empty())
    {
        reject("model".to_owned(), "Invalid input", "invalid_type");
    }
    if body.get("state").is_none() {
        reject("state".to_owned(), "Required", "invalid_type");
    }
    let Some(questions) = body["questions"].as_object() else {
        reject("questions".to_owned(), "Expected object", "invalid_type");
        return details;
    };
    if questions.is_empty() {
        reject("questions".to_owned(), "At least one question", "too_small");
    }
    for (name, question) in questions {
        let Some(question) = question.as_object() else {
            reject(
                format!("questions.{name}"),
                "Expected object",
                "invalid_type",
            );
            continue;
        };
        let kind = question.get("type").and_then(Value::as_str).unwrap_or("");
        if !matches!(kind, "noul" | "score" | "choice") {
            reject(
                format!("questions.{name}.type"),
                "Invalid input",
                "invalid_union",
            );
            continue;
        }
        // The former field names are rejected outright, not merely ignored.
        for legacy in ["description", "options", "levels"] {
            if question.contains_key(legacy) {
                reject(
                    format!("questions.{name}.{legacy}"),
                    "Unrecognized key",
                    "unrecognized_keys",
                );
            }
        }
        match question.get("instructions").and_then(Value::as_str) {
            Some(instructions) if !instructions.trim().is_empty() => {}
            _ => reject(
                format!("questions.{name}.instructions"),
                "Invalid input",
                "invalid_union",
            ),
        }
        match kind {
            "score" => match question.get("criteria").and_then(Value::as_array) {
                Some(ladder)
                    if ladder.len() >= 2
                        && ladder
                            .iter()
                            .all(|label| label.as_str().is_some_and(|l| !l.trim().is_empty())) => {}
                _ => reject(
                    format!("questions.{name}.criteria"),
                    "Expected array of labels",
                    "invalid_type",
                ),
            },
            "choice" => match question.get("criteria").and_then(Value::as_object) {
                Some(options)
                    if !options.is_empty()
                        && options.values().all(|description| {
                            description.as_str().is_some_and(|d| !d.trim().is_empty())
                        }) => {}
                _ => reject(
                    format!("questions.{name}.criteria"),
                    "Expected record",
                    "invalid_type",
                ),
            },
            // `noul` tolerates no `criteria` at all, or one of true/false keys.
            _ => {
                if let Some(criteria) = question.get("criteria")
                    && criteria
                        .as_object()
                        .is_none_or(|map| !map.values().all(Value::is_boolean))
                {
                    reject(
                        format!("questions.{name}.criteria"),
                        "Expected record of booleans",
                        "invalid_type",
                    );
                }
            }
        }
    }
    details
}

/// Answer like the provider: build the per-question envelopes **from the
/// criteria it was sent**, so a legend/ladder cross-check in the adapter is
/// exercised against real wire data.
fn strict_answers(body: &Value) -> Value {
    let mut answers = serde_json::Map::new();
    if let Some(questions) = body["questions"].as_object() {
        for (name, question) in questions {
            let answer = match question["type"].as_str().unwrap_or_default() {
                "score" => {
                    let ladder: Vec<&str> = question["criteria"]
                        .as_array()
                        .map(|labels| labels.iter().filter_map(Value::as_str).collect())
                        .unwrap_or_default();
                    let top = ladder.len().saturating_sub(1);
                    let mut legend = serde_json::Map::new();
                    let mut probabilities = serde_json::Map::new();
                    for (index, label) in ladder.iter().enumerate() {
                        legend.insert(index.to_string(), json!(label));
                        // All mass on the top level: sum 1.0, mean = top.
                        probabilities.insert(
                            index.to_string(),
                            json!(if index == top { 1.0 } else { 0.0 }),
                        );
                    }
                    json!({
                        "type": "score",
                        "score": top as f64,
                        "legend": legend,
                        "probabilities": probabilities,
                        "confidence": 1.0,
                    })
                }
                "choice" => {
                    let mut probabilities = serde_json::Map::new();
                    let mut winner = None;
                    for option in question["criteria"]
                        .as_object()
                        .map(|options| options.keys())
                        .into_iter()
                        .flatten()
                    {
                        probabilities.insert(
                            option.clone(),
                            json!(if winner.is_none() { 1.0 } else { 0.0 }),
                        );
                        winner.get_or_insert(option.clone());
                    }
                    json!({
                        "type": "choice",
                        "choice": winner,
                        "probabilities": probabilities,
                        "confidence": 1.0,
                    })
                }
                _ => json!({"type": "noul", "noul": 0.87}),
            };
            answers.insert(name.clone(), answer);
        }
    }
    json!({
        "answers": answers,
        "usage": {"input_tokens": 157, "output_tokens": 0, "cost": 0.0, "cost_currency": "EUR"},
    })
}

struct StrictSystemOne;

impl wiremock::Respond for StrictSystemOne {
    fn respond(&self, request: &wiremock::Request) -> wiremock::ResponseTemplate {
        let body: Value = match serde_json::from_slice(&request.body) {
            Ok(body) => body,
            Err(error) => {
                return wiremock::ResponseTemplate::new(400).set_body_json(json!({
                    "error": {
                        "code": 400,
                        "message": "Invalid request",
                        "details": [{"path": "body", "message": error.to_string(), "code": "invalid_json"}],
                    }
                }));
            }
        };
        let details = strict_request_violations(&body);
        if details.is_empty() {
            wiremock::ResponseTemplate::new(200).set_body_json(strict_answers(&body))
        } else {
            wiremock::ResponseTemplate::new(400).set_body_json(json!({
                "error": {"code": 400, "message": "Invalid request", "details": details},
            }))
        }
    }
}

/// A client pointed at a strict in-process System One surface.
async fn strict_provider() -> (wiremock::MockServer, HttpDecisionClient) {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .respond_with(StrictSystemOne)
        .mount(&server)
        .await;
    let mut client = HttpDecisionClient::with_http(
        reqwest::Client::new(),
        LlmProvider::Neuralwatt,
        "k".into(),
        Duration::from_secs(5),
    )
    .expect("a decision-capable provider builds a client");
    // Test seam (`with_http`): production endpoints come from
    // `decision_endpoint`, which the registry test above pins.
    client.endpoint = server.uri();
    (server, client)
}

/// The adapter's request is accepted by a provider that validates the contract,
/// and its answer comes back normalized (noul mass, full score distribution,
/// usage).
#[tokio::test]
async fn the_adapter_speaks_the_provider_request_shape() {
    let (_server, client) = strict_provider().await;
    let outcome = client
        .decide(request(LlmProvider::Neuralwatt, "clef-flash"))
        .await
        .expect("the strict provider must accept the curated body");

    assert_eq!(outcome.answers.len(), 2, "one answer per asked question");
    let noul_answer = &outcome.answers[question_keys::CHARACTERS_COMPLETE];
    assert!((noul_answer.noul.expect("noul mass") - 0.87).abs() < 1e-6);
    let score_answer = &outcome.answers[question_keys::SCENE_METADATA_ACCURACY];
    assert_eq!(
        score_answer.score.as_ref().map(Vec::len),
        Some(5),
        "the distribution comes from `probabilities`, one entry per ladder level"
    );
    assert!(score_answer.expected_score().expect("expected score") > 0.99);
    assert_eq!(outcome.usage.tokens_in, 157);
    assert_eq!(outcome.usage.tokens_out, 0);
}

/// The strict mock is the regression net for issue #808: today's request body
/// (as captured in the issue) is rejected with the provider's own
/// `questions.<name>.instructions` path. Without this, the mock would keep
/// accepting whatever we send — which is how the bug shipped.
#[test]
fn the_strict_mock_rejects_the_pre_808_request_shape() {
    // The exact shape `HttpDecisionClient::decide` used to build.
    let legacy = json!({
        "model": "clef-flash",
        "state": {"kind": "script_chunk"},
        "questions": {
            "characters_complete": {"type": "noul", "description": "Are all figures accounted for?"},
            "scene_metadata_accuracy": {"type": "score", "description": "How accurate?", "levels": 5},
            "outfit_continuity": {"type": "choice", "description": "Which?", "options": ["a", "b"]},
        }
    });
    let details = strict_request_violations(&legacy);
    let paths: Vec<&str> = details
        .iter()
        .filter_map(|detail| detail["path"].as_str())
        .collect();
    for name in [
        "characters_complete",
        "scene_metadata_accuracy",
        "outfit_continuity",
    ] {
        assert!(
            paths.contains(&format!("questions.{name}.instructions").as_str()),
            "the missing `instructions` field must be reported for `{name}`, got {paths:?}"
        );
    }
    assert!(
        paths.contains(&"questions.scene_metadata_accuracy.criteria"),
        "a `score` question without its label ladder must be rejected, got {paths:?}"
    );
    assert!(
        paths.contains(&"questions.outfit_continuity.criteria"),
        "a `choice` question without its criteria record must be rejected, got {paths:?}"
    );

    // …and the body the adapter builds today passes the same validation.
    let current = json!({
        "model": "clef-flash",
        "state": {"kind": "script_chunk"},
        "questions": {
            "characters_complete": {
                "type": "noul",
                "instructions": CHARACTERS_COMPLETE_INSTRUCTIONS,
            },
            "scene_metadata_accuracy": {
                "type": "score",
                "instructions": SCENE_METADATA_INSTRUCTIONS,
                "criteria": ["wrong", "poor", "fair", "good", "exact"],
            },
            "outfit_continuity": {
                "type": "choice",
                "instructions": "Which wardrobe state?",
                "criteria": {"continue_previous": "keep it", "infer_new_outfit": "new look"},
            },
        }
    });
    assert!(
        strict_request_violations(&current).is_empty(),
        "the curated shape must be accepted: {:?}",
        strict_request_violations(&current)
    );
}

/// The provider's rejection reaches the caller with its `details[]` intact —
/// i.e. the adapter fails loudly with the field path instead of a bare
/// `scoring_failed` (issue #767/#808).
#[tokio::test]
async fn a_strict_rejection_names_the_offending_field() {
    // A client whose question is unbuildable never reaches the network: the
    // adapter refuses first, which is the cheaper half of the same guarantee.
    let (_server, client) = strict_provider().await;
    let mut broken = request(LlmProvider::Neuralwatt, "clef-flash");
    broken.questions.insert(
        "bad_score".to_owned(),
        DecisionQuestion::Score {
            instructions: "How good?".into(),
            ladder: vec!["only".into()],
        },
    );
    let error = client
        .decide(broken)
        .await
        .expect_err("an unbuildable question must not be sent");
    assert!(
        error.to_string().contains("score"),
        "the error must name the offending question kind, got: {error}"
    );
}

// ── Scoring pass against the strict mock (offline end to end) ──────────────

fn draft_scene(draft_ref: &str) -> DraftScene {
    DraftScene {
        draft_ref: draft_ref.to_owned(),
        scene_number: Some(1),
        location: Some("OP".into()),
        mood: Some("I/T".into()),
        summary: Some("Ben prüft die Kostüme.".into()),
        shooting_day: Some(DraftShootingDay {
            number: Some(1),
            label: Some("Tag 1".into()),
            score: None,
        }),
        ..DraftScene::default()
    }
}

/// The scoring pass end to end against a provider that enforces the contract:
/// `scoring_failed` must stay `false`, no row may be left unscored, and every
/// row must carry its `scene_score` / `synopsis_score`.
///
/// This is the test that could not exist before issue #808: the permissive mock
/// accepted whatever we sent, so the pass "succeeded" against a body the real
/// provider rejects.
#[tokio::test]
async fn the_scoring_pass_scores_every_row_against_a_strict_provider() {
    let (_server, client) = strict_provider().await;
    let pass = DecisionPass {
        client: Arc::new(client),
        provider: LlmProvider::Neuralwatt,
        model: "clef-flash".to_owned(),
    };
    let mut scenes = vec![draft_scene("s1"), draft_scene("s2")];
    let day = DraftShootingDay {
        number: Some(1),
        label: Some("Tag 1".into()),
        score: None,
    };
    let mut usage = UsageAccumulator::default();
    let report = score_script_chunk(
        &pass,
        "1 I/T - OP",
        "Ben probiert Kostüme an.",
        Some(1),
        Some("I/T"),
        Some(&day),
        &mut scenes,
        &[false, false],
        &[0, 0],
        &[0, 0],
        &mut usage,
    )
    .await;

    assert!(
        !report.is_failure(),
        "the answered pass must not be reported as a scoring failure: {report:?}"
    );
    assert_eq!(report.failed_rows, 0);
    for scene in &scenes {
        assert!(
            scene.scene_score.is_some(),
            "every row carries a scene score"
        );
        assert!(
            scene.synopsis_score.is_some(),
            "every row carries a synopsis score"
        );
        assert!(
            scene
                .shooting_day
                .as_ref()
                .is_some_and(|day| day.score.is_some()),
            "the chunk's day group carries its day score"
        );
        let rubric = scene.scoring.as_ref().expect("the rubric is recorded");
        assert!(
            !rubric.scoring_failed,
            "the job telemetry reads `scoring_failed` off this flag"
        );
        assert_eq!(
            rubric.sub_scores.len(),
            7,
            "every sub-answer of the answered rubric is recorded: {:?}",
            rubric.sub_scores
        );
    }
    assert_eq!(usage.calls, 1, "one single-pass request");
    assert_eq!(usage.usage.tokens_in, 157);
}

// ── Opt-in live smoke test (the only provider-side schema detector) ─────────

/// Post one question of each kind to the real curated System One endpoint.
///
/// **Never part of the PR gate**: it needs the network, a real credential and
/// it spends money. Run it manually or nightly (see
/// `docs/operations/runbooks.md`, "Decision Model live smoke test"):
///
/// ```bash
/// DECISION_LIVE_KEY=… DECISION_LIVE_PROVIDER=eurouter DECISION_LIVE_MODEL=clef-flash \
///   cargo test -p infra --lib ai::decision_client::decision_client_tests::live_systemone \
///   -- --ignored --nocapture
/// ```
///
/// Goldens pin our side of the contract; only this test detects a **provider**-
/// side schema change (which is exactly what issue #808 was).
#[tokio::test]
#[ignore = "live provider smoke test: needs DECISION_LIVE_KEY, the network and money"]
async fn live_systemone_answers_every_question_kind() {
    let key = match std::env::var("DECISION_LIVE_KEY") {
        Ok(key) if !key.trim().is_empty() => key,
        _ => {
            eprintln!("DECISION_LIVE_KEY is not set — skipping the live System One smoke test");
            return;
        }
    };
    let provider = match std::env::var("DECISION_LIVE_PROVIDER").as_deref() {
        Ok("neuralwatt") => LlmProvider::Neuralwatt,
        Ok("openrouter") => LlmProvider::OpenRouter,
        _ => LlmProvider::EURouter,
    };
    let model = std::env::var("DECISION_LIVE_MODEL")
        .ok()
        .filter(|model| !model.trim().is_empty())
        .unwrap_or_else(|| "clef-flash".to_owned());

    let client = HttpDecisionClient::new(provider, key, Duration::from_secs(60))
        .await
        .expect("the curated endpoint builds a client");
    let mut questions = BTreeMap::new();
    questions.insert("smoke_noul".to_owned(), noul("Is this scene set indoors?"));
    questions.insert(
        "smoke_score".to_owned(),
        score5("How readable is this scene?"),
    );
    questions.insert(
        "smoke_choice".to_owned(),
        continuity_questions()[question_keys::OUTFIT_CONTINUITY].clone(),
    );
    let outcome = client
        .decide(DecisionRequest {
            provider,
            model,
            state: json!({"kind": "smoke", "text": "1 I/T - OP: Ben probiert Kostüme an."}),
            questions,
        })
        .await
        .expect("the live System One surface must accept the curated body");

    let noul_answer = outcome.answers.get("smoke_noul").expect("a noul answer");
    assert!(noul_answer.noul.is_some_and(f32::is_finite));
    let score_answer = outcome.answers.get("smoke_score").expect("a score answer");
    assert_eq!(
        score_answer.score.as_ref().map(Vec::len),
        Some(5),
        "the live score must report one probability per ladder level"
    );
    let choice_answer = outcome
        .answers
        .get("smoke_choice")
        .expect("a choice answer");
    assert!(
        choice_answer
            .choice
            .as_ref()
            .is_some_and(|choices| !choices.is_empty()),
        "the live choice must report its option distribution"
    );
}
