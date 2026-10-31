// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Pass 2 — the cross-scene outfit continuity scan (OpenSpec change
//! `ai-import-decision-outfit-continuity`).
//!
//! Runs once per script job, after every chunk is extracted and merged, over the
//! merged [`ScriptContext`]. For each wardrobe gap (a figure the scene names, in
//! a scene with real action, with no extracted outfit — design D1) it asks the
//! Decision Model one calibrated choice question (design D2) and records the
//! answer:
//!
//! - **Option A** — attach a `ContinuedFromScene` outfit; the apply then binds
//!   this scene's beat to the source scene's `Outfit` (design D3);
//! - **Option B** — attach an `InferredFromContext` look whose name is the
//!   scene's own location, with no pieces (the script states no garment);
//! - **Option C / low confidence** — record a non-blocking gap uncertainty that
//!   carries only the candidates the script actually supports (design D4).
//!
//! The pass is **best-effort**: a provider failure logs and ends it, leaving the
//! extracted preview untouched. Nothing here may fail a job that already paid
//! for its extraction.

use breakdown_core::ai::{
    ContinuityOutcome, DecisionRequest, DraftOutfit, DraftOutfitCandidate, DraftOutfitOrigin,
    DraftOutfitProvenance, OutfitContinuityGap, ScriptContext, Uncertainty, UncertaintyKind,
    UsageAccumulator, character_identity, context_look_name, continuity_candidates,
    continuity_questions, continuity_state, draft_row_ref, outfit_continuity_gaps, prior_outfit,
    question_keys, resolve_continuity_outcome,
};

use super::workers::DecisionPass;

/// The `field` a Pass-2 gap uncertainty is attached to.
pub const CONTINUITY_FIELD: &str = "outfits";

/// What one Pass 2 run did — telemetry and tests only, never persisted.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ContinuityPassReport {
    /// Gaps the eligibility gate let through.
    pub gaps: usize,
    /// Gaps resolved to Option A (a continued look).
    pub continued: usize,
    /// Gaps resolved to Option B (a context look).
    pub inferred: usize,
    /// Gaps surfaced as a non-blocking uncertainty (Option C / low confidence).
    pub gaps_reported: usize,
    /// Gaps whose decision request failed or was never sent (claim lost).
    pub undecided: usize,
}

impl ContinuityPassReport {
    /// Gaps that produced no row and no uncertainty — only a stopped pass has
    /// any (claim lost, provider failure, or an answer without choice mass).
    #[must_use]
    pub fn unresolved(&self) -> usize {
        self.gaps
            .saturating_sub(self.continued + self.inferred + self.gaps_reported)
    }
}

