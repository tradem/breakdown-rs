// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Decision Model scoring primitives (issue #722).
//!
//! A Decision Model is a **non-autoregressive System One decision model**
//! (`clef-flash`, `clef`, `jev`, `metis`, …) that evaluates one `state`
//! payload against typed `questions` (`noul`, `choice`, `score`) in a single
//! forward pass and returns mathematically calibrated probability
//! distributions — unlike a generative LLM asked to emit self-confidence in
//! JSON, which suffers from verbal overconfidence.
//!
//! This module holds the pure domain side of the capability:
//! - the [`DecisionClient`] port (implemented by an `infra` HTTP adapter),
//! - the typed question/answer primitives,
//! - the curated per-provider decision model catalog,
//! - the deterministic **hybrid score** formulas that combine calibrated
//!   probabilities with server-side grounding signals into the three
//!   reviewer-facing scores (`scene_score`, `synopsis_score`,
//!   `shooting_day_score`).
//!
//! Scoring is strictly **best-effort** (non-fatal): every failure mode of the
//! decision pass degrades scores to `None` — it never fails an extraction
//! job, and it never invents a value where no evidence exists.

use std::collections::BTreeMap;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::ports::{LlmCallUsage, LlmProvider};
use crate::error::DomainError;

/// The curated providers that natively host Decision Models (issue #722).
/// A `decision_provider` outside this set is rejected at the aggregate edge.
#[must_use]
pub const fn is_decision_capable(provider: LlmProvider) -> bool {
    matches!(
        provider,
        LlmProvider::Neuralwatt | LlmProvider::EURouter | LlmProvider::OpenRouter
    )
}

/// Curated Decision Model IDs per provider (issue #722), refreshed against
/// the live catalogs at the time of writing. All of them bill **zero output
/// tokens** — a decision model emits no completion. Single source for the
/// decision-models endpoint and the aggregate validation; legacy rotated-out
/// IDs stay in the `ai_model_pricing` seed so persisted configs remain valid.
#[must_use]
pub fn curated_decision_model_ids(provider: LlmProvider) -> &'static [&'static str] {
    match provider {
        LlmProvider::Neuralwatt => &["clef-flash", "clef"],
        LlmProvider::EURouter => &["clef-flash", "metis"],
        LlmProvider::OpenRouter => &[
            "cloudflare/clef-flash",
            "cloudflare/clef",
            "typesafe/jev-1.14",
            "perplexity/pplx-decider-flash-v1.2",
            "liquid/d1",
        ],
        // `LlmProvider` is `#[non_exhaustive]`; non-decision providers have
        // no curated decision models.
        _ => &[],
    }
}

/// Whether `model` is a curated decision model of `provider` (or a legacy
/// rotated-out ID that a persisted config may still carry — the aggregate
/// validation accepts curated IDs only for *new* writes, while the worker
/// side accepts any non-empty model string for a configured decision
/// provider, so a rotation can never brick a stored config).
#[must_use]
pub fn is_curated_decision_model(provider: LlmProvider, model: &str) -> bool {
    curated_decision_model_ids(provider).contains(&model)
}

/// Question keys of the rubric (issue #722 §3). The names are part of the
/// telemetry contract — they seed the `0.5.x` automatic prompt optimization
/// reward signal and must not be renamed casually.
pub mod question_keys {
    /// All named figures of the chunk appear accounted for.
    pub const CHARACTERS_COMPLETE: &str = "characters_complete";
    /// Every listed costume is extractable from the chunk text.
    pub const COSTUMES_COMPLETE: &str = "costumes_complete";
    /// Scene metadata (number, location, mood) matches the heading — 5-level.
    pub const SCENE_METADATA_ACCURACY: &str = "scene_metadata_accuracy";
    /// The TL;DR `summary` is grounded in the scene block (no hallucination).
    pub const SYNOPSIS_GROUNDED: &str = "synopsis_grounded";
    /// The `summary` is concise and retells no dialogue.
    pub const SYNOPSIS_CONCISE_NO_DIALOGUE: &str = "synopsis_concise_no_dialogue";
    /// The `summary` carries costume / cross-department relevance — 5-level.
    pub const SYNOPSIS_COSTUME_AND_DEPT_RELEVANCE: &str = "synopsis_costume_and_dept_relevance";
    /// The schedule row's day assignment is consistent with the scene's
    /// deterministic day marker.
    pub const DAY_ASSIGNMENT_CONSISTENT: &str = "day_assignment_consistent";
}

