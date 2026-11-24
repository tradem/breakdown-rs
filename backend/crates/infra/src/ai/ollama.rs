// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: gemini-4-argon (opencode-go)

use async_trait::async_trait;
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use breakdown_core::ai::{
    LlmCallOutcome, LlmCallUsage, LlmChatRequest, LlmClient, LlmProvider, LlmVisionRequest,
    SchedulePageExtraction, ScriptContext,
};
use breakdown_core::error::DomainError;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::time::Duration;

use super::client::{RateLimitVerdict, classify_http_status_rich, classify_transport_error};
use super::transport::ollama_redirect_policy;
use super::user_agent::resolve_user_agent;
use super::{CuratedLlmProvider, CuratedProviderUrls};
use crate::retry::{log_hint, parse_retry_hint};

#[cfg(test)]
#[path = "ollama_tests.rs"]
mod ollama_tests;

/// Ollama adapter. Ollama's broad JSON mode is used when strict schema mode is
/// unavailable; malformed responses are retried only a bounded number of times.
pub struct OllamaChatClient {
    http: reqwest::Client,
    max_parse_retries: u32,
    timeout: Duration,
    /// The provider breaker (issue #871). `None` in tests and in builds that run
    /// without a breaker.
    health: Option<std::sync::Arc<dyn breakdown_core::ai::ProviderHealth>>,
}

impl OllamaChatClient {
    /// Attach the provider breaker (issue #871).
    ///
    /// Inside the client on purpose: one attempt may issue up to
    /// `1 + max_parse_retries <= 4` billed requests while re-requesting a
    /// malformed answer, and a guard only at the caller's attempt boundary would
    /// let those extra requests out after another worker opened the breaker.
    #[must_use]
    pub fn with_provider_health(
        mut self,
        health: std::sync::Arc<dyn breakdown_core::ai::ProviderHealth>,
    ) -> Self {
        self.health = Some(health);
        self
    }

    /// Test seam: inject a prebuilt client. The injected client's transport
    /// configuration is caller owned, so the issue #170 local-only redirect
    /// policy is **not** applied here; the production path ([`Self::new`])
    /// applies it automatically.
    pub fn with_http(http: reqwest::Client, max_parse_retries: u32, timeout: Duration) -> Self {
        Self {
            http,
            // The cap is the number `AiImportBounds::attempt_worst_case_secs`
            // multiplies with (issue #871, D-C2), declared in `core`.
            max_parse_retries: max_parse_retries.min(breakdown_core::ai::OLLAMA_INNER_RETRIES),
            timeout,
            health: None,
        }
    }

    /// Production constructor: builds a client carrying the issue #170
    /// local-only redirect policy and the request deadline.
    pub fn new(max_parse_retries: u32, timeout: Duration) -> Result<Self, DomainError> {
        // Transport policy (issue #170): local-only redirects. The Ollama
        // request body carries untrusted source-document text, so a redirect
        // to a public destination must never be followed.
        let http = reqwest::Client::builder()
            .timeout(timeout)
            .redirect(ollama_redirect_policy())
            // Descriptive agent so gateways do not triage the request as a bot
            // (issue #521).
            .user_agent(resolve_user_agent(LlmProvider::Ollama))
            .build()
            .map_err(|error| DomainError::validation(format!("invalid HTTP client: {error}")))?;
        Ok(Self::with_http(http, max_parse_retries, timeout))
    }

    /// Test seam: the production-built client, so wire tests can assert its
    /// default headers reach the request (issue #521 review).
    #[cfg(test)]
    pub(crate) fn http(&self) -> &reqwest::Client {
        &self.http
    }

