// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Pass 2: cross-scene outfit continuity (OpenSpec change
//! `ai-import-decision-outfit-continuity`).
//!
//! Pass 1 extracts wardrobe only where the script names it. Production
//! screenplays mention a look when a figure first appears or changes clothes and
//! stay silent afterwards, so after Pass 1 many `(scene, character)` pairs carry
//! action but no outfit. This module holds the **pure, deterministic** half of
//! the second pass: which gaps are eligible (design D1), what the Decision Model
//! is asked (design D2), and how its answer is interpreted (design D3/D4).
//!
//! The pass itself — the one Decision Model request per gap and the mutation of
//! the preview — lives in `infra::ai::outfit_continuity`, because it talks to a
//! provider port. Nothing here reads a projection, calls a provider, or depends
//! on infrastructure (AGENTS.md §2).

use std::collections::BTreeMap;

use super::decision::{DecisionAnswer, DecisionQuestion, question_keys};
use super::preview::{
    DraftOutfit, DraftOutfitCandidate, DraftOutfitOrigin, DraftScene, ScriptContext,
    character_identity, draft_row_ref, is_meta_summary,
};

/// Minimum calibrated probability for an Option A / Option B row to become a
/// wardrobe entry. Below it the gap is surfaced for review instead (design D4):
/// an uncertain inference is worth less than a visible gap, because a wrong
/// outfit silently flows into the wardrobe while a gap costs one click.
pub const CONTINUITY_MIN_CONFIDENCE: f32 = 0.6;

/// One `(scene, character)` pair Pass 2 may evaluate — a figure the scene names,
/// for whom Pass 1 extracted no outfit, in a scene that carries real action
/// (design D1).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutfitContinuityGap {
    /// Index of the scene in [`ScriptContext::scenes`].
    pub scene_index: usize,
    /// The scene's stable preview row reference.
    pub draft_ref: String,
    /// The scene's document scene number, when it carries one.
    pub scene_number: Option<u32>,
    /// The figure's preview-wide identity key ([`character_identity`]).
    pub character_identity: String,
    /// The figure's name as the script wrote it (display only).
    pub character_name: String,
}

/// A figure's most recent earlier appearance that carries an outfit — the
/// Option A source and the first Option C candidate.
#[derive(Debug, Clone, Copy)]
pub struct PriorOutfit<'a> {
    /// Index of the source scene in [`ScriptContext::scenes`].
    pub scene_index: usize,
    /// The source draft row.
    pub scene: &'a DraftScene,
    /// The figure's outfit in that row.
    pub outfit: &'a DraftOutfit,
}

/// The deterministic context label of an inferred look (Option B, design D4).
///
/// A Decision Model emits a distribution, not text, and the script states no
/// garment for the gap — so the only honest name is the scene's own location.
/// The look therefore carries **no pieces**: inventing garments to fill it would
/// be exactly the fabrication the Pass-1 grounding check exists to prevent.
#[must_use]
pub fn context_look_name(scene: &DraftScene) -> Option<String> {
    let location = scene.location.as_deref().map(str::trim).unwrap_or_default();
    if location.is_empty() {
        return None;
    }
    // Capped so a pathological heading cannot become a wardrobe name.
    let mut label: String = location.chars().take(80).collect();
    label = label.trim().to_owned();
    if label.is_empty() {
        return None;
    }
    Some(format!("Kontext-Look ({label})"))
}

/// Whether a scene carries plausible action — the gate from design D1.
///
/// Outline stubs, empty headers and meta-descriptions ("Keine Handlung im
/// Block") must never trigger inference: they would produce outfits (or
/// conflicts) for scenes that have no content at all.
#[must_use]
pub fn has_plausible_action(scene: &DraftScene) -> bool {
    match scene.summary.as_deref() {
        Some(summary) => {
            let trimmed = summary.trim();
            !trimmed.is_empty() && !is_meta_summary(trimmed)
        }
        None => false,
    }
}

/// Every gap Pass 2 may evaluate, in preview order (design D1).
#[must_use]
pub fn outfit_continuity_gaps(preview: &ScriptContext) -> Vec<OutfitContinuityGap> {
    let mut gaps = Vec::new();
    for (scene_index, scene) in preview.scenes.iter().enumerate() {
        if !has_plausible_action(scene) {
            continue;
        }
        let dressed: Vec<String> = scene
            .outfits
            .iter()
            .map(|outfit| character_identity(&outfit.character_name))
            .collect();
        let mut seen: Vec<String> = Vec::new();
        for character in &scene.characters {
            let identity = character_identity(&character.name);
            if identity.is_empty() || dressed.iter().any(|known| known == &identity) {
                continue;
            }
            if seen.iter().any(|known| known == &identity) {
                continue;
            }
            seen.push(identity.clone());
            gaps.push(OutfitContinuityGap {
                scene_index,
                draft_ref: draft_row_ref(scene, scene_index),
                scene_number: scene.scene_number,
                character_identity: identity,
                character_name: character.name.clone(),
            });
        }
    }
    gaps
}

