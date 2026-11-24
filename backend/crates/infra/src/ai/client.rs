// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: gemini-4-argon (opencode-go)

use std::time::Duration;

use async_trait::async_trait;
use breakdown_core::ai::{
    CuratedLlmProvider, LlmCallOutcome, LlmCallUsage, LlmChatRequest, LlmClient, LlmProvider,
    LlmVisionRequest, SchedulePageExtraction, ScriptContext, ShootingSchedule, ShootingScheduleRow,
    parse_schedule_scene_ref, vision_egress_compliant, vision_egress_policy,
};
use breakdown_core::error::DomainError;
use breakdown_core::settings::SecretValue;

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use reqwest::StatusCode;
use schemars::JsonSchema;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::CuratedProviderUrls;
use super::transport::build_hosted_client_with_user_agent;
use super::user_agent::resolve_user_agent;
use crate::retry::{RetryClass, log_hint, parse_retry_hint};

#[cfg(test)]
#[path = "client_tests.rs"]
mod client_tests;

/// OpenAI-compatible `/chat/completions` adapter. The provider URL is chosen
/// exclusively from the curated provider registry; callers cannot supply one.
pub struct OpenAiCompatibleChatClient {
    http: reqwest::Client,
    provider: LlmProvider,
    /// The resolved `/chat/completions` URL. OWNED (rather than derived per
    /// call) purely as a test seam: the production value still comes from
    /// [`CuratedProviderUrls::base_url`], but a [`Self::with_http`] client can
    /// be pointed at a local mock server to drive the REAL request loop —
    /// budget growth, usage summation and the number of billable requests —
    /// instead of only the pure decision function. The curated provider
    /// allowlist is untouched by this.
    endpoint: String,
    api_key: SecretValue,
    timeout: Duration,
    /// The provider breaker (issue #871, D-C2/2.9b). `None` in tests and in
    /// builds that run without a breaker: no guard, no behaviour change.
    health: Option<std::sync::Arc<dyn breakdown_core::ai::ProviderHealth>>,
}

/// Output-token budget growth per truncation retry (doubling) and the number
/// of bounded retries granted when a provider reports a token-ceiling
/// truncation (`finish_reason: "length"`). Together they bound the worst-case
/// paid cost of one `chat_constrained` call: at most
/// `MAX_TRUNCATION_RETRIES + 1` attempts with budgets
/// `B, B·2, …, B·2^MAX_TRUNCATION_RETRIES` (saturating at the `u32` ceiling) —
/// mirroring the Ollama adapter's bounded parse-or-retry. Without the growth a
/// response cut off at the caller's `max_tokens` budget failed permanently
/// although a larger budget would have succeeded (nightly AI Import smoke
/// 2026-08-13: `EOF while parsing an object at line 1 column 1158`).
const TRUNCATION_RETRY_BUDGET_GROWTH: u32 = 2;
/// Declared in `core` (issue #871, D-C2): the permit bound multiplies the two
/// nested retry layers, so the number the client actually uses and the number the
/// bound is computed from must be the same one.
const MAX_TRUNCATION_RETRIES: u32 = breakdown_core::ai::HOSTED_INNER_RETRIES;

impl OpenAiCompatibleChatClient {
    /// Attach the provider breaker (issue #871).
    ///
    /// The guard has to live **inside** the client, because one attempt is not
    /// one request: `request_decoded` issues up to `1 + MAX_TRUNCATION_RETRIES =
    /// 3` billed requests while re-requesting a truncated answer. A guard only at
    /// the caller's attempt boundary would let the second and third request go out
    /// after another worker had already opened the breaker.
    #[must_use]
    pub fn with_provider_health(
        mut self,
        health: std::sync::Arc<dyn breakdown_core::ai::ProviderHealth>,
    ) -> Self {
        self.health = Some(health);
        self
    }

    /// Refuse the next billable request when the breaker is open.
    ///
    /// A failed read admits (the consult only ever saves money).
    async fn admits_billable_request(&self, model: &str) -> bool {
        let Some(health) = &self.health else {
            return true;
        };
        health
            .state(self.provider, model)
            .await
            .map(|snapshot| snapshot.admits_claim())
            .unwrap_or(true)
    }

    /// Reject Ollama in this client: its curated base URL is plain HTTP and
    /// sending vaulted bearer credentials there would leak them (CWE-319).
    /// Ollama must be routed through `OllamaChatClient`.
    fn reject_ollama(provider: LlmProvider) -> Result<(), DomainError> {
        if provider == LlmProvider::Ollama {
            return Err(DomainError::validation(
                "Ollama must be routed through OllamaChatClient — the \
             OpenAI-compatible client would send bearer auth to its HTTP \
             base URL"
                    .to_owned(),
            ));
        }
        Ok(())
    }

    pub async fn new(
        provider: LlmProvider,
        api_key: String,
        timeout: Duration,
    ) -> Result<Self, DomainError> {
        Self::reject_ollama(provider)?;
        if api_key.trim().is_empty() {
            return Err(DomainError::validation("LLM API key must not be empty"));
        }
        // Transport policy (issue #170): HTTPS-only, same-origin redirects
        // AND a DNS-resolution guard — the curated provider hostname must
        // resolve exclusively to globally routable addresses, which are then
        // pinned for the whole request chain (initial request + same-origin
        // redirects). Vaulted bearer credentials therefore never reach an
        // internal service, even if the hostname text is allowlisted but
        // resolves privately (DNS rebinding).
        let host = Self::hosted_origin_host(provider)?;
        let http =
            build_hosted_client_with_user_agent(&host, timeout, resolve_user_agent(provider))
                .await
                .map_err(|violation| DomainError::validation(violation.to_string()))?;
        Ok(Self {
            http,
            provider,
            endpoint: Self::curated_endpoint(provider)?,
            api_key: SecretValue::new(api_key),
            timeout,
            health: None,
        })
    }

    /// Host of the curated provider base URL. The base URLs are static
    /// literals under our control; a parse failure is a programming error and
    /// surfaces as a validation error (fail closed, no panic).
    fn hosted_origin_host(provider: LlmProvider) -> Result<String, DomainError> {
        let base = CuratedProviderUrls::base_url(provider);
        let url = reqwest::Url::parse(base).map_err(|error| {
            DomainError::validation(format!(
                "invalid curated base URL for {provider:?}: {error}"
            ))
        })?;
        url.host_str().map(str::to_owned).ok_or_else(|| {
            DomainError::validation(format!("curated base URL for {provider:?} has no host"))
        })
    }

    /// Test seam: inject a prebuilt client while still enforcing the request
    /// deadline per call (the injected client may not carry one). The caller
    /// owns transport configuration when injecting; the production path
    /// ([`Self::new`]) applies the issue #170 redirect policy automatically.
    pub fn with_http(
        http: reqwest::Client,
        provider: LlmProvider,
        api_key: String,
        timeout: Duration,
    ) -> Result<Self, DomainError> {
        Self::reject_ollama(provider)?;
        if api_key.trim().is_empty() {
            return Err(DomainError::validation("LLM API key must not be empty"));
        }
        Ok(Self {
            http,
            provider,
            endpoint: Self::curated_endpoint(provider)?,
            api_key: SecretValue::new(api_key),
            timeout,
            health: None,
        })
    }

    /// The provider's own `/chat/completions` URL. Resolved once per client and
    /// stored, so the request loop cannot drift from the client's provider.
    fn curated_endpoint(provider: LlmProvider) -> Result<String, DomainError> {
        Ok(format!(
            "{}/chat/completions",
            CuratedProviderUrls::base_url(provider)
        ))
    }

    fn endpoint(&self) -> &str {
        &self.endpoint
    }

    async fn request(
        &self,
        req: &LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        // Strict Structured Outputs (issue #726): the script path sends the
        // same `strict: true` response format as the schedule path, so its
        // schema must pass through the same post-processing — including a
        // caller-supplied `response_schema`, which is equally
        // schemars-shaped today and must not bypass the guarantee.
        let schema = match req.response_schema.clone() {
            Some(schema) => strict_compatible(schema),
            None => strict_schema::<ScriptContextSchema>(),
        };
        self.request_decoded(req, schema, "ScriptContext").await
    }

