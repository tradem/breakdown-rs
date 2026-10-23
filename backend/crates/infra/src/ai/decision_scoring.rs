// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! Best-effort Decision Model scoring pass (issue #722, design D3).
//!
//! One **single-pass** decision request per script chunk / LLM-extracted
//! schedule evaluates the whole rubric (`noul` + 5-level `score` questions)
//! against a state payload assembled from the chunk facts and the
//! deterministic grounding signals. The calibrated answers are blended with
//! the per-unit grounding factors into the three reviewer-facing scores.
//!
//! **Non-fatal by contract:** any decision-endpoint failure after the bounded
//! quick retry logs a `tracing::warn!`, marks the rubric `scoring_failed`,
//! and leaves every score honestly `None` — the extraction job never fails
//! and never discards extracted data because of a decision-model outage.

use std::collections::BTreeMap;

use breakdown_core::ai::{
    DecisionClient, DecisionQuestion, DecisionRequest, DecisionRubric, DraftScene,
    DraftShootingDay, LlmCallUsage, compute_scene_score, compute_shooting_day_score,
    compute_synopsis_score, question_keys, scene_grounding_factor,
};
use breakdown_core::error::DomainError;
use serde_json::json;

use super::workers::DecisionPass;

/// Quick-retry budget of the scoring pass: one bounded retry on a transient
/// error (timeout, 5xx, 429). The scoring pass is best-effort — a longer
/// budget would stall a job the extraction already finished. Worst case per
/// scoring unit: 2 requests + 1 backoff of [`DECISION_RETRY_BACKOFF`].
pub const DECISION_SCORING_ATTEMPTS: usize = 2;
pub const DECISION_RETRY_BACKOFF: std::time::Duration = std::time::Duration::from_millis(250);

/// Build the chunk rubric's question set (issue #722 §3). One shared set for
/// the whole single-pass request.
#[must_use]
pub fn script_chunk_questions() -> std::collections::BTreeMap<String, DecisionQuestion> {
    let mut questions = std::collections::BTreeMap::new();
    questions.insert(
        question_keys::CHARACTERS_COMPLETE.to_owned(),
        breakdown_core::ai::noul(
            "Are all figures named in this scene chunk accounted for in the extracted scenes?",
        ),
    );
    questions.insert(
        question_keys::COSTUMES_COMPLETE.to_owned(),
        breakdown_core::ai::noul("Are all costume-relevant descriptions of this chunk extracted?"),
    );
    questions.insert(
        question_keys::SCENE_METADATA_ACCURACY.to_owned(),
        breakdown_core::ai::score5(
            "How accurately do the extracted scene number, location and mood match the heading?",
        ),
    );
    questions.insert(
        question_keys::SYNOPSIS_GROUNDED.to_owned(),
        breakdown_core::ai::noul(
            "Are the extracted TL;DR summaries grounded in the scene text (no hallucination)?",
        ),
    );
    questions.insert(
        question_keys::SYNOPSIS_CONCISE_NO_DIALOGUE.to_owned(),
        breakdown_core::ai::noul("Are the TL;DR summaries concise and free of dialogue retelling?"),
    );
    questions.insert(
        question_keys::SYNOPSIS_COSTUME_AND_DEPT_RELEVANCE.to_owned(),
        breakdown_core::ai::score5(
            "How well do the TL;DR summaries surface costume and cross-department relevance?",
        ),
    );
    questions.insert(
        question_keys::DAY_ASSIGNMENT_CONSISTENT.to_owned(),
        breakdown_core::ai::noul(
            "Is the extracted shooting-day assignment consistent with the scene content?",
        ),
    );
    questions
}

#[allow(clippy::too_many_arguments)]
async fn decide_with_quick_retry(
    client: &dyn DecisionClient,
    request: DecisionRequest,
) -> Result<breakdown_core::ai::DecisionCallOutcome, DomainError> {
    let mut attempt = 0usize;
    loop {
        match client.decide(request.clone()).await {
            Ok(outcome) => return Ok(outcome),
            Err(error) if is_transient(&error) && attempt + 1 < DECISION_SCORING_ATTEMPTS => {
                attempt += 1;
                tokio::time::sleep(DECISION_RETRY_BACKOFF).await;
            }
            Err(error) => return Err(error),
        }
    }
}

