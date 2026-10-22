// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Unit tests for the Decision Model primitives and hybrid score formulas
//! (issue #722).

use std::collections::BTreeMap;

use super::*;

#[test]
fn decision_capable_providers_are_the_curated_three() {
    assert!(is_decision_capable(LlmProvider::Neuralwatt));
    assert!(is_decision_capable(LlmProvider::EURouter));
    assert!(is_decision_capable(LlmProvider::OpenRouter));
    // Generative / local providers host no decision models.
    assert!(!is_decision_capable(LlmProvider::OpenAI));
    assert!(!is_decision_capable(LlmProvider::Gemini));
    assert!(!is_decision_capable(LlmProvider::Ollama));
    assert!(!is_decision_capable(LlmProvider::OpenCode));
}

#[test]
fn curated_decision_models_cover_the_issue_catalog() {
    assert_eq!(
        curated_decision_model_ids(LlmProvider::Neuralwatt),
        &["clef-flash", "clef"]
    );
    assert_eq!(
        curated_decision_model_ids(LlmProvider::EURouter),
        &["clef-flash", "metis"]
    );
    assert!(curated_decision_model_ids(LlmProvider::OpenRouter).contains(&"cloudflare/clef-flash"));
    assert!(curated_decision_model_ids(LlmProvider::OpenRouter).contains(&"typesafe/jev-1.14"));
    // Non-decision providers have no curated decision models.
    assert!(curated_decision_model_ids(LlmProvider::OpenAI).is_empty());
    assert!(!is_curated_decision_model(LlmProvider::OpenAI, "clef"));
    assert!(is_curated_decision_model(
        LlmProvider::Neuralwatt,
        "clef-flash"
    ));
    assert!(!is_curated_decision_model(LlmProvider::Neuralwatt, "metis"));
}

#[test]
fn question_kinds_are_stable() {
    assert_eq!(noul("x").kind(), "noul");
    assert_eq!(
        DecisionQuestion::Choice {
            description: "x".into(),
            options: vec!["a".into()]
        }
        .kind(),
        "choice"
    );
    assert_eq!(score5("x").kind(), "score");
}

#[test]
fn expected_score_normalizes_the_ordinal_distribution() {
    // Certain top level (index 4 of 5) → 1.0.
    let top = DecisionAnswer {
        score: Some(vec![0.0, 0.0, 0.0, 0.0, 1.0]),
        ..Default::default()
    };
    assert!((top.expected_score().unwrap() - 1.0).abs() < 1e-6);
    // Certain bottom level → 0.0.
    let bottom = DecisionAnswer {
        score: Some(vec![1.0, 0.0, 0.0, 0.0, 0.0]),
        ..Default::default()
    };
    assert!(bottom.expected_score().unwrap().abs() < 1e-6);
    // Even spread over 5 levels → expected index 2 → 0.5.
    let even = DecisionAnswer {
        score: Some(vec![0.2, 0.2, 0.2, 0.2, 0.2]),
        ..Default::default()
    };
    assert!((even.expected_score().unwrap() - 0.5).abs() < 1e-6);
    // No distribution → None (honest degradation).
    assert_eq!(DecisionAnswer::default().expected_score(), None);
    assert_eq!(
        DecisionAnswer {
            score: Some(Vec::new()),
            ..Default::default()
        }
        .expected_score(),
        None
    );
    // A distribution that does not sum to 1 still normalizes over its mass.
    let partial = DecisionAnswer {
        score: Some(vec![0.0, 0.0, 0.5, 0.0, 0.5]),
        ..Default::default()
    };
    assert!((partial.expected_score().unwrap() - 0.75).abs() < 1e-6);
}

#[test]
fn scene_grounding_factor_blends_signals_and_penalties() {
    // Fully grounded, no penalties.
    assert!((scene_grounding_factor(true, true, 0, 0) - 0.9).abs() < 1e-6);
    // Nothing matched.
    assert!((scene_grounding_factor(false, false, 0, 0) - 0.5).abs() < 1e-6);
    // Each dropped costume costs 0.1; ambiguities 0.05.
    assert!((scene_grounding_factor(true, true, 1, 0) - 0.8).abs() < 1e-6);
    assert!((scene_grounding_factor(true, true, 0, 2) - 0.8).abs() < 1e-6);
    // Saturates at zero, never negative.
    assert_eq!(scene_grounding_factor(false, false, 99, 99), 0.0);
}

