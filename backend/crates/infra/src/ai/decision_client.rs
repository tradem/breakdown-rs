// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Decision API adapter (issue #722, design D2; wire contract corrected by
//! issue #808).
//!
//! Routes the [`DecisionClient`] port to the curated providers' Decision
//! endpoints:
//! - **Neuralwatt**: `POST {base}/systemone` (energy-billed System One API),
//! - **EURouter**: `POST {base}/systemone` (the same System One surface under
//!   `/api/v1`; `/api/v1/decisions` does not exist and answers 404),
//! - **OpenRouter**: `POST https://openrouter.ai/api/alpha/decisions`.
//!
//! Transport policy (ADR-024 / issue #170): HTTPS-only, DNS-resolution pin,
//! same-origin redirects and a descriptive `User-Agent` — enforced by
//! [`build_hosted_client_with_user_agent`], the same builder the chat
//! adapters use. The request body carries no secrets beyond the bearer key.
//!
//! # The System One wire contract (probed live against EURouter, 2026-11-03)
//!
//! The route is only half the contract (issue #803 fixed the URL); the bodies
//! in **both** directions are the other half, and they were wrong (issue #808:
//! every scoring call answered `400 Invalid request`, so a configured Decision
//! Model scored nothing).
//!
//! **Request** — `POST /api/v1/systemone`, bearer key, one body for the whole
//! rubric:
//!
//! ```json
//! {"model": "clef-flash",
//!  "state": { … free-form evaluation payload … },
//!  "questions": {
//!    "q": {"type": "noul",   "instructions": "…"},
//!    "r": {"type": "score",  "instructions": "…",
//!          "criteria": ["wrong", "poor", "fair", "good", "exact"]},
//!    "s": {"type": "choice", "instructions": "…",
//!          "criteria": {"costume": "…", "props": "…"}}}}
//! ```
//!
//! Every question carries **`instructions`** (the text the model evaluates);
//! `score` and `choice` additionally carry **`criteria`** — the label ladder
//! (array) and the option map (name → description). The surface is validated as
//! a strict discriminated union: a question with the former `description`,
//! `options` or `levels` fields (and without `instructions`) is rejected with
//! `400 {"error":{"code":400,"message":"Invalid request","details":[{"path":
//! "questions.q.instructions","message":"Invalid input","code":
//! "invalid_union"}]}}` — and **one** bad question rejects the whole body, so a
//! wrong shape fails every chunk deterministically. `noul` accepts an optional
//! `criteria` record of `true`/`false` keys; nothing else in that record is
//! accepted, so we send none.
//!
//! **Response** — an envelope of per-question answers plus usage:
//!
//! ```json
//! {"answers": {
//!    "q": {"type": "noul",   "noul": 0.461},
//!    "r": {"type": "score",  "score": 3.2361,
//!          "legend": {"0": "wrong", …, "4": "exact"},
//!          "probabilities": {"0": 0.0149, …, "4": 0.5432},
//!          "confidence": 0.5432},
//!    "s": {"type": "choice", "choice": "props",
//!          "probabilities": {"costume": 0.2751, "props": 0.7249},
//!          "confidence": 0.7249}},
//!  "usage": {"input_tokens": 157, "output_tokens": 0, "cost": 0.0000…,
//!            "cost_currency": "EUR"}}
//! ```
//!
//! `score` is the **scalar mean** over the ladder and `choice` the **winning
//! label**; the mass rides under `probabilities` (level index → probability for
//! `score`, option name → probability for `choice`), and `legend` echoes the
//! ladder that was sent. The internal [`DecisionAnswer`] is the normalized
//! shape, so this adapter is where the mapping happens — and where a
//! contradiction (a `legend` that is not the sent ladder, a distribution that
//! does not sum to 1.0, a winning label outside its own map) is a hard error
//! rather than a silent mis-scaling.
//!
//! The providers are documented as proxying one System One surface, but only
//! EURouter has been probed live (the credential available on 2026-11-03);
//! Neuralwatt and OpenRouter are **not** verified against these bodies, which is
//! why the opt-in live smoke test (`decision_client_tests.rs`, `#[ignore]`,
//! `DECISION_LIVE_KEY`) is the artifact that detects a provider-side schema
//! change.