/// Transient classification mirroring the worker loop's retry semantics:
/// timeouts / service-unavailability / rate limiting retry once, permanent
/// validation errors do not.
fn is_transient(error: &DomainError) -> bool {
    // `ServiceUnavailable` covers timeouts, 5xx and 429 in the existing
    // classification (`classify_http_status` / `classify_transport_error`);
    // everything else is permanent for the bounded scoring pass.
    matches!(error, DomainError::ServiceUnavailable { .. })
}

/// The calibrated probabilities one scoring pass consumes, `None` when the
/// endpoint did not answer that question (honest per-question degradation).
struct ChunkAnswers {
    characters_complete: Option<f32>,
    costumes_complete: Option<f32>,
    metadata_accuracy: Option<f32>,
    synopsis_grounded: Option<f32>,
    synopsis_concise: Option<f32>,
    synopsis_relevance: Option<f32>,
    day_consistent: Option<f32>,
}

fn noul_p(
    answers: &BTreeMap<String, breakdown_core::ai::DecisionAnswer>,
    key: &str,
) -> Option<f32> {
    answers.get(key).and_then(|answer| answer.noul)
}

fn score5_expected(
    answers: &BTreeMap<String, breakdown_core::ai::DecisionAnswer>,
    key: &str,
) -> Option<f32> {
    answers.get(key).and_then(|answer| answer.expected_score())
}

