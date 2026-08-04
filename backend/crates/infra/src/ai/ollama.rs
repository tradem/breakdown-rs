// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use async_trait::async_trait;
use breakdown_core::ai::{LlmChatRequest, LlmClient, LlmProvider, ScriptContext};
use breakdown_core::error::DomainError;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::client::{classify_http_status, classify_transport_error};
use super::{CuratedLlmProvider, CuratedProviderUrls};

/// Ollama adapter. Ollama's broad JSON mode is used when strict schema mode is
/// unavailable; malformed responses are retried only a bounded number of times.
pub struct OllamaChatClient {
    http: reqwest::Client,
    max_parse_retries: u32,
}

impl OllamaChatClient {
    pub fn new(http: reqwest::Client, max_parse_retries: u32) -> Self {
        Self {
            http,
            max_parse_retries: max_parse_retries.min(3),
        }
    }

    pub fn with_default_client(max_parse_retries: u32) -> Result<Self, DomainError> {
        let http = reqwest::Client::builder().build().map_err(|error| {
            DomainError::ValidationError(format!("invalid HTTP client: {error}"))
        })?;
        Ok(Self::new(http, max_parse_retries))
    }

    async fn request_once(&self, req: &LlmChatRequest) -> Result<String, DomainError> {
        let body = OllamaRequest {
            model: req.model.clone(),
            messages: vec![OllamaMessage {
                role: "user".to_owned(),
                content: format!(
                    "{}\n\n<context>\n{}\n</context>",
                    req.prompt, req.source_text
                ),
            }],
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
            .json(&body)
            .send()
            .await
            .map_err(classify_transport_error)?;
        let status = response.status();
        if !status.is_success() {
            return Err(classify_http_status(status));
        }
        let payload = response.json::<OllamaResponse>().await.map_err(|error| {
            DomainError::ValidationError(format!("invalid Ollama response: {error}"))
        })?;
        Ok(payload.message.content)
    }
}

#[async_trait]
impl LlmClient for OllamaChatClient {
    async fn chat_constrained(&self, req: LlmChatRequest) -> Result<ScriptContext, DomainError> {
        if req.provider != LlmProvider::Ollama {
            return Err(DomainError::ValidationError(
                "Ollama client received a non-Ollama request".to_owned(),
            ));
        }
        let mut last_parse_error = None;
        for _attempt in 0..=self.max_parse_retries {
            let content = self.request_once(&req).await?;
            match serde_json::from_str::<ScriptContext>(&content) {
                Ok(context) => return Ok(context),
                Err(error) => last_parse_error = Some(error),
            }
        }
        let detail = last_parse_error
            .map(|error| error.to_string())
            .unwrap_or_else(|| "unknown JSON parse error".to_owned());
        Err(DomainError::ValidationError(format!(
            "Ollama returned invalid ScriptContext after bounded retries: {detail}"
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
}

#[derive(Debug, Serialize)]
struct OllamaOptions {
    num_predict: u32,
}

#[derive(Debug, Deserialize)]
struct OllamaResponse {
    message: OllamaResponseMessage,
}

#[derive(Debug, Deserialize)]
struct OllamaResponseMessage {
    content: String,
}
