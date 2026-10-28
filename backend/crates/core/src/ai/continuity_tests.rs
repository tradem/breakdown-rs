// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for the Pass-2 continuity core (OpenSpec change
//! `ai-import-decision-outfit-continuity`, design D1–D4).

use std::collections::BTreeMap;

use super::*;
use crate::ai::decision::{DecisionAnswer, question_keys};
use crate::ai::preview::{
    DraftCharacter, DraftOutfit, DraftPiece, DraftScene, DraftShootingDay, ScriptContext,
};

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

fn scene(draft_ref: &str, characters: &[&str], summary: Option<&str>) -> DraftScene {
    DraftScene {
        draft_ref: draft_ref.to_owned(),
        location: Some("FLUR".to_owned()),
        summary: summary.map(str::to_owned),
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

fn choice(pairs: &[(&str, f32)]) -> DecisionAnswer {
    DecisionAnswer {
        choice: Some(
            pairs
                .iter()
                .map(|(key, value)| ((*key).to_owned(), *value))
                .collect::<BTreeMap<_, _>>(),
        ),
        ..Default::default()
    }
}

#[test]
fn a_scene_without_action_is_never_a_gap() {
    // Design D1: outline stubs and meta-summaries must not trigger inference.
    let preview = preview(vec![
        scene("s1", &["BEN"], None),
        scene("s2", &["BEN"], Some("   ")),
        scene("s3", &["BEN"], Some("Keine Handlung im Block")),
        scene("s4", &["BEN"], Some("Ben sucht den Schlüssel.")),
    ]);
    let gaps = outfit_continuity_gaps(&preview);
    assert_eq!(gaps.len(), 1, "only the scene with real action is a gap");
    assert_eq!(gaps[0].scene_index, 3);
    assert_eq!(gaps[0].character_identity, "ben");
    assert_eq!(gaps[0].draft_ref, "s4");
}

#[test]
fn a_dressed_figure_and_an_unlisted_figure_produce_no_gap() {
    let mut dressed = scene("s1", &["BEN", "ANNA"], Some("Ben wartet."));
    dressed.outfits.push(outfit(" ben ", "Zivil-Look"));
    let preview = preview(vec![dressed]);
    let gaps = outfit_continuity_gaps(&preview);
    assert_eq!(gaps.len(), 1, "only the undressed figure is a gap");
    assert_eq!(gaps[0].character_identity, "anna");
}

#[test]
fn a_figure_named_twice_in_one_scene_is_one_gap() {
    let preview = preview(vec![scene("s1", &["BEN", "ben"], Some("Ben wartet."))]);
    assert_eq!(outfit_continuity_gaps(&preview).len(), 1);
}

#[test]
fn the_prior_outfit_is_the_most_recent_earlier_dressed_scene() {
    let mut first = scene("s1", &["BEN"], Some("Ben kommt an."));
    first.location = Some("WOHNUNG".to_owned());
    first.outfits.push(outfit("BEN", "Zivil-Look"));
    let mut second = scene("s2", &["BEN"], Some("Ben fährt los."));
    second.outfits.push(outfit("BEN", "Overall"));
    let mut third = scene("s3", &["BEN"], Some("Ben kehrt zurück."));
    third.outfits.clear();
    let preview = preview(vec![first, second, third]);
    let prior = prior_outfit(&preview, 2, "ben").expect("prior outfit");
    assert_eq!(
        prior.scene_index, 1,
        "most recent earlier dressed scene wins"
    );
    assert_eq!(prior.outfit.name, "Overall");
    assert!(
        prior_outfit(&preview, 0, "ben").is_none(),
        "a figure's first appearance has no prior outfit"
    );
}

#[test]
fn a_look_later_in_the_document_is_never_evidence() {
    let mut later = scene("s2", &["BEN"], Some("Ben geht."));
    later.outfits.push(outfit("BEN", "Overall"));
    let preview = preview(vec![scene("s1", &["BEN"], Some("Ben kommt.")), later]);
    assert!(prior_outfit(&preview, 0, "ben").is_none());
}

#[test]
fn candidates_are_empty_without_a_prior_outfit() {
    // Design D4 C2: a first appearance offers no choice at all.
    let preview = preview(vec![scene("s1", &["BEN"], Some("Ben wartet."))]);
    let gap = outfit_continuity_gaps(&preview).remove(0);
    let candidates = continuity_candidates(&gap, None, &preview.scenes[0]);
    assert!(candidates.is_empty());
}

#[test]
fn a_location_shift_offers_continuation_and_a_context_look() {
    let mut first = scene("s1", &["BEN"], Some("Ben kommt an."));
    first.location = Some("WOHNUNG".to_owned());
    first.outfits.push(outfit("BEN", "Zivil-Look"));
    let mut second = scene("s2", &["BEN"], Some("Ben betritt den OP."));
    second.location = Some("OP-SAAL".to_owned());
    let preview = preview(vec![first, second]);
    let gap = outfit_continuity_gaps(&preview).remove(0);
    let prior = prior_outfit(&preview, gap.scene_index, &gap.character_identity);
    let candidates = continuity_candidates(&gap, prior, &preview.scenes[1]);
    assert_eq!(candidates.len(), 2);
    assert_eq!(candidates[0].name, "Zivil-Look");
    assert_eq!(candidates[0].source_draft_ref, "s1");
    assert!(candidates[0].origin.is_continuation());
    assert_eq!(candidates[1].name, "Kontext-Look (OP-SAAL)");
    assert!(!candidates[1].origin.is_continuation());
    assert_eq!(candidates[1].source_draft_ref, "s2");
}

#[test]
fn the_same_location_offers_only_the_continuation() {
    let mut first = scene("s1", &["BEN"], Some("Ben kommt an."));
    first.outfits.push(outfit("BEN", "Zivil-Look"));
    let second = scene("s2", &["BEN"], Some("Ben bleibt hier."));
    let preview = preview(vec![first, second]);
    let gap = outfit_continuity_gaps(&preview).remove(0);
    let prior = prior_outfit(&preview, gap.scene_index, &gap.character_identity);
    let candidates = continuity_candidates(&gap, prior, &preview.scenes[1]);
    assert_eq!(candidates.len(), 1, "unchanged context offers no new look");
    assert!(candidates[0].origin.is_continuation());
}

#[test]
fn a_day_change_alone_offers_a_context_look() {
    let mut first = scene("s1", &["BEN"], Some("Ben kommt an."));
    first.shooting_day = Some(DraftShootingDay {
        number: Some(1),
        label: Some("Tag 1".to_owned()),
        score: None,
    });
    first.outfits.push(outfit("BEN", "Zivil-Look"));
    let mut second = scene("s2", &["BEN"], Some("Ben am nächsten Morgen."));
    second.shooting_day = Some(DraftShootingDay {
        number: Some(2),
        label: Some("Tag 2".to_owned()),
        score: None,
    });
    let preview = preview(vec![first, second]);
    let gap = outfit_continuity_gaps(&preview).remove(0);
    let prior = prior_outfit(&preview, gap.scene_index, &gap.character_identity);
    let candidates = continuity_candidates(&gap, prior, &preview.scenes[1]);
    assert_eq!(candidates.len(), 2);
}

#[test]
fn a_blank_location_derives_no_context_look() {
    let mut dressed = scene("s1", &["BEN"], Some("Ben kommt an."));
    dressed.outfits.push(outfit("BEN", "Zivil-Look"));
    let mut gap_scene = scene("s2", &["BEN"], Some("Ben ist da."));
    gap_scene.location = None;
    let _preview = preview(vec![dressed, gap_scene.clone()]);
    assert!(context_look_name(&gap_scene).is_none());
}

#[test]
fn the_state_names_the_current_scene_and_the_prior_appearance() {
    let mut first = scene("s1", &["BEN"], Some("Ben kommt an."));
    first.outfits.push(outfit("BEN", "Zivil-Look"));
    let second = scene("s2", &["BEN"], Some("Ben wartet."));
    let preview = preview(vec![first, second]);
    let gap = outfit_continuity_gaps(&preview).remove(0);
    let prior = prior_outfit(&preview, gap.scene_index, &gap.character_identity);
    let state = continuity_state(&preview.scenes[1], &gap, prior);
    assert_eq!(state["kind"], "outfit_continuity");
    assert_eq!(state["character"], "BEN");
    assert_eq!(state["scene"]["location"], "FLUR");
    assert_eq!(state["prior_appearance"]["outfit_name"], "Zivil-Look");
    assert_eq!(state["prior_appearance"]["outfit_pieces"][0], "Hemd");
    assert_eq!(state["context_changed"], false);
}

#[test]
fn the_question_offers_exactly_three_options() {
    let questions = continuity_questions();
    let question = questions
        .get(question_keys::OUTFIT_CONTINUITY)
        .expect("continuity question present");
    match question {
        DecisionQuestion::Choice { options, .. } => {
            assert_eq!(
                options,
                &vec![
                    question_keys::CONTINUITY_CONTINUE_PREVIOUS.to_owned(),
                    question_keys::CONTINUITY_INFER_NEW_OUTFIT.to_owned(),
                    question_keys::CONTINUITY_REPORT_GAP.to_owned(),
                ]
            );
        }
        other => panic!("expected a choice question, got {other:?}"),
    }
}

#[test]
fn a_confident_continuation_resolves_to_option_a() {
    let mut first = scene("s1", &["BEN"], Some("Ben kommt an."));
    first.outfits.push(outfit("BEN", "Zivil-Look"));
    let second = scene("s2", &["BEN"], Some("Ben wartet."));
    let preview = preview(vec![first, second]);
    let prior = prior_outfit(&preview, 1, "ben");
    let outcome = resolve_continuity_outcome(
        &choice(&[
            (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.9),
            (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.1),
            (question_keys::CONTINUITY_REPORT_GAP, 0.0),
        ]),
        prior,
    );
    match outcome {
        Some(ContinuityOutcome::Continue { prior, confidence }) => {
            assert_eq!(prior.source_draft_ref, "s1");
            assert_eq!(prior.name, "Zivil-Look");
            assert!((confidence - 0.9).abs() < f32::EPSILON);
        }
        other => panic!("expected a continuation, got {other:?}"),
    }
}

#[test]
fn a_confident_inference_resolves_to_option_b() {
    let outcome = resolve_continuity_outcome(
        &choice(&[
            (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.05),
            (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.85),
            (question_keys::CONTINUITY_REPORT_GAP, 0.1),
        ]),
        None,
    );
    assert!(matches!(outcome, Some(ContinuityOutcome::Infer { .. })));
}

#[test]
fn continuation_without_a_prior_outfit_falls_back_to_the_next_option() {
    // Design D2: an unavailable option can never win, whatever the model says.
    let outcome = resolve_continuity_outcome(
        &choice(&[
            (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.9),
            (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.05),
            (question_keys::CONTINUITY_REPORT_GAP, 0.05),
        ]),
        None,
    );
    assert!(
        matches!(outcome, Some(ContinuityOutcome::Gap { .. })),
        "continuation must be unavailable, so the next best option wins: {outcome:?}"
    );
}

#[test]
fn a_weak_winner_surfaces_a_gap_instead_of_committing() {
    let mut first = scene("s1", &["BEN"], Some("Ben kommt an."));
    first.outfits.push(outfit("BEN", "Zivil-Look"));
    let second = scene("s2", &["BEN"], Some("Ben wartet."));
    let preview = preview(vec![first, second]);
    let prior = prior_outfit(&preview, 1, "ben");
    let outcome = resolve_continuity_outcome(
        &choice(&[
            (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.5),
            (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.3),
            (question_keys::CONTINUITY_REPORT_GAP, 0.2),
        ]),
        prior,
    );
    assert!(
        matches!(outcome, Some(ContinuityOutcome::Gap { .. })),
        "0.5 is below the confidence floor: {outcome:?}"
    );
}

#[test]
fn an_answer_without_choice_mass_is_not_evaluated() {
    assert!(resolve_continuity_outcome(&DecisionAnswer::default(), None).is_none());
}

#[test]
fn an_exact_tie_prefers_the_conservative_option() {
    // 0.4/0.4 tie between continuation and inference: continuation wins as the
    // more conservative reading, and lands below the floor as a gap.
    let mut first = scene("s1", &["BEN"], Some("Ben kommt an."));
    first.outfits.push(outfit("BEN", "Zivil-Look"));
    let second = scene("s2", &["BEN"], Some("Ben wartet."));
    let preview = preview(vec![first, second]);
    let prior = prior_outfit(&preview, 1, "ben");
    let outcome = resolve_continuity_outcome(
        &choice(&[
            (question_keys::CONTINUITY_CONTINUE_PREVIOUS, 0.4),
            (question_keys::CONTINUITY_INFER_NEW_OUTFIT, 0.4),
            (question_keys::CONTINUITY_REPORT_GAP, 0.2),
        ]),
        prior,
    );
    assert!(matches!(outcome, Some(ContinuityOutcome::Gap { .. })));
}