/// Score the scenes of one extracted script chunk (issue #722 §3.1/3.2/3.3).
///
/// `scenes` is the chunk's slice of the preview's scene rows (already pushed
/// with their deterministic grounding applied); `sanitized`, `dropped` and
/// `ambiguities` are per-scene signals captured by the extraction loop and
/// aligned with `scenes`. On success every scene receives its `scene_score`,
/// `synopsis_score`, the structured [`DecisionRubric`], and — when its day
/// group matches the chunk's day — the day group's `shooting_day_score` on
/// its own [`DraftShootingDay`] clone.
#[allow(clippy::too_many_arguments)]
pub async fn score_script_chunk(
    pass: &DecisionPass,
    heading: &str,
    text: &str,
    chunk_scene_number: Option<u32>,
    chunk_mood: Option<&str>,
    chunk_day: Option<&DraftShootingDay>,
    scenes: &mut [DraftScene],
    sanitized: &[bool],
    dropped_costumes: &[usize],
    open_ambiguities: &[usize],
    usage: &mut LlmCallUsage,
) {
    if scenes.is_empty() {
        return;
    }
    let request = DecisionRequest {
        provider: pass.provider,
        model: pass.model.clone(),
        state: json!({
            "kind": "script_chunk",
            "heading": heading,
            "text": text,
            "scene_number": chunk_scene_number,
            "mood": chunk_mood,
            "shooting_day": chunk_day.map(|day| json!({
                "number": day.number,
                "label": day.label,
            })),
            "scenes": scenes.iter().enumerate().map(|(index, scene)| json!({
                "draft_ref": scene.draft_ref,
                "scene_number": scene.scene_number,
                "location": scene.location,
                "mood": scene.mood,
                "summary": scene.summary,
                "characters": scene.characters.iter().map(|c| &c.name).collect::<Vec<_>>(),
                "costume_count": scene.costumes.len(),
                "grounding": {
                    "scene_number_match": scene.scene_number.is_some()
                        && scene.scene_number == chunk_scene_number,
                    "mood_match": scene.mood.is_some() && scene.mood.as_deref() == chunk_mood,
                    "dropped_costumes": dropped_costumes.get(index).copied().unwrap_or(0),
                    "open_ambiguities": open_ambiguities.get(index).copied().unwrap_or(0),
                },
            })).collect::<Vec<_>>(),
        }),
        questions: script_chunk_questions(),
    };
    let outcome = match decide_with_quick_retry(pass.client.as_ref(), request).await {
        Ok(outcome) => outcome,
        Err(error) => {
            tracing::warn!(
                provider = pass.provider.as_str(),
                model = %pass.model,
                %error,
                "ai-decision: scoring pass failed after the bounded quick retry; \
                 scores degrade to None (non-fatal, issue #722)"
            );
            let failed = DecisionRubric {
                decision_provider: Some(pass.provider),
                decision_model: Some(pass.model.clone()),
                sub_scores: BTreeMap::new(),
                grounding_factor: None,
                scoring_failed: true,
            };
            for scene in scenes {
                scene.scoring = Some(failed.clone());
            }
            return;
        }
    };
    usage.accumulate(outcome.usage);
    let answers = outcome.answers;
    let resolved = ChunkAnswers {
        characters_complete: noul_p(&answers, question_keys::CHARACTERS_COMPLETE),
        costumes_complete: noul_p(&answers, question_keys::COSTUMES_COMPLETE),
        metadata_accuracy: score5_expected(&answers, question_keys::SCENE_METADATA_ACCURACY),
        synopsis_grounded: noul_p(&answers, question_keys::SYNOPSIS_GROUNDED),
        synopsis_concise: noul_p(&answers, question_keys::SYNOPSIS_CONCISE_NO_DIALOGUE),
        synopsis_relevance: score5_expected(
            &answers,
            question_keys::SYNOPSIS_COSTUME_AND_DEPT_RELEVANCE,
        ),
        day_consistent: noul_p(&answers, question_keys::DAY_ASSIGNMENT_CONSISTENT),
    };
    // Day-group score: the deterministic marker scan is authoritative — a
    // chunk without a marker cannot score a day assignment.
    let day_score = compute_shooting_day_score(chunk_day.is_some(), resolved.day_consistent);

    for (index, scene) in scenes.iter_mut().enumerate() {
        let grounding = scene_grounding_factor(
            scene.scene_number.is_some() && scene.scene_number == chunk_scene_number,
            scene.mood.is_some() && scene.mood.as_deref() == chunk_mood,
            dropped_costumes.get(index).copied().unwrap_or(0),
            open_ambiguities.get(index).copied().unwrap_or(0),
        );
        scene.scene_score = compute_scene_score(
            grounding,
            resolved.characters_complete,
            resolved.costumes_complete,
            resolved.metadata_accuracy,
        );
        // A scene without a summary (outline-only block) stays None; a
        // summary the #668 guard rewrote (`was_sanitized`, now summary-less
        // itself) scores the honest 0.0.
        let was_sanitized = sanitized.get(index).copied().unwrap_or(false);
        scene.synopsis_score = if scene.summary.is_none() && !was_sanitized {
            None
        } else {
            compute_synopsis_score(
                was_sanitized,
                resolved.synopsis_grounded,
                resolved.synopsis_concise,
                resolved.synopsis_relevance,
            )
        };
        // The chunk's day decision applies to the scene's own day clone only
        // when it is the SAME day group the chunk's marker carried.
        if let (Some(chunk_day), Some(scene_day)) = (chunk_day, scene.shooting_day.as_mut())
            && chunk_day.group_key().is_some()
            && chunk_day.group_key() == scene_day.group_key()
        {
            scene_day.score = day_score;
        }
        let mut sub_scores = BTreeMap::new();
        if let Some(value) = resolved.characters_complete {
            sub_scores.insert(question_keys::CHARACTERS_COMPLETE.to_owned(), value);
        }
        if let Some(value) = resolved.costumes_complete {
            sub_scores.insert(question_keys::COSTUMES_COMPLETE.to_owned(), value);
        }
        if let Some(value) = resolved.metadata_accuracy {
            sub_scores.insert(question_keys::SCENE_METADATA_ACCURACY.to_owned(), value);
        }
        if let Some(value) = resolved.synopsis_grounded {
            sub_scores.insert(question_keys::SYNOPSIS_GROUNDED.to_owned(), value);
        }
        if let Some(value) = resolved.synopsis_concise {
            sub_scores.insert(
                question_keys::SYNOPSIS_CONCISE_NO_DIALOGUE.to_owned(),
                value,
            );
        }
        if let Some(value) = resolved.synopsis_relevance {
            sub_scores.insert(
                question_keys::SYNOPSIS_COSTUME_AND_DEPT_RELEVANCE.to_owned(),
                value,
            );
        }
        if let Some(value) = resolved.day_consistent {
            sub_scores.insert(question_keys::DAY_ASSIGNMENT_CONSISTENT.to_owned(), value);
        }
        scene.scoring = Some(DecisionRubric {
            decision_provider: Some(pass.provider),
            decision_model: Some(pass.model.clone()),
            sub_scores,
            grounding_factor: Some(grounding),
            scoring_failed: false,
        });
    }
}