/// Run Pass 2 over the merged preview.
///
/// `claim_lost` is polled before every paid request: a worker whose lease lapsed
/// must stop rather than spend on a job another worker now owns. The pass never
/// returns an error — the caller stores the preview either way.
pub async fn run_outfit_continuity_pass(
    pass: &DecisionPass,
    preview: &mut ScriptContext,
    // The Decision Model's own accumulator (issue #768): it counts the calls as
    // well as their usage, so a 2xx answer that reports no usage is still a
    // recorded Decision-Model call.
    usage: &mut UsageAccumulator,
    claim_lost: impl Fn() -> bool,
) -> ContinuityPassReport {
    let gaps = outfit_continuity_gaps(preview);
    let mut report = ContinuityPassReport {
        gaps: gaps.len(),
        ..Default::default()
    };
    if gaps.is_empty() {
        return report;
    }
    let questions = continuity_questions();
    // Rows and uncertainties are collected first and written afterwards: every
    // request must see the SAME evidence, so a look this pass attached can never
    // become the source of a later gap in the same run.
    let mut attached: Vec<(usize, DraftOutfit)> = Vec::new();
    let mut uncertainties: Vec<Uncertainty> = Vec::new();
    for (position, gap) in gaps.iter().enumerate() {
        if claim_lost() {
            tracing::warn!(
                remaining = gaps.len() - position,
                "ai outfit-continuity: claim lost, Pass 2 stops"
            );
            break;
        }
        let scene = &preview.scenes[gap.scene_index];
        let prior = prior_outfit(preview, gap.scene_index, &gap.character_identity);
        let request = DecisionRequest {
            provider: pass.provider,
            model: pass.model.clone(),
            state: continuity_state(scene, gap, prior),
            questions: questions.clone(),
        };
        let outcome =
            match super::decision_scoring::decide_with_quick_retry(pass.client.as_ref(), request)
                .await
            {
                Ok(outcome) => outcome,
                Err(error) => {
                    // Best-effort by contract: a decision outage must never cost
                    // the extraction the job already paid for.
                    tracing::warn!(
                        %error,
                        scene_index = gap.scene_index,
                        "ai outfit-continuity: decision request failed, Pass 2 stops"
                    );
                    report.undecided += 1;
                    break;
                }
            };
        usage.record(outcome.usage);
        let answer = outcome.answers.get(question_keys::OUTFIT_CONTINUITY);
        let resolved = answer.and_then(|answer| resolve_continuity_outcome(answer, prior));
        let Some(resolved) = resolved else {
            report.undecided += 1;
            continue;
        };
        let candidates = continuity_candidates(gap, prior, scene);
        match resolved {
            ContinuityOutcome::Continue {
                prior: source,
                confidence,
            } => {
                attached.push((
                    position,
                    DraftOutfit {
                        character_name: gap.character_name.clone(),
                        name: source.name,
                        notes: None,
                        // A continued look quotes nothing: the source row carries
                        // the quote, and duplicating it here would let the two
                        // drift apart.
                        source_quote: String::new(),
                        origin: DraftOutfitOrigin::ContinuedFromScene,
                        provenance: Some(DraftOutfitProvenance {
                            source_draft_ref: Some(source.source_draft_ref),
                            source_scene_number: source.source_scene_number,
                            confidence,
                        }),
                        pieces: Vec::new(),
                    },
                ));
                report.continued += 1;
            }
            ContinuityOutcome::Infer { confidence } => match context_look_name(scene) {
                Some(name) => {
                    tracing::info!(
                        scene_index = gap.scene_index,
                        character = %gap.character_name,
                        confidence,
                        "ai outfit-continuity: inferred a context look"
                    );
                    attached.push((
                        position,
                        DraftOutfit {
                            character_name: gap.character_name.clone(),
                            name: name.clone(),
                            notes: None,
                            source_quote: String::new(),
                            origin: DraftOutfitOrigin::InferredFromContext,
                            provenance: Some(DraftOutfitProvenance {
                                // An inferred look has no source row of its own:
                                // the scene it belongs to IS the source.
                                source_draft_ref: None,
                                source_scene_number: None,
                                confidence,
                            }),
                            pieces: Vec::new(),
                        },
                    ));
                    // The reviewer must see that wardrobe was INFERRED rather
                    // than extracted, and can replace or drop it.
                    uncertainties.push(gap_uncertainty(
                        gap,
                        vec![DraftOutfitCandidate {
                            origin: DraftOutfitOrigin::InferredFromContext,
                            name,
                            source_draft_ref: draft_row_ref(scene, gap.scene_index),
                            source_scene_number: gap.scene_number,
                            confidence,
                        }],
                        format!(
                            "outfit of {} was inferred from the scene context (confidence {confidence:.2}); review it",
                            gap.character_name
                        ),
                    ));
                    report.inferred += 1;
                }
                // No location to derive a label from: the inference would have
                // to invent one, so the gap is surfaced instead (design D4).
                None => {
                    uncertainties.push(gap_uncertainty(
                        gap,
                        candidates,
                        format!(
                            "no outfit for {} and the scene gives no location to derive one from",
                            gap.character_name
                        ),
                    ));
                    report.gaps_reported += 1;
                }
            },
            ContinuityOutcome::Gap { confidence } => {
                // The candidates are derived without a decision; stamp each with
                // the probability the model just reported, so the reviewer sees
                // the actual confidence of the choice they are offered.
                let candidates = candidates
                    .into_iter()
                    .map(|candidate| DraftOutfitCandidate {
                        confidence,
                        ..candidate
                    })
                    .collect();
                uncertainties.push(gap_uncertainty(
                    gap,
                    candidates,
                    format!(
                        "no certain wardrobe state for {} (confidence {confidence:.2}); pick a look or leave the scene empty",
                        gap.character_name
                    ),
                ));
                report.gaps_reported += 1;
            }
        }
    }

    for (position, outfit) in attached {
        let gap = &gaps[position];
        let scene = &mut preview.scenes[gap.scene_index];
        // Never a second look for one figure in one scene — the pass would
        // otherwise contradict its own eligibility gate.
        if scene
            .outfits
            .iter()
            .any(|existing| character_identity(&existing.character_name) == gap.character_identity)
        {
            continue;
        }
        scene.outfits.push(outfit);
    }
    preview.uncertainties.extend(uncertainties);
    if report.gaps > 0 {
        tracing::info!(
            gaps = report.gaps,
            continued = report.continued,
            inferred = report.inferred,
            reported = report.gaps_reported,
            undecided = report.undecided,
            "ai outfit-continuity: Pass 2 finished"
        );
    }
    report
}

/// One gap uncertainty — always non-blocking: a gap is information, not a
/// blocker, so the preview stays appliable and the reviewer may simply leave the
/// scene without an outfit.
fn gap_uncertainty(
    gap: &OutfitContinuityGap,
    candidates: Vec<DraftOutfitCandidate>,
    note: String,
) -> Uncertainty {
    Uncertainty {
        scene_index: gap.scene_index,
        field: CONTINUITY_FIELD.to_owned(),
        note,
        suggested_value: candidates.first().map(|candidate| candidate.name.clone()),
        kind: UncertaintyKind::DroppedRow,
        candidates,
    }
}

#[cfg(test)]
#[path = "outfit_continuity_tests.rs"]
mod outfit_continuity_tests;
