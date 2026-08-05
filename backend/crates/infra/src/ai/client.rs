// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

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

/// OpenAI-compatible `/chat/completions` adapter. The provider URL is chosen
/// exclusively from the curated provider registry; callers cannot supply one.
pub struct OpenAiCompatibleChatClient {
    http: reqwest::Client,
    provider: LlmProvider,
    api_key: SecretValue,
    timeout: Duration,
}

impl OpenAiCompatibleChatClient {
    pub fn new(
        provider: LlmProvider,
        api_key: String,
        timeout: Duration,
    ) -> Result<Self, DomainError> {
        if provider == LlmProvider::Ollama {
            return Err(DomainError::ValidationError(
                "Ollama must be routed through OllamaChatClient — the \
                 OpenAI-compatible client would send bearer auth to its HTTP \
                 base URL"
                    .to_owned(),
            ));
        }
        if api_key.trim().is_empty() {
            return Err(DomainError::ValidationError(
                "LLM API key must not be empty".to_owned(),
            ));
        }
        let http = reqwest::Client::builder()
            .timeout(timeout)
            .build()
            .map_err(|error| {
                DomainError::ValidationError(format!("invalid HTTP client: {error}"))
            })?;
        Ok(Self {
            http,
            provider,
            api_key: SecretValue::new(api_key),
            timeout,
        })
    }

    /// Test seam: inject a prebuilt client while still enforcing the request
    /// deadline per call (the injected client may not carry one).
    pub fn with_http(
        http: reqwest::Client,
        provider: LlmProvider,
        api_key: String,
        timeout: Duration,
    ) -> Result<Self, DomainError> {
        if provider == LlmProvider::Ollama {
            return Err(DomainError::ValidationError(
                "Ollama must be routed through OllamaChatClient — the \
                 OpenAI-compatible client would send bearer auth to its HTTP \
                 base URL"
                    .to_owned(),
            ));
        }
        if api_key.trim().is_empty() {
            return Err(DomainError::ValidationError(
                "LLM API key must not be empty".to_owned(),
            ));
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
            max_tokens: req.max_tokens,
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
                DomainError::ValidationError(format!("invalid LLM response: {error}"))
            })?;
        let content = envelope
            .choices
            .first()
            .and_then(|choice| choice.message.content.as_deref())
            .ok_or_else(|| {
                DomainError::ValidationError("LLM response contained no content".to_owned())
            })?;
        serde_json::from_str(content).map_err(|error| {
            DomainError::ValidationError(format!("LLM JSON did not match ScriptContext: {error}"))
        })
    }
}

#[async_trait]
impl LlmClient for OpenAiCompatibleChatClient {
    async fn chat_constrained(&self, req: LlmChatRequest) -> Result<ScriptContext, DomainError> {
        if req.provider != self.provider {
            return Err(DomainError::ValidationError(
                "LLM request provider does not match configured client".to_owned(),
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
        DomainError::ServiceUnavailable(format!("LLM provider returned HTTP {status}"))
    } else if status.is_client_error() {
        DomainError::ValidationError(format!("LLM provider rejected request with HTTP {status}"))
    } else {
        DomainError::ValidationError(format!("unexpected LLM provider HTTP status {status}"))
    }
}

pub fn classify_transport_error(error: reqwest::Error) -> DomainError {
    if error.is_timeout() || error.is_connect() {
        DomainError::ServiceUnavailable(format!("LLM provider transport unavailable: {error}"))
    } else {
        DomainError::ValidationError(format!("LLM provider request failed: {error}"))
    }
}