use std::time::Duration;

use async_trait::async_trait;
use breakdown_core::ai::{
    ChoiceOption, DecisionAnswer, DecisionCallOutcome, DecisionClient, DecisionQuestion,
    DecisionRequest, LlmCallUsage, LlmProvider, SCORE_MIN_LEVELS,
};
use breakdown_core::error::DomainError;
use breakdown_core::settings::SecretValue;
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::BTreeMap;

use super::transport::build_hosted_client_with_user_agent;
use super::user_agent::resolve_user_agent;
use crate::ai::client::{classify_http_status_with_detail, classify_transport_error};

#[cfg(test)]
#[path = "decision_client_tests.rs"]
mod decision_client_tests;

/// The curated Decision endpoint per provider. Static literals only — a
/// provider that hosts no decision models is rejected by the constructor.
#[must_use]
pub fn decision_endpoint(provider: LlmProvider) -> Option<&'static str> {
    match provider {
        // Neuralwatt hosts the System One API under its `/v1` base.
        LlmProvider::Neuralwatt => Some("https://api.neuralwatt.com/v1/systemone"),
        // EURouter proxies the SAME System One decision surface under its
        // `/api/v1` base. The earlier `/api/v1/decisions` path does not exist:
        // it answers `404 {"error":{"code":404,"message":"Route not found"}}`
        // for every request, which made each scoring call fail and left every
        // row with `scoring_failed: true` and no stars (job telemetry:
        // `outcome=scoring_failed`, `failed_rows=59/59`). Verified live:
        // `POST /api/v1/systemone` answers `401 invalid credentials` without a
        // key (route exists) while `/api/v1/decisions`, `/v1/decisions`,
        // `/api/decisions` and the `/decisions/evaluate` variants all answer
        // 404.
        //
        // The URL alone is NOT the contract — see the module docs: reachability
        // was fixed by issue #803, the request/response bodies by issue #808.
        LlmProvider::EURouter => Some("https://api.eurouter.ai/api/v1/systemone"),
        // OpenRouter's Decisions API lives on the `/api/alpha` surface.
        LlmProvider::OpenRouter => Some("https://openrouter.ai/api/alpha/decisions"),
        _ => None,
    }
}

/// Maximum number of bytes read from a NON-2xx response body before the
/// failure is classified. The detail kept for the error is further truncated to
/// 400 characters; this constant only bounds the READ, so a large error body
/// cannot hold the worker's permit for the whole request timeout.
const MAX_ERROR_DETAIL_BYTES: usize = 1024;

/// Tolerance of the `score` distribution sum check. A provider that reports
/// five 4-decimal probabilities can miss 1.0 by ≤ 0.00025; anything beyond a few
/// percent is not rounding but a different scale (a logit, a percentage, a
/// truncated map), and silently re-normalizing it would mis-scale every score
/// the rubric blends.
const PROBABILITY_SUM_TOLERANCE: f32 = 0.02;

/// Tolerance of the scalar-mean check (see
/// [`score_answers_agree_with_the_distribution`]). The live provider reports a
/// mean that equals the mass-weighted level index to within the rounding of its
/// own four-decimal probabilities (≤ 0.0003 over the samples pinned in
/// `testdata/decision_wire/` and the 2026-11-03 probes), so 0.01 leaves two
/// orders of magnitude of headroom while still catching a different scale.
const MEAN_BAND_TOLERANCE: f32 = 0.01;

/// Tolerance of the `choice` winner check: a provider may break a tie in any
/// direction, so two options within float noise are not a contradiction.
const PROBABILITY_TIE_TOLERANCE: f32 = 1e-6;

/// One wire answer of the Decision API. All three curated gateways normalize
/// on the same envelope (mirroring the chat adapters' normalization): a named
/// map of per-question probability payloads plus a usage object.
#[derive(Debug, Deserialize)]
struct DecisionWireResponse {
    #[serde(default)]
    answers: BTreeMap<String, DecisionWireAnswer>,
    #[serde(default)]
    usage: Option<DecisionWireUsage>,
}