/// The figure's most recent EARLIER scene carrying an outfit (design D2).
///
/// Only earlier rows count: a later appearance cannot be the source of a
/// continuation, and a look later in the document is what the reviewer must
/// decide about, not evidence for the current scene.
#[must_use]
pub fn prior_outfit<'a>(
    preview: &'a ScriptContext,
    scene_index: usize,
    identity: &str,
) -> Option<PriorOutfit<'a>> {
    preview
        .scenes
        .iter()
        .enumerate()
        .take(scene_index)
        .rev()
        .find_map(|(index, scene)| {
            scene
                .outfits
                .iter()
                .find(|outfit| character_identity(&outfit.character_name) == identity)
                .map(|outfit| PriorOutfit {
                    scene_index: index,
                    scene,
                    outfit,
                })
        })
}

/// Whether the scene's context differs from the prior appearance's (design D4):
/// a location shift or a day change is the evidence that makes a NEW look
/// derivable. Without it a context candidate would be a guess.
#[must_use]
fn context_changed(prior: &PriorOutfit<'_>, scene: &DraftScene) -> bool {
    let location_changed = match (
        prior.scene.location.as_deref().map(str::trim),
        scene.location.as_deref().map(str::trim),
    ) {
        (Some(before), Some(after)) => !before.eq_ignore_ascii_case(after),
        _ => false,
    };
    let day_changed = match (
        prior
            .scene
            .shooting_day
            .as_ref()
            .and_then(|day| day.group_key()),
        scene.shooting_day.as_ref().and_then(|day| day.group_key()),
    ) {
        (Some(before), Some(after)) => before != after,
        _ => false,
    };
    location_changed || day_changed
}

/// The looks the script actually supports for a gap (design D4).
///
/// Continuation first (the prior outfit, when there is one), then a context look
/// when the scene's location or day moved away from the prior appearance. Empty
/// when neither is derivable — an invented option is never offered.
#[must_use]
pub fn continuity_candidates(
    gap: &OutfitContinuityGap,
    prior: Option<PriorOutfit<'_>>,
    scene: &DraftScene,
) -> Vec<DraftOutfitCandidate> {
    let mut candidates = Vec::new();
    if let Some(prior) = prior {
        let source_ref = draft_row_ref(prior.scene, prior.scene_index);
        candidates.push(DraftOutfitCandidate {
            origin: DraftOutfitOrigin::ContinuedFromScene,
            name: prior.outfit.name.trim().to_owned(),
            source_draft_ref: source_ref,
            source_scene_number: prior.scene.scene_number,
            confidence: CONTINUITY_MIN_CONFIDENCE,
        });
        // A context look is only derivable when the scene moved away from the
        // prior appearance AND its own location yields a label.
        if context_changed(&prior, scene)
            && let Some(name) = context_look_name(scene)
        {
            candidates.push(DraftOutfitCandidate {
                origin: DraftOutfitOrigin::InferredFromContext,
                name,
                source_draft_ref: gap.draft_ref.clone(),
                source_scene_number: gap.scene_number,
                confidence: CONTINUITY_MIN_CONFIDENCE,
            });
        }
    }
    candidates
}

/// The continuity state one decision request evaluates (design D2).
///
/// Compact and deterministic: the current scene's own extracted facts plus the
/// figure's most recent dressed appearance. No chunk text — Pass 2 runs after
/// every chunk is merged, so quoting a chunk here would attribute one block's
/// prose to another scene.
#[must_use]
pub fn continuity_state(
    scene: &DraftScene,
    gap: &OutfitContinuityGap,
    prior: Option<PriorOutfit<'_>>,
) -> serde_json::Value {
    let prior_appearance = prior.map(|prior| {
        serde_json::json!({
            "scene_number": prior.scene.scene_number,
            "location": prior.scene.location,
            "mood": prior.scene.mood,
            "shooting_day": prior.scene
                .shooting_day
                .as_ref()
                .and_then(|day| day.display_label()),
            "outfit_name": prior.outfit.name,
            "outfit_pieces": prior
                .outfit
                .pieces
                .iter()
                .map(|piece| piece.name.clone())
                .collect::<Vec<_>>(),
        })
    });
    serde_json::json!({
        "kind": "outfit_continuity",
        "character": gap.character_name,
        "character_identity": gap.character_identity,
        "scene": {
            "scene_number": scene.scene_number,
            "location": scene.location,
            "mood": scene.mood,
            "shooting_day": scene
                .shooting_day
                .as_ref()
                .and_then(|day| day.display_label()),
            "summary": scene.summary,
        },
        "prior_appearance": prior_appearance,
        "context_changed": prior.map(|prior| context_changed(&prior, scene)),
    })
}