    /// One constrained `/chat/completions` round-trip against a JSON schema,
    /// decoded into `T`. Shared by `chat_constrained` (`ScriptContext`) and
    /// `extract_schedule` (`ShootingScheduleSchema`): identical transport,
    /// truncation-retry and usage-accumulation semantics, different payload.
    async fn request_decoded<T: DeserializeOwned>(
        &self,
        req: &LlmChatRequest,
        schema: serde_json::Value,
        schema_name: &str,
    ) -> Result<LlmCallOutcome<T>, DomainError> {
        // Retry policy (issue #925): this loop grants a bounded number of
        // **re-requests**, not timed retries — there is no inter-attempt pause,
        // so it consumes no `retry::Backoff`; what it does share with every
        // other provider site is the status classification and the server's
        // retry hint (below).
        let mut budget = req.max_tokens;
        let mut truncation_retries = MAX_TRUNCATION_RETRIES;
        // Usage accumulates across every paid HTTP response, including the
        // discarded responses of truncation retries (issue #675) — the
        // provider billed those tokens too.
        let mut total_usage = LlmCallUsage::default();
        loop {
            // Issue #871: BEFORE every billable request, truncation retries
            // included. An open breaker costs no request and no delay.
            if !self.admits_billable_request(&req.model).await {
                return Err(super::provider_health::breaker_open_error());
            }
            let body = ChatCompletionRequest {
                model: req.model.clone(),
                // The configured prompt (instructions) is carried in a system
                // message; the source document is untrusted user data in its own
                // message so it cannot override prompt directives via delimiters.
                messages: vec![
                    ChatMessage {
                        role: "system".to_owned(),
                        content: req.prompt.clone(),
                    },
                    ChatMessage {
                        role: "user".to_owned(),
                        content: format!("<context>\n{}\n</context>", req.source_text),
                    },
                ],
                max_tokens: budget,
                // 2026-11-20 output-budget investigation: `None` keeps the
                // request body byte-identical to the pre-field one.
                reasoning_effort: req.reasoning_effort.clone(),
                response_format: Some(json!({
                    "type": "json_schema",
                    "json_schema": {
                        "name": "script_context",
                        "strict": true,
                        "schema": schema,
                    }
                })),
            };
            let mut response = self
                .http
                .post(self.endpoint())
                .timeout(self.timeout)
                .bearer_auth(self.api_key.as_str())
                .json(&body)
                .send()
                .await
                .map_err(classify_transport_error)?;
            let status = response.status();
            // Issue #925: the hint must be read from the headers BEFORE the body
            // is consumed (`Response::json`/`chunk` take the response): the
            // schedulers honour a server-requested wait since #926.
            let hint = parse_retry_hint(response.headers(), status);
            log_hint("hosted_chat", &hint);
            if !status.is_success() {
                // Issue #927: a `429` is two conditions, and only the provider's
                // own error body tells them apart — a rate limit (wait) from an
                // exhausted quota (dead-letter). The read is bounded in bytes AND
                // in time, never fails the path it runs on, and an incomplete
                // read is not evidence (so it stays retryable).
                let body = read_error_body(&mut response, self.timeout).await;
                let verdict = body.verdict(self.provider);
                // Issue #926: the hint travels in the error payload, so the retry
                // scheduler upstream honours it without a second header read.
                return Err(classify_http_status_rich(
                    status, &body.text, hint.wait, verdict,
                ));
            }
            // Empty-completion fix (2026-11-20 incident): the identifying
            // response headers must be read BEFORE `.json()` consumes the
            // response. An empty completion is only diagnosable with the
            // provider's own request id — without it the failed call cannot
            // even be located in the provider's dashboard.
            let meta = ResponseMeta::capture(response.headers());
            let envelope = response
                .json::<ChatCompletionResponse>()
                .await
                .map_err(|error| {
                    DomainError::validation(format!("invalid LLM response: {error}"))
                })?;
            total_usage.accumulate(envelope.usage());
            let (content, finish_reason) = match step_for_response(
                &envelope,
                &meta,
                budget,
                truncation_retries,
            ) {
                ResponseStep::Decode {
                    content,
                    finish_reason,
                } => (content, finish_reason),
                ResponseStep::RetryWithBudget {
                    budget: grown,
                    retries_left,
                    reason,
                } => {
                    // The provider billed this call and answered with nothing
                    // usable. Grow the budget exactly as a truncated answer is
                    // retried: an empty body is the extreme case of a body that
                    // did not fit — a model that spends its whole output
                    // ceiling on reasoning emits no content token at all.
                    tracing::warn!(
                        provider = ?self.provider,
                        model = %req.model,
                        %reason,
                        grown_budget = grown,
                        retries_left,
                        "LLM provider returned no usable content — re-requesting with a grown budget"
                    );
                    budget = grown;
                    truncation_retries = retries_left;
                    continue;
                }
                ResponseStep::Fail { error } => {
                    tracing::warn!(
                        provider = ?self.provider,
                        model = %req.model,
                        %error,
                        "LLM provider returned no usable content — failing the attempt"
                    );
                    return Err(error);
                }
            };
            match serde_json::from_str(content) {
                Ok(context) => {
                    return Ok(LlmCallOutcome::new(context, total_usage));
                }
                Err(error) => {
                    match next_truncation_budget(finish_reason, budget, truncation_retries) {
                        Some(grown) => {
                            budget = grown;
                            truncation_retries -= 1;
                        }
                        None => {
                            let truncated = finish_reason == Some("length");
                            let suffix = if truncated {
                                " (response truncated at the output-token budget \
                                 after bounded retries)"
                            } else {
                                " (after bounded retries with a grown output-token \
                                 budget)"
                            };
                            return Err(DomainError::validation(format!(
                                "LLM JSON did not match {schema_name}: {error}{suffix}"
                            )));
                        }
                    }
                }
            }
        }
    }

    /// Multimodal counterpart of [`Self::request_decoded`] (issue #960).
    ///
    /// Mirrors the text path's bounded retry semantics — breaker consult before
    /// every billable request, usage accumulation across discarded retries,
    /// bounded truncation-budget growth — but sends an `image_url` data-URI page
    /// plus a text context part and decodes into `T`. A provider that rejects
    /// the combined `image_url` + strict `json_schema` body gets ONE bounded
    /// fallback re-request with plain JSON-object `response_format`.
    async fn request_vision_decoded<T: DeserializeOwned>(
        &self,
        req: &LlmVisionRequest,
        schema_name: &str,
    ) -> Result<LlmCallOutcome<T>, DomainError> {
        let schema = req
            .response_schema
            .clone()
            .unwrap_or_else(strict_schema::<SchedulePageExtractionSchema>);
        let data_uri = format!(
            "data:image/png;base64,{}",
            BASE64.encode(&req.page.png_bytes)
        );
        let mut plain_json_fallback = false;
        let mut budget = req.max_tokens;
        let mut truncation_retries = MAX_TRUNCATION_RETRIES;
        let mut total_usage = LlmCallUsage::default();
        loop {
            if !self.admits_billable_request(&req.model).await {
                return Err(super::provider_health::breaker_open_error());
            }
            let body = VisionChatCompletionRequest {
                model: req.model.clone(),
                messages: vec![
                    VisionChatMessage {
                        role: "system".to_owned(),
                        content: vec![VisionContentPart::Text {
                            text: req.prompt.clone(),
                        }],
                    },
                    VisionChatMessage {
                        role: "user".to_owned(),
                        content: vec![
                            VisionContentPart::ImageUrl {
                                image_url: VisionImageUrl {
                                    url: data_uri.clone(),
                                },
                            },
                            VisionContentPart::Text {
                                text: req.user_context.clone(),
                            },
                        ],
                    },
                ],
                max_tokens: budget,
                reasoning_effort: req.reasoning_effort.clone(),
                response_format: Some(if plain_json_fallback {
                    json!({ "type": "json_object" })
                } else {
                    json!({
                        "type": "json_schema",
                        "json_schema": {
                            "name": "schedule_page",
                            "strict": true,
                            "schema": schema,
                        }
                    })
                }),
            };
            let mut response = self
                .http
                .post(self.endpoint())
                .timeout(self.timeout)
                .bearer_auth(self.api_key.as_str())
                .json(&body)
                .send()
                .await
                .map_err(classify_transport_error)?;
            let status = response.status();
            let hint = parse_retry_hint(response.headers(), status);
            log_hint("hosted_vision_chat", &hint);
            if !status.is_success() {
                let body = read_error_body(&mut response, self.timeout).await;
                // One bounded fallback: a provider that rejects the combined
                // image + strict-schema body answers 4xx naming the response
                // format; retry once with plain JSON-object mode.
                if !plain_json_fallback
                    && status.is_client_error()
                    && body.text.to_ascii_lowercase().contains("response_format")
                {
                    tracing::warn!(
                        provider = ?self.provider,
                        model = %req.model,
                        "vision provider rejected image_url + json_schema; re-requesting with plain json_object response_format"
                    );
                    plain_json_fallback = true;
                    continue;
                }
                let verdict = body.verdict(self.provider);
                return Err(classify_http_status_rich(
                    status, &body.text, hint.wait, verdict,
                ));
            }
            let meta = ResponseMeta::capture(response.headers());
            let envelope = response
                .json::<ChatCompletionResponse>()
                .await
                .map_err(|error| {
                    DomainError::validation(format!("invalid LLM response: {error}"))
                })?;
            total_usage.accumulate(envelope.usage());
            let (content, finish_reason) = match step_for_response(
                &envelope,
                &meta,
                budget,
                truncation_retries,
            ) {
                ResponseStep::Decode {
                    content,
                    finish_reason,
                } => (content, finish_reason),
                ResponseStep::RetryWithBudget {
                    budget: grown,
                    retries_left,
                    reason,
                } => {
                    tracing::warn!(
                        provider = ?self.provider,
                        model = %req.model,
                        %reason,
                        grown_budget = grown,
                        retries_left,
                        "vision provider returned no usable content — re-requesting with a grown budget"
                    );
                    budget = grown;
                    truncation_retries = retries_left;
                    continue;
                }
                ResponseStep::Fail { error } => {
                    tracing::warn!(
                        provider = ?self.provider,
                        model = %req.model,
                        %error,
                        "vision provider returned no usable content — failing the attempt"
                    );
                    return Err(error);
                }
            };
            match serde_json::from_str(content) {
                Ok(decoded) => return Ok(LlmCallOutcome::new(decoded, total_usage)),
                Err(error) => {
                    match next_truncation_budget(finish_reason, budget, truncation_retries) {
                        Some(grown) => {
                            budget = grown;
                            truncation_retries -= 1;
                        }
                        None => {
                            return Err(DomainError::validation(format!(
                                "vision LLM JSON did not match {schema_name}: {error}"
                            )));
                        }
                    }
                }
            }
        }
    }
}