/// One answer as the System One surface returns it (probe of 2026-11-03, see
/// the module docs). `noul` is the probability itself; `score` and `choice`
/// each carry their mass under `probabilities`.
#[derive(Debug, Deserialize)]
struct DecisionWireAnswer {
    /// The answer's own type discriminator — cross-checked against the
    /// question that was asked when the provider sends it.
    #[serde(rename = "type", default)]
    kind: Option<String>,
    /// `noul`: calibrated yes/no probability.
    #[serde(default)]
    noul: Option<f32>,
    /// `score`: the scalar mean over the ladder. The scoring formulas need the
    /// distribution, so the mean is only used to prove the provider scaled its
    /// ladder the way we did — it never reaches [`DecisionAnswer`].
    #[serde(default)]
    score: Option<f32>,
    /// `score`: the ladder the provider actually used, level index → label.
    /// Must agree with the `criteria` we sent.
    #[serde(default)]
    legend: Option<BTreeMap<String, String>>,
    /// `score` / `choice`: the probability mass, level index → probability /
    /// option name → probability.
    #[serde(default)]
    probabilities: Option<BTreeMap<String, f32>>,
    /// `choice`: the single winning option name.
    #[serde(default)]
    choice: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
struct DecisionWireUsage {
    #[serde(default)]
    input_tokens: u64,
    /// Hardware energy in millijoules where the provider reports it
    /// (Neuralwatt); absent → 0, never a fabricated value.
    #[serde(default)]
    millijoules: u64,
}

/// Reject `value` unless it is a usable probability.
fn checked_probability(name: &str, key: &str, value: f32) -> Result<f32, DomainError> {
    if !value.is_finite() || !(0.0..=1.0).contains(&value) {
        return Err(DomainError::validation(format!(
            "decision answer `{name}`: probability `{key}` is {value}, not a value in 0.0..=1.0"
        )));
    }
    Ok(value)
}

/// Parse a wire map that is keyed by a numeric index and return its values in
/// index order, rejecting anything that is not a contiguous `0..n` ladder.
fn ordered_by_index<T>(
    name: &str,
    label: &str,
    map: &BTreeMap<String, T>,
) -> Result<Vec<T>, DomainError>
where
    T: Clone,
{
    if map.is_empty() {
        return Err(DomainError::validation(format!(
            "decision answer `{name}`: {label} is empty"
        )));
    }
    let mut ordered: Vec<(usize, T)> = Vec::with_capacity(map.len());
    for (key, value) in map {
        let index: usize = key.trim().parse().map_err(|_| {
            DomainError::validation(format!(
                "decision answer `{name}`: {label} key `{key}` is not a level index"
            ))
        })?;
        ordered.push((index, value.clone()));
    }
    ordered.sort_by_key(|(index, _)| *index);
    for (position, (index, _)) in ordered.iter().enumerate() {
        if *index != position {
            return Err(DomainError::validation(format!(
                "decision answer `{name}`: {label} indices are not contiguous from 0 \
                 (found index {index} at position {position})"
            )));
        }
    }
    Ok(ordered.into_iter().map(|(_, value)| value).collect())
}

/// Cross-check the scalar `score` mean against the distribution it summarises.
///
/// The formulas blend the **mass**, so the mean is never consumed — but it is
/// the provider's own statement about that mass, and it is the cheap proof that
/// both sides mean the same ladder. A mean off the level axis (`0..=levels-1`)
/// is a different scale (1-based labels, a percentage, a logit); a mean that
/// disagrees with `Σ level × probability` means the mass and the mean describe
/// different levels, so whichever one the formulas read is mis-scaled.
///
/// Verified live (EURouter, 2026-11-03): the mean equals `Σ level × probability`
/// to within the rounding of the provider's four-decimal probabilities.
fn score_answers_agree_with_the_distribution(
    name: &str,
    mean: f32,
    distribution: &[f32],
) -> Result<(), DomainError> {
    let top = distribution.len().saturating_sub(1) as f32;
    if !mean.is_finite() || mean < -MEAN_BAND_TOLERANCE || mean > top + MEAN_BAND_TOLERANCE {
        return Err(DomainError::validation(format!(
            "decision answer `{name}`: score mean {mean} lies outside the level axis 0..={top} \
             of its own {}-level distribution",
            distribution.len()
        )));
    }
    let weighted: f32 = distribution
        .iter()
        .enumerate()
        .map(|(level, probability)| level as f32 * probability)
        .sum();
    if (mean - weighted).abs() > MEAN_BAND_TOLERANCE {
        return Err(DomainError::validation(format!(
            "decision answer `{name}`: score mean {mean} does not match the mass-weighted level \
             index {weighted} of its own distribution {distribution:?}"
        )));
    }
    Ok(())
}

/// Normalize a `score` answer into the ordinal distribution [`DecisionAnswer`]
/// carries.
///
/// The mass is ordered by **numeric level index** (never by map order), the
/// provider's `legend` must be the ladder we sent, and the distribution must
/// sum to ~1.0 — a silent mis-scaling is worse than a failed pass.
fn score_distribution(
    name: &str,
    answer: &DecisionWireAnswer,
    ladder: &[String],
) -> Result<Vec<f32>, DomainError> {
    let probabilities = answer.probabilities.as_ref().ok_or_else(|| {
        DomainError::validation(format!(
            "decision answer `{name}`: a `score` answer carries no probabilities map \
             (the provider's score is the scalar mean; the mass rides under `probabilities`)"
        ))
    })?;
    let mut distribution = ordered_by_index(name, "probabilities", probabilities)?;
    for (index, probability) in distribution.iter_mut().enumerate() {
        *probability = checked_probability(name, &index.to_string(), *probability)?;
    }
    match answer.legend.as_ref() {
        Some(legend) => {
            let labels = ordered_by_index(name, "legend", legend)?;
            let matches = labels.len() == ladder.len()
                && labels
                    .iter()
                    .zip(ladder)
                    .all(|(got, want)| got.trim().eq_ignore_ascii_case(want.trim()));
            if !matches {
                return Err(DomainError::validation(format!(
                    "decision answer `{name}`: the provider's legend {labels:?} contradicts the \
                     ladder that was sent {ladder:?}"
                )));
            }
            // A matching legend means the provider used our labels; it does not
            // mean it reported one probability per label. Two entries under a
            // five-label legend would make `expected_score` divide by one step
            // instead of four and feed an inflated score into every formula
            // that consumes `scene_metadata_accuracy`.
            if distribution.len() != ladder.len() {
                return Err(DomainError::validation(format!(
                    "decision answer `{name}`: {} probabilities for a {}-level legend",
                    distribution.len(),
                    ladder.len()
                )));
            }
        }
        // Without a legend the distribution length is the only evidence that
        // the provider used the same ladder.
        None => {
            if distribution.len() != ladder.len() {
                return Err(DomainError::validation(format!(
                    "decision answer `{name}`: {} probabilities for a {}-level ladder and no \
                     legend to explain the difference",
                    distribution.len(),
                    ladder.len()
                )));
            }
        }
    }
    let total: f32 = distribution.iter().sum();
    if (total - 1.0).abs() > PROBABILITY_SUM_TOLERANCE {
        return Err(DomainError::validation(format!(
            "decision answer `{name}`: probabilities sum to {total}, not 1.0 \
             (±{PROBABILITY_SUM_TOLERANCE})"
        )));
    }
    if let Some(mean) = answer.score {
        score_answers_agree_with_the_distribution(name, mean, &distribution)?;
    }
    Ok(distribution)
}

/// Normalize a `choice` answer into the option distribution [`DecisionAnswer`]
/// carries.
///
/// The map keys are the option names the question's `criteria` declared — which
/// is exactly the key set `continuity::resolve_continuity_outcome` reads, so an
/// answer keyed by anything else would leave the resolver comparing zeroes and
/// quietly degrading to a gap. Three contradictions are therefore hard errors:
/// an undeclared key, mass that does not sum to ~1.0 (the resolver compares the
/// raw values against `CONTINUITY_MIN_CONFIDENCE`) and a winning label that is
/// not the best option (the resolver reads the mass and ignores the label).
fn choice_distribution(
    name: &str,
    answer: &DecisionWireAnswer,
    options: &[ChoiceOption],
) -> Result<BTreeMap<String, f32>, DomainError> {
    let probabilities = answer
        .probabilities
        .as_ref()
        .filter(|map| !map.is_empty())
        .ok_or_else(|| {
            DomainError::validation(format!(
                "decision answer `{name}`: a `choice` answer carries no probabilities map \
                 (the provider's choice is the winning label; the mass rides under \
                 `probabilities`)"
            ))
        })?;
    let mut distribution = BTreeMap::new();
    for (option, probability) in probabilities {
        if option.trim().is_empty() {
            return Err(DomainError::validation(format!(
                "decision answer `{name}`: probabilities carry a blank option name"
            )));
        }
        if !options.iter().any(|declared| declared.name == *option) {
            return Err(DomainError::validation(format!(
                "decision answer `{name}`: probability key `{option}` is not one of the options \
                 the question declared {:?}",
                options
                    .iter()
                    .map(|declared| declared.name.as_str())
                    .collect::<Vec<_>>()
            )));
        }
        distribution.insert(
            option.clone(),
            checked_probability(name, option, *probability)?,
        );
    }
    let total: f32 = distribution.values().sum();
    if (total - 1.0).abs() > PROBABILITY_SUM_TOLERANCE {
        return Err(DomainError::validation(format!(
            "decision answer `{name}`: probabilities sum to {total}, not 1.0 \
             (±{PROBABILITY_SUM_TOLERANCE})"
        )));
    }
    if let Some(winner) = answer.choice.as_ref() {
        let Some(winner_probability) = distribution.get(winner).copied() else {
            return Err(DomainError::validation(format!(
                "decision answer `{name}`: the winning label `{winner}` is not a key of its own \
                 probabilities map {:?}",
                distribution.keys().collect::<Vec<_>>()
            )));
        };
        // A tie is the provider's to break; strictly more mass on another option
        // contradicts its own answer.
        if distribution
            .values()
            .any(|probability| *probability > winner_probability + PROBABILITY_TIE_TOLERANCE)
        {
            return Err(DomainError::validation(format!(
                "decision answer `{name}`: the winning label `{winner}` is not the \
                 highest-probability option of its own probabilities map {distribution:?}"
            )));
        }
    }
    Ok(distribution)
}

/// Map the provider's per-question answers onto the normalized
/// [`DecisionAnswer`] the scoring pass consumes.
///
/// Unknown question names are skipped (the scoring formulas treat a missing
/// answer as the honest `None` degradation). A known question whose answer
/// contradicts the question it was asked for is an error: a wrong-contract
/// response must not be silently reinterpreted.
fn normalize_answers(
    questions: &BTreeMap<String, DecisionQuestion>,
    wire_answers: BTreeMap<String, DecisionWireAnswer>,
) -> Result<BTreeMap<String, DecisionAnswer>, DomainError> {
    let mut answers = BTreeMap::new();
    for (name, wire_answer) in wire_answers {
        let Some(question) = questions.get(&name) else {
            continue;
        };
        if let Some(kind) = wire_answer.kind.as_deref()
            && !kind.eq_ignore_ascii_case(question.kind())
        {
            return Err(DomainError::validation(format!(
                "decision answer `{name}`: the provider answered a `{kind}` question where a \
                 `{}` question was asked",
                question.kind()
            )));
        }
        let answer = match question {
            DecisionQuestion::Noul { .. } => DecisionAnswer {
                // The `noul` head is probability mass like any other: the score
                // formulas clamp their output, but an out-of-range value would
                // still land in `DecisionRubric.sub_scores`.
                noul: wire_answer
                    .noul
                    .map(|value| checked_probability(&name, "noul", value))
                    .transpose()?,
                ..DecisionAnswer::default()
            },
            DecisionQuestion::Choice { options, .. } => DecisionAnswer {
                choice: Some(choice_distribution(&name, &wire_answer, options)?),
                ..DecisionAnswer::default()
            },
            DecisionQuestion::Score { ladder, .. } => DecisionAnswer {
                score: Some(score_distribution(&name, &wire_answer, ladder)?),
                ..DecisionAnswer::default()
            },
        };
        answers.insert(name, answer);
    }
    Ok(answers)
}

/// Build the provider wire form of one question (see the module docs for the
/// live request shape).
///
/// This is the **only** place a question becomes a provider payload, so the
/// checked-in goldens under `testdata/decision_wire/` pin the contract that a
/// wrong field silently broke (issue #808). Both directions of the union are
/// validated here rather than at the provider: a blank instruction, a ladder of
/// one level or a duplicated option name would otherwise be answered with an
/// opaque `400 Invalid request` that names none of our code.
fn question_payload(question: &DecisionQuestion) -> Result<Value, DomainError> {
    let instructions = question.instructions().trim();
    if instructions.is_empty() {
        return Err(DomainError::validation(format!(
            "decision question `{}` has no instructions",
            question.kind()
        )));
    }
    match question {
        DecisionQuestion::Noul { .. } => Ok(json!({
            "type": "noul",
            "instructions": instructions,
        })),
        DecisionQuestion::Choice { options, .. } => {
            if options.is_empty() {
                return Err(DomainError::validation(
                    "a `choice` decision question needs at least one option",
                ));
            }
            let mut criteria = BTreeMap::new();
            for option in options {
                let name = option.name.trim();
                let description = option.description.trim();
                if name.is_empty() || description.is_empty() {
                    return Err(DomainError::validation(
                        "a `choice` decision option needs a non-blank name and description",
                    ));
                }
                if criteria.insert(name, description).is_some() {
                    return Err(DomainError::validation(format!(
                        "decision option `{name}` is declared twice in one `choice` question"
                    )));
                }
            }
            Ok(json!({
                "type": "choice",
                "instructions": instructions,
                "criteria": criteria,
            }))
        }
        DecisionQuestion::Score { ladder, .. } => {
            if ladder.len() < SCORE_MIN_LEVELS {
                return Err(DomainError::validation(format!(
                    "a `score` decision question needs at least {SCORE_MIN_LEVELS} levels, got {}",
                    ladder.len()
                )));
            }
            let mut seen: Vec<String> = Vec::with_capacity(ladder.len());
            for label in ladder {
                let label = label.trim();
                if label.is_empty() {
                    return Err(DomainError::validation(
                        "a `score` decision ladder carries a blank level label",
                    ));
                }
                let normalized = label.to_lowercase();
                if seen.contains(&normalized) {
                    return Err(DomainError::validation(format!(
                        "decision ladder label `{label}` is declared twice — the answer's legend \
                         could not be matched unambiguously"
                    )));
                }
                seen.push(normalized);
            }
            Ok(json!({
                "type": "score",
                "instructions": instructions,
                "criteria": ladder,
            }))
        }
    }
}

/// HTTP adapter implementing [`DecisionClient`] over one provider's Decision
/// endpoint. Built per job by the worker loop with the decision credential.
pub struct HttpDecisionClient {
    http: reqwest::Client,
    provider: LlmProvider,
    /// The resolved Decision endpoint. OWNED (not `&'static str`) purely as a
    /// test seam: the production values still come from [`decision_endpoint`],
    /// but a child test can point an `with_http` client at a local mock server
    /// to exercise the non-2xx path end to end (CodeRabbit review, PR #806).
    endpoint: String,
    api_key: SecretValue,
    timeout: Duration,
}

impl HttpDecisionClient {
    /// Reject providers that host no decision models (fail closed: a config
    /// validated at the API edge should never reach here with one, but a
    /// hand-edited projection must not produce a client with a garbage URL).
    fn reject_non_decision_provider(provider: LlmProvider) -> Result<(), DomainError> {
        if breakdown_core::ai::is_decision_capable(provider) {
            return Ok(());
        }
        Err(DomainError::validation(format!(
            "provider {provider:?} does not host decision models"
        )))
    }