/// The decision question Pass 2 asks for one gap (design D2).
#[must_use]
pub fn continuity_questions() -> BTreeMap<String, DecisionQuestion> {
    let mut questions = BTreeMap::new();
    questions.insert(
        question_keys::OUTFIT_CONTINUITY.to_owned(),
        DecisionQuestion::Choice {
            description: "What is the most probable wardrobe state of the character in this scene?"
                .to_owned(),
            options: vec![
                question_keys::CONTINUITY_CONTINUE_PREVIOUS.to_owned(),
                question_keys::CONTINUITY_INFER_NEW_OUTFIT.to_owned(),
                question_keys::CONTINUITY_REPORT_GAP.to_owned(),
            ],
        },
    );
    questions
}

/// How a gap resolved (design D2/D3/D4).
#[derive(Debug, Clone, PartialEq)]
pub enum ContinuityOutcome {
    /// Option A — keep wearing the prior scene's outfit.
    Continue {
        /// The source row of the continued look.
        prior: PriorOutfitOwned,
        /// Winning probability.
        confidence: f32,
    },
    /// Option B — a context-derived look.
    Infer {
        /// Winning probability.
        confidence: f32,
    },
    /// Option C, or a winning probability below [`CONTINUITY_MIN_CONFIDENCE`].
    Gap {
        /// Probability of the winning option (or the `report_conflict_or_gap`
        /// probability for a plain conflict answer).
        confidence: f32,
    },
}

/// An owned copy of what a continuation needs — the outcome outlives the borrow
/// of the preview it was resolved from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PriorOutfitOwned {
    /// `draft_ref` of the source row.
    pub source_draft_ref: String,
    /// The source row's scene number.
    pub source_scene_number: Option<u32>,
    /// Display name of the continued look.
    pub name: String,
}

impl From<PriorOutfit<'_>> for PriorOutfitOwned {
    fn from(prior: PriorOutfit<'_>) -> Self {
        let scene_index = prior.scene_index;
        Self {
            source_draft_ref: draft_row_ref(prior.scene, scene_index),
            source_scene_number: prior.scene.scene_number,
            name: prior.outfit.name.trim().to_owned(),
        }
    }
}

/// Interpret the Decision Model's answer for one gap.
///
/// The winning option is the highest-probability option of the `choice` answer.
/// `continue_previous` is **unavailable** when the figure has no prior outfit —
/// a model that names it anyway is answered by the next best available option,
/// never by inventing a source. A winner below [`CONTINUITY_MIN_CONFIDENCE`]
/// resolves to [`ContinuityOutcome::Gap`]: the pass then surfaces the choice
/// instead of committing to it. `None` means the answer carried no usable
/// `choice` mass at all (honest degradation — the gap is not evaluated).
#[must_use]
pub fn resolve_continuity_outcome(
    answer: &DecisionAnswer,
    prior: Option<PriorOutfit<'_>>,
) -> Option<ContinuityOutcome> {
    let choice = answer.choice.as_ref()?;
    let probability = |key: &str| -> Option<f32> {
        choice
            .get(key)
            .copied()
            .filter(|value| value.is_finite() && *value >= 0.0)
    };
    let continue_p = if prior.is_some() {
        probability(question_keys::CONTINUITY_CONTINUE_PREVIOUS)
    } else {
        None
    };
    let infer_p = probability(question_keys::CONTINUITY_INFER_NEW_OUTFIT);
    let gap_p = probability(question_keys::CONTINUITY_REPORT_GAP);

    let mut best: Option<(&'static str, f32)> = None;
    for (key, value) in [
        (
            question_keys::CONTINUITY_CONTINUE_PREVIOUS,
            continue_p.unwrap_or(0.0),
        ),
        (
            question_keys::CONTINUITY_INFER_NEW_OUTFIT,
            infer_p.unwrap_or(0.0),
        ),
        (question_keys::CONTINUITY_REPORT_GAP, gap_p.unwrap_or(0.0)),
    ] {
        // `>`, not `>=`: on an exact tie the earlier (more conservative) option
        // wins — continuation before inference, both before a gap.
        if best.is_none_or(|(_, current)| value > current) {
            best = Some((key, value));
        }
    }
    let (winner, confidence) = best?;
    if winner == question_keys::CONTINUITY_CONTINUE_PREVIOUS
        && confidence >= CONTINUITY_MIN_CONFIDENCE
    {
        return prior
            .map(|prior| ContinuityOutcome::Continue {
                prior: PriorOutfitOwned::from(prior),
                confidence,
            })
            .or(Some(ContinuityOutcome::Gap { confidence }));
    }
    if winner == question_keys::CONTINUITY_INFER_NEW_OUTFIT
        && confidence >= CONTINUITY_MIN_CONFIDENCE
    {
        return Some(ContinuityOutcome::Infer { confidence });
    }
    Some(ContinuityOutcome::Gap { confidence })
}

#[cfg(test)]
#[path = "continuity_tests.rs"]
mod continuity_tests;