#[async_trait]
impl LlmClient for OpenAiCompatibleChatClient {
    async fn chat_constrained(
        &self,
        req: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        if req.provider != self.provider {
            return Err(DomainError::validation(
                "LLM request provider does not match configured client",
            ));
        }
        self.request(&req).await
    }

    async fn extract_schedule(
        &self,
        req: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ShootingSchedule>, DomainError> {
        if req.provider != self.provider {
            return Err(DomainError::validation(
                "LLM request provider does not match configured client",
            ));
        }
        let schema = strict_schema::<ShootingScheduleSchema>();
        let decoded = self
            .request_decoded::<ShootingScheduleSchema>(&req, schema, "ShootingSchedule")
            .await?;
        Ok(LlmCallOutcome::new(
            decoded.output.into_core(),
            decoded.usage,
        ))
    }

    async fn chat_vision_constrained(
        &self,
        req: LlmVisionRequest,
    ) -> Result<LlmCallOutcome<SchedulePageExtraction>, DomainError> {
        // Pre-egress provider-policy gate (ADR-041 `D2`): runs BEFORE any base64
        // encoding or HTTP call, so a rejected call performs zero egress and
        // cannot be retried into a leak by the circuit-breaker/retry loop.
        if !vision_egress_compliant(vision_egress_policy(self.provider)) {
            return Err(DomainError::validation(format!(
                "provider {:?} does not declare Zero Data Retention, no training \
                 on inputs, and EU data residency; multimodal page-image egress \
                 is refused (ADR-041 D2)",
                self.provider
            )));
        }
        if req.provider != self.provider {
            return Err(DomainError::validation(
                "LLM request provider does not match configured client",
            ));
        }
        self.request_vision_decoded(&req, "schedule_page").await
    }
}

/// One multimodal content part: an `image_url` data URI or a text part.
#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum VisionContentPart {
    ImageUrl { image_url: VisionImageUrl },
    Text { text: String },
}

#[derive(Debug, Serialize)]
struct VisionImageUrl {
    url: String,
}

/// Multimodal chat request. `content` is a JSON array of parts (unlike the
/// text path's plain string) — the OpenAI vision wire shape.
#[derive(Debug, Serialize)]
struct VisionChatCompletionRequest {
    model: String,
    messages: Vec<VisionChatMessage>,
    max_tokens: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    reasoning_effort: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    response_format: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
struct VisionChatMessage {
    role: String,
    content: Vec<VisionContentPart>,
}

/// Make a schemars-derived schema valid for OpenAI strict Structured Outputs
/// (`strict: true`, CodeRabbit review PR #725): every object must set
/// `additionalProperties: false` and list EVERY property in `required` —
/// schemars leaves optional (`Option`) fields out of `required` and emits no
/// `additionalProperties`, so a strict-enforcing provider would reject the
/// schedule request before extraction. schemars already renders `Option`
/// fields as nullable (`"type": ["string", "null"]` / `anyOf: [T, null]`),
/// so requiring them keeps every value the model may omit representable as
/// `null` — the decode semantics are unchanged.
fn strict_compatible(mut schema: serde_json::Value) -> serde_json::Value {
    fn walk(value: &mut serde_json::Value) {
        match value {
            serde_json::Value::Object(map) => {
                // Recurse first so `$defs` entries and nested objects are
                // covered too.
                for child in map.values_mut() {
                    walk(child);
                }
                let is_object = map.get("type").and_then(serde_json::Value::as_str)
                    == Some("object")
                    || map.contains_key("properties");
                if !is_object {
                    return;
                }
                map.insert(
                    "additionalProperties".to_owned(),
                    serde_json::Value::Bool(false),
                );
                let names: Vec<String> = map
                    .get("properties")
                    .and_then(serde_json::Value::as_object)
                    .map(|properties| properties.keys().cloned().collect())
                    .unwrap_or_default();
                if names.is_empty() {
                    return;
                }
                let required = map
                    .entry("required".to_owned())
                    .or_insert_with(|| serde_json::Value::Array(Vec::new()));
                if let Some(list) = required.as_array_mut() {
                    for name in names {
                        let name_value = serde_json::Value::String(name);
                        if !list.contains(&name_value) {
                            list.push(name_value);
                        }
                    }
                }
            }
            serde_json::Value::Array(items) => {
                for item in items {
                    walk(item);
                }
            }
            _ => {}
        }
    }
    walk(&mut schema);
    schema
}

/// Shared schema-preparation helper (issue #726): derive the JSON schema for
/// `T` and run it through [`strict_compatible`], so every extraction path —
/// script (`ScriptContextSchema`) and schedule (`ShootingScheduleSchema`) —
/// sends a strict Structured Outputs-compatible schema and any future schema
/// inherits the guarantee by construction instead of remembering to call
/// [`strict_compatible`] at each new call site.
fn strict_schema<T: schemars::JsonSchema>() -> serde_json::Value {
    strict_compatible(schemars::schema_for!(T).to_value())
}

/// Provider-facing mirror of [`breakdown_core::ai::ShootingSchedule`] for the
/// schedule-extraction path (issue #721). `block_id` is deliberately absent:
/// the worker sets it from the job row, never from model output.
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct ShootingScheduleSchema {
    rows: Vec<ScheduleRowSchema>,
}

/// One schedule row as the document writes it. The scene reference is
/// accepted as a STRING or a number: production schedules write
/// `<Episode>.<Scene>` references (`"294.10"`, `"03.05"`) that a JSON number
/// would coerce to the decimal `294.1` — silently turning scene 10 into
/// scene 1 (issue #721). The server splits the string as two integer
/// components ([`parse_schedule_scene_ref`]), never as a float.
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct ScheduleRowSchema {
    /// A verbatim row label of the document, used to correlate extraction
    /// with the review grid. When the document has no label, use the row's
    /// 0-based position as a string ("0", "1", …).
    row_ref: String,
    scene_number: Option<ScheduleSceneRefSchema>,
    shooting_day_label: Option<String>,
    /// ISO `YYYY-MM-DD` when the document carries a calendar date; an
    /// unparseable date degrades to `None` (the row keeps its label, the
    /// reviewer fills the date) instead of failing the extraction.
    date: Option<String>,
    location: Option<String>,
    order: Option<u32>,
}

/// A schedule scene reference exactly as the document writes it: a JSON
/// number for a plain scene number, a string for anything else (especially
/// the dot-separated `<Episode>.<Scene>` notation).
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
#[serde(untagged)]
enum ScheduleSceneRefSchema {
    Number(u32),
    Text(String),
}

/// Role modifier of one `"ROLLEN"` legend entry, as the model reports it
/// (ADR-041 `D5`, issue #960). Accepted as a free string and normalized
/// through [`ScheduleRoleModifier::parse_tag`] so truncated table cells
/// (`"(Dummy"` without the closing parenthesis) still classify.
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct ScheduleModifierSchema(String);

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct ScheduleLegendEntrySchema {
    code: String,
    character_name: String,
    #[serde(default)]
    modifier: Option<ScheduleModifierSchema>,
}

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct ScheduleCastCodeSchema(String);

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct SchedulePageRowSchema {
    row_ref: String,
    #[serde(default)]
    scene_ref: Option<String>,
    #[serde(default)]
    shooting_day_label: Option<String>,
    #[serde(default)]
    date: Option<String>,
    #[serde(default)]
    location: Option<String>,
    #[serde(default)]
    order: Option<u32>,
    #[serde(default)]
    cast_codes: Vec<ScheduleCastCodeSchema>,
}

/// Provider-facing mirror of [`breakdown_core::ai::SchedulePageExtraction`]
/// for the multimodal page-streaming schedule path (issue #960).
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct SchedulePageExtractionSchema {
    #[serde(default)]
    legend_entries: Vec<ScheduleLegendEntrySchema>,
    #[serde(default)]
    rows: Vec<SchedulePageRowSchema>,
    #[serde(default)]
    end_of_page_shooting_day_label: Option<String>,
    #[serde(default)]
    end_of_page_date: Option<String>,
}

impl ShootingScheduleSchema {
    /// Map the provider-facing rows onto the core schedule rows, decoding
    /// every scene reference losslessly (plain number → scene only; text →
    /// [`parse_schedule_scene_ref`]; an unparseable reference → both `None`,
    /// the row stays unmatched for review instead of matching by accident).
    fn into_core(self) -> ShootingSchedule {
        ShootingSchedule {
            block_id: None,
            cast_legend: Default::default(),
            rows: self
                .rows
                .into_iter()
                .map(|row| {
                    let (episode_number, scene_number, shot_suffix) = match row.scene_number {
                        Some(ScheduleSceneRefSchema::Number(number)) => (None, Some(number), None),
                        Some(ScheduleSceneRefSchema::Text(text)) => parse_schedule_scene_ref(&text),
                        None => (None, None, None),
                    };
                    ShootingScheduleRow {
                        shooting_day_score: None,
                        row_ref: row.row_ref,
                        scene_number,
                        episode_number,
                        shot_suffix,
                        shooting_day_label: row.shooting_day_label,
                        date: row.date.as_deref().and_then(|raw| raw.parse().ok()),
                        location: row.location,
                        order: row.order,
                        cast_refs: Vec::new(),
                    }
                })
                .collect(),
        }
    }
}

#[derive(Debug, Serialize)]
struct ChatCompletionRequest {
    model: String,
    messages: Vec<ChatMessage>,
    max_tokens: u32,
    /// Sent ONLY when the caller asked for one. An unset effort must produce a
    /// body byte-identical to the pre-field one: a provider that does not
    /// advertise the capability would answer `400` for the unknown parameter,
    /// which is exactly why this stays optional end to end.
    #[serde(skip_serializing_if = "Option::is_none")]
    reasoning_effort: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    response_format: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
struct ChatMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionResponse {
    choices: Vec<ChatChoice>,
    /// Provider-assigned completion id (`id`) and the model that actually
    /// SERVED the request (`model`). Both are diagnostic only: a router may
    /// answer with a different model than the one asked for, and an empty
    /// completion makes that difference worth knowing.
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    model: Option<String>,
    /// Token usage reported by the provider (issue #675). Absent on some
    /// providers/streams — tolerated, usage stays at the accumulated zeros.
    #[serde(default)]
    usage: Option<ChatUsage>,
    /// Hardware energy telemetry reported by Neuralwatt (issue #675).
    #[serde(default)]
    energy: Option<ChatEnergy>,
}

impl ChatCompletionResponse {
    /// Extract the `LlmCallUsage` of this one response (zeros when the
    /// provider reports nothing).
    fn usage(&self) -> LlmCallUsage {
        let tokens_in = self.usage.as_ref().and_then(|u| u.prompt_tokens);
        let tokens_out = self.usage.as_ref().and_then(|u| u.completion_tokens);
        let cached_tokens_in = self
            .usage
            .as_ref()
            .and_then(|u| u.prompt_tokens_details.as_ref())
            .and_then(|d| d.cached_tokens);
        let energy_millijoules = self
            .energy
            .as_ref()
            .and_then(parse_energy_millijoules)
            .unwrap_or(0);
        LlmCallUsage {
            tokens_in: tokens_in.unwrap_or(0),
            tokens_out: tokens_out.unwrap_or(0),
            cached_tokens_in: cached_tokens_in.unwrap_or(0),
            energy_millijoules,
        }
    }
}

/// OpenAI-compatible `usage` object.
#[derive(Debug, Deserialize)]
struct ChatUsage {
    #[serde(default)]
    prompt_tokens: Option<u64>,
    #[serde(default)]
    completion_tokens: Option<u64>,
    #[serde(default)]
    prompt_tokens_details: Option<ChatPromptTokensDetails>,
}

#[derive(Debug, Deserialize)]
struct ChatPromptTokensDetails {
    #[serde(default)]
    cached_tokens: Option<u64>,
}

/// Neuralwatt hardware-energy telemetry. Values are JSON numbers or numeric
/// strings in joules or kWh; parsed with integer decimal math (no floats).
#[derive(Debug, Deserialize)]
struct ChatEnergy {
    #[serde(default)]
    energy_joules: Option<serde_json::Value>,
    #[serde(default)]
    energy_kwh: Option<serde_json::Value>,
}

/// Parse a hardware-energy value into millijoules with integer arithmetic.
/// Joules take precedence over kWh (`1 kWh = 3.6 × 10^9 mJ`). Accepts JSON
/// numbers and numeric strings, both integral and fractional decimal.
fn parse_energy_millijoules(energy: &ChatEnergy) -> Option<u64> {
    if let Some(joules) = &energy.energy_joules {
        return parse_decimal_scaled(joules, JOULES_TO_MILLIJOULES);
    }
    parse_decimal_scaled(energy.energy_kwh.as_ref()?, KWH_TO_MILLIJOULES)
}

/// `1 J = 1_000 mJ`.
const JOULES_TO_MILLIJOULES: i128 = 1_000;
/// `1 kWh = 3.6 × 10^9 mJ`.
const KWH_TO_MILLIJOULES: i128 = 3_600_000_000;

/// Convert a JSON number-or-string decimal (optional `e±N` exponent —
/// serde_json renders small floats in scientific notation, e.g. `5e-6`)
/// into `value × factor` millijoules, half-up rounded, with `i128`
/// intermediate math (no floats). The FULL fraction participates in the
/// scaling: quantizing to three fraction digits before multiplying by a
/// large factor (kWh = 3.6e9) would round a realistic 0.000005 kWh Neuralwatt
/// reading (18 000 mJ) down to zero. Returns `None` for non-numeric input —
/// callers treat that as "no telemetry reported", never as zero.
fn parse_decimal_scaled(value: &serde_json::Value, factor: i128) -> Option<u64> {
    let text = match value {
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::String(s) => s.trim().to_owned(),
        _ => return None,
    };
    let (mantissa_text, exp) = match text.split_once(['e', 'E']) {
        Some((mantissa, exponent)) => (mantissa, exponent.parse::<i32>().ok()?),
        None => (text.as_str(), 0),
    };
    let (negative, digits) = match mantissa_text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, mantissa_text),
    };
    let (int_part, frac_part) = match digits.split_once('.') {
        Some((i, f)) => (i, f),
        None => (digits, ""),
    };
    if int_part.is_empty() && frac_part.is_empty() {
        return None;
    }
    if !int_part.chars().all(|c| c.is_ascii_digit())
        || !frac_part.chars().all(|c| c.is_ascii_digit())
    {
        return None;
    }
    let int_val: i128 = if int_part.is_empty() {
        0
    } else {
        int_part.parse().ok()?
    };
    // Exact value = mantissa × 10^exp × factor / 10^frac_len, half-up
    // rounded to a whole millijoule count. A positive exponent shifts the
    // decimal point before the division, so `5e-6` kWh = 18 000 mJ comes
    // out exactly instead of being quantized to zero.
    let mut mantissa = int_val;
    for digit in frac_part.chars() {
        mantissa = mantissa
            .checked_mul(10)?
            .checked_add(i128::from(digit.to_digit(10)?))?;
    }
    let scaled = if exp > 0 {
        mantissa
            .checked_mul(10_i128.checked_pow(u32::try_from(exp).ok()?)?)?
            .checked_mul(factor)?
    } else {
        mantissa.checked_mul(factor)?
    };
    let den_shift = if exp < 0 {
        // `unsigned_abs()` cannot overflow (unlike `-exp` at `i32::MIN`) —
        // `exp` comes from provider-controlled text. The checked add/pow
        // turn an absurd shift into `None` ("no telemetry"), never a panic.
        exp.unsigned_abs()
            .checked_add(u32::try_from(frac_part.len()).ok()?)?
    } else {
        frac_part.len() as u32
    };
    let den = 10_i128.checked_pow(den_shift)?;
    let (quotient, remainder) = (scaled / den, scaled % den);
    let total = if remainder * 2 >= den {
        quotient + 1
    } else {
        quotient
    };
    if negative {
        return None;
    }
    u64::try_from(total).ok()
}