/// Score the rows of one LLM-extracted shooting schedule (issue #722 §3.3).
///
/// One single-pass decision call evaluates the day assignments; the
/// deterministic grounding signal per row is whether the row carries a
/// parseable day label at all. Rows are grouped by day label — the score is
/// exposed per row and aggregates per `DraftShootingDay` group on apply.
pub async fn score_schedule_rows(
    pass: &DecisionPass,
    rows: &mut [breakdown_core::ai::ShootingScheduleRow],
    usage: &mut LlmCallUsage,
) {
    if rows.is_empty() {
        return;
    }
    let mut questions = BTreeMap::new();
    questions.insert(
        question_keys::DAY_ASSIGNMENT_CONSISTENT.to_owned(),
        breakdown_core::ai::noul(
            "Are the shooting-day assignments of these schedule rows consistent with the scenes' content and order?",
        ),
    );
    questions.insert(
        question_keys::SCENE_METADATA_ACCURACY.to_owned(),
        breakdown_core::ai::score5(
            "How accurately do the extracted scene references and locations match the schedule?",
        ),
    );
    let request = DecisionRequest {
        provider: pass.provider,
        model: pass.model.clone(),
        state: json!({
            "kind": "shooting_schedule",
            "rows": rows.iter().map(|row| json!({
                "row_ref": row.row_ref,
                "episode_number": row.episode_number,
                "scene_number": row.scene_number,
                "shooting_day_label": row.shooting_day_label,
                "date": row.date,
                "location": row.location,
                "order": row.order,
                "grounding": {
                    "has_day_label": row.shooting_day_label.is_some(),
                },
            })).collect::<Vec<_>>(),
        }),
        questions,
    };
    let outcome = match decide_with_quick_retry(pass.client.as_ref(), request).await {
        Ok(outcome) => outcome,
        Err(error) => {
            tracing::warn!(
                provider = pass.provider.as_str(),
                model = %pass.model,
                %error,
                "ai-decision: schedule scoring pass failed after the bounded quick retry; \
                 scores degrade to None (non-fatal, issue #722)"
            );
            return;
        }
    };
    usage.accumulate(outcome.usage);
    let consistency = outcome
        .answers
        .get(question_keys::DAY_ASSIGNMENT_CONSISTENT)
        .and_then(|answer| answer.noul);
    for row in rows {
        // The deterministic grounding: a row without any day label has no
        // assignment to be consistent with — the score degrades to None for
        // it rather than rewarding the absence.
        if row.shooting_day_label.is_none() {
            continue;
        }
        row.shooting_day_score = compute_shooting_day_score(true, consistency);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use breakdown_core::ai::{DecisionAnswer, DecisionCallOutcome, LlmCallUsage};
    use std::sync::Arc;

    struct FailingClient;

    #[async_trait]
    impl DecisionClient for FailingClient {
        async fn decide(&self, _req: DecisionRequest) -> Result<DecisionCallOutcome, DomainError> {
            Err(DomainError::ServiceUnavailable {
                code: &breakdown_core::error_registry::AI_IMPORT_DISABLED,
                reason: "decision endpoint down".into(),
            })
        }
    }

    struct OkClient;

    #[async_trait]
    impl DecisionClient for OkClient {
        async fn decide(&self, req: DecisionRequest) -> Result<DecisionCallOutcome, DomainError> {
            let mut answers = std::collections::BTreeMap::new();
            for name in req.questions.keys() {
                answers.insert(
                    name.clone(),
                    DecisionAnswer {
                        noul: Some(0.9),
                        choice: None,
                        score: Some(vec![0.0, 0.0, 0.0, 0.0, 1.0]),
                    },
                );
            }
            Ok(DecisionCallOutcome {
                answers,
                usage: LlmCallUsage {
                    tokens_in: 42,
                    tokens_out: 0,
                    cached_tokens_in: 0,
                    energy_millijoules: 7,
                },
            })
        }
    }

    fn pass(client: Arc<dyn DecisionClient>) -> DecisionPass {
        DecisionPass {
            client,
            provider: breakdown_core::ai::LlmProvider::Neuralwatt,
            model: "clef-flash".to_owned(),
        }
    }

    fn scene(draft_ref: &str) -> DraftScene {
        DraftScene {
            draft_ref: draft_ref.to_owned(),
            scene_number: Some(1),
            location: Some("OP".into()),
            mood: Some("I/T".into()),
            summary: Some("Ben prüft die Kostüme.".into()),
            script_day: None,
            characters: Vec::new(),
            costumes: Vec::new(),
            episode: None,
            shooting_day: Some(DraftShootingDay {
                number: Some(1),
                label: Some("Tag 1".into()),
                score: None,
            }),
            scene_score: None,
            synopsis_score: None,
            scoring: None,
        }
    }

    #[tokio::test]
    async fn a_failing_decision_pass_degrades_scores_and_marks_the_rubric() {
        // The whole point of the non-fatal contract (issue #722): an endpoint
        // outage after the bounded quick retry leaves the extracted data
        // untouched, every score honestly `None`, and a `scoring_failed`
        // rubric as the telemetry signal.
        let mut scenes = vec![scene("s1"), scene("s2")];
        let mut usage = LlmCallUsage::default();
        score_script_chunk(
            &pass(Arc::new(FailingClient)),
            "1 I/T - OP",
            "Ben probiert Kostüme an.",
            Some(1),
            Some("I/T"),
            Some(&DraftShootingDay {
                number: Some(1),
                label: Some("Tag 1".into()),
                score: None,
            }),
            &mut scenes,
            &[false, false],
            &[0, 0],
            &[0, 0],
            &mut usage,
        )
        .await;
        assert!(scenes.iter().all(|scene| scene.scene_score.is_none()));
        assert!(scenes.iter().all(|scene| scene.synopsis_score.is_none()));
        assert!(
            scenes
                .iter()
                .all(|scene| scene.shooting_day.as_ref().unwrap().score.is_none())
        );
        let rubric = scenes[0].scoring.as_ref().unwrap();
        assert!(rubric.scoring_failed);
        assert!(rubric.sub_scores.is_empty());
        assert_eq!(
            rubric.decision_provider,
            Some(breakdown_core::ai::LlmProvider::Neuralwatt)
        );
        // No usage: the failed call consumed nothing.
        assert_eq!(usage.tokens_in, 0);
    }

    #[tokio::test]
    async fn a_successful_pass_scores_every_dimension() {
        let mut scenes = vec![scene("s1")];
        let mut usage = LlmCallUsage::default();
        score_script_chunk(
            &pass(Arc::new(OkClient)),
            "1 I/T - OP",
            "Ben probiert Kostüme an.",
            Some(1),
            Some("I/T"),
            Some(&DraftShootingDay {
                number: Some(1),
                label: Some("Tag 1".into()),
                score: None,
            }),
            &mut scenes,
            &[false],
            &[0],
            &[0],
            &mut usage,
        )
        .await;
        // Perfect answers + full grounding → the maximum blend.
        let score = scenes[0].scene_score.unwrap();
        assert!((0.9..=1.0).contains(&score));
        // Grounded noul 0.9 × concise 0.9 × relevance expected 1.0 → 0.81+.
        let synopsis = scenes[0].synopsis_score.unwrap();
        assert!((synopsis - 0.81).abs() < 1e-5);
        // The chunk's day group received the day score.
        assert!(scenes[0].shooting_day.as_ref().unwrap().score.is_some());
        let rubric = scenes[0].scoring.as_ref().unwrap();
        assert!(!rubric.scoring_failed);
        assert_eq!(rubric.sub_scores.len(), 7);
        assert_eq!(rubric.grounding_factor, Some(0.9));
        // Usage accumulated (input tokens + energy).
        assert_eq!(usage.tokens_in, 42);
        assert_eq!(usage.energy_millijoules, 7);
    }

    #[tokio::test]
    async fn schedule_scoring_skips_rows_without_a_day_label() {
        let mut rows = vec![
            breakdown_core::ai::ShootingScheduleRow {
                row_ref: "r1".into(),
                scene_number: Some(10),
                episode_number: Some(294),
                shooting_day_label: Some("Tag 1".into()),
                date: None,
                location: None,
                order: Some(1),
                shooting_day_score: None,
            },
            breakdown_core::ai::ShootingScheduleRow {
                row_ref: "r2".into(),
                scene_number: Some(11),
                episode_number: Some(294),
                shooting_day_label: None,
                date: None,
                location: None,
                order: Some(2),
                shooting_day_score: None,
            },
        ];
        let mut usage = LlmCallUsage::default();
        score_schedule_rows(&pass(Arc::new(OkClient)), &mut rows, &mut usage).await;
        assert!(rows[0].shooting_day_score.is_some());
        // A row without a day label has no assignment to score — honest None.
        assert!(rows[1].shooting_day_score.is_none());
        assert_eq!(usage.tokens_in, 42);
    }
}
