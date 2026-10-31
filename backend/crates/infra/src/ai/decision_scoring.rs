// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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
    DraftShootingDay, UsageAccumulator, compute_scene_score, compute_shooting_day_score,
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

/// What ONE scoring unit (a script chunk, the schedule pass) left behind
/// (issue #767).
///
/// A bare row count cannot carry both facts the job telemetry needs:
///
/// * [`Self::request_failed`] — the unit's decision request failed after the
///   bounded quick retry. This is a failure **even when no row had anything to
///   score** (a schedule whose rows carry no day label): deriving the job
///   outcome from `failed_rows > 0` alone would record `ran` for a pass that
///   never answered.
/// * [`Self::failed_rows`] — how many rows the unit left without the score it
///   asked for. Nonzero without a failed request is a *partial* answer: the
///   endpoint answered, but not with what the unit needs, so those rows must
///   not be reported as a successful pass either.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ScoringReport {
    /// The unit's decision request failed after the bounded quick retry.
    pub request_failed: bool,
    /// Rows this unit left without the score it asked for.
    pub failed_rows: u32,
}

impl ScoringReport {
    /// A pass whose request answered with everything it was asked for.
    const SCORED: Self = Self {
        request_failed: false,
        failed_rows: 0,
    };

    /// Whether this unit counts as a scoring failure for the job's telemetry.
    #[must_use]
    pub fn is_failure(&self) -> bool {
        self.request_failed || self.failed_rows > 0
    }

    /// Fold another unit's report into the job-level one.
    pub fn merge(&mut self, other: Self) {
        self.request_failed |= other.request_failed;
        self.failed_rows = self.failed_rows.saturating_add(other.failed_rows);
    }
}

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
pub(crate) async fn decide_with_quick_retry(
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
///
/// Returns a [`ScoringReport`]: whether this unit's own request failed after
/// the bounded quick retry, and how many of its rows were left unscored
/// (issue #767). The caller folds it into the job's decision telemetry, so a
/// partial outage is counted instead of disappearing behind the rows that did
/// score.
///
/// A chunk that answered *partially* is deliberately not counted here: its
/// rubric records every sub-answer it did get, so the partial pass is visible
/// on the row itself. The single-question schedule pass has no such carrier
/// (see [`score_schedule_rows`]).
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
    // The Decision Model's own accumulator (issue #768): it counts the calls as
    // well as their usage, so a 2xx answer that reports no usage is still a
    // recorded Decision-Model call.
    usage: &mut UsageAccumulator,
) -> ScoringReport {
    if scenes.is_empty() {
        return ScoringReport::SCORED;
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
                "piece_count": scene.outfits.iter().map(|o| o.pieces.len()).sum::<usize>(),
                "outfit_count": scene.outfits.len(),
                "grounding": {
                    "scene_number_match": scene.scene_number.is_some()
                        && scene.scene_number == chunk_scene_number,
                    "mood_match": scene.mood.is_some() && scene.mood.as_deref() == chunk_mood,
                    "dropped_outfits": dropped_costumes.get(index).copied().unwrap_or(0),
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
            // Count before the loop consumes the slice: every row of this
            // unit is left unscored by the failed request (issue #767).
            let failed_rows = u32::try_from(scenes.len()).unwrap_or(u32::MAX);
            for scene in scenes {
                scene.scoring = Some(failed.clone());
            }
            return ScoringReport {
                request_failed: true,
                failed_rows,
            };
        }
    };
    usage.record(outcome.usage);
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
    // The request answered: no row was left unscored by a failed unit.
    ScoringReport::SCORED
}