#[derive(Debug, Deserialize)]
struct ChatChoice {
    message: ChatMessageResponse,
    /// Provider-side stop reason. `Some("length")` signals the response was
    /// cut off at the `max_tokens` ceiling — the JSON payload is typically
    /// truncated mid-object and must be retried with a grown budget.
    finish_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ChatMessageResponse {
    content: Option<String>,
    /// Present when the model refused instead of answering. Reported in the
    /// empty-completion diagnosis: `content: null` plus a `refusal` is a
    /// policy decision, `content: null` without one is a broken answer.
    #[serde(default)]
    refusal: Option<String>,
    /// Reasoning models (and OpenAI-compatible gateways that relay them) put
    /// their thinking here. Its LENGTH in the diagnosis tells the two causes
    /// of an empty completion apart: a large `reasoning_content` with
    /// `finish_reason: "length"` means the output ceiling was spent before the
    /// first content token.
    #[serde(default)]
    reasoning_content: Option<String>,
}

/// Infra-local schema mirror. Core remains independent of schemars while the
/// wire schema stays statically derived from the same JSON shape.
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct ScriptContextSchema {
    title: Option<String>,
    /// The production block number the scene block's page headers state
    /// (issue #827) — the number only, e.g. `2` for `Block: 2` and `98` for
    /// the glued header `Block: 098/Ep.: 294`. Null when the block states
    /// none: the deterministic scan is the primary source and this field is
    /// the fallback for a document whose header the scan could not read.
    block_number: Option<i32>,
    scenes: Vec<DraftSceneSchema>,
    uncertainties: Vec<UncertaintySchema>,
}

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct DraftSceneSchema {
    draft_ref: String,
    scene_number: Option<u32>,
    location: Option<String>,
    mood: Option<String>,
    summary: Option<String>,
    script_day: Option<String>,
    characters: Vec<String>,
    /// Outfits worn by characters of THIS scene. Empty when the block states no
    /// clothing at all — never omit the field, and never invent an entry to fill
    /// it. `strict` schema mode requires the property, so a scene without
    /// wardrobe answers with `[]`.
    outfits: Vec<DraftOutfitSchema>,
}

/// Provider-facing mirror of [`breakdown_core::ai::DraftOutfit`]. One entry per
/// look the text states for one named character.
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct DraftOutfitSchema {
    /// The character this outfit belongs to. MUST be spelled as in this scene's
    /// `characters`; an entry naming anyone else is dropped by the server.
    character_name: String,
    /// Short display name of the look, e.g. "OP-Kleidung" or
    /// "ölverschmierter Mechaniker-Overall". Derived from the text; the look's
    /// own wording when the script states one.
    name: String,
    /// The script's own wording for the look (colour, condition, material) in a
    /// sentence or two. Never move this into `summary`.
    notes: Option<String>,
    /// A verbatim fragment of the supplied text this outfit came from — for a
    /// shorthand that is the shorthand itself ("in OP", "KHK"). The server
    /// checks that the fragment occurs in the block and drops the outfit (with
    /// its pieces) when it does not.
    source_quote: String,
    /// The constituent garments of this look. Derive them when the block names
    /// only the look ("in OP" -> "OP-Kasack", "OP-Hose"): the garments a
    /// shorthand implies are what the wardrobe department needs. Empty is a
    /// valid answer for a look the text describes as a whole.
    pieces: Vec<DraftPieceSchema>,
}

/// Provider-facing mirror of [`breakdown_core::ai::DraftPiece`]. One garment of
/// an outfit: the unit the wardrobe fundus files and the season repertoire holds.
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct DraftPieceSchema {
    /// German garment name as the wardrobe department would file it:
    /// "OP-Kasack", "KHK-Hose", "Gummistiefel".
    name: String,
    /// One of the season's category names when the garment clearly belongs to
    /// one — "Oberteil", "Unterteil", "Schuhe", "Jacke", "Accessoires" — else
    /// null. An unknown value leaves the piece uncategorized, it is not an
    /// error.
    category_hint: Option<String>,
    /// Optional detail from the script (colour, condition, material).
    description: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct UncertaintySchema {
    scene_index: usize,
    field: String,
    note: String,
    suggested_value: Option<String>,
}

pub fn classify_http_status(status: StatusCode) -> DomainError {
    classify_http_status_with_detail(status, "")
}

/// Whether a provider's `429` is a **rate limit** (waiting solves it) or an
/// **exhausted quota** (nothing helps until a human acts) — issue #927.
///
/// Owned, `Copy`, payload-free on purpose: it is a verdict, not a record. The
/// supporting evidence (the provider's own bounded body) travels separately as
/// the classification `detail`, so the verdict never has to hold a `String` and
/// the error payload stays `Clone + Send + 'static` across the `await` that
/// separates the provider call from the scheduler.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RateLimitVerdict {
    /// Worth another attempt: RPM/TPM exhaustion, an unreadable body, or a
    /// provider with no quota concept at all (Ollama, EURouter's plan RPM).
    RateLimited,
    /// The account has no quota left. Retrying burns paid calls that are
    /// answered `429` again, while holding an `ai_import.concurrency_permit`.
    ///
    /// `marker` is the curated table entry that fired (`insufficient_quota`,
    /// `perdayperproject`, `free-models-per-day`, …). It travels in the verdict
    /// on purpose: the attempt narrative truncates the raw body, and a provider
    /// that puts the code behind a long `error.message` would otherwise
    /// dead-letter a job whose history does not say why (CodeRabbit review, PR
    /// #931). A `&'static str` keeps the verdict `Copy`.
    QuotaExhausted { marker: &'static str },
}

/// Largest NON-2xx response body read before the failure is classified
/// (issue #927).
///
/// The decision adapter introduced the number when a live `400` left every
/// failure unexplained (issue #767); #927 needs the same bound at the
/// hosted-chat site, where the body is now read to tell a rate limit from an
/// exhausted quota. A provider error message needs far less than a kilobyte, and
/// the read stops there instead of waiting for a chatty or hostile body to
/// finish streaming while a concurrency permit is held.
pub(crate) const MAX_ERROR_BODY_BYTES: usize = 1024;

/// Upper bound on the wall-clock budget of one error-body read (issue #927).
///
/// The byte bound alone is not a time bound: a provider can send half a chunk
/// and then stall, and `chunk().await` would wait for it until the request
/// timeout (`AI_IMPORT_REQUEST_TIMEOUT_SECS`, default 120 s) — the whole permit
/// hold for a body we only wanted as *evidence*. A provider that has already
/// answered with a failure has sent its error text long before 5 s.
///
/// This is a **cap**, not the budget itself: [`error_body_budget`] takes the
/// smaller of it and the caller's request timeout, because that knob is
/// configurable down to 1 s and a fixed 5 s deadline would then outlive the
/// request it belongs to.
pub(crate) const ERROR_BODY_DEADLINE: Duration = Duration::from_secs(5);

/// The wall-clock budget of one error-body read: at most [`ERROR_BODY_DEADLINE`],
/// and never longer than the request timeout that already bounds the response.
///
/// Pure so the composition is asserted analytically instead of slept through
/// (AGENTS.md §4).
#[must_use]
pub(crate) fn error_body_budget(request_timeout: Duration) -> Duration {
    ERROR_BODY_DEADLINE.min(request_timeout)
}

/// What one bounded error-body read produced.
///
/// The two things a caller needs are deliberately separate: the bytes that
/// arrived (for the narrative) and whether the read **completed**. A partial
/// read is not evidence (issue #927, and CodeRabbit review PR #931): a stream cut
/// mid-body by a proxy may have lost the part that changes the meaning, so the
/// classifier falls back to its conservative default while the narrative still
/// shows what arrived.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ErrorBody {
    /// The bytes that arrived, as UTF-8 (lossy) and already byte-bounded.
    pub(crate) text: String,
    /// Whether the read ended on the body's own end or on the deliberate byte
    /// bound — as opposed to an IO error or the [`ERROR_BODY_DEADLINE`], either
    /// of which leaves the body's integrity unknown.
    pub(crate) complete: bool,
}

impl ErrorBody {
    /// The [`RateLimitVerdict`] this body supports.
    ///
    /// The one rule that matters lives here instead of at each call site: **an
    /// incomplete read is never evidence**, so it stays retryable even when the
    /// bytes that did arrive look like a quota code. A wrong "non-retryable"
    /// verdict dead-letters a job a retry would have saved.
    #[must_use]
    pub(crate) fn verdict(&self, provider: LlmProvider) -> RateLimitVerdict {
        if !self.complete {
            tracing::debug!(
                provider = provider.as_str(),
                body_len = self.text.len(),
                "#927 provider error body read did not complete; a 429 stays retryable"
            );
            return RateLimitVerdict::RateLimited;
        }
        classify_provider_body(provider, &self.text)
    }
}

/// Read at most [`MAX_ERROR_BODY_BYTES`] of a response body within
/// [`error_body_budget`], chunk by chunk.
///
/// Streams with [`reqwest::Response::chunk`] instead of `text()`/`bytes()`:
/// those buffer whatever the provider sends, so an HTML gateway page or a
/// hostile error would hold the caller — and with it an
/// `ai_import.concurrency_permit` — for as long as it likes.
///
/// Two bounds **limit** that hold: at most 1 KiB is read, and the whole read
/// ends within `min(ERROR_BODY_DEADLINE, request_timeout)`. They do not always
/// end it *earlier* than the request timeout: at the knob's 1–5 s floor the
/// budget equals the timeout, so the read may last as long as the request
/// itself would have. What is guaranteed is the honest part — the read never
/// extends the permit hold beyond the request's own timeout, and at the default
/// 120 s it ends after at most 5 s instead of 120.
///
/// Never fails. It runs on a path that already decided the request failed; an IO
/// error or the deadline keeps the bytes collected so far and logs at `debug`,
/// because a broken read must not replace the provider's real failure with a
/// parsing error of our own — and it must not spend more of the timeout than the
/// budget allows.
pub(crate) async fn read_error_body(
    response: &mut reqwest::Response,
    request_timeout: Duration,
) -> ErrorBody {
    read_error_body_within(response, error_body_budget(request_timeout)).await
}

/// [`read_error_body`] against an explicit deadline (the test seam).
#[must_use]
async fn read_error_body_within(response: &mut reqwest::Response, deadline: Duration) -> ErrorBody {
    let cutoff = tokio::time::Instant::now() + deadline;
    let mut collected: Vec<u8> = Vec::with_capacity(MAX_ERROR_BODY_BYTES);
    let mut complete = true;
    while collected.len() < MAX_ERROR_BODY_BYTES {
        let remaining = cutoff.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() {
            tracing::debug!(
                "#927 provider error body read hit its deadline; classifying on what arrived"
            );
            complete = false;
            break;
        }
        match tokio::time::timeout(remaining, response.chunk()).await {
            Ok(Ok(Some(chunk))) => {
                let keep = (MAX_ERROR_BODY_BYTES - collected.len()).min(chunk.len());
                collected.extend_from_slice(&chunk[..keep]);
            }
            // The body ended (or the byte bound stopped us, which the loop
            // condition sees): a complete-enough read.
            Ok(Ok(None)) => break,
            Ok(Err(error)) => {
                tracing::debug!(
                    %error,
                    "#927 provider error body read failed; classifying on what arrived"
                );
                complete = false;
                break;
            }
            Err(_elapsed) => {
                tracing::debug!(
                    "#927 provider error body deadline elapsed; classifying on what arrived"
                );
                complete = false;
                break;
            }
        }
    }
    ErrorBody {
        text: String::from_utf8_lossy(&collected).into_owned(),
        complete,
    }
}

/// OpenAI-shaped accounts (OpenAI itself and its compatible gateways) name the
/// exhausted quota in the error `code`/`type`.
///
/// `insufficient_quota` is "you are out of credits", `credit_balance_exhausted`
/// the newer spelling of the same state, and `billing_hard_limit_reached` a
/// configured spend ceiling. All three are terminal for this job: paying for
/// another attempt cannot change them.
const OPENAI_QUOTA_MARKERS: &[&str] = &[
    "insufficient_quota",
    "credit_balance_exhausted",
    "billing_hard_limit_reached",
];

/// Gemini's `RESOURCE_EXHAUSTED` covers **both** conditions, and only the quota
/// id distinguishes them: a per-minute limit carries an RPM quota id, an
/// exhausted free tier carries a per-day one
/// (`…PerDayPerProject…`, e.g. `GenerateRequestsPerDayPerProjectPerModel-FreeTier`
/// inside `error.details[].metadata.quota_limit`).
const GEMINI_QUOTA_MARKERS: &[&str] = &["perdayperproject", "per_day_per_project"];

/// OpenRouter's free tier caps requests **per day** and says so in the message
/// (`Rate limit exceeded: free-models-per-day…`). The `X-RateLimit-*` headers
/// are deliberately not evidence: a per-minute window reaches zero the same way.
const OPENROUTER_QUOTA_MARKERS: &[&str] = &["free-models-per-day", "free_models_per_day"];

/// The curated per-provider quota markers (issue #927).
///
/// Static data, in the transport layer next to [`super::CuratedProviderUrls`],
/// and **not** user-configurable: the same trust rule as the curated URLs — user
/// input never decides how a provider failure is read. `eurouter` and `ollama`
/// are deliberately empty: EURouter's budget and spend caps arrive as `402` (not
/// `429`), its `429` is plan RPM, and Ollama is self-hosted with no account
/// quota.
fn quota_markers(provider: LlmProvider) -> &'static [&'static str] {
    match provider {
        LlmProvider::OpenAI
        | LlmProvider::Neuralwatt
        | LlmProvider::OpenCode
        | LlmProvider::OpenCodeGo => OPENAI_QUOTA_MARKERS,
        LlmProvider::Gemini => GEMINI_QUOTA_MARKERS,
        LlmProvider::OpenRouter => OPENROUTER_QUOTA_MARKERS,
        LlmProvider::EURouter | LlmProvider::Ollama => &[],
        // `LlmProvider` is deliberately `#[non_exhaustive]` (ai/ports.rs): a
        // future provider ships retryable until its evidence is verified
        // against a live response — the same conservative default every
        // unreadable body gets.
        _ => &[],
    }
}