    async fn request_once(
        &self,
        req: &LlmChatRequest,
    ) -> Result<(String, LlmCallUsage), DomainError> {
        let body = OllamaRequest {
            model: req.model.clone(),
            // Same system/user split as the OpenAI-compatible adapter: the
            // configured prompt stays in a system message so the untrusted
            // source document cannot override instructions via delimiters.
            messages: vec![
                OllamaMessage {
                    role: "system".to_owned(),
                    content: req.prompt.clone(),
                    images: Vec::new(),
                },
                OllamaMessage {
                    role: "user".to_owned(),
                    content: format!("<context>\n{}\n</context>", req.source_text),
                    images: Vec::new(),
                },
            ],
            format: json!("json"),
            stream: false,
            options: OllamaOptions {
                num_predict: req.max_tokens,
            },
        };
        let endpoint = format!(
            "{}/chat",
            CuratedProviderUrls::base_url(LlmProvider::Ollama)
        );
        let response = self
            .http
            .post(endpoint)
            .timeout(self.timeout)
            .json(&body)
            .send()
            .await
            .map_err(classify_transport_error)?;
        let status = response.status();
        // Issue #925: read the hint before the body is consumed. Ollama itself
        // enforces no API rate limit, but deployments front it with a gateway
        // that does — the hint is what a follow-up would honour.
        let hint = parse_retry_hint(response.headers(), status);
        log_hint("ollama_chat", &hint);
        if !status.is_success() {
            // A rate-limiting gateway in front of Ollama can send a hint; the
            // self-hosted server itself cannot. Issue #926.
            //
            // Issue #927: deliberately `RateLimited`. Ollama has no account, so
            // there is no quota to exhaust — a `429` here is always a gateway
            // window, and reading the body to look for a quota code would only
            // invent evidence that cannot exist.
            return Err(classify_http_status_rich(
                status,
                "",
                hint.wait,
                RateLimitVerdict::RateLimited,
            ));
        }
        let payload = response.json::<OllamaResponse>().await.map_err(|error| {
            DomainError::validation(format!("invalid Ollama response: {error}"))
        })?;
        // Ollama reports token counts as `prompt_eval_count` (prompt) and
        // `eval_count` (completion) (issue #675). No energy telemetry.
        let usage = LlmCallUsage {
            tokens_in: payload.prompt_eval_count.unwrap_or(0),
            tokens_out: payload.eval_count.unwrap_or(0),
            cached_tokens_in: 0,
            energy_millijoules: 0,
        };
        Ok((payload.message.content, usage))
    }
    /// Multimodal counterpart of [`Self::request_once`] (issue #960): the page
    /// PNG rides in Ollama's `images` array on the user message, with the same
    /// system/user split and bounded JSON formatting as the text path. Zero
    /// Vault lookup — Ollama needs no API key.
    async fn request_vision_once(
        &self,
        req: &LlmVisionRequest,
    ) -> Result<(String, LlmCallUsage), DomainError> {
        let body = OllamaRequest {
            model: req.model.clone(),
            messages: vec![
                OllamaMessage {
                    role: "system".to_owned(),
                    content: req.prompt.clone(),
                    images: Vec::new(),
                },
                OllamaMessage {
                    role: "user".to_owned(),
                    content: format!("<context>\n{}\n</context>", req.user_context),
                    images: vec![BASE64.encode(&req.page.png_bytes)],
                },
            ],
            format: json!("json"),
            stream: false,
            options: OllamaOptions {
                num_predict: req.max_tokens,
            },
        };
        let endpoint = format!(
            "{}/chat",
            CuratedProviderUrls::base_url(LlmProvider::Ollama)
        );
        let response = self
            .http
            .post(endpoint)
            .timeout(self.timeout)
            .json(&body)
            .send()
            .await
            .map_err(classify_transport_error)?;
        let status = response.status();
        let hint = parse_retry_hint(response.headers(), status);
        log_hint("ollama_vision_chat", &hint);
        if !status.is_success() {
            // Deliberately `RateLimited` (issue #927): Ollama has no account, so
            // a `429` here is always a gateway window.
            return Err(classify_http_status_rich(
                status,
                "",
                hint.wait,
                RateLimitVerdict::RateLimited,
            ));
        }
        let payload = response.json::<OllamaResponse>().await.map_err(|error| {
            DomainError::validation(format!("invalid Ollama response: {error}"))
        })?;
        let usage = LlmCallUsage {
            tokens_in: payload.prompt_eval_count.unwrap_or(0),
            tokens_out: payload.eval_count.unwrap_or(0),
            cached_tokens_in: 0,
            energy_millijoules: 0,
        };
        Ok((payload.message.content, usage))
    }
}