    pub async fn new(
        provider: LlmProvider,
        api_key: String,
        timeout: Duration,
    ) -> Result<Self, DomainError> {
        Self::reject_non_decision_provider(provider)?;
        if api_key.trim().is_empty() {
            return Err(DomainError::validation(
                "decision API key must not be empty",
            ));
        }
        let endpoint = decision_endpoint(provider).ok_or_else(|| {
            DomainError::validation(format!(
                "provider {provider:?} has no curated decision endpoint"
            ))
        })?;
        // Same transport policy as the chat adapters (issue #170 / #521):
        // HTTPS-only, DNS pin, same-origin redirects, descriptive User-Agent.
        let host = reqwest::Url::parse(endpoint)
            .ok()
            .and_then(|url| url.host_str().map(str::to_owned))
            .ok_or_else(|| {
                DomainError::validation(format!(
                    "curated decision endpoint for {provider:?} has no host"
                ))
            })?;
        let http =
            build_hosted_client_with_user_agent(&host, timeout, resolve_user_agent(provider))
                .await
                .map_err(|violation| DomainError::validation(violation.to_string()))?;
        Ok(Self {
            http,
            provider,
            endpoint: endpoint.to_owned(),
            api_key: SecretValue::new(api_key),
            timeout,
        })
    }