/// Decide a provider `429` on **response-body evidence**, not on the status
/// alone (issue #927; the #521 "verify before attributing" rule).
///
/// The provider's own error text is parsed as JSON and its **string values** are
/// matched case-insensitively against that provider's curated markers. Every
/// shape we know puts the evidence in a different place — OpenAI in
/// `error.code`, Gemini inside `error.details[].metadata.quota_limit`, OpenRouter
/// in a prose `error.message` — so matching the values rather than a fixed path
/// is what keeps one table honest for all of them without per-provider
/// deserializers. The markers are long and provider-specific
/// (`insufficient_quota`, `perdayperproject`, `free-models-per-day`), so a
/// substring hit cannot plausibly come from unrelated prose.
///
/// **The conservative default is [`RateLimitVerdict::RateLimited`]**: an empty
/// body, an unparsable one (an HTML gateway page), a body we could not read or a
/// provider whose table is empty. A wrong "non-retryable" verdict dead-letters a
/// job a retry would have saved; a wrong "retryable" one costs one wasted
/// attempt. Either way this never fails the request path — it only *classifies*
/// a failure that already happened.
#[must_use]
pub fn classify_provider_body(provider: LlmProvider, body: &str) -> RateLimitVerdict {
    let markers = quota_markers(provider);
    if markers.is_empty() || body.trim().is_empty() {
        return RateLimitVerdict::RateLimited;
    }
    let Ok(value) = serde_json::from_str::<serde_json::Value>(body) else {
        tracing::debug!(
            provider = provider.as_str(),
            body_len = body.len(),
            "#927 provider error body is not JSON; a 429 stays retryable (conservative default)"
        );
        return RateLimitVerdict::RateLimited;
    };
    let mut evidence: Vec<String> = Vec::new();
    collect_strings(&value, &mut evidence);
    let hit = evidence.iter().find_map(|candidate| {
        let lowered = candidate.to_ascii_lowercase();
        markers
            .iter()
            .find(|marker| lowered.contains(**marker))
            .copied()
    });
    match hit {
        Some(marker) => {
            tracing::debug!(
                provider = provider.as_str(),
                marker,
                "#927 provider 429 names an exhausted quota; the failure is terminal"
            );
            RateLimitVerdict::QuotaExhausted { marker }
        }
        None => RateLimitVerdict::RateLimited,
    }
}