#[test]
fn scene_score_requires_every_decision_answer() {
    let grounding = scene_grounding_factor(true, true, 0, 0);
    // All answers present → blended score.
    let score = compute_scene_score(grounding, Some(0.8), Some(0.9), Some(0.7));
    let expected = (grounding * 0.4 + ((0.8 + 0.9 + 0.7) / 3.0) * 0.6).clamp(0.0, 1.0);
    assert!((score.unwrap() - expected).abs() < 1e-6);
    // Any missing answer → None (no fabricated mid-range value).
    assert_eq!(
        compute_scene_score(grounding, None, Some(0.9), Some(0.7)),
        None
    );
    assert_eq!(
        compute_scene_score(grounding, Some(0.8), None, Some(0.7)),
        None
    );
    assert_eq!(
        compute_scene_score(grounding, Some(0.8), Some(0.9), None),
        None
    );
    // Stays within 0.0..=1.0 even for extreme inputs.
    let clamped = compute_scene_score(1.0, Some(1.0), Some(1.0), Some(1.0)).unwrap();
    assert!((0.0..=1.0).contains(&clamped));
}

#[test]
fn synopsis_score_degrades_honestly() {
    // The #668 deterministic guard fired → honest 0.0, independent of answers.
    assert_eq!(
        compute_synopsis_score(true, Some(0.9), Some(0.9), Some(0.9)),
        Some(0.0)
    );
    // Outline-only block (no summary scored) stays None.
    assert_eq!(
        compute_synopsis_score(false, None, Some(0.9), Some(0.9)),
        None
    );
    assert_eq!(
        compute_synopsis_score(false, Some(0.9), None, Some(0.9)),
        None
    );
    assert_eq!(
        compute_synopsis_score(false, Some(0.9), Some(0.9), None),
        None
    );
    // Grounded is a multiplier: perfect grounded/concise with mid relevance.
    let score = compute_synopsis_score(false, Some(1.0), Some(1.0), Some(0.5)).unwrap();
    assert!((score - 0.75).abs() < 1e-6);
    // An ungrounded summary collapses to ~0 regardless of the rest.
    let ungrounded = compute_synopsis_score(false, Some(0.0), Some(1.0), Some(1.0)).unwrap();
    assert!(ungrounded.abs() < 1e-6);
}

#[test]
fn shooting_day_score_needs_marker_and_consistency() {
    assert_eq!(compute_shooting_day_score(true, None), None);
    let score = compute_shooting_day_score(true, Some(0.8)).unwrap();
    assert!((score - (0.3 + 0.7 * 0.8)).abs() < 1e-6);
    // A marker mismatch zeroes the score: the deterministic scan is
    // authoritative and a contradicting assignment cannot score well.
    let mismatched = compute_shooting_day_score(false, Some(0.8)).unwrap();
    assert!(mismatched.abs() < 1e-6);
}

#[test]
fn rubric_serializes_additively() {
    let mut sub_scores = BTreeMap::new();
    sub_scores.insert("characters_complete".to_owned(), 0.9);
    let rubric = DecisionRubric {
        decision_provider: Some(LlmProvider::Neuralwatt),
        decision_model: Some("clef-flash".to_owned()),
        sub_scores,
        grounding_factor: Some(0.9),
        scoring_failed: false,
    };
    let json = serde_json::to_value(&rubric).unwrap();
    // `scoring_failed: false` is omitted (skip_serializing_if).
    assert!(json.get("scoring_failed").is_none());
    // Round-trips.
    let back: DecisionRubric = serde_json::from_value(json).unwrap();
    assert_eq!(back, rubric);
    // Pre-#722 payloads (no fields) deserialize to the default.
    let legacy: DecisionRubric = serde_json::from_value(serde_json::json!({})).unwrap();
    assert_eq!(legacy, DecisionRubric::default());
}
