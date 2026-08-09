// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)

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

    // --- Lifecycle transitions (owner-fenced) ------------------------------
    //
    // A claim can expire, so two workers may briefly run the same job: the
    // original worker is still executing while a second one has already
    // reclaimed it. Every worker-originated transition therefore carries the
    // claiming `worker_id`, and production adapters MUST reject the write when
    // the caller no longer owns the claim (`DomainError::Conflict`). Without
    // this fence a stale worker would silently overwrite the new owner's
    // result — e.g. stamping an outdated `preview_handle` over a fresh
    // success, or failing a job another worker just completed.

    /// The claim lease window, when the implementation has one.
    ///
    /// Workers derive their heartbeat interval from this so a long job keeps
    /// its claim alive. `None` (the default) means "no lease" — in-memory and
    /// test queues never expire a claim, so they need no heartbeat.
    fn lease_window(&self) -> Option<std::time::Duration> {
        None
    }

    /// Re-affirm `running` and extend the claim lease (heartbeat).
    async fn mark_running(&self, id: AiImportJobId, worker_id: &str) -> Result<(), DomainError>;
    async fn mark_succeeded(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        preview_handle: &str,
    ) -> Result<(), DomainError>;
    async fn mark_failed(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        error_summary: &str,
        retryable: bool,
    ) -> Result<(), DomainError>;
    /// Record telemetry produced by a *worker* while it holds the claim.
    ///
    /// Owner-fenced like the other worker transitions: a displaced worker must
    /// not overwrite the telemetry of the worker that reclaimed the job. It is
    /// deliberately separate from [`record_telemetry`](Self::record_telemetry)
    /// because that one is called from the API apply path, where the job is
    /// already terminal and there is no claim to fence on.
    async fn record_worker_telemetry(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        telemetry: Telemetry,
    ) -> Result<(), DomainError>;

    /// Record apply-time telemetry from the API boundary. Not owner-fenced:
    /// the job is terminal by then and no worker holds a claim.
    async fn record_telemetry(
        &self,
        id: AiImportJobId,
        telemetry: Telemetry,
    ) -> Result<(), DomainError>;
}

/// Idempotency mapping from a reviewed preview row (`draft_ref`) to the
/// aggregate it was applied to.
///
/// A mapping exists in two states, discriminated by [`Self::is_reserved`]:
///
/// * **Reserved** (`aggregate_version == AggregateVersion(0)`) — the
///   `aggregate_id` is durable but the command has not been confirmed to have
///   appended yet. Written by [`AiImportMappingRepository::reserve`] *before*
///   command dispatch so a crashed apply retries onto the *same* aggregate id
///   instead of generating a fresh one (issue #179).
/// * **Confirmed** (`aggregate_version > 0`) — the command appended and the
///   resulting aggregate version is recorded.
///
/// `AggregateVersion(0)` is the established "no version yet" sentinel in this
/// codebase (an empty event stream maps to it), so a reservation needs no
/// extra column.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiImportMapping {
    pub preview_id: AiImportJobId,
    pub draft_ref: String,
    pub aggregate_kind: String,
    pub aggregate_id: Uuid,
    pub aggregate_version: AggregateVersion,
}

impl AiImportMapping {
    /// Version sentinel marking a mapping whose aggregate id is durable but
    /// whose command has not been confirmed as appended.
    pub const RESERVED_VERSION: AggregateVersion = AggregateVersion(0);

    /// Build a reservation for `aggregate_id` (see [`Self::is_reserved`]).
    #[must_use]
    pub fn reservation(
        preview_id: AiImportJobId,
        draft_ref: String,
        aggregate_kind: String,
        aggregate_id: Uuid,
    ) -> Self {
        Self {
            preview_id,
            draft_ref,
            aggregate_kind,
            aggregate_id,
            aggregate_version: Self::RESERVED_VERSION,
        }
    }

    /// `true` while the mapping only reserves an id (no confirmed append).
    #[must_use]
    pub fn is_reserved(&self) -> bool {
        self.aggregate_version == Self::RESERVED_VERSION
    }
}

#[async_trait]
pub trait AiImportMappingRepository: Send + Sync {
    async fn find(
        &self,
        preview_id: AiImportJobId,
        draft_ref: &str,
    ) -> Result<Option<AiImportMapping>, DomainError>;

    /// Durably reserve `mapping.aggregate_id` for `(preview_id, draft_ref)`
    /// and return the **winning** row.
    ///
    /// Implementations SHALL be insert-if-absent: when a row already exists
    /// (a previous attempt reserved or confirmed it) that existing row is
    /// returned unchanged, so concurrent or retried applies converge on one
    /// aggregate id. The returned mapping is the one the caller must use —
    /// never the argument.
    ///
    /// Callers reserve *before* dispatching a create-style command, then call
    /// [`Self::insert`] with the real version to confirm (issue #179).
    async fn reserve(&self, mapping: AiImportMapping) -> Result<AiImportMapping, DomainError>;

    /// Upsert a confirmed mapping. Implementations SHALL only ever advance
    /// `aggregate_version` (monotonic), so a late duplicate cannot roll a row
    /// back — including back to a reservation.
    async fn insert(&self, mapping: AiImportMapping) -> Result<(), DomainError>;

    async fn list_by_preview(
        &self,
        preview_id: AiImportJobId,
    ) -> Result<Vec<AiImportMapping>, DomainError>;
}
