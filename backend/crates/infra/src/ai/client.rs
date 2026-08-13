// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

use std::time::Duration;

use async_trait::async_trait;
use breakdown_core::ai::{
    CuratedLlmProvider, LlmChatRequest, LlmClient, LlmProvider, ScriptContext,
};
use breakdown_core::error::DomainError;
use breakdown_core::settings::SecretValue;
use reqwest::StatusCode;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::CuratedProviderUrls;
use super::transport::build_hosted_client;

/// OpenAI-compatible `/chat/completions` adapter. The provider URL is chosen
/// exclusively from the curated provider registry; callers cannot supply one.
pub struct OpenAiCompatibleChatClient {
    http: reqwest::Client,
    provider: LlmProvider,
    api_key: SecretValue,
    timeout: Duration,
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
const MAX_TRUNCATION_RETRIES: u32 = 2;

impl OpenAiCompatibleChatClient {
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
        let http = build_hosted_client(&host, timeout)
            .await
            .map_err(|violation| DomainError::validation(violation.to_string()))?;
        Ok(Self {
            http,
            provider,
            api_key: SecretValue::new(api_key),
            timeout,
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
            api_key: SecretValue::new(api_key),
            timeout,
        })
    }

    fn endpoint(&self) -> String {
        format!(
            "{}/chat/completions",
            CuratedProviderUrls::base_url(self.provider)
        )
    }

    async fn request(&self, req: &LlmChatRequest) -> Result<ScriptContext, DomainError> {
        let schema = req
            .response_schema
            .clone()
            .unwrap_or_else(|| schemars::schema_for!(ScriptContextSchema).to_value());
        let mut budget = req.max_tokens;
        let mut truncation_retries = MAX_TRUNCATION_RETRIES;
        loop {
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
                response_format: Some(json!({
                    "type": "json_schema",
                    "json_schema": {
                        "name": "script_context",
                        "strict": true,
                        "schema": schema,
                    }
                })),
            };
            let response = self
                .http
                .post(self.endpoint())
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
            let envelope = response
                .json::<ChatCompletionResponse>()
                .await
                .map_err(|error| {
                    DomainError::validation(format!("invalid LLM response: {error}"))
                })?;
            let choice = envelope
                .choices
                .first()
                .ok_or_else(|| DomainError::validation("LLM response contained no choices"))?;
            let content = choice
                .message
                .content
                .as_deref()
                .ok_or_else(|| DomainError::validation("LLM response contained no content"))?;
            match serde_json::from_str(content) {
                Ok(context) => return Ok(context),
                Err(error) => {
                    match next_truncation_budget(
                        choice.finish_reason.as_deref(),
                        budget,
                        truncation_retries,
                    ) {
                        Some(grown) => {
                            budget = grown;
                            truncation_retries -= 1;
                        }
                        None => {
                            let truncated = choice.finish_reason.as_deref() == Some("length");
                            let suffix = if truncated {
                                " (response truncated at the output-token budget \
                                 after bounded retries)"
                            } else {
                                ""
                            };
                            return Err(DomainError::validation(format!(
                                "LLM JSON did not match ScriptContext: {error}{suffix}"
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
    async fn chat_constrained(&self, req: LlmChatRequest) -> Result<ScriptContext, DomainError> {
        if req.provider != self.provider {
            return Err(DomainError::validation(
                "LLM request provider does not match configured client",
            ));
        }
        self.request(&req).await
    }
}

#[derive(Debug, Serialize)]
struct ChatCompletionRequest {
    model: String,
    messages: Vec<ChatMessage>,
    max_tokens: u32,
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
}

/// Infra-local schema mirror. Core remains independent of schemars while the
/// wire schema stays statically derived from the same JSON shape.
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct ScriptContextSchema {
    title: Option<String>,
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
}

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct UncertaintySchema {
    scene_index: usize,
    field: String,
    note: String,
    suggested_value: Option<String>,
}

pub fn classify_http_status(status: StatusCode) -> DomainError {
    if status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
        DomainError::service_unavailable(format!("LLM provider returned HTTP {status}"))
    } else if status.is_client_error() {
        DomainError::validation(format!("LLM provider rejected request with HTTP {status}"))
    } else {
        DomainError::validation(format!("unexpected LLM provider HTTP status {status}"))
    }
}

pub fn classify_transport_error(error: reqwest::Error) -> DomainError {
    if error.is_timeout() || error.is_connect() {
        DomainError::service_unavailable(format!("LLM provider transport unavailable: {error}"))
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
    if finish_reason == Some("length") && truncation_retries_left > 0 {
        Some(budget.saturating_mul(TRUNCATION_RETRY_BUDGET_GROWTH))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn non_truncated_malformed_response_is_not_retried() {
        // A `stop` or missing `finish_reason` means the JSON is genuinely
        // malformed — retrying would re-pay a paid call for the same input.
        assert_eq!(next_truncation_budget(Some("stop"), 2048, 2), None);
        assert_eq!(
            next_truncation_budget(Some("content_filter"), 2048, 2),
            None
        );
        assert_eq!(next_truncation_budget(None, 2048, 2), None);
    }

    #[test]
    fn truncation_budget_growth_saturates_at_u32_ceiling() {
        // `saturating_mul` keeps the budget growth total even at the ceiling.
        assert_eq!(
            next_truncation_budget(Some("length"), u32::MAX, 1),
            Some(u32::MAX)
        );
    }
}
