// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Decision API adapter (issue #722, design D2).
//!
//! Routes the [`DecisionClient`] port to the curated providers' Decision
//! endpoints:
//! - **Neuralwatt**: `POST {base}/systemone` (energy-billed System One API),
//! - **EURouter**: `POST {base}/decisions` (Decisions API),
//! - **OpenRouter**: `POST https://openrouter.ai/api/alpha/decisions`.
//!
//! Transport policy (ADR-024 / issue #170): HTTPS-only, DNS-resolution pin,
//! same-origin redirects and a descriptive `User-Agent` — enforced by
//! [`build_hosted_client_with_user_agent`], the same builder the chat
//! adapters use. The request body carries no secrets beyond the bearer key.

use std::time::Duration;

use async_trait::async_trait;
use breakdown_core::ai::{
    DecisionAnswer, DecisionCallOutcome, DecisionClient, DecisionQuestion, DecisionRequest,
    LlmCallUsage, LlmProvider,
};
use breakdown_core::error::DomainError;
use breakdown_core::settings::SecretValue;
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::BTreeMap;

use super::transport::build_hosted_client_with_user_agent;
use super::user_agent::resolve_user_agent;
use crate::ai::client::{classify_http_status, classify_transport_error};

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
        // EURouter exposes the Decisions API next to its OpenAI-compatible
        // surface (`/api/v1`), selected with `output_modalities=decisions`
        // on the model listing; the evaluation endpoint is `/api/v1/decisions`.
        LlmProvider::EURouter => Some("https://api.eurouter.ai/api/v1/decisions"),
        // OpenRouter's Decisions API lives on the `/api/alpha` surface.
        LlmProvider::OpenRouter => Some("https://openrouter.ai/api/alpha/decisions"),
        _ => None,
    }
}

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

#[derive(Debug, Deserialize)]
struct DecisionWireAnswer {
    /// `noul` calibrated yes/no probability.
    #[serde(default)]
    noul: Option<f32>,
    /// `choice` categorical distribution.
    #[serde(default)]
    choice: Option<BTreeMap<String, f32>>,
    /// `score` ordinal distribution, index 0 = worst level.
    #[serde(default)]
    score: Option<Vec<f32>>,
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

/// HTTP adapter implementing [`DecisionClient`] over one provider's Decision
/// endpoint. Built per job by the worker loop with the decision credential.
pub struct HttpDecisionClient {
    http: reqwest::Client,
    provider: LlmProvider,
    endpoint: &'static str,
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
            endpoint,
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
            endpoint,
            api_key: SecretValue::new(api_key),
            timeout,
        })
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
        // One single-pass request: the whole rubric rides in one body.
        let questions: BTreeMap<&str, Value> = req
            .questions
            .iter()
            .map(|(name, question)| {
                let payload = match question {
                    DecisionQuestion::Noul { description } => json!({
                        "type": "noul",
                        "description": description,
                    }),
                    DecisionQuestion::Choice {
                        description,
                        options,
                    } => json!({
                        "type": "choice",
                        "description": description,
                        "options": options,
                    }),
                    DecisionQuestion::Score {
                        description,
                        levels,
                    } => json!({
                        "type": "score",
                        "description": description,
                        "levels": levels,
                    }),
                };
                (name.as_str(), payload)
            })
            .collect();
        let body = json!({
            "model": req.model,
            "state": req.state,
            "questions": questions,
        });
        let response = self
            .http
            .post(self.endpoint)
            .timeout(self.timeout)
            .bearer_auth(self.api_key.as_str())
            .json(&body)
            .send()
            .await
            .map_err(classify_transport_error)?;
        let status = response.status();
        if !status.is_success() {
            return Err(classify_http_status(status));
        }
        let wire = response
            .json::<DecisionWireResponse>()
            .await
            .map_err(|error| {
                DomainError::validation(format!("invalid decision response: {error}"))
            })?;
        // Unknown/missing question names are skipped — the scoring formulas
        // treat a missing answer as the honest `None` degradation.
        let mut answers = BTreeMap::new();
        for (name, wire_answer) in wire.answers {
            if !req.questions.contains_key(&name) {
                continue;
            }
            answers.insert(
                name,
                DecisionAnswer {
                    noul: wire_answer.noul,
                    choice: wire_answer.choice,
                    score: wire_answer.score,
                },
            );
        }
        let usage = wire.usage.unwrap_or_default();
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