/// One typed question a Decision Model answers about the `state`.
///
/// - `Noul`: a calibrated yes/no probability (`noul` = "not null" — the
///   model's native binary head).
/// - `Choice`: a categorical distribution over the listed options.
/// - `Score`: a discrete ordinal rating over `levels` levels (e.g. 5); the
///   answer is consumed as its expected value normalized to `0.0..=1.0`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum DecisionQuestion {
    Noul {
        /// Reviewer-facing description embedded in the request state.
        description: String,
    },
    Choice {
        description: String,
        options: Vec<String>,
    },
    Score {
        description: String,
        /// Number of ordinal levels (≥ 2). Issue #722 uses 5-level scores.
        levels: u8,
    },
}

impl DecisionQuestion {
    /// The question's wire type discriminator (telemetry stability).
    #[must_use]
    pub const fn kind(&self) -> &'static str {
        match self {
            Self::Noul { .. } => "noul",
            Self::Choice { .. } => "choice",
            Self::Score { .. } => "score",
        }
    }
}

/// The calibrated answer to one question, as probability mass.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize, ToSchema)]
pub struct DecisionAnswer {
    /// `noul`: calibrated probability that the answer is "yes".
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub noul: Option<f32>,
    /// `choice`: probability per option (keys mirror the question's options).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub choice: Option<BTreeMap<String, f32>>,
    /// `score`: probability per ordinal level, index 0 = worst.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub score: Option<Vec<f32>>,
}

impl DecisionAnswer {
    /// The expected value of a `score` answer, normalized to `0.0..=1.0`.
    /// `None` when the answer carries no score distribution.
    #[must_use]
    pub fn expected_score(&self) -> Option<f32> {
        let distribution = self.score.as_ref()?;
        if distribution.is_empty() {
            return None;
        }
        let levels = distribution.len();
        let mut expected = 0.0_f32;
        let mut total = 0.0_f32;
        for (index, probability) in distribution.iter().enumerate() {
            let probability = probability.max(0.0);
            expected += index as f32 * probability;
            total += probability;
        }
        if total <= 0.0 {
            return None;
        }
        // Normalize to 0.0..=1.0 over the level axis; clamp defends against a
        // slightly-overfeeding distribution (rounding in the provider payload).
        let normalized = expected / (levels as f32 - 1.0).max(1.0) / total;
        Some(normalized.clamp(0.0, 1.0))
    }
}

/// One single-pass decision request (design D2): the configured
/// `(provider, model)` pair, the `state` payload to evaluate, and the named
/// questions to answer — all in one non-autoregressive forward pass.
#[derive(Debug, Clone, PartialEq)]
pub struct DecisionRequest {
    pub provider: LlmProvider,
    pub model: String,
    /// The evaluated payload (chunk/schedule facts + deterministic grounding
    /// signals). Free-form JSON — the provider's `state` object.
    pub state: serde_json::Value,
    /// Named questions, ordered by name for deterministic wire payloads.
    pub questions: BTreeMap<String, DecisionQuestion>,
}

/// The outcome of one decision call: the calibrated answers plus the call's
/// usage telemetry (a decision model emits **zero** completion tokens; input
/// tokens and — where the provider reports it — millijoules energy).
#[derive(Debug, Clone, PartialEq)]
pub struct DecisionCallOutcome {
    pub answers: BTreeMap<String, DecisionAnswer>,
    pub usage: LlmCallUsage,
}

/// Port over the provider Decision API (design D2). Implemented by the
/// `infra` HTTP adapter, which enforces the ADR-024 / issue #170 transport
/// guards (HTTPS-only, DNS-rebinding pin, descriptive `User-Agent`).
#[async_trait]
pub trait DecisionClient: Send + Sync {
    /// Evaluate `req` in one forward pass. Errors are the caller's cue to
    /// degrade scores to `None` — never to fail the extraction job.
    async fn decide(&self, req: DecisionRequest) -> Result<DecisionCallOutcome, DomainError>;
}

/// Convenience constructor for the rubric's `noul` questions.
#[must_use]
pub fn noul(description: impl Into<String>) -> DecisionQuestion {
    DecisionQuestion::Noul {
        description: description.into(),
    }
}

/// Convenience constructor for the rubric's 5-level `score` questions.
#[must_use]
pub fn score5(description: impl Into<String>) -> DecisionQuestion {
    DecisionQuestion::Score {
        description: description.into(),
        levels: 5,
    }
}

// ── Hybrid score formulas (issue #722 §3, design D3) ────────────────────────