/// Score the rows of one LLM-extracted shooting schedule (issue #722 §3.3).
///
/// One single-pass decision call evaluates the day assignments; the
/// deterministic grounding signal per row is whether the row carries a
/// parseable day label at all. Rows are grouped by day label — the score is
/// exposed per row and aggregates per `DraftShootingDay` group on apply.
///
/// Returns a [`ScoringReport`] (issue #767). The whole schedule scores in ONE
/// request whose only output is the day-assignment probability, so *any*
/// answerless outcome of that request — a failed request after the bounded
/// quick retry, or a 2xx that omits the answer — leaves every labelled row
/// without a score. Unlike a script chunk (whose rubric carries whatever
/// sub-answers did arrive), a schedule row has no per-row carrier for this, so
/// the count itself is the honest record: without it, a schedule pass that
/// scored nothing would be indistinguishable from a successful one.
pub async fn score_schedule_rows(
    pass: &DecisionPass,
    rows: &mut [breakdown_core::ai::ShootingScheduleRow],
    usage: &mut UsageAccumulator,
) -> ScoringReport {
    if rows.is_empty() {
        return ScoringReport::SCORED;
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
            // A row without a day label had no assignment to score in the
            // first place, so only the labelled rows are counted as failed.
            // The request itself failed either way — `request_failed` keeps
            // that fact even when this count is `0`.
            return ScoringReport {
                request_failed: true,
                failed_rows: u32::try_from(
                    rows.iter()
                        .filter(|row| row.shooting_day_label.is_some())
                        .count(),
                )
                .unwrap_or(u32::MAX),
            };
        }
    };
    usage.record(outcome.usage);
    let consistency = outcome
        .answers
        .get(question_keys::DAY_ASSIGNMENT_CONSISTENT)
        .and_then(|answer| answer.noul);
    let mut failed_rows = 0u32;
    for row in rows {
        // The deterministic grounding: a row without any day label has no
        // assignment to be consistent with — the score degrades to None for
        // it rather than rewarding the absence.
        if row.shooting_day_label.is_none() {
            continue;
        }
        row.shooting_day_score = compute_shooting_day_score(true, consistency);
        // The request answered 2xx but without the single answer this pass
        // asked for, so this labelled row got nothing out of it. Counted, not
        // assumed: the count follows the score the row actually holds.
        if row.shooting_day_score.is_none() {
            failed_rows = failed_rows.saturating_add(1);
        }
    }
    ScoringReport {
        request_failed: false,
        failed_rows,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use breakdown_core::ai::{DecisionAnswer, DecisionCallOutcome, LlmCallUsage, UsageAccumulator};
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

    /// A 2xx answer that carries none of the asked questions — the "the
    /// provider answered, but not with the score" case (issue #767).
    struct SilentClient;

    #[async_trait]
    impl DecisionClient for SilentClient {
        async fn decide(&self, _req: DecisionRequest) -> Result<DecisionCallOutcome, DomainError> {
            Ok(DecisionCallOutcome {
                answers: std::collections::BTreeMap::new(),
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
            outfits: Vec::new(),
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
        let mut usage = UsageAccumulator::default();
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
        assert_eq!(usage.usage.tokens_in, 0);
        assert_eq!(usage.calls, 0, "a failed call recorded nothing");
    }

    #[tokio::test]
    async fn a_successful_pass_scores_every_dimension() {
        let mut scenes = vec![scene("s1")];
        let mut usage = UsageAccumulator::default();
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
        assert_eq!(usage.usage.tokens_in, 42);
        assert_eq!(usage.usage.energy_millijoules, 7);
        assert_eq!(usage.calls, 1, "the answered call is counted");
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
        let mut usage = UsageAccumulator::default();
        let report = score_schedule_rows(&pass(Arc::new(OkClient)), &mut rows, &mut usage).await;
        assert!(rows[0].shooting_day_score.is_some());
        // A row without a day label has no assignment to score — honest None.
        assert!(rows[1].shooting_day_score.is_none());
        assert_eq!(usage.usage.tokens_in, 42);
        // The answered pass left nothing unscored (issue #767): the unlabelled
        // row was never in scope, so it is not a failure count.
        assert_eq!(report, ScoringReport::SCORED);
        assert!(!report.is_failure());
    }

    fn schedule_row(row_ref: &str, label: Option<&str>) -> breakdown_core::ai::ShootingScheduleRow {
        breakdown_core::ai::ShootingScheduleRow {
            row_ref: row_ref.to_owned(),
            scene_number: Some(10),
            episode_number: Some(294),
            shooting_day_label: label.map(str::to_owned),
            date: None,
            location: None,
            order: Some(1),
            shooting_day_score: None,
        }
    }

    #[tokio::test]
    async fn a_failed_schedule_request_reports_the_failure_even_without_labelled_rows() {
        // Issue #767 (review): every row lacked a day label, so the old
        // `failed_rows`-only contract returned `0` and the job recorded `ran`
        // for a request that never answered. The failure signal is independent
        // of the row count.
        let mut rows = vec![schedule_row("r1", None), schedule_row("r2", None)];
        let mut usage = UsageAccumulator::default();
        let report =
            score_schedule_rows(&pass(Arc::new(FailingClient)), &mut rows, &mut usage).await;
        assert!(report.request_failed, "the request did not answer");
        assert_eq!(report.failed_rows, 0, "no row had an assignment to score");
        assert!(
            report.is_failure(),
            "a failed request is a scoring failure whatever the row count"
        );
        assert!(rows.iter().all(|row| row.shooting_day_score.is_none()));
    }

    #[tokio::test]
    async fn a_failed_schedule_request_counts_its_labelled_rows() {
        let mut rows = vec![schedule_row("r1", Some("Tag 1")), schedule_row("r2", None)];
        let mut usage = UsageAccumulator::default();
        let report =
            score_schedule_rows(&pass(Arc::new(FailingClient)), &mut rows, &mut usage).await;
        assert!(report.request_failed);
        assert_eq!(report.failed_rows, 1, "only the labelled row had a chance");
    }

    #[tokio::test]
    async fn an_answerless_schedule_response_counts_its_labelled_rows_as_failed() {
        // Issue #767 (review): a 2xx without the day-assignment answer leaves
        // every labelled row unscored while the request "succeeded". The count
        // must follow the score the rows actually hold, not the response code.
        let mut rows = vec![
            schedule_row("r1", Some("Tag 1")),
            schedule_row("r2", Some("Tag 2")),
        ];
        let mut usage = UsageAccumulator::default();
        let report =
            score_schedule_rows(&pass(Arc::new(SilentClient)), &mut rows, &mut usage).await;
        assert!(!report.request_failed, "the endpoint answered");
        assert_eq!(report.failed_rows, 2, "both labelled rows stayed unscored");
        assert!(report.is_failure());
        assert!(rows.iter().all(|row| row.shooting_day_score.is_none()));
        // The answered call still billed its usage: the count reports the
        // missing SCORE, never a phantom failed request.
        assert_eq!(usage.usage.tokens_in, 42);
    }

    #[test]
    fn a_report_merges_every_unit_of_one_job() {
        let mut merged = ScoringReport::default();
        merged.merge(ScoringReport::SCORED);
        assert!(!merged.is_failure());
        merged.merge(ScoringReport {
            request_failed: false,
            failed_rows: 3,
        });
        merged.merge(ScoringReport {
            request_failed: true,
            failed_rows: 0,
        });
        assert_eq!(
            merged,
            ScoringReport {
                request_failed: true,
                failed_rows: 3,
            }
        );
        assert!(merged.is_failure());
    }
}
