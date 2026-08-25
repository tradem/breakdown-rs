// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

//! AI infrastructure adapters.
//!
//! The module is intentionally additive: transport, persistence, workers, and
//! document adapters can be added without making the core domain depend on
//! `reqwest`, `sqlx`, `schemars`, or subprocess APIs.

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

pub mod catalog;
pub mod client;
pub mod concurrency;
pub mod credentials;
pub mod csv_schedule;
pub mod gdrive_source;
pub mod heartbeat;
pub mod mapping;
pub mod merge_worker;
pub mod ollama;
pub mod payload_cleanup;
pub mod payload_storage;
pub mod pdf;
pub mod pg_concurrency;
pub mod preview_store;
pub mod prompts;
pub mod provider_registry;
pub mod queue;
pub mod runtime;
pub mod schedule_apply;
pub mod shutdown;
pub mod transport;
pub mod worker_loop;
pub mod workers;

pub use catalog::OpenAiCompatibleModelCatalog;
pub use client::{OpenAiCompatibleChatClient, classify_http_status, classify_transport_error};
pub use concurrency::{AiConcurrencyLimiter, AiConcurrencyPermit};
pub use credentials::AiCredentialResolver;
pub use csv_schedule::parse_schedule_csv;
pub use gdrive_source::{GDriveDocument, GDriveDocumentSource};
pub use heartbeat::{LeaseHeartbeat, renewal_interval};
pub use mapping::PgAiImportMappingRepository;
pub use merge_worker::{QueueMergeWorker, merge_loaded_schedule};
pub use ollama::OllamaChatClient;
pub use payload_cleanup::AiPayloadGcConfig;
pub use payload_storage::OpenDalAiPayloadStorage;
pub use pdf::PdfTextExtractor;
pub use pg_concurrency::{
    DEFAULT_PERMIT_LEASE, PermitReclaimer, PgAiConcurrencyLimiter, PgAiConcurrencyPermit,
    permit_renewal_interval,
};
pub use preview_store::{
    AiDocumentSource, AiDocumentStore, AiPreviewStore, MemoryAiPreviewStore,
    UnconfiguredAiPayloadStore,
};
pub use prompts::default_prompt;
pub use provider_registry::{
    PROVIDER_REGISTRY, ProviderInfo, curated_models, list_providers, resolve_provider,
};
pub use queue::PgAiImportQueue;
pub use runtime::AiWorkerRuntime;
pub use schedule_apply::{
    AppliedDay, ScheduleApplyRequest, ScheduleApplyResult, ScheduleApplyWorker,
};
pub use shutdown::{AiJobGuard, AiWorkerLifecycle, DRAIN_TIMEOUT};
pub use transport::{
    curated_provider_redirect_policy, hosted_provider_redirect_policy, ollama_redirect_policy,
};
pub use worker_loop::{
    WorkerDeps, shutdown_signal, spawn_schedule_import_worker, spawn_script_import_worker,
};
pub use workers::{
    ApplyScriptRequest, ApplyWorker, MergeWorker, ScheduleImportWorker, ScriptImportWorker,
    UuidVersion, validate_chunk_count,
};

use breakdown_core::ai::{AiImportBounds, CuratedLlmProvider, LlmProvider};

#[cfg(test)]
mod catalog_misc_tests;
#[cfg(test)]
mod payload_recovery_tests;
#[cfg(test)]
mod provider_url_tests;
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