/// Deterministic grounding factor of one extracted scene chunk.
///
/// Combines the server-side signals the extraction pipeline already computes:
/// - `scene_number_match`: the deterministic heading scan's number survived
///   on the row (the model agreed with the document),
/// - `mood_match`: a canonical set-shorthand mood is present,
/// - `dropped_costumes`: rows `verify_draft_costumes` removed (grounding),
/// - `open_ambiguities`: unresolved `FieldAmbiguity` uncertainties.
///
/// Returns a factor in `0.0..=1.0`; penalties are additive per dropped row
/// / ambiguity and saturate at zero.
#[must_use]
pub fn scene_grounding_factor(
    scene_number_match: bool,
    mood_match: bool,
    dropped_costumes: usize,
    open_ambiguities: usize,
) -> f32 {
    let factor = 0.5 + f32::from(scene_number_match) * 0.2 + f32::from(mood_match) * 0.2;
    let penalties = dropped_costumes as f32 * 0.1 + open_ambiguities as f32 * 0.05;
    (factor - penalties).clamp(0.0, 1.0)
}

/// Compute the reviewer-facing **scene score** (issue #722 §3.1).
///
/// `grounding` is [`scene_grounding_factor`]'s output; the three `Option`s
/// are the calibrated question probabilities (`characters_complete` /
/// `costumes_complete` `noul`, `scene_metadata_accuracy` expected score).
/// `None` when the decision pass produced no usable answers (no decision
/// model configured, endpoint failure) — the honest degradation, never a
/// fabricated mid-range value.
#[must_use]
pub fn compute_scene_score(
    grounding: f32,
    characters_complete: Option<f32>,
    costumes_complete: Option<f32>,
    metadata_accuracy: Option<f32>,
) -> Option<f32> {
    let characters = characters_complete?;
    let costumes = costumes_complete?;
    let metadata = metadata_accuracy?;
    let decision_mean = (characters + costumes + metadata) / 3.0;
    // Geometric-style blend: a bad grounding factor caps the whole score,
    // but perfect decisions cannot fully rescue an ungrounded chunk.
    Some((grounding * 0.4 + decision_mean * 0.6).clamp(0.0, 1.0))
}

/// Compute the reviewer-facing **synopsis score** (issue #722 §3.2).
///
/// `sanitized` = `sanitize_meta_summary` rewrote the summary to `null` —
/// the score is honestly `Some(0.0)` (the guard *did* find a violation).
/// A block that legitimately has no `summary` (outline-only) stays `None`.
/// `grounded` is the hallucination multiplier: an ungrounded summary scores
/// ~0 regardless of the other sub-scores.
#[must_use]
pub fn compute_synopsis_score(
    sanitized: bool,
    grounded: Option<f32>,
    concise_no_dialogue: Option<f32>,
    relevance: Option<f32>,
) -> Option<f32> {
    if sanitized {
        return Some(0.0);
    }
    let grounded = grounded?;
    let concise = concise_no_dialogue?;
    let relevance = relevance?;
    Some((grounded * concise * (0.5 + 0.5 * relevance)).clamp(0.0, 1.0))
}

/// Compute the reviewer-facing **shooting day score** (issue #722 §3.3).
///
/// `marker_match`: the scene/schedule row's day assignment agrees with the
/// deterministic day-marker scan (or, for schedule rows, the row carries a
/// parseable day label); `consistency` is the calibrated
/// `day_assignment_consistent` expected probability. `None` stays `None` —
/// no decision pass, no invented score.
#[must_use]
pub fn compute_shooting_day_score(marker_match: bool, consistency: Option<f32>) -> Option<f32> {
    let consistency = consistency?;
    Some(((0.3 + 0.7 * consistency) * f32::from(marker_match)).clamp(0.0, 1.0))
}

/// Structured rubric sub-scores persisted on the preview payload (issue
/// #722: "persist structured rubric sub-scores … to prepare the 0.5.x
/// automatic prompt optimization loop"). Additive with `serde(default)` so
/// previews stored before this field existed still deserialize.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize, ToSchema)]
pub struct DecisionRubric {
    /// Decision provider that produced the sub-scores.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision_provider: Option<LlmProvider>,
    /// Decision model that produced the sub-scores.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision_model: Option<String>,
    /// Calibrated sub-question probabilities keyed by
    /// [`question_keys`] names — the APO reward-signal foundation.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub sub_scores: BTreeMap<String, f32>,
    /// The deterministic grounding signals blended into the scores.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub grounding_factor: Option<f32>,
    /// Whether the decision endpoint failed for this unit (telemetry only —
    /// the scores degraded to `None` either way). Omitted when `false`.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub scoring_failed: bool,
}

#[cfg(test)]
#[path = "decision_tests.rs"]
mod decision_tests;