/// Collect the string **values** of a JSON document, bounded in both directions.
///
/// Values only (never keys): the keys of an OpenAI error object (`code`, `type`,
/// `message`) are also the names of fields a provider may echo from *our*
/// request, and a marker must come from what the provider said, not from a key we
/// happen to look at. The walk stops at [`MAX_ERROR_BODY_BYTES`] characters of
/// collected evidence — the body is already bounded, so this only guards against
/// a pathological array of one-character strings.
fn collect_strings(value: &serde_json::Value, out: &mut Vec<String>) {
    let mut total = 0usize;
    let mut stack = vec![value];
    while let Some(node) = stack.pop() {
        if total >= MAX_ERROR_BODY_BYTES {
            return;
        }
        match node {
            serde_json::Value::String(text) => {
                total = total.saturating_add(text.len());
                out.push(text.clone());
            }
            serde_json::Value::Array(items) => stack.extend(items.iter()),
            serde_json::Value::Object(map) => stack.extend(map.values()),
            serde_json::Value::Null | serde_json::Value::Bool(_) | serde_json::Value::Number(_) => {
            }
        }
    }
}

/// Same classification as [`classify_http_status`], plus the provider's own
/// error body as a bounded suffix.
///
/// A status alone cannot be acted on: `HTTP 404` hid "Route not found" on a
/// wrong curated Decision endpoint and `HTTP 400` hides *which* property a
/// provider rejected, so every failure degraded to the same unexplained
/// `scoring_failed` row (the issue #767 class). The suffix is truncated because
/// a provider error can echo the request; it carries no credential.
pub fn classify_http_status_with_detail(status: StatusCode, detail: &str) -> DomainError {
    classify_http_status_rich(status, detail, None, RateLimitVerdict::RateLimited)
}

/// [`classify_http_status_with_detail`] **plus the response's retry hint**
/// (issue #926) **and its quota verdict** (issue #927).
///
/// The hint becomes (a) the `retry_after` payload field the schedulers read —
/// in-attempt backoff floor, `next_attempt_at` floor, breaker probe schedule —
/// and (b) part of the narrative, which is what the attempt row's
/// `error_summary` shows. Both come from the one `retry_after` input, so the
/// typed value and the text cannot disagree, and no presentation `format!` moves
/// into `core` (ADR-031).
///
/// A hint never changes the classification: the variant, code, status and
/// retryability are identical to the hint-less call. The **verdict** does, and
/// only for a `429`: [`RateLimitVerdict::QuotaExhausted`] produces the terminal
/// [`DomainError::llm_provider_quota_exhausted`]. A `5xx` that happens to carry a
/// quota-looking body stays retryable — the evidence table is a `429` fact, and a
/// gateway error page must never dead-letter a job.
///
/// Since issue #942 W3 the same terminal verdict is produced by an upstream
/// `402 Payment Required`, which is the shape EURouter's budget/spend cap
/// actually takes (`quota_markers` is deliberately empty for it): a `402` is not
/// a burst and not a validation problem, it is an empty account. It previously
/// fell through to `RetryClass::Rejected` → `DomainError::validation`, so the
/// app rendered "invalid request" for a top-up. It is **terminal**
/// (`is_retryable() == false`) and therefore dead-letters immediately without
/// touching the deployment-wide `(provider, model)` breaker (#927's invariant,
/// `provider_gate_tests::a_quota_exhausted_provider_failure_is_terminal_*`).
pub fn classify_http_status_rich(
    status: StatusCode,
    detail: &str,
    retry_after: Option<Duration>,
    verdict: RateLimitVerdict,
) -> DomainError {
    let suffix = {
        let trimmed = detail.trim();
        if trimmed.is_empty() {
            String::new()
        } else {
            let bounded: String = trimmed.chars().take(400).collect();
            format!(" — {bounded}")
        }
    };
    // The verdict only ever narrows a `429`: every other status keeps the
    // classification it had, so the quota table cannot misfile a 5xx or a 402.
    //
    // The narrative names the MATCHED marker, not just the truncated body: a
    // provider that puts its code behind a long `error.message` would otherwise
    // dead-letter a job whose attempt row never says which evidence fired
    // (CodeRabbit review, PR #931).
    if status == StatusCode::TOO_MANY_REQUESTS
        && let RateLimitVerdict::QuotaExhausted { marker } = verdict
    {
        return DomainError::llm_provider_quota_exhausted(format!(
            "LLM provider returned HTTP {status} with no quota left ({marker}){suffix}"
        ));
    }
    // Issue #942 W3: `402 Payment Required` is an exhausted account, not a
    // malformed request. It is classified BEFORE the generic retry core for the
    // same reason as the quota `429` above: a client must branch on the code
    // (ADR-031 D2), and `domain.validation` told the user their request was
    // wrong when their wallet was empty.
    if status == StatusCode::PAYMENT_REQUIRED {
        return DomainError::llm_provider_quota_exhausted(format!(
            "LLM provider returned HTTP {status} — no budget or credit left{suffix}"
        ));
    }
    // The classification itself is the shared retry core's (issue #925); the
    // `DomainError` mapping stays here, at the call boundary, so the error
    // taxonomy every caller matches on is unchanged.
    match RetryClass::of(status) {
        // Issue #822: attributed to the PROVIDER, not "a service". The
        // generic `domain.service-unavailable` is shared with the mapping DB,
        // the pricing read model and payload storage, so a client could not
        // name this dependency from the attempt's stable code.
        RetryClass::Retryable => match retry_after {
            Some(wait) => DomainError::llm_provider_unavailable_with_hint(
                format!(
                    "LLM provider returned HTTP {status} and asked to wait {}s{suffix}",
                    wait.as_secs()
                ),
                Some(wait),
            ),
            None => DomainError::llm_provider_unavailable(format!(
                "LLM provider returned HTTP {status}{suffix}"
            )),
        },
        RetryClass::Rejected => DomainError::validation(format!(
            "LLM provider rejected request with HTTP {status}{suffix}"
        )),
        RetryClass::Unexpected => DomainError::validation(format!(
            "unexpected LLM provider HTTP status {status}{suffix}"
        )),
    }
}