#[async_trait]
impl LlmClient for OllamaChatClient {
    async fn chat_constrained(
        &self,
        req: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        if req.provider != LlmProvider::Ollama {
            return Err(DomainError::validation(
                "Ollama client received a non-Ollama request",
            ));
        }
        let mut last_parse_error = None;
        // Usage accumulates across every paid call, including the discarded
        // responses of bounded parse retries (issue #675).
        let mut total_usage = LlmCallUsage::default();
        for _attempt in 0..=self.max_parse_retries {
            // Issue #871: before EVERY billable request, parse retries included.
            if let Some(health) = &self.health
                && !health
                    .state(LlmProvider::Ollama, &req.model)
                    .await
                    // `admits_paid_call`, NOT `admits_claim` (CodeRabbit review, PR
                    // #967): this in-process gate runs inside a fenced job, so
                    // a `half_open` breaker must admit the trial holder.
                    .map(|snapshot| snapshot.admits_paid_call())
                    .unwrap_or(true)
            {
                // Issue #970 (CodeRabbit review PR #967): prior billed
                // responses of this attempt travel on the sentinel.
                return Err(super::provider_health::breaker_open_error_with_usage(
                    total_usage,
                ));
            }
            // Issue #970 (CodeRabbit review PR #967 round 9): prior billed
            // responses of this attempt ride the error instead of being
            // dropped at the `?`.
            let (content, usage) = self
                .request_once(&req)
                .await
                .map_err(|error| error.with_billed_usage(total_usage))?;
            total_usage.accumulate(usage);
            match serde_json::from_str::<ScriptContext>(&content) {
                Ok(context) => return Ok(LlmCallOutcome::new(context, total_usage)),
                Err(error) => last_parse_error = Some(error),
            }
        }
        let detail = last_parse_error
            .map(|error| error.to_string())
            .unwrap_or_else(|| "unknown JSON parse error".to_owned());
        Err(DomainError::validation(format!(
            "Ollama returned invalid ScriptContext after bounded retries: {detail}"
        )))
    }

    async fn chat_vision_constrained(
        &self,
        req: &LlmVisionRequest,
    ) -> Result<LlmCallOutcome<SchedulePageExtraction>, DomainError> {
        // Local-only transport: no pre-egress policy gate is needed because no
        // bytes leave the host (ADR-041 `D2`), but a misrouted request must
        // still fail closed.
        if req.provider != LlmProvider::Ollama {
            return Err(DomainError::validation(
                "Ollama client received a non-Ollama vision request",
            ));
        }
        let mut last_parse_error: Option<String> = None;
        let mut total_usage = LlmCallUsage::default();
        for _attempt in 0..=self.max_parse_retries {
            if let Some(health) = &self.health
                && !health
                    .state(LlmProvider::Ollama, &req.model)
                    .await
                    // `admits_paid_call`, NOT `admits_claim` (CodeRabbit review, PR
                    // #967): this in-process gate runs inside a fenced job, so
                    // a `half_open` breaker must admit the trial holder.
                    .map(|snapshot| snapshot.admits_paid_call())
                    .unwrap_or(true)
            {
                // Issue #970 (CodeRabbit review PR #967): prior billed
                // responses of this attempt travel on the sentinel.
                return Err(super::provider_health::breaker_open_error_with_usage(
                    total_usage,
                ));
            }
            // Issue #970 (CodeRabbit review PR #967 round 9): see the text path.
            let (content, usage) = self
                .request_vision_once(req)
                .await
                .map_err(|error| error.with_billed_usage(total_usage))?;
            total_usage.accumulate(usage);
            // Decode through the provider-facing schema type (CodeRabbit
            // review, PR #967), like the hosted vision path: a rows-less
            // object must FAIL (not silently default to an empty page), and a
            // free-string modifier (the schema permits any text plus null)
            // must normalize instead of failing the whole page.
            match serde_json::from_str::<crate::ai::client::SchedulePageExtractionSchema>(&content)
            {
                Ok(extraction) => match extraction.into_core() {
                    Ok(extraction) => return Ok(LlmCallOutcome::new(extraction, total_usage)),
                    Err(error) => last_parse_error = Some(error.to_string()),
                },
                Err(error) => last_parse_error = Some(error.to_string()),
            }
        }
        let detail = last_parse_error.unwrap_or_else(|| "unknown JSON parse error".to_owned());
        Err(DomainError::validation(format!(
            "Ollama returned invalid SchedulePageExtraction after bounded retries: {detail}"
        )))
    }
}

#[derive(Debug, Serialize)]
struct OllamaRequest {
    model: String,
    messages: Vec<OllamaMessage>,
    format: serde_json::Value,
    stream: bool,
    options: OllamaOptions,
}

#[derive(Debug, Serialize)]
struct OllamaMessage {
    role: String,
    content: String,
    /// Base64-encoded page image for the multimodal path (issue #960).
    /// Absent on the text path so the request body stays byte-identical.
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    images: Vec<String>,
}

#[derive(Debug, Serialize)]
struct OllamaOptions {
    num_predict: u32,
}

#[derive(Debug, Deserialize)]
struct OllamaResponse {
    message: OllamaResponseMessage,
    /// Prompt token count (`prompt_eval_count`, issue #675).
    #[serde(default)]
    prompt_eval_count: Option<u64>,
    /// Completion token count (`eval_count`, issue #675).
    #[serde(default)]
    eval_count: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct OllamaResponseMessage {
    content: String,
}
