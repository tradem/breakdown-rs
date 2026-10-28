// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Tests for the Pass-2 runner (OpenSpec change
//! `ai-import-decision-outfit-continuity`).

use std::collections::BTreeMap;
use std::sync::Arc;

use async_trait::async_trait;
use breakdown_core::ai::{
    DecisionAnswer, DecisionCallOutcome, DecisionClient, DecisionRequest, DraftCharacter,
    DraftOutfit, DraftOutfitOrigin, DraftPiece, DraftScene, LlmCallUsage, LlmProvider,
    ScriptContext, UncertaintyKind, question_keys,
};
use breakdown_core::error::DomainError;

use super::*;
use crate::ai::workers::DecisionPass;

/// Answers every choice question with the supplied distribution.
struct ChoiceClient {
    distribution: Vec<(&'static str, f32)>,
}

#[async_trait]
impl DecisionClient for ChoiceClient {
    async fn decide(&self, req: DecisionRequest) -> Result<DecisionCallOutcome, DomainError> {
        let mut answers = BTreeMap::new();
        for name in req.questions.keys() {
            answers.insert(
                name.clone(),
                DecisionAnswer {
                    choice: Some(
                        self.distribution
                            .iter()
                            .map(|(key, value)| ((*key).to_owned(), *value))
                            .collect(),
                    ),
                    ..Default::default()
                },
            );
        }
        Ok(DecisionCallOutcome {
            answers,
            usage: LlmCallUsage {
                tokens_in: 11,
                tokens_out: 0,
                cached_tokens_in: 0,
                energy_millijoules: 3,
            },
        })
    }
}

struct FailingClient;

#[async_trait]
impl DecisionClient for FailingClient {
    async fn decide(&self, _req: DecisionRequest) -> Result<DecisionCallOutcome, DomainError> {
        Err(DomainError::validation("decision endpoint refused"))
    }
}

fn pass(client: Arc<dyn DecisionClient>) -> DecisionPass {
    DecisionPass {
        client,
        provider: LlmProvider::Neuralwatt,
        model: "clef-flash".to_owned(),
    }
}

fn outfit(character: &str, name: &str) -> DraftOutfit {
    DraftOutfit {
        character_name: character.to_owned(),
        name: name.to_owned(),
        notes: None,
        source_quote: format!("{character} in {name}"),
        origin: DraftOutfitOrigin::ExplicitQuote,
        provenance: None,
        pieces: vec![DraftPiece {
            name: "Hemd".to_owned(),
            category_hint: None,
            description: None,
        }],
    }
}

fn scene(draft_ref: &str, location: &str, characters: &[&str]) -> DraftScene {
    DraftScene {
        draft_ref: draft_ref.to_owned(),
        scene_number: Some(1),
        location: Some(location.to_owned()),
        summary: Some(format!("action of {draft_ref}")),
        characters: characters
            .iter()
            .map(|name| DraftCharacter::from(*name))
            .collect(),
        ..Default::default()
    }
}

fn preview(scenes: Vec<DraftScene>) -> ScriptContext {
    ScriptContext {
        title: None,
        scenes,
        uncertainties: Vec::new(),
    }
}

fn continuous_preview() -> ScriptContext {
    let mut source = scene("source", "WOHNUNG", &["BEN"]);
    source.outfits.push(outfit("BEN", "Zivil-Look"));
    preview(vec![source, scene("target", "OP-SAAL", &["BEN"])])
}

#[tokio::test]
async fn a_continuation_attaches_a_continued_from_scene_outfit() {
    let mut preview = continuous_preview();
    let report = run_outfit_continuity_pass(
        &pass(Arc::new(ChoiceClient {
            distribution: vec![
                (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.9),
                (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.05),
                (question_keys::CONTINUITY_REPORT_GAP, 0.05),
            ],
        })),
        &mut preview,
        &mut LlmCallUsage::default(),
        || false,
    )
    .await;
    assert_eq!(report.gaps, 1);
    assert_eq!(report.continued, 1);
    let attached = &preview.scenes[1].outfits;
    assert_eq!(attached.len(), 1);
    assert_eq!(attached[0].name, "Zivil-Look");
    assert!(attached[0].pieces.is_empty());
    assert!(attached[0].origin.is_continuation());
    let provenance = attached[0]
        .provenance
        .as_ref()
        .expect("a Pass-2 row carries its provenance");
    assert_eq!(provenance.source_draft_ref.as_deref(), Some("source"));
    assert!((provenance.confidence - 0.9).abs() < f32::EPSILON);
    assert!(
        preview.uncertainties.is_empty(),
        "a confident continuation needs no review entry"
    );
}

#[tokio::test]
async fn an_inference_attaches_a_context_look_and_a_review_entry() {
    let mut preview = continuous_preview();
    let report = run_outfit_continuity_pass(
        &pass(Arc::new(ChoiceClient {
            distribution: vec![
                (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.05),
                (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.9),
                (question_keys::CONTINUITY_REPORT_GAP, 0.05),
            ],
        })),
        &mut preview,
        &mut LlmCallUsage::default(),
        || false,
    )
    .await;
    assert_eq!(report.inferred, 1);
    let attached = &preview.scenes[1].outfits;
    assert_eq!(attached.len(), 1);
    assert_eq!(attached[0].name, "Kontext-Look (OP-SAAL)");
    assert!(attached[0].pieces.is_empty(), "the script named no garment");
    assert_eq!(attached[0].origin, DraftOutfitOrigin::InferredFromContext);
    assert!(attached[0].provenance.is_some());
    assert_eq!(preview.uncertainties.len(), 1);
    assert_eq!(preview.uncertainties[0].kind, UncertaintyKind::DroppedRow);
    assert!(!preview.uncertainties[0].kind.blocks_apply());
    assert_eq!(preview.uncertainties[0].candidates.len(), 1);
}

#[tokio::test]
async fn a_gap_answer_records_the_script_derivable_candidates_only() {
    let mut preview = continuous_preview();
    let report = run_outfit_continuity_pass(
        &pass(Arc::new(ChoiceClient {
            distribution: vec![
                (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.2),
                (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.1),
                (question_keys::CONTINUITY_REPORT_GAP, 0.7),
            ],
        })),
        &mut preview,
        &mut LlmCallUsage::default(),
        || false,
    )
    .await;
    assert_eq!(report.gaps_reported, 1);
    assert!(preview.scenes[1].outfits.is_empty(), "nothing was invented");
    let uncertainty = &preview.uncertainties[0];
    assert_eq!(uncertainty.field, "outfits");
    assert_eq!(uncertainty.candidates.len(), 2);
    assert!(uncertainty.candidates[0].origin.is_continuation());
    assert_eq!(uncertainty.candidates[1].name, "Kontext-Look (OP-SAAL)");
}

#[tokio::test]
async fn a_first_appearance_offers_no_candidates() {
    // Design D4 C2: no prior outfit and no location ⇒ a plain gap, no choices.
    let mut gap_scene = scene("only", "OP-SAAL", &["BEN"]);
    gap_scene.location = None;
    let mut preview = preview(vec![gap_scene]);
    let report = run_outfit_continuity_pass(
        &pass(Arc::new(ChoiceClient {
            distribution: vec![
                (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.1),
                (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.1),
                (question_keys::CONTINUITY_REPORT_GAP, 0.8),
            ],
        })),
        &mut preview,
        &mut LlmCallUsage::default(),
        || false,
    )
    .await;
    assert_eq!(report.gaps_reported, 1);
    assert!(preview.uncertainties[0].candidates.is_empty());
}

#[tokio::test]
async fn a_decision_failure_leaves_the_preview_untouched() {
    let mut before = continuous_preview();
    let mut preview = before.clone();
    let report = run_outfit_continuity_pass(
        &pass(Arc::new(FailingClient)),
        &mut preview,
        &mut LlmCallUsage::default(),
        || false,
    )
    .await;
    assert_eq!(report.undecided, 1);
    assert_eq!(preview.scenes[1].outfits, before.scenes[1].outfits);
    assert!(preview.uncertainties.is_empty());
    // The extraction itself is never discarded.
    before.scenes[0].outfits.clear();
    assert!(!preview.scenes[0].outfits.is_empty());
}

#[tokio::test]
async fn a_lost_claim_stops_before_the_next_paid_request() {
    let mut source = scene("source", "WOHNUNG", &["BEN"]);
    source.outfits.push(outfit("BEN", "Zivil-Look"));
    let mut preview = preview(vec![
        source,
        scene("target", "OP-SAAL", &["BEN"]),
        scene("target2", "OP-SAAL", &["ANNA"]),
    ]);
    let report = run_outfit_continuity_pass(
        &pass(Arc::new(ChoiceClient {
            distribution: vec![
                (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.9),
                (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.05),
                (question_keys::CONTINUITY_REPORT_GAP, 0.05),
            ],
        })),
        &mut preview,
        &mut LlmCallUsage::default(),
        || true,
    )
    .await;
    assert_eq!(report.gaps, 2);
    assert_eq!(report.continued, 0);
    assert_eq!(report.unresolved(), 2);
    assert!(preview.uncertainties.is_empty());
    assert!(preview.scenes[1].outfits.is_empty());
}

#[tokio::test]
async fn a_preview_without_gaps_is_a_no_op() {
    let mut preview = preview(vec![scene("s1", "OP", &[])]);
    let report = run_outfit_continuity_pass(
        &pass(Arc::new(FailingClient)),
        &mut preview,
        &mut LlmCallUsage::default(),
        || false,
    )
    .await;
    assert_eq!(report, ContinuityPassReport::default());
}

#[tokio::test]
async fn pass_two_telemetry_accumulates_into_the_job_usage() {
    let mut preview = continuous_preview();
    let mut usage = LlmCallUsage::default();
    run_outfit_continuity_pass(
        &pass(Arc::new(ChoiceClient {
            distribution: vec![
                (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.9),
                (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.05),
                (question_keys::CONTINUITY_REPORT_GAP, 0.05),
            ],
        })),
        &mut preview,
        &mut usage,
        || false,
    )
    .await;
    assert_eq!(usage.tokens_in, 11);
    assert_eq!(usage.energy_millijoules, 3);
}