pub fn classify_transport_error(error: reqwest::Error) -> DomainError {
    if error.is_timeout() || error.is_connect() {
        // Issue #822: provider-attributed (see `classify_http_status_with_detail`).
        DomainError::llm_provider_unavailable(format!(
            "LLM provider transport unavailable: {error}"
        ))
    } else if error.is_redirect() {
        // Deterministic policy rejection (issue #170): retrying cannot change
        // the outcome, so it is a permanent validation failure.
        DomainError::validation(format!(
            "LLM provider redirect rejected by transport policy: {error}"
        ))
    } else {
        DomainError::validation(format!("LLM provider request failed: {error}"))
    }
}

/// Output-token budget for the next truncation retry, or `None` when the
/// response must fail permanently. Only a provider-reported token-ceiling
/// truncation (`finish_reason == "length"`) qualifies for a retry: a
/// well-formed JSON that decodes to the wrong shape (`finish_reason ==
/// "stop"`) is not retried, because re-paying a paid LLM call on arbitrary
/// malformed output is a cost risk, not a recovery. Retries are bounded by
/// `truncation_retries_left`, so the worst-case spend of one call stays
/// bounded (see [`MAX_TRUNCATION_RETRIES`]).
fn next_truncation_budget(
    finish_reason: Option<&str>,
    budget: u32,
    truncation_retries_left: u32,
) -> Option<u32> {
    // Any malformed response may be retryable, not only a provider-confirmed
    // `finish_reason: "length"`. Gateways and routers routinely cut a body
    // short while reporting `stop` (or omitting the field entirely), and a
    // strict `== Some("length")` then classified a truncated answer as
    // permanent and dead-lettered the job after ONE attempt — observed live
    // against eurouter: "LLM JSON did not match ScriptContext: EOF while
    // parsing a string at line 1 column 1437" with no
    // "after bounded retries" suffix, i.e. the growth path was never taken.
    //
    // The bound is unchanged (MAX_TRUNCATION_RETRIES attempts, budget x2), so
    // a genuinely malformed response still fails after a fixed, bounded number
    // of paid retries instead of retrying forever.
    let _ = finish_reason;
    if truncation_retries_left > 0 {
        Some(budget.saturating_mul(TRUNCATION_RETRY_BUDGET_GROWTH))
    } else {
        None
    }
}

/// Upper bound of the empty-completion diagnosis embedded in the error.
///
/// The text lands in `ai_import_job.last_error` and is rendered by the client,
/// so it must stay greppable and readable — never a full response body dump.
const MAX_COMPLETION_DETAIL_CHARS: usize = 400;

/// Identifying metadata of one provider response, read from the headers before
/// the body is consumed.
///
/// Exists for one failure class: a `200` whose `choices[0].message.content` is
/// empty. `request_id` is the provider's own handle for the call — the
/// 2026-11-20 incident produced a dead-lettered job whose request was not
/// visible in the provider's dashboard at all, and nothing on our side could
/// name it. `upstream_service_time` says whether the upstream generated
/// anything before answering.
#[derive(Debug, Default, Clone)]
struct ResponseMeta {
    request_id: Option<String>,
    upstream_service_time: Option<String>,
    server: Option<String>,
}

impl ResponseMeta {
    /// Header names carrying the provider's request handle, in priority order:
    /// OpenAI-compatible gateways differ (`x-request-id`, `request-id`,
    /// `openai-request-id`) and a proxy may add `server`/upstream timing.
    const REQUEST_ID_HEADERS: [&'static str; 4] = [
        "x-request-id",
        "request-id",
        "x-eurouter-request-id",
        "openai-request-id",
    ];

    fn capture(headers: &reqwest::header::HeaderMap) -> Self {
        let value = |names: &[&str]| {
            names
                .iter()
                .find_map(|name| headers.get(*name))
                .and_then(|value| value.to_str().ok())
                .map(str::to_owned)
        };
        Self {
            request_id: value(&Self::REQUEST_ID_HEADERS),
            upstream_service_time: value(&["x-envoy-upstream-service-time"]),
            server: value(&["server"]),
        }
    }
}

/// What to do with one decoded `200` response.
#[derive(Debug)]
enum ResponseStep<'a> {
    /// The provider delivered a content payload — decode it.
    Decode {
        content: &'a str,
        finish_reason: Option<&'a str>,
    },
    /// Nothing usable arrived, and the bounded budget growth may try again.
    RetryWithBudget {
        budget: u32,
        retries_left: u32,
        reason: String,
    },
    /// Nothing usable arrived and the bounded retries are spent. This is a
    /// **provider failure**, not a validation failure of our own input: a `200`
    /// without an answer is the endpoint failing to deliver, so it stays
    /// retryable and may move the `(provider, model)` breaker. Classifying it as
    /// `validation` (the pre-fix behaviour) granted zero in-attempt retries and
    /// dead-lettered the job after a single empty answer (2026-11-20 incident).
    ///
    /// The **refusal** arm also reports through here, but with a
    /// `validation` error: a content-level rejection is terminal and
    /// breaker-neutral (see [`is_content_refusal`]).
    Fail { error: DomainError },
}

/// Reduce one decoded provider response to the next step.
///
/// Pure and provider-agnostic so the whole decision is unit-testable without
/// HTTP — the previous shape put it inline in the request loop, which is why no
/// test ever exercised the empty-completion branch.
fn step_for_response<'a>(
    envelope: &'a ChatCompletionResponse,
    meta: &ResponseMeta,
    budget: u32,
    truncation_retries_left: u32,
) -> ResponseStep<'a> {
    let choice = envelope.choices.first();
    let finish_reason = choice.and_then(|choice| choice.finish_reason.as_deref());
    // A blank string is the same failure as a missing field: the provider
    // answered with nothing. Both must reach the truncation retry instead of the
    // JSON parser (which turned the empty string into an unhelpful
    // "LLM JSON did not match" after bounded retries).
    if let Some(content) = choice
        .and_then(|choice| choice.message.content.as_deref())
        .filter(|content| !content.trim().is_empty())
    {
        return ResponseStep::Decode {
            content,
            finish_reason,
        };
    }
    let reason = describe_empty_completion(envelope, choice, meta);
    // A content-level REFUSAL is terminal (review finding): the provider
    // declines on content grounds, and a larger output budget cannot turn that
    // into an answer — re-requesting pays the same rejection again. It is not an
    // outage either, so it must not reach the retryable
    // `ai-import.llm-provider-unavailable` arm below: with two inner retries one
    // refusal cost three identical paid requests per attempt, and repeating it
    // could open the `(provider, model)` breaker for a healthy pair. A
    // `validation` error is non-retryable and breaker-neutral, and the bounded
    // diagnosis still carries `refusal=...` / `finish_reason=content_filter`.
    if is_content_refusal(choice, finish_reason) {
        return ResponseStep::Fail {
            error: DomainError::validation(format!("LLM provider refused the request: {reason}")),
        };
    }
    match next_truncation_budget(finish_reason, budget, truncation_retries_left) {
        Some(grown) => ResponseStep::RetryWithBudget {
            budget: grown,
            // `next_truncation_budget` only grows while a retry is left, so the
            // subtraction cannot underflow; `saturating_sub` keeps it panic-free
            // regardless (house rule: no panics in production code).
            retries_left: truncation_retries_left.saturating_sub(1),
            reason,
        },
        None => ResponseStep::Fail {
            error: DomainError::llm_provider_unavailable(format!(
                "LLM provider returned no usable content: {reason}"
            )),
        },
    }
}

/// Whether a `200` carried a content-level REFUSAL rather than a provider
/// failure: a non-empty `message.refusal`, or the safety `content_filter`
/// finish reason. Both mean the request was declined on its content, so the
/// same request run again answers the same way however large the output budget
/// is.
fn is_content_refusal(choice: Option<&ChatChoice>, finish_reason: Option<&str>) -> bool {
    let refused = choice
        .and_then(|choice| choice.message.refusal.as_deref())
        .is_some_and(|refusal| !refusal.trim().is_empty());
    refused || finish_reason == Some("content_filter")
}

