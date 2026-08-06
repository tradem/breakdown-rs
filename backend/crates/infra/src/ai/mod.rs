// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

//! AI infrastructure adapters.
//!
//! The module is intentionally additive: transport, persistence, workers, and
//! document adapters can be added without making the core domain depend on
//! `reqwest`, `sqlx`, `schemars`, or subprocess APIs.

pub mod catalog;
pub mod client;
pub mod concurrency;
pub mod credentials;
pub mod csv_schedule;
pub mod gdrive_source;
pub mod mapping;
pub mod merge_worker;
pub mod ollama;
pub mod pdf;
pub mod pg_concurrency;
pub mod preview_store;
pub mod prompts;
pub mod queue;
pub mod runtime;
pub mod schedule_apply;
pub mod shutdown;
pub mod transport;
pub mod workers;

pub use catalog::OpenAiCompatibleModelCatalog;
pub use client::{OpenAiCompatibleChatClient, classify_http_status, classify_transport_error};
pub use concurrency::{AiConcurrencyLimiter, AiConcurrencyPermit};
pub use credentials::AiCredentialResolver;
pub use csv_schedule::parse_schedule_csv;
pub use gdrive_source::{GDriveDocument, GDriveDocumentSource};
pub use mapping::PgAiImportMappingRepository;
pub use merge_worker::{QueueMergeWorker, merge_loaded_schedule};
pub use ollama::OllamaChatClient;
pub use pdf::PdfTextExtractor;
pub use pg_concurrency::{PgAiConcurrencyLimiter, PgAiConcurrencyPermit};
pub use preview_store::{AiDocumentSource, AiPreviewStore, MemoryAiPreviewStore};
pub use prompts::default_prompt;
pub use queue::PgAiImportQueue;
pub use runtime::AiWorkerRuntime;
pub use schedule_apply::{
    AppliedDay, ScheduleApplyRequest, ScheduleApplyResult, ScheduleApplyWorker,
};
pub use shutdown::{AiJobGuard, AiWorkerLifecycle};
pub use transport::{
    curated_provider_redirect_policy, hosted_provider_redirect_policy, ollama_redirect_policy,
};
pub use workers::{
    ApplyScriptRequest, ApplyWorker, MergeWorker, ScheduleImportWorker, ScriptImportWorker,
    UuidVersion, validate_chunk_count,
};

use breakdown_core::ai::{AiImportBounds, CuratedLlmProvider, LlmProvider, ModelInfo};

#[cfg(test)]
mod tests;

/// Environment-gated rollout switch. It is off unless explicitly enabled.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AiImportFeature {
    pub enabled: bool,
    pub bounds: AiImportBounds,
}

impl AiImportFeature {
    pub fn from_env() -> Self {
        let enabled = std::env::var("AI_IMPORT_ENABLED")
            .ok()
            .map(|value| {
                matches!(
                    value.trim().to_ascii_lowercase().as_str(),
                    "1" | "true" | "yes"
                )
            })
            .unwrap_or(false);
        Self {
            enabled,
            bounds: AiImportBounds::from_env(),
        }
    }

    pub fn from_enabled_value(value: &str) -> Self {
        Self {
            enabled: matches!(
                value.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes"
            ),
            bounds: AiImportBounds::default(),
        }
    }
}

/// Curated provider URL registry. User input is never used for these values.
#[derive(Debug, Clone, Copy, Default)]
pub struct CuratedProviderUrls;

pub fn curated_models(provider: LlmProvider) -> Vec<ModelInfo> {
    let ids: &[&str] = match provider {
        LlmProvider::OpenAI => &["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"],
        LlmProvider::OpenRouter => &[
            "openai/gpt-4o-mini",
            "openai/gpt-4o",
            "meta-llama/llama-3.1-8b-instruct:free",
        ],
        LlmProvider::EURouter => &["mistral-large-3", "mistral-small-3.1", "deepseek-v4-flash"],
        LlmProvider::Neuralwatt => &[
            "deepseek-v4-flash",
            "glm-5.2",
            "glm-5.2-fast",
            "kimi-k2.7-code",
            "kimi-k3",
            "qwen3.6-35b",
        ],
        LlmProvider::OpenCodeGo | LlmProvider::OpenCode => &[
            "deepseek-v4-pro",
            "deepseek-v4-flash",
            "glm-5.2",
            "glm-5.1",
            "kimi-k3",
            "kimi-k2.7-code",
            "kimi-k2.6",
            "minimax-m3",
            "minimax-m2.7",
            "mimo-v2.5",
            "grok-4.5",
        ],
        LlmProvider::Ollama => &["llama3.1:8b", "qwen2.5:7b"],
        _ => &[],
    };
    ids.iter()
        .map(|id| ModelInfo {
            id: (*id).to_owned(),
            display_name: None,
            provider,
        })
        .collect()
}

impl CuratedLlmProvider for CuratedProviderUrls {
    fn base_url(provider: LlmProvider) -> &'static str {
        match provider {
            LlmProvider::OpenAI => "https://api.openai.com/v1",
            LlmProvider::OpenRouter => "https://openrouter.ai/api/v1",
            LlmProvider::EURouter => "https://api.eurouter.ai/api/v1",
            LlmProvider::Neuralwatt => "https://api.neuralwatt.com/v1",
            LlmProvider::OpenCodeGo => "https://opencode.ai/zen/go/v1",
            LlmProvider::OpenCode => "https://opencode.ai/zen/v1",
            LlmProvider::Ollama => "http://ollama:11434/api",
            _ => "",
        }
    }
}