    /// Test seam: inject a prebuilt client (the caller owns transport
    /// configuration; the production path applies the issue #170 policy).
    pub fn with_http(
        http: reqwest::Client,
        provider: LlmProvider,
        api_key: String,
        timeout: Duration,
    ) -> Result<Self, DomainError> {
        Self::reject_non_decision_provider(provider)?;
        let endpoint = decision_endpoint(provider).ok_or_else(|| {
            DomainError::validation(format!(
                "provider {provider:?} has no curated decision endpoint"
            ))
        })?;
        Ok(Self {
            http,
            provider,
            endpoint: endpoint.to_owned(),
            api_key: SecretValue::new(api_key),
            timeout,
        })
    }

    /// The endpoint this client posts to (production: [`decision_endpoint`]).
    #[must_use]
    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }
}

#[async_trait]
impl DecisionClient for HttpDecisionClient {
    async fn decide(&self, req: DecisionRequest) -> Result<DecisionCallOutcome, DomainError> {
        if req.provider != self.provider {
            return Err(DomainError::validation(
                "decision request provider does not match the configured client provider",
            ));
        }
        // One single-pass request: the whole rubric rides in one body, and the
        // provider rejects the WHOLE body if one question is malformed — which
        // is why a question is validated here instead of being smuggled through
        // as free-form JSON.
        let questions: BTreeMap<&str, Value> = req
            .questions
            .iter()
            .map(|(name, question)| {
                question_payload(question).map(|payload| (name.as_str(), payload))
            })
            .collect::<Result<_, _>>()?;
        let body = json!({
            "model": req.model,
            "state": req.state,
            "questions": questions,
        });
        let mut response = self
            .http
            .post(self.endpoint.as_str())
            .timeout(self.timeout)
            .bearer_auth(self.api_key.as_str())
            .json(&body)
            .send()
            .await
            .map_err(classify_transport_error)?;
        let status = response.status();
        if !status.is_success() {
            // The provider's body says WHY (a 400 names the offending property,
            // a 404 names the route). Discarding it made every failure look
            // alike — a wrong curated URL and a rejected rubric both surfaced
            // as an unexplained `scoring_failed` row (issue #767).
            // Bound the READ of that body, not just the characters kept: the
            // 400-character cap below applies after the body is in memory, so
            // `Response::text()` would first buffer whatever the provider sends
            // (a chatty or hostile error could stream for the whole request
            // timeout while holding the job's concurrency permit). One KiB is
            // far more than any provider error message needs, and the read stops
            // there instead of waiting for the body to finish.
            let mut collected: Vec<u8> = Vec::with_capacity(MAX_ERROR_DETAIL_BYTES);
            while collected.len() < MAX_ERROR_DETAIL_BYTES {
                let Some(chunk) = response.chunk().await.map_err(classify_transport_error)? else {
                    break;
                };
                let remaining = MAX_ERROR_DETAIL_BYTES - collected.len();
                collected.extend_from_slice(&chunk[..chunk.len().min(remaining)]);
            }
            let detail = String::from_utf8_lossy(&collected);
            return Err(classify_http_status_with_detail(status, &detail));
        }
        let wire = response
            .json::<DecisionWireResponse>()
            .await
            .map_err(|error| {
                DomainError::validation(format!("invalid decision response: {error}"))
            })?;
        let DecisionWireResponse {
            answers: wire_answers,
            usage,
        } = wire;
        let answers = normalize_answers(&req.questions, wire_answers)?;
        let usage = usage.unwrap_or_default();
        // A decision model emits zero completion tokens by construction.
        Ok(DecisionCallOutcome {
            answers,
            usage: LlmCallUsage {
                tokens_in: usage.input_tokens,
                tokens_out: 0,
                cached_tokens_in: 0,
                energy_millijoules: usage.millijoules,
            },
        })
    }
}