/// Bounded, greppable description of a response that carried no usable
/// content.
///
/// Every field answers a question the 2026-11-20 incident could not answer from
/// the recorded error (`validation failed: LLM response contained no content`):
/// did the provider answer at all (`request_id`, `server`, `upstream_ms`), did it
/// truncate (`finish_reason`), did it spend the ceiling on reasoning
/// (`reasoning_content_chars`, `tokens_out`), did it refuse (`refusal`), and did
/// it route to a different model (`response_model`).
fn describe_empty_completion(
    envelope: &ChatCompletionResponse,
    choice: Option<&ChatChoice>,
    meta: &ResponseMeta,
) -> String {
    let usage = envelope.usage();
    let mut parts: Vec<String> = vec![match choice {
        Some(_) => "blank content".to_owned(),
        None => "no choices".to_owned(),
    }];
    push_detail(&mut parts, "completion_id", envelope.id.as_deref());
    push_detail(&mut parts, "response_model", envelope.model.as_deref());
    if let Some(choice) = choice {
        push_detail(&mut parts, "finish_reason", choice.finish_reason.as_deref());
        push_detail(&mut parts, "refusal", choice.message.refusal.as_deref());
        if let Some(reasoning) = &choice.message.reasoning_content {
            parts.push(format!(
                "reasoning_content_chars={}",
                reasoning.chars().count()
            ));
        }
        if let Some(content) = &choice.message.content {
            parts.push(format!("content_chars={}", content.chars().count()));
        }
    }
    parts.push(format!("tokens_in={}", usage.tokens_in));
    parts.push(format!("tokens_out={}", usage.tokens_out));
    push_detail(&mut parts, "request_id", meta.request_id.as_deref());
    push_detail(
        &mut parts,
        "upstream_ms",
        meta.upstream_service_time.as_deref(),
    );
    push_detail(&mut parts, "server", meta.server.as_deref());
    truncate_detail(&parts.join(", "))
}

/// Append `label=value` when the provider actually sent the value.
fn push_detail(parts: &mut Vec<String>, label: &str, value: Option<&str>) {
    if let Some(value) = value.map(str::trim).filter(|value| !value.is_empty()) {
        parts.push(format!("{label}={value}"));
    }
}

/// Cap the diagnosis at [`MAX_COMPLETION_DETAIL_CHARS`], counting CHARACTERS
/// (provider text is untrusted and multi-byte).
fn truncate_detail(text: &str) -> String {
    if text.chars().count() <= MAX_COMPLETION_DETAIL_CHARS {
        return text.to_owned();
    }
    let mut truncated: String = text.chars().take(MAX_COMPLETION_DETAIL_CHARS).collect();
    truncated.push('…');
    truncated
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decimal_scaled_keeps_sub_milli_kwh_precision() {
        // The spec example: 0.000005 kWh (a realistic Neuralwatt reading) is
        // exactly 18 000 mJ — the old three-digit pre-rounding returned 0.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("0.000005"), KWH_TO_MILLIJOULES),
            Some(18_000)
        );
        // Joules stay exact.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("18"), JOULES_TO_MILLIJOULES),
            Some(18_000)
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!(4.2), JOULES_TO_MILLIJOULES),
            Some(4_200)
        );
    }

    #[test]
    fn decimal_scaled_accepts_scientific_notation() {
        // serde_json renders small floats via ryu as `5e-6` — the digit
        // check must not reject the exponent form.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!(5e-6), KWH_TO_MILLIJOULES),
            Some(18_000)
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("5E-6"), KWH_TO_MILLIJOULES),
            Some(18_000)
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("1.5e3"), JOULES_TO_MILLIJOULES),
            Some(1_500_000)
        );
    }

    #[test]
    fn decimal_scaled_rounds_half_up_and_rejects_non_numeric() {
        // 0.5 mJ (in joules) — the exact half boundary rounds UP.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("0.0005"), JOULES_TO_MILLIJOULES),
            Some(1)
        );
        // 0.4 mJ rounds DOWN.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("0.0004"), JOULES_TO_MILLIJOULES),
            Some(0)
        );
        // 3.6 mJ (1e-9 kWh) rounds half-up to 4.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("0.000000001"), KWH_TO_MILLIJOULES),
            Some(4)
        );
        // `i32::MIN` exponent: `-exp` would overflow-panic in debug builds —
        // the parse must degrade to `None` instead (regression for the
        // provider-controlled-exponent hardening).
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("-1e-2147483648"), JOULES_TO_MILLIJOULES),
            None
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("-1e2147483647"), JOULES_TO_MILLIJOULES),
            None
        );
        // Negative telemetry is not a valid reading (never a negative cost).
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!(-1), JOULES_TO_MILLIJOULES),
            None
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("not-a-number"), JOULES_TO_MILLIJOULES),
            None
        );
    }

    #[test]
    fn truncated_response_grows_budget_while_retries_remain() {
        assert_eq!(next_truncation_budget(Some("length"), 2048, 2), Some(4096));
        assert_eq!(next_truncation_budget(Some("length"), 4096, 1), Some(8192));
    }

    #[test]
    fn truncation_without_retries_left_fails_permanently() {
        assert_eq!(next_truncation_budget(Some("length"), 2048, 0), None);
    }

    #[test]
    fn unconfirmed_truncation_is_still_retried_within_the_bound() {
        // Gateways/routers report a cut-off body as `stop` (or omit the field)
        // instead of `length`. Live case against eurouter: "EOF while parsing a
        // string at line 1 column 1437" dead-lettered after ONE attempt because
        // the strict `== Some("length")` guard never grew the budget. The
        // response may be truncated regardless of what the provider claims, so
        // the bound — not the reported reason — decides retryability.
        assert_eq!(next_truncation_budget(Some("stop"), 2048, 2), Some(4096));
        assert_eq!(next_truncation_budget(None, 2048, 2), Some(4096));
        assert_eq!(
            next_truncation_budget(Some("content_filter"), 2048, 1),
            Some(4096)
        );
    }

    #[test]
    fn a_genuinely_malformed_response_still_stops_at_the_bound() {
        // The retry growth is bounded: a permanently malformed answer (e.g. a
        // content-filtered one) must fail after the fixed attempt count rather
        // than re-paying the call forever.
        for reason in [Some("stop"), None, Some("content_filter"), Some("length")] {
            assert_eq!(
                next_truncation_budget(reason, 8192, 0),
                None,
                "exhausted budget must fail for {reason:?}"
            );
        }
    }

    #[test]
    fn truncation_budget_growth_saturates_at_u32_ceiling() {
        // `saturating_mul` keeps the budget growth total even at the ceiling.
        assert_eq!(
            next_truncation_budget(Some("length"), u32::MAX, 1),
            Some(u32::MAX)
        );
    }

    /// The mirror the provider is handed must carry the costume list, or the model
    /// has nowhere to put a costume it recognised and `serde` drops it silently —
    /// the exact failure that produced 0 costumes from a script that names them.
    /// schemars 1.x emits `$defs` (draft 2020-12); older releases emitted
    /// `definitions`. Resolve either so the assertions below test the contract
    /// and not the generator's dialect.
    fn defs(value: &serde_json::Value) -> &serde_json::Value {
        value
            .get("$defs")
            .or_else(|| value.get("definitions"))
            .unwrap_or_else(|| panic!("no type definitions in the emitted schema: {value}"))
    }

    /// Issue #827: the block number the prompt asks for only reaches the
    /// server because the provider-facing mirror declares it — a prompt rule
    /// without a schema field is unreachable under `strict` Structured Outputs
    /// (the model cannot emit a property the schema does not define, which is
    /// why the per-scene `episode` rule never arrives).
    #[test]
    fn provider_schema_mirrors_the_block_number_field() {
        let schema = schemars::schema_for!(ScriptContextSchema);
        let value = serde_json::to_value(&schema).expect("schema serializes");
        let block = &defs(&value)["ScriptContextSchema"]["properties"]["block_number"];
        let block = if block.is_object() {
            block
        } else {
            &value["properties"]["block_number"]
        };
        assert!(
            block.is_object(),
            "the schema sent to the provider must carry `block_number`"
        );
        assert!(
            block["description"].is_string(),
            "`block_number` needs a description, the schema is the model's contract"
        );
    }

    #[test]
    fn provider_schema_mirrors_the_outfit_and_piece_fields() {
        let schema = schemars::schema_for!(ScriptContextSchema);
        let value = serde_json::to_value(&schema).unwrap();
        let scene = &defs(&value)["DraftSceneSchema"]["properties"];
        assert!(
            scene["outfits"].is_object(),
            "the schema sent to the provider must carry `outfits`, got {scene:?}"
        );
        let outfit = &defs(&value)["DraftOutfitSchema"]["properties"];
        for field in ["character_name", "name", "notes", "source_quote", "pieces"] {
            assert!(
                outfit[field].is_object(),
                "DraftOutfitSchema must expose `{field}`: {outfit:?}"
            );
            assert!(
                outfit[field]["description"].is_string(),
                "`{field}` needs a description, the schema is the model's contract"
            );
        }
        let piece = &defs(&value)["DraftPieceSchema"]["properties"];
        for field in ["name", "category_hint", "description"] {
            assert!(
                piece[field].is_object(),
                "DraftPieceSchema must expose `{field}`: {piece:?}"
            );
        }
        let required = defs(&value)["DraftSceneSchema"]["required"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect::<Vec<_>>();
        assert!(
            required.contains(&"outfits"),
            "`strict` schema mode requires every property: {required:?}"
        );
    }
}
