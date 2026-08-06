// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, BlockId, UserId};

use super::preview::{ScriptContext, ShootingSchedule};
use super::views::{AiImportJob, AiImportJobId, DocumentKind, Telemetry};

/// Curated providers. The enum is intentionally non-exhaustive so adding a
/// provider is additive and does not break downstream matches.
#[non_exhaustive]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum LlmProvider {
    #[serde(rename = "openai")]
    OpenAI,
    #[serde(rename = "openrouter")]
    OpenRouter,
    #[serde(rename = "eurouter", alias = "openrouter_eu")]
    EURouter,
    #[serde(rename = "neuralwatt")]
    Neuralwatt,
    #[serde(rename = "opencode-go")]
    OpenCodeGo,
    #[serde(rename = "opencode")]
    OpenCode,
    Ollama,
}

impl LlmProvider {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::OpenAI => "openai",
            Self::OpenRouter => "openrouter",
            Self::EURouter => "eurouter",
            Self::Neuralwatt => "neuralwatt",
            Self::OpenCodeGo => "opencode-go",
            Self::OpenCode => "opencode",
            Self::Ollama => "ollama",
        }
    }

    /// Stable provider key used by infra's hardcoded URL registry. No URL is
    /// accepted from a user or stored in the core aggregate.
    pub const fn curated_base_url_key(self) -> &'static str {
        self.as_str()
    }

    pub const fn is_local(self) -> bool {
        matches!(self, Self::Ollama)
    }
}

/// The curated provider set in display order. Single source for the providers
/// and models endpoints; a new `LlmProvider` variant must be added to the
/// exhaustive `as_str` match above (compile-time) and to this list (curation).
pub const CURATED_PROVIDERS: [LlmProvider; 7] = [
    LlmProvider::OpenAI,
    LlmProvider::OpenRouter,
    LlmProvider::EURouter,
    LlmProvider::Neuralwatt,
    LlmProvider::OpenCodeGo,
    LlmProvider::OpenCode,
    LlmProvider::Ollama,
];

/// Infra supplies the hardcoded URL for a curated provider.
pub trait CuratedLlmProvider: Send + Sync {
    fn base_url(provider: LlmProvider) -> &'static str;
}

#[async_trait]
pub trait AiConfigCommands: Send + Sync {
    async fn create(
        &self,
        actor: UserId,
        command: super::commands::CreateAiConfig,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;
    async fn update(
        &self,
        actor: UserId,
        command: super::commands::UpdateAiConfig,
    ) -> Result<AggregateVersion, DomainError>;
    async fn revoke(
        &self,
        actor: UserId,
        command: super::commands::RevokeAiConfig,
    ) -> Result<AggregateVersion, DomainError>;
}

#[async_trait]
pub trait AiConfigRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<super::views::AiConfigView, DomainError>;
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ModelInfo {
    pub id: String,
    pub display_name: Option<String>,
    pub provider: LlmProvider,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmChatRequest {
    pub provider: LlmProvider,
    pub model: String,
    pub prompt: String,
    pub source_text: String,
    pub max_tokens: u32,
    /// Serialized schema passed by infra to a constrained provider. Core does
    /// not generate or validate this provider-specific schema.
    pub response_schema: Option<serde_json::Value>,
}

#[async_trait]
pub trait LlmModelCatalog: Send + Sync {
    async fn list(
        &self,
        provider: LlmProvider,
        vaulted_key: &str,
    ) -> Result<Vec<ModelInfo>, DomainError>;
}

#[async_trait]
pub trait LlmClient: Send + Sync {
    async fn chat_constrained(&self, req: LlmChatRequest) -> Result<ScriptContext, DomainError>;

    async fn extract_schedule(&self, req: LlmChatRequest) -> Result<ShootingSchedule, DomainError> {
        let _ = req;
        Err(DomainError::ValidationError(
            "schedule extraction is not supported by this client".to_owned(),
        ))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiImportEnqueueRequest {
    pub id: AiImportJobId,
    pub user_id: UserId,
    pub document_kind: DocumentKind,
    pub block_id: Option<BlockId>,
    pub dedup_key: String,
    pub document_digest: String,
    pub source_handle: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiImportEnqueueResult {
    Enqueued(AiImportJobId),
    Existing(AiImportJobId),
}

#[async_trait]
pub trait AiImportQueue: Send + Sync {
    async fn enqueue(
        &self,
        request: AiImportEnqueueRequest,
    ) -> Result<AiImportEnqueueResult, DomainError>;
    async fn claim_next(&self, worker_id: &str) -> Result<Option<AiImportJob>, DomainError>;

    /// Claim only jobs for a worker's document kind. Production adapters must
    /// apply the filter atomically in SQL so a worker never claims a job for a
    /// different worker type.
    async fn claim_next_kind(
        &self,
        worker_id: &str,
        kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError>;

    async fn get(&self, id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError>;
    async fn mark_running(&self, id: AiImportJobId) -> Result<(), DomainError>;
    async fn mark_succeeded(
        &self,
        id: AiImportJobId,
        preview_handle: &str,
    ) -> Result<(), DomainError>;
    async fn mark_failed(
        &self,
        id: AiImportJobId,
        error_summary: &str,
        retryable: bool,
    ) -> Result<(), DomainError>;
    async fn record_telemetry(
        &self,
        id: AiImportJobId,
        telemetry: Telemetry,
    ) -> Result<(), DomainError>;
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiImportMapping {
    pub preview_id: AiImportJobId,
    pub draft_ref: String,
    pub aggregate_kind: String,
    pub aggregate_id: Uuid,
    pub aggregate_version: AggregateVersion,
}

#[async_trait]
pub trait AiImportMappingRepository: Send + Sync {
    async fn find(
        &self,
        preview_id: AiImportJobId,
        draft_ref: &str,
    ) -> Result<Option<AiImportMapping>, DomainError>;
    async fn insert(&self, mapping: AiImportMapping) -> Result<(), DomainError>;
    async fn list_by_preview(
        &self,
        preview_id: AiImportJobId,
    ) -> Result<Vec<AiImportMapping>, DomainError>;
}
