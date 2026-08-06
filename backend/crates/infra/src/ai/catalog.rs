// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::collections::HashSet;
use std::time::Duration;

use async_trait::async_trait;
use breakdown_core::ai::{CuratedLlmProvider, LlmModelCatalog, LlmProvider, ModelInfo};
use breakdown_core::error::DomainError;
use breakdown_core::settings::SecretValue;
use serde::Deserialize;

use super::CuratedProviderUrls;
use super::client::{classify_http_status, classify_transport_error};
use super::transport::curated_provider_redirect_policy;

/// Deadline for curated model-catalog requests. The catalog has no
/// caller-supplied timeout, so the bound is fixed here (the sibling chat
/// clients take a caller-supplied `Duration` instead).
const CATALOG_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// Model catalog backed by a curated allowlist. The allowlist is an operator
/// policy, not user input, and prevents arbitrary provider model selection.
pub struct OpenAiCompatibleModelCatalog {
    http: reqwest::Client,
    allowlist: HashSet<String>,
}

impl OpenAiCompatibleModelCatalog {
    /// Builds a catalog with its own HTTP client carrying the issue #170
    /// redirect policy and a fixed request deadline. The catalog serves both
    /// hosted and Ollama providers from one client, so the policy dispatches
    /// on the original request URL: the curated Ollama origin is local-only,
    /// everything else HTTPS-only.
    pub fn new() -> Result<Self, DomainError> {
        let http = reqwest::Client::builder()
            .timeout(CATALOG_REQUEST_TIMEOUT)
            .redirect(curated_provider_redirect_policy())
            .build()
            .map_err(|error| {
                DomainError::ValidationError(format!("invalid HTTP client: {error}"))
            })?;
        Ok(Self {
            http,
            allowlist: default_allowlist(),
        })
    }

    /// Test seam: inject a prebuilt client. Transport configuration is caller
    /// owned; the production path ([`Self::new`]) applies the policy.
    pub fn with_http(http: reqwest::Client) -> Self {
        Self {
            http,
            allowlist: default_allowlist(),
        }
    }

    /// Test seam: inject a prebuilt client and a custom allowlist.
    pub fn with_allowlist(
        http: reqwest::Client,
        allowlist: impl IntoIterator<Item = String>,
    ) -> Self {
        Self {
            http,
            allowlist: allowlist.into_iter().collect(),
        }
    }

    pub fn is_allowed(&self, model: &str) -> bool {
        self.allowlist.contains(model)
    }
}

#[async_trait]
impl LlmModelCatalog for OpenAiCompatibleModelCatalog {
    async fn list(
        &self,
        provider: LlmProvider,
        vaulted_key: &str,
    ) -> Result<Vec<ModelInfo>, DomainError> {
        if vaulted_key.trim().is_empty() {
            return Err(DomainError::ValidationError(
                "LLM API key must not be empty".to_owned(),
            ));
        }
        let key = SecretValue::new(vaulted_key.to_owned());
        let endpoint = format!("{}/models", CuratedProviderUrls::base_url(provider));
        let response = self
            .http
            .get(endpoint)
            .bearer_auth(key.as_str())
            .send()
            .await
            .map_err(classify_transport_error)?;
        let status = response.status();
        if !status.is_success() {
            return Err(classify_http_status(status));
        }
        let payload = response.json::<ModelsResponse>().await.map_err(|error| {
            DomainError::ValidationError(format!("invalid model catalog: {error}"))
        })?;
        Ok(payload
            .data
            .into_iter()
            .filter(|model| self.is_allowed(&model.id))
            .map(|model| ModelInfo {
                id: model.id,
                display_name: None,
                provider,
            })
            .collect())
    }
}

#[derive(Debug, Deserialize)]
struct ModelsResponse {
    data: Vec<ModelRecord>,
}

#[derive(Debug, Deserialize)]
struct ModelRecord {
    id: String,
}

fn default_allowlist() -> HashSet<String> {
    [
        "gpt-4o-mini",
        "gpt-4o",
        "gpt-4.1-mini",
        "openai/gpt-4o-mini",
        "openai/gpt-4o",
        "meta-llama/llama-3.1-8b-instruct:free",
        "mistral-large-3",
        "mistral-small-3.1",
        "deepseek-v4-flash",
        "glm-5.2",
        "glm-5.2-fast",
        "glm-5.1",
        "kimi-k2.7-code",
        "kimi-k3",
        "kimi-k2.6",
        "qwen3.6-35b",
        "deepseek-v4-pro",
        "minimax-m3",
        "minimax-m2.7",
        "mimo-v2.5",
        "grok-4.5",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect()
}
