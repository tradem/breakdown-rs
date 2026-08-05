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
pub mod mapping;
pub mod merge_worker;
pub mod ollama;
pub mod pdf;
pub mod pg_concurrency;
pub mod preview_store;
pub mod prompts;
pub mod queue;
pub mod schedule_apply;
pub mod shutdown;
pub mod workers;

pub use catalog::OpenAiCompatibleModelCatalog;
pub use client::{OpenAiCompatibleChatClient, classify_http_status, classify_transport_error};
pub use concurrency::{AiConcurrencyLimiter, AiConcurrencyPermit};
pub use credentials::AiCredentialResolver;
pub use csv_schedule::parse_schedule_csv;
pub use mapping::PgAiImportMappingRepository;
pub use merge_worker::{QueueMergeWorker, merge_loaded_schedule};
pub use ollama::OllamaChatClient;
pub use pdf::PdfTextExtractor;
pub use pg_concurrency::{PgAiConcurrencyLimiter, PgAiConcurrencyPermit};
pub use preview_store::{AiDocumentSource, AiPreviewStore, MemoryAiPreviewStore};
pub use prompts::default_prompt;
pub use queue::PgAiImportQueue;
pub use schedule_apply::{
    AppliedDay, ScheduleApplyRequest, ScheduleApplyResult, ScheduleApplyWorker,
};
pub use shutdown::{AiJobGuard, AiWorkerLifecycle};
pub use workers::{
    ApplyScriptRequest, ApplyWorker, MergeWorker, ScheduleImportWorker, ScriptImportWorker,
    UuidVersion,
};

use breakdown_core::ai::{AiImportBounds, CuratedLlmProvider, LlmProvider};

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

impl CuratedLlmProvider for CuratedProviderUrls {
    fn base_url(provider: LlmProvider) -> &'static str {
        match provider {
            LlmProvider::OpenAI => "https://api.openai.com/v1",
            LlmProvider::OpenRouterEU => "https://openrouter.ai/api/v1",
            LlmProvider::Ollama => "http://ollama:11434/api",
            _ => "",
        }
    }
}
