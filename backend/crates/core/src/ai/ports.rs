// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

#[cfg(test)]
#[path = "ports_tests.rs"]
mod ports_tests;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, BlockId, UserId};

use super::preview::{ScriptContext, ShootingSchedule};
use super::views::{AiImportJob, AiImportJobId, DocumentKind, SourceFormat, Telemetry};

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

    /// List the caller's configs, newest first (issue #337).
    ///
    /// Backs `GET /v1/ai-import/config`. The default empty impl keeps
    /// test-only backends compiling; production and API fakes override it.
    async fn list_for_user(
        &self,
        _user_id: &UserId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<super::views::AiConfigView>, DomainError> {
        Ok(Vec::new())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ModelInfo {
    pub id: String,
    pub display_name: Option<String>,
    pub provider: LlmProvider,
    /// Whether the curated catalog designates this model as the provider's
    /// recommended default for a new AI-config creation (issue #471). Only
    /// set by the curated models endpoint (`curated_models`); models fetched
    /// live from a provider never carry the flag (`false`).
    ///
    /// `#[serde(default)]`: the flag is additive on the wire — a backend
    /// that predates the field deserializes it as `false`, so clients keep
    /// their "first model" fallback for pre-flag deployments (CodeRabbit
    /// review, PR #489).
    #[serde(default)]
    pub recommended: bool,
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
        Err(DomainError::validation(
            "schedule extraction is not supported by this client",
        ))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiImportEnqueueRequest {
    pub id: AiImportJobId,
    pub user_id: UserId,
    pub document_kind: DocumentKind,
    pub source_format: SourceFormat,
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

    /// Claim the next runnable job **and** release the concurrency permit
    /// orphaned by the worker that previously held it (issue #180).
    ///
    /// A worker that dies mid-job leaves two leases behind: the job lease
    /// (recovered by the reclaim predicate, issue #177) and the permit lease
    /// (recovered only when it lapses, up to `AI_IMPORT_LEASE_SECS` later).
    /// The second one is capacity consumed by a job that is already running
    /// elsewhere. This method closes that gap by deleting the permit recorded
    /// on the job in the *same transaction* as the claim.
    ///
    /// The returned tuple is `(job, released_permit_id)`, where
    /// `released_permit_id` is `Some(orphan)` when this was a re-claim of an
    /// abandoned `running` job and `None` for a fresh `pending`/`failed`
    /// claim. Callers use the id for audit logging only — the release has
    /// already happened.
    ///
    /// Reconciliation is **exactly once**: only the worker that wins the
    /// `FOR UPDATE SKIP LOCKED` race observes a non-null orphan id, the
    /// DELETE is by primary key, and the job's `permit_id` is cleared by the
    /// same statement.
    ///
    /// The claim is left *without* a permit: the caller acquires capacity for
    /// [`AiImportJob::user_id`] next and records it with
    /// [`attach_permit`](Self::attach_permit). Freeing the orphan here rather
    /// than after the acquisition is deliberate — at a saturated ceiling the
    /// reclaiming worker would otherwise be refused the very slot the dead
    /// worker is still holding.
    ///
    /// The default implementation is for backends with no permit link
    /// (in-memory and test queues): it claims normally and reports no orphan.
    async fn claim_next_reconciling(
        &self,
        worker_id: &str,
    ) -> Result<Option<(AiImportJob, Option<Uuid>)>, DomainError> {
        Ok(self.claim_next(worker_id).await?.map(|job| (job, None)))
    }

    /// Kind-filtered variant of
    /// [`claim_next_reconciling`](Self::claim_next_reconciling) with identical
    /// permit-reconciliation semantics.
    async fn claim_next_kind_reconciling(
        &self,
        worker_id: &str,
        kind: DocumentKind,
    ) -> Result<Option<(AiImportJob, Option<Uuid>)>, DomainError> {
        Ok(self
            .claim_next_kind(worker_id, kind)
            .await?
            .map(|job| (job, None)))
    }

    /// Record the permit that now owns this worker's claim.
    ///
    /// Called after the permit was acquired for the job's own `user_id`, so
    /// the per-user ceiling is charged to the user whose work it is. The link
    /// is what lets a future reclaim release this permit if *this* worker dies
    /// (see [`claim_next_reconciling`](Self::claim_next_reconciling)).
    ///
    /// Owner-fenced like every other worker transition: a worker whose lease
    /// lapsed and whose job was reclaimed gets `DomainError::Conflict` rather
    /// than overwriting the new owner's permit link.
    ///
    /// The default implementation is a no-op for backends with no permit link.
    async fn attach_permit(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _permit_id: Uuid,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    /// Return a claimed job to the runnable pool without counting an attempt.
    ///
    /// Used when a worker claimed a job but could not acquire capacity for it:
    /// the job never ran, so it must not be charged a retry, and it must not
    /// stay `running` until its lease lapses. Owner-fenced.
    ///
    /// The default implementation is a no-op: in-memory queues have no lease,
    /// so an unreleased claim cannot block a later one.
    async fn release_claim(&self, _id: AiImportJobId, _worker_id: &str) -> Result<(), DomainError> {
        Ok(())
    }

    async fn get(&self, id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError>;

    /// List the caller's jobs, newest first (issue #337).
    ///
    /// Backs `GET /v1/ai-import/jobs`. The default empty impl keeps
    /// test-only backends compiling; production and API fakes override it.
    async fn list_for_user(
        &self,
        _user_id: &UserId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<AiImportJob>, DomainError> {
        Ok(Vec::new())
    }

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

    /// Terminate the job as [`JobStatus::PayloadUnavailable`] (issue #181).
    ///
    /// Called when a worker finds that a durable payload the job needs — its
    /// source document or its preview blob — is *absent* from storage. The
    /// remaining retry budget is deliberately bypassed: every retry could only
    /// re-discover the same absence, while consuming a concurrency permit and
    /// a claim each time.
    ///
    /// Only absence leads here. A storage backend that is merely unreachable
    /// yields `DomainError::ServiceUnavailable` and must keep using
    /// [`mark_failed`](Self::mark_failed) with `retryable = true`, because the
    /// bytes may well still be there.
    ///
    /// Owner-fenced like every other worker transition.
    ///
    /// The default implementation records a non-retryable failure, which is
    /// the closest equivalent for backends without the distinct status
    /// (in-memory and test queues).
    async fn mark_payload_unavailable(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        error_summary: &str,
    ) -> Result<(), DomainError> {
        self.mark_failed(id, worker_id, error_summary, false).await
    }

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

/// Idempotency mapping from a reviewed preview row to the aggregate it was
/// applied to.
///
/// One preview produces **several kinds of row**: the scene a draft row
/// describes, the figures that row names, and each of its costumes. They share
/// the row's `draft_ref`, so a mapping is addressed by the full key
/// `(preview_id, draft_ref, aggregate_kind, ordinal)` — without the kind and the
/// ordinal, the first costume of a scene would resolve to the scene's own
/// aggregate (design D4).
///
/// A figure is the exception, and deliberately so: a `Character` is a *season*
/// concept, not a scene concept, so its `draft_ref` is the preview-wide
/// [`crate::ai::character_mapping_ref`] of its normalised name rather than the
/// scene row that mentioned it. Keying it per scene row would create one
/// aggregate per mention (measured live: 268 mentions over 131 scenes) and
/// destroy the costume continuity the domain exists to manage.
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
    /// Disambiguates rows that share `draft_ref` *and* `aggregate_kind` — the
    /// costumes of one figure in one scene. Every other kind carries
    /// [`PRIMARY_ORDINAL`].
    pub ordinal: i32,
    pub aggregate_id: Uuid,
    pub aggregate_version: AggregateVersion,
}

/// `aggregate_kind` discriminators of `projection_ai_import_mapping`. A new kind
/// is additive: the column is free text, the discriminator is what keeps the
/// per-row ordinals of one kind from colliding with another kind's.
pub mod mapping_kind {
    pub const SCENE: &str = "scene";
    pub const CHARACTER: &str = "character";
    pub const COSTUME: &str = "costume";
    pub const SHOOTING_DAY: &str = "shooting_day";
    pub const SCENE_SHOOT: &str = "scene_shoot";
    /// One costume beat the AI apply added to a draft row's scene (issue
    /// #546 §5.8). Addressed by the figure's preview-wide mapping reference
    /// (the same `draft_ref` the `character` rows use) plus the costume's
    /// PER-FIGURE position — two figures of one row would otherwise share
    /// one row and the second figure's first beat would silently never be
    /// applied. `aggregate_id` is the scene the beat was added to.
    pub const SCENE_COSTUME_BEAT: &str = "scene_costume_beat";
    /// One episode an AI script apply created for a draft episode group
    /// (issue #581). Keyed by the group ref (`ep:<n>` / `ep-t:<title>`,
    /// [`breakdown_core::ai::DraftEpisode::group_key`]) with
    /// [`PRIMARY_ORDINAL`]; `aggregate_id` is the created Episode.
    pub const EPISODE: &str = "episode";
}

/// Ordinal of a mapping kind that has exactly one row per `draft_ref` — scenes,
/// figures and schedule rows. Only `costume` numbers its rows, because one scene
/// can carry several costumes of the same figure.
pub const PRIMARY_ORDINAL: i32 = 0;

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
        ordinal: i32,
        aggregate_id: Uuid,
    ) -> Self {
        Self {
            preview_id,
            draft_ref,
            aggregate_kind,
            ordinal,
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
    /// Look one mapping row up by its full key. A draft scene and its first
    /// costume share a `draft_ref`; only `(kind, ordinal)` tells them apart.
    async fn find(
        &self,
        preview_id: AiImportJobId,
        draft_ref: &str,
        aggregate_kind: &str,
        ordinal: i32,
    ) -> Result<Option<AiImportMapping>, DomainError>;

    /// Durably reserve `mapping.aggregate_id` for
    /// `(preview_id, draft_ref, aggregate_kind, ordinal)` and return the
    /// **winning** row.
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
