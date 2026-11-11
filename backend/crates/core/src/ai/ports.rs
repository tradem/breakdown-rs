// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use async_trait::async_trait;
use futures::Stream;
use serde::{Deserialize, Serialize};
use std::pin::Pin;
use utoipa::ToSchema;
use uuid::Uuid;

#[cfg(test)]
#[path = "ports_tests.rs"]
mod ports_tests;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, BlockId, UserId};

use super::preview::{ScriptContext, ShootingSchedule};
use super::provider_health::{BreakerCounters, BreakerDecision, ProviderOutcome};
use super::views::{
    AiImportAttempt, AiImportJob, AiImportJobId, AiImportProgress, AiImportTarget, ApplyProgress,
    ApplyRunId, ApplyRunState, DocumentKind, ModelPricing, ProviderBreakerState, ProviderHold,
    SourceFormat, Telemetry,
};

/// Curated providers. The enum is intentionally non-exhaustive so adding a
/// provider is additive and does not break downstream matches.
#[non_exhaustive]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum LlmProvider {
    #[serde(rename = "openai")]
    OpenAI,
    /// Google Gemini via its official OpenAI-compatible endpoint
    /// (issue #675). `"google"` is accepted as an alias on input so the
    /// provider can be addressed by either key; the canonical wire key is
    /// `"gemini"`.
    #[serde(rename = "gemini", alias = "google")]
    Gemini,
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
            Self::Gemini => "gemini",
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
pub const CURATED_PROVIDERS: [LlmProvider; 8] = [
    LlmProvider::OpenAI,
    LlmProvider::Gemini,
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
    /// Pricing snapshot from the `ai_import.ai_model_pricing` read model
    /// (issue #675). `None` for models without known pricing (e.g. local
    /// Ollama models) — never a fabricated zero-price object. Additive with
    /// `serde(default)` on the wire.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pricing: Option<ModelPricing>,
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

/// Token and energy usage of one LLM call, extracted from the provider
/// response (issue #675). Accumulated across all chunks and bounded
/// truncation/parse retries of a job; persisted via `record_worker_telemetry`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LlmCallUsage {
    pub tokens_in: u64,
    pub tokens_out: u64,
    /// Prompt tokens served from the provider cache.
    pub cached_tokens_in: u64,
    /// Hardware energy reported by the provider (e.g. Neuralwatt), in
    /// millijoules.
    pub energy_millijoules: u64,
}

impl LlmCallUsage {
    /// Element-wise saturating accumulation across calls.
    pub fn accumulate(&mut self, other: Self) {
        self.tokens_in = self.tokens_in.saturating_add(other.tokens_in);
        self.tokens_out = self.tokens_out.saturating_add(other.tokens_out);
        self.cached_tokens_in = self.cached_tokens_in.saturating_add(other.cached_tokens_in);
        self.energy_millijoules = self
            .energy_millijoules
            .saturating_add(other.energy_millijoules);
    }
}

/// One cost component's accumulated usage **plus** how many billable calls
/// produced it (issue #768) and the per-call usages themselves (issue #794).
///
/// The call count is tracked next to the counters instead of being inferred
/// from them: a successful provider answer may report no usage metadata at all,
/// so an all-zero [`LlmCallUsage`] is a recorded call with zero counters — not
/// an absent one. Only `calls == 0` means "this component spent nothing", which
/// is what keeps an unpriced Decision Model's component (and its honest
/// `incomplete` total) from being dropped.
///
/// `per_call` retains every billable call's own [`LlmCallUsage`] because a
/// provider may cap energy per **request** (Neuralwatt surge protection): the
/// honest figure is `Σ_calls min(raw_i, token_i)`, and
/// `Σ min(a_i, b_i) <= min(Σ a_i, Σ b_i)` — the aggregate cap is only an upper
/// bound and can overstate what was billed (issue #794). The ledger is bounded
/// by the job's request budget (`max_chunks_per_script` extraction calls plus
/// the bounded Decision-Model passes), i.e. a few hundred entries.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UsageAccumulator {
    /// Summed counters of every recorded call.
    pub usage: LlmCallUsage,
    /// Number of billable calls that produced `usage` (saturating).
    pub calls: u32,
    /// Per-call usage in call order, written only by [`Self::record`] (issue
    /// #794). `#[serde(default)]`: additive on any persisted payload.
    #[serde(default)]
    pub per_call: Vec<LlmCallUsage>,
}

impl UsageAccumulator {
    /// Record one call's usage: accumulate the counters, keep the entry for the
    /// per-request pricing of issue #794, and count the call, whatever the
    /// counters say.
    pub fn record(&mut self, usage: LlmCallUsage) {
        self.usage.accumulate(usage);
        self.calls = self.calls.saturating_add(1);
        self.per_call.push(usage);
    }

    /// The requests this component's cost is priced over (issue #794).
    ///
    /// Normally the retained per-call ledger. An accumulator whose counters were
    /// set without a ledger (a hand-built value, or a payload recorded before
    /// the ledger existed) prices as the single aggregate request — which is
    /// exactly the pre-#794 figure, never a zero.
    #[must_use]
    pub fn priced_calls(&self) -> &[LlmCallUsage] {
        if self.per_call.is_empty() {
            std::slice::from_ref(&self.usage)
        } else {
            &self.per_call
        }
    }
}

/// The parsed output of one LLM call plus its usage telemetry (design D3).
#[derive(Debug, Clone, PartialEq)]
pub struct LlmCallOutcome<T> {
    pub output: T,
    pub usage: LlmCallUsage,
}

impl<T> LlmCallOutcome<T> {
    pub fn new(output: T, usage: LlmCallUsage) -> Self {
        Self { output, usage }
    }
}

#[async_trait]
pub trait LlmClient: Send + Sync {
    async fn chat_constrained(
        &self,
        req: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError>;

    async fn extract_schedule(
        &self,
        req: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ShootingSchedule>, DomainError> {
        let _ = req;
        Err(DomainError::validation(
            "schedule extraction is not supported by this client",
        ))
    }
}

/// One `(provider, model)` pricing row of the read model (issue #675).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelPricingRow {
    pub provider: LlmProvider,
    pub model: String,
    pub pricing: ModelPricing,
}

/// Read-model port over `ai_import.ai_model_pricing` (issue #675). The
/// API edge consumes `find_for_model` / `list_for_provider`; the pricing
/// refresh worker consumes `upsert_batch` (UPSERT-only — never deletes rows
/// that a live feed rotated out).
#[async_trait]
pub trait AiModelPricingRepository: Send + Sync {
    async fn find_for_model(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<Option<ModelPricing>, DomainError>;

    /// All pricing rows of one provider; the model list endpoint attaches
    /// them to the returned `ModelInfo`s.
    async fn list_for_provider(
        &self,
        provider: LlmProvider,
    ) -> Result<Vec<ModelPricingRow>, DomainError>;

    /// UPSERT a batch of pricing rows keyed `(provider, model)`. Existing
    /// rows absent from the batch remain untouched (rotated-model retention).
    async fn upsert_batch(&self, entries: Vec<ModelPricingRow>) -> Result<(), DomainError>;
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiImportEnqueueRequest {
    pub id: AiImportJobId,
    pub user_id: UserId,
    pub document_kind: DocumentKind,
    pub source_format: SourceFormat,
    pub block_id: Option<BlockId>,
    /// The target the upload DECLARED, resolved at the API edge (issue #771).
    ///
    /// Persisted alongside [`Self::block_id`] as display metadata, not as a
    /// second write target: the apply path keeps pinning itself to `block_id`.
    /// `None` when the season's read metadata could not be resolved — an
    /// honest absence the wire renders as `null`, never a fabricated season.
    pub target: Option<AiImportTarget>,
    pub dedup_key: String,
    pub document_digest: String,
    pub source_handle: String,
    /// The uploaded document's own file name, already sanitized at the API
    /// edge (issue #763). `None` for an upload that carried no name, which the
    /// job row stores as `NULL` — never a fabricated or handle-derived value.
    pub source_file_name: Option<String>,
    /// The provider of the user's active AI config, snapshotted at the API edge
    /// (issue #871, D-A2b).
    ///
    /// Source of the value is the API edge — the only legitimate read-model
    /// consumer, exactly as for the `target` snapshot (#771) and
    /// `source_file_name` (#763). The claim predicate filters on this pair and
    /// runs *before* `resolve_config`, so a stale snapshot is refreshed at the
    /// config-change edge and re-checked (authoritatively) after resolution.
    /// `None` means "could not be resolved" — such a job is never
    /// breaker-filtered, which is the honest degradation.
    pub provider: Option<LlmProvider>,
    /// The model of the user's active AI config. See [`Self::provider`].
    pub model: Option<String>,
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
        error_code: Option<&str>,
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
        error_code: Option<&str>,
    ) -> Result<(), DomainError> {
        self.mark_failed(id, worker_id, error_summary, error_code, false)
            .await
    }

    /// Park a claimed job on its provider's breaker **without** spending a
    /// retry (issue #871, D-A4).
    ///
    /// Deliberately not `mark_failed`:
    ///
    /// | | `mark_failed` | `mark_held` |
    /// |---|---|---|
    /// | `retries` | +1 | **unchanged** |
    /// | attempt row | appended | **none** |
    /// | `status` | `failed` → maybe `dead_letter` | `failed` |
    /// | `next_attempt_at` | job backoff (1 min · 2^n) | the breaker's `retry_at` |
    /// | `last_error` | error summary | provider summary (old clients keep the #822 narrative) |
    /// | `progress` | kept on the retryable branch | kept |
    /// | `provider_hold` | cleared | set |
    ///
    /// The budget must not be consumed by an attempt that never reached the
    /// provider, and the attempt history must not fill with identical rows —
    /// that is the whole point of the separate write.
    ///
    /// Owner-fenced like every other worker transition. The implementation also
    /// owns the hold **series clock** (`COALESCE(provider_hold_series_started_at,
    /// now())`) and therefore the `hold_deadline`, so a re-hold can never
    /// restart the expiry budget (D-C4).
    ///
    /// The default hands the job back through
    /// [`release_claim`](Self::release_claim) — the pre-existing "return a
    /// claimed job to the runnable pool **without** counting an attempt"
    /// transition. That is the honest fallback for a backend with no durable
    /// breaker: nothing is charged, and the job stays claimable. Falling back to
    /// [`mark_failed`](Self::mark_failed) would charge the very budget this
    /// write exists to protect.
    ///
    /// `hold_window_secs` is the configured
    /// `AI_IMPORT_MAX_PROVIDER_HOLD_SECS`: the deadline is derived from the
    /// job's own series clock plus this window, so it must be passed in rather
    /// than inferred from the hold's `hold_deadline - until` (that difference is
    /// short by the current open window, which grows to 30 min under flapping).
    async fn mark_held(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        _hold: ProviderHold,
        _hold_window_secs: u64,
    ) -> Result<(), DomainError> {
        self.release_claim(id, worker_id).await
    }

    /// Materialize a hold on every **runnable** job of a pair (issue #871,
    /// D-A4 writer 2).
    ///
    /// Runs on the `closed → open` transition: a job whose pair is already open
    /// is never claimed, so an owner-fenced write could not reach it — it would
    /// sit `pending` with no reason and no deadline, which is exactly the
    /// invisibility #822 removed. No claim, no owner, no provider call.
    ///
    /// Returns the ids it touched so the caller can notify each one through the
    /// existing hub.
    ///
    /// The default implementation is a no-op for backends with no job table.
    async fn hold_runnable_jobs(
        &self,
        _provider: LlmProvider,
        _model: &str,
        _hold: ProviderHold,
        _hold_window_secs: u64,
    ) -> Result<Vec<AiImportJobId>, DomainError> {
        Ok(Vec::new())
    }

    /// Re-point every held job of a pair at a new probe time (issue #871,
    /// D-A6 `half_open → open`).
    ///
    /// Without it a held job would display a resume time that has already
    /// passed while the claim predicate — which reads the **breaker**, not the
    /// job — keeps it unclaimable.
    ///
    /// The default implementation is a no-op for backends with no job table.
    async fn refresh_held_jobs(
        &self,
        _provider: LlmProvider,
        _model: &str,
        _until: chrono::DateTime<chrono::Utc>,
    ) -> Result<Vec<AiImportJobId>, DomainError> {
        Ok(Vec::new())
    }

    /// Rewrite the breaker-key snapshot of one job (issue #871, D-A2b).
    ///
    /// The snapshot is taken at enqueue, but the pair a job actually uses is
    /// resolved per attempt. When the two differ the resolved pair wins: the
    /// claim predicate must filter on the pair the next attempt will call, or a
    /// job could be filtered forever against a breaker it no longer uses.
    ///
    /// Owner-fenced: only the worker holding the claim may rewrite it, so a
    /// displaced worker cannot stamp a pair onto a job another worker is running.
    ///
    /// The default implementation is a no-op for backends without a snapshot.
    async fn stamp_breaker_pair(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _provider: LlmProvider,
        _model: &str,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    /// Rewrite the breaker-key snapshot of **every runnable job of one user**
    /// (issue #871, D-A2b layer 1).
    ///
    /// The config-change edge calls this: when a user switches provider or model,
    /// their queued jobs must be filtered against the breaker of the pair they
    /// will now use — not the one they were enqueued with. One statement, and it
    /// deliberately touches only `pending`/`failed` rows: a `running` job has an
    /// owner and its own attempt refreshes the snapshot authoritatively, and a
    /// terminal job will never be claimed again.
    ///
    /// The default implementation is a no-op for backends without a snapshot.
    async fn restamp_user_breaker_pair(
        &self,
        _user_id: &UserId,
        _provider: LlmProvider,
        _model: &str,
    ) -> Result<u64, DomainError> {
        Ok(0)
    }

    /// Release every held job of a pair because the breaker **closed**
    /// (issue #871, D-A6).
    ///
    /// A close means the endpoint answers again, so the wait is over: the rows
    /// drop `provider_hold` and become claimable through their own (now past)
    /// `next_attempt_at`. Without this the marker would linger until each job is
    /// claimed, and a client would keep rendering "waiting until X" for a job
    /// that is already runnable.
    ///
    /// The **hold series clock survives** (`provider_hold_series_started_at` is
    /// deliberately not touched): a short recovery must not hand the next
    /// incident a fresh 6 h budget, which is exactly the flapping hole D-C4
    /// closes. The clock is cleared on claim, or by the sweeper once the job has
    /// been un-held for the stable window.
    ///
    /// The default implementation is a no-op for backends with no job table.
    async fn release_held_jobs(
        &self,
        _provider: LlmProvider,
        _model: &str,
    ) -> Result<Vec<AiImportJobId>, DomainError> {
        Ok(Vec::new())
    }

    /// Expire held jobs whose own `hold_deadline` passed (issue #871, D-C4).
    ///
    /// The **only** path that can reach such a job: it is `failed` while its
    /// pair is open, so the claim predicate keeps it unclaimable, and
    /// [`mark_held`](Self::mark_held)'s owner fence needs a `running` row that
    /// no longer exists. A claim-free sweeper therefore performs it, keyed on
    /// the job's own deadline rather than on any claim.
    ///
    /// `retries` stays untouched — the document did not fail, the provider did,
    /// so the operator's "documents that failed" count must not be inflated by
    /// infrastructure — and `provider_hold` is kept with
    /// `state = expired`, the durable marker that separates an expiry from a
    /// spent retry budget.
    ///
    /// Returns the ids it dead-lettered.
    ///
    /// The default implementation is a no-op for backends with no job table.
    async fn expire_provider_holds(
        &self,
        _error_summary: &str,
        _error_code: Option<&str>,
    ) -> Result<Vec<AiImportJobId>, DomainError> {
        Ok(Vec::new())
    }

    /// The provider breaker's verdict for one `(provider, model)` pair
    /// (issue #871).
    ///
    /// Consulted by the worker at the **chunk boundary** and by the in-attempt
    /// retry loop before every attempt, which is how an outage stops costing
    /// money mid-run: the in-flight request is not aborted (an aborted HTTP
    /// request is not refunded), so the only honest saving is not *starting* the
    /// next one. The overspend bound is therefore exactly one chunk per worker.
    ///
    /// The default reports `closed` — a backend with no durable breaker admits
    /// everything, which is exactly the pre-#871 behaviour.
    async fn provider_breaker(
        &self,
        _provider: LlmProvider,
        _model: &str,
    ) -> Result<ProviderBreakerSnapshot, DomainError> {
        Ok(ProviderBreakerSnapshot::closed())
    }

    /// Record one paid-call outcome in the durable breaker (issue #871, D-A3).
    ///
    /// This is the **write** side of the breaker and the only thing that makes
    /// it real: without it `consecutive_failures` never moves, so a closed
    /// breaker can never open from actual traffic and the claim filter, the holds
    /// and the expiry machinery would all be inert.
    ///
    /// Only **retryable provider failures** may be recorded as
    /// [`ProviderOutcome::RetryableFailure`] — a revoked key or an entitlement 4xx
    /// is permanent (#637) and would convert one user's misconfiguration into an
    /// outage for everyone on the endpoint.
    ///
    /// Returns the transition, so the caller can act on it: `opened` means the
    /// caller holds its job, `closed` means the pair's held jobs may be released.
    ///
    /// The default reports "nothing changed" for backends without a breaker.
    async fn record_provider_outcome(
        &self,
        _provider: LlmProvider,
        _model: &str,
        _outcome: ProviderOutcome,
        _threshold: u32,
    ) -> Result<BreakerDecision, DomainError> {
        Ok(BreakerDecision::unchanged(BreakerCounters {
            state: ProviderBreakerState::Closed,
            consecutive_failures: 0,
            flap_count: 0,
            closed_at: None,
        }))
    }

    /// Whether a paid call for this pair may be started right now.
    ///
    /// Derived from [`provider_breaker`](Self::provider_breaker) so there is one
    /// source of truth for "only `closed` admits work". A **failed read fails
    /// open**: this consult only ever *saves* money, so a database hiccup must
    /// not silently stop the whole pipeline.
    async fn provider_admits(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<bool, DomainError> {
        Ok(self
            .provider_breaker(provider, model)
            .await
            .map(|snapshot| snapshot.admits_claim())
            .unwrap_or(true))
    }

    /// Publish live extraction progress for a claimed job (issue #664).
    ///
    /// Owner-fenced like every other worker transition: a worker whose lease
    /// lapsed and whose job was reclaimed gets [`DomainError::Conflict`]
    /// rather than overwriting the new owner's progress — the displaced
    /// worker aborts before its next billable LLM call.
    ///
    /// Throttling contract (ADR-038 D3): called only at stage boundaries and
    /// once per completed chunk (`1..=chunks_total`), NEVER per generated
    /// LLM token.
    ///
    /// The default is a no-op for backends and test fakes that do not track
    /// progress.
    async fn mark_progress(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _progress: &AiImportProgress,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    /// Claim (or steal) the **apply-run slot** of one job (issue #800).
    ///
    /// The apply path had no single-flight gate, so two accepted applies of one
    /// `succeeded` job could run at once: their counters overwrote each other
    /// and the first run to finish cleared the slot, closing the still-running
    /// run's stream. This is the atomic claim that makes the run unique.
    ///
    /// Returns `true` when `run_id` now owns the slot, `false` when a **live**
    /// run already does (the caller answers `409 ai-import.apply-in-flight`).
    /// A claim whose payload is older than
    /// [`ApplyProgress::STALE_AFTER`] belongs to a dead process and is stolen
    /// inside the same statement — the crash/release path needs no separate
    /// reaper.
    ///
    /// The claim also bumps the job's monotonic run counter
    /// ([`ApplyRunState::seq`]), which is what lets the apply stream tell "no run
    /// ever started" from "a run started and already ended".
    ///
    /// Production adapters MUST refuse the claim while the job is not
    /// `succeeded` (same predicate as [`mark_apply_progress`](Self::mark_apply_progress)).
    ///
    /// The default answers `true` for backends and test fakes that do not track
    /// the slot: an adapter with no slot has nothing to single-flight.
    async fn claim_apply_run(
        &self,
        _id: AiImportJobId,
        _run_id: ApplyRunId,
    ) -> Result<bool, DomainError> {
        Ok(true)
    }

    /// Read the apply-run slot of one job (issue #800): its owning run, the
    /// monotonic run counter, the owner's last published payload and the instant
    /// that owner took the slot ([`ApplyRunState::owner_claimed_at`], issues
    /// #863).
    ///
    /// `None` when the job does not exist (the stream closes). The apply stream
    /// needs the counter, not just the payload: a run that starts and clears
    /// between two re-reads leaves no payload behind, and inferring "a run
    /// happened" from the frames it managed to emit is exactly the bug this
    /// read fixes.
    ///
    /// The claim instant is not decorative: the single-flight claim
    /// ([`claim_apply_run`](Self::claim_apply_run)) judges an owner that has
    /// published **nothing** by that owner-scoped stamp, so a refusal cannot
    /// report an age for that state without it — which is what left a run that
    /// died before its first frame unageable (issue #863).
    ///
    /// The default **mirrors [`get`](Self::get)** rather than reporting an
    /// empty slot: the stream ends when this returns `None`, so a default
    /// `None` would cut the stream off after its snapshot frame — with no final
    /// `null` frame — for every adapter that publishes progress and wake-ups but
    /// does not track a slot. Such an adapter has no counter to offer either, so
    /// `seq` stays `0` and the owner is derived from the payload it published:
    /// the pre-#800 behaviour (a run that starts and clears between two reads
    /// stays invisible) without losing the runs it *did* publish.
    async fn apply_run_state(
        &self,
        id: AiImportJobId,
    ) -> Result<Option<ApplyRunState>, DomainError> {
        Ok(self.get(id).await?.map(|job| {
            let progress = job.apply_progress;
            let owner = progress.as_ref().map(|frame| frame.run_id);
            ApplyRunState {
                owner,
                seq: 0,
                // A job DTO carries no claim instant, and guessing one from the
                // row's `updated_at` is exactly what #863 review rejected: the
                // owner is derived from the payload here, so an age comes from
                // that payload anyway.
                owner_claimed_at: None,
                progress,
            }
        }))
    }

    /// Publish (or clear, with `None`) the progress of one **apply run**
    /// (issues #762, #800).
    ///
    /// Fenced by the run identity, not by a worker lease: an apply runs against
    /// a job that is already terminal (`succeeded`), so there is no claim to
    /// fence on — the same contract as
    /// [`record_telemetry`](Self::record_telemetry), the other write the API
    /// edge performs. A write from a run that no longer owns the slot is a
    /// no-op, which is what keeps a superseded (stale-stealing) run from
    /// ending the current run's stream.
    ///
    /// `None` clears the payload **and** releases the slot: the run ended
    /// (successfully or not) and the dedicated apply stream closes on that
    /// signal instead of on a timeout. The run counter is never cleared, so the
    /// ended run stays provable. Every write is expected to wake
    /// [`subscribe`](Self::subscribe).
    ///
    /// The default is a no-op for backends and test fakes that do not track
    /// apply progress.
    async fn mark_apply_progress(
        &self,
        _id: AiImportJobId,
        _run_id: ApplyRunId,
        _progress: Option<&ApplyProgress>,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    /// Subscribe to wake-up notifications for one job (issue #664).
    ///
    /// Storage-agnostic push seam for the SSE endpoint: every adapter that
    /// changes a job's state or progress is expected to wake the stream — in
    /// PostgreSQL mode via `pg_notify` bridged into the in-process hub, in
    /// in-process modes (test fakes, future SQLite) by direct publication.
    /// The stream yields the job id itself; receivers always re-read the
    /// authoritative row via [`AiImportQueue::get`], so duplicate or lagged
    /// notifications are harmless.
    ///
    /// The default is an empty stream for backends without push distribution
    /// (existing in-memory fakes keep compiling and simply never wake — the
    /// SSE snapshot is still delivered).
    fn subscribe(&self, _id: AiImportJobId) -> Pin<Box<dyn Stream<Item = AiImportJobId> + Send>> {
        Box::pin(futures::stream::empty())
    }

    /// Insert a job that is ALREADY terminal (`succeeded`) and points at
    /// [preview_handle] — the storage seam for the `test-support`-only stored
    /// preview fixture (issue #748).
    ///
    /// Exists because the fixture must be *deterministic*: the ordinary
    /// lifecycle needs a worker claim (`enqueue` → `claim_next_kind` →
    /// `mark_succeeded`), and a claim is not addressable by id — it hands out
    /// the oldest runnable job, so a busy or worker-polled queue either wins the
    /// race or leaves the fixture's own `pending` row (and its blobs) behind.
    /// A row inserted straight into a terminal state can never be claimed and
    /// never occupies the runnable pool.
    ///
    /// Compile-time absent unless the `test-support` feature is enabled; the
    /// default refuses, so every existing adapter keeps compiling unchanged and
    /// an adapter that does not implement it fails loudly instead of writing a
    /// half-seeded job.
    #[cfg(feature = "test-support")]
    async fn seed_succeeded(
        &self,
        _request: AiImportEnqueueRequest,
        _preview_handle: &str,
    ) -> Result<(), DomainError> {
        Err(DomainError::ServiceUnavailable {
            code: &crate::error_registry::DOMAIN_SERVICE_UNAVAILABLE,
            reason: "seed_succeeded is not implemented by this AI import queue adapter".to_owned(),
        })
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

    /// List a job's recorded attempt history, newest first (issue #637).
    ///
    /// Backs the `attempts` field of `GET /ai-import/jobs/{id}` so the reason
    /// an earlier attempt failed stays retrievable after `last_error` was
    /// overwritten. `limit` is clamped by the adapter.
    ///
    /// The default returns no history for backends that do not persist
    /// attempts (in-memory and test queues).
    async fn list_attempts(
        &self,
        _id: AiImportJobId,
        _limit: i64,
    ) -> Result<Vec<AiImportAttempt>, DomainError> {
        Ok(Vec::new())
    }

    /// Delete a **terminal** job row (issue #671).
    ///
    /// Backs `DELETE /v1/ai-import/jobs/{id}`. Only terminal jobs
    /// (`succeeded`, `dead_letter`, `payload_unavailable` — the exact set of
    /// [`JobStatus::is_terminal`](super::views::JobStatus::is_terminal)) may
    /// be deleted: `pending`/`running`/`failed` rows are leased, queued or
    /// backed off, and removing one would corrupt the claim/permit machinery.
    /// The API handler refuses those with the registered
    /// `ai-import.job-not-deletable` 409 before this method is reached; the
    /// status predicate in the adapter's statement is the authoritative
    /// backstop, not the only defense.
    ///
    /// Returns `true` when a row was deleted, `false` when no terminal row
    /// existed for `id` (never existed, already gone, or non-terminal — the
    /// caller maps `false` to the established `ai-import.not-found` 404).
    /// Attempt-history and payload-cleanup rows go via their
    /// `ON DELETE CASCADE` foreign keys; the adapter MUST also remove the
    /// apply-idempotency mapping rows, which have no FK to the job row.
    ///
    /// The default reports "not deleted" for backends without row deletion
    /// (in-memory and test queues); production adapters MUST override it.
    async fn delete_terminal(&self, _id: AiImportJobId) -> Result<bool, DomainError> {
        Ok(false)
    }

    /// Attach the write target of a block-less job — **set-once** (issue #829).
    ///
    /// Backs `PUT /v1/ai-import/jobs/{id}/target`. The block id and the number
    /// the visible snapshot renders are written by ONE statement, so the guard
    /// value and the displayed target cannot drift; `target_season_id` stays
    /// what the upload resolved (the handler refuses a block of another season
    /// before this is reached).
    ///
    /// Set-once is enforced in the statement, not by a read-then-write in the
    /// handler: `WHERE block_id IS NULL AND accept_as_is IS NULL`. `accept_as_is`
    /// is the persisted "an apply landed" fact (`AiImportJob::applied` is derived
    /// from it), so a job whose rows already went into a block cannot be moved
    /// afterwards. A repeated attach of the SAME block is reported as
    /// [`TargetAttachOutcome::Unchanged`] and writes nothing.
    ///
    /// The default refuses loudly instead of returning a benign value: an
    /// adapter that cannot attach must not look like a successful no-op, because
    /// the caller would then render a target the job does not carry.
    async fn set_target_once(
        &self,
        _id: AiImportJobId,
        _block_id: BlockId,
        _block_number: i32,
    ) -> Result<TargetAttachOutcome, DomainError> {
        Err(DomainError::ServiceUnavailable {
            code: &crate::error_registry::DOMAIN_SERVICE_UNAVAILABLE,
            reason: "this AI import queue adapter cannot attach a target block".to_owned(),
        })
    }
}

/// What [`AiImportQueue::set_target_once`] did (issue #829).
///
/// Distinguishing these four is the whole contract: `Unchanged` is a successful
/// idempotent repeat, while `AlreadySet` and `AlreadyApplied` are refusals with
/// different user-facing narratives (the target is taken / the rows are already
/// written). Collapsing them would force the handler to re-read and re-diagnose
/// state the adapter already observed atomically.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TargetAttachOutcome {
    /// The target was attached by this call.
    Attached,
    /// The job already carried exactly this block — nothing was written.
    Unchanged,
    /// A different block is already attached; the job is unchanged.
    AlreadySet {
        /// The block that won, so the client can render it.
        existing_block_id: BlockId,
    },
    /// An apply already recorded rows for this job; its target is frozen.
    AlreadyApplied,
    /// No such job (or it vanished between the read and the write).
    NotFound,
    /// The job carries no target **season**, so it cannot receive a block.
    ///
    /// The season is what the attach is authorized against and what the write
    /// keeps alongside the block number: storing one without the other would
    /// leave a row whose target no longer decodes. No path produces that state
    /// today (every upload resolves a season); the outcome exists so the
    /// adapter's refusal is truthful instead of borrowing another outcome's
    /// name.
    NoTargetSeason,
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
    /// One fundus `Piece` an AI apply created for a draft row. Addressed by the
    /// row's `draft_ref` plus the row-flat piece position (two figures may wear
    /// the same garment, so a per-outfit ordinal would collide).
    pub const PIECE: &str = "piece";
    /// One `Outfit` an AI apply created for a draft row. Addressed by the row's
    /// `draft_ref` plus the outfit's position in the row's outfit list.
    pub const OUTFIT: &str = "outfit";
    pub const SHOOTING_DAY: &str = "shooting_day";
    pub const SCENE_SHOOT: &str = "scene_shoot";
    /// One outfit beat the AI apply added to a draft row's scene (issue
    /// #546 §5.8). Addressed by the figure's preview-wide mapping reference
    /// (the same `draft_ref` the `character` rows use) plus the outfit's
    /// PER-FIGURE position — two figures of one row would otherwise share
    /// one row and the second figure's first beat would silently never be
    /// applied. `aggregate_id` is the scene the beat was added to.
    pub const SCENE_OUTFIT_BEAT: &str = "scene_outfit_beat";
    /// One `Outfit` an AI apply created for a reviewer's continuity selection
    /// (OpenSpec `ai-import-decision-outfit-continuity`). Separate from
    /// [`OUTFIT`] on purpose: a selection is request-carried, so its address
    /// cannot be a preview index — it is the row's `draft_ref` plus the figure's
    /// position in the draft's own character list, and its own kind keeps it from
    /// ever colliding with an extracted row's ordinal.
    pub const OUTFIT_CONTINUITY: &str = "outfit_continuity";
    /// One outfit beat for a reviewer-selected gap row. Same reasoning as
    /// [`OUTFIT_CONTINUITY`]: own kind, addressed by the row's `draft_ref` plus
    /// the figure's draft position.
    pub const SCENE_OUTFIT_BEAT_CONTINUITY: &str = "scene_outfit_beat_continuity";
    /// One episode an AI script apply created for a draft episode group
    /// (issue #581). Keyed by the group ref (`ep:<n>` / `ep-t:<title>`,
    /// [`breakdown_core::ai::DraftEpisode::group_key`]) with
    /// [`PRIMARY_ORDINAL`]; `aggregate_id` is the created Episode.
    pub const EPISODE: &str = "episode";
}

/// Ordinal of a mapping kind that has exactly one row per `draft_ref` — scenes,
/// figures and schedule rows. Only `piece` and `outfit` number their rows,
/// because one scene can carry several outfits per figure and several pieces per
/// outfit.
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

/// One breaker row as the worker needs to read it (issue #871).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProviderBreakerSnapshot {
    pub state: ProviderBreakerState,
    pub consecutive_failures: u32,
    pub flap_count: u32,
    /// The next probe time; `None` while `closed`.
    pub retry_at: Option<chrono::DateTime<chrono::Utc>>,
}

impl ProviderBreakerSnapshot {
    /// A pair nobody has observed a failure for yet.
    #[must_use]
    pub const fn closed() -> Self {
        Self {
            state: ProviderBreakerState::Closed,
            consecutive_failures: 0,
            flap_count: 0,
            retry_at: None,
        }
    }

    /// Whether a job of this pair may be claimed. Only `closed` admits a claim:
    /// `retry_at` is the probe schedule, never a claim gate (D-A2).
    #[must_use]
    pub const fn admits_claim(&self) -> bool {
        matches!(self.state, ProviderBreakerState::Closed)
    }
}

/// A breaker row that is **not** closed, as the sweeper/probe task selects it
/// (issue #871, D-A3/D-C4).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenBreaker {
    pub provider: LlmProvider,
    pub model: String,
    pub state: ProviderBreakerState,
    pub retry_at: Option<chrono::DateTime<chrono::Utc>>,
}

/// The fence of one probe attempt (issue #871, D-A6).
///
/// `probe_owner` alone is **not** the fence: the same worker (or task instance)
/// can reacquire the lease, and its earlier result would then still match. The
/// fence is `lease_id`, a fresh UUIDv7 written by the `open → half_open` CAS and
/// matched by the result write.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProbeLease {
    pub provider: LlmProvider,
    pub model: String,
    pub owner: String,
    pub lease_id: Uuid,
}

/// What a probe observed about the **endpoint** (issue #871, D-A3).
///
/// Reachability only: a probe result is a verdict about the endpoint, never
/// about a document, so it never retires or terminalizes a job.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProbeOutcome {
    /// The endpoint answered (2xx, or a 401/403 credential rejection — the
    /// endpoint demonstrably answered, which is what the probe measures).
    Reachable,
    /// Transport error, timeout, 429 or 5xx: the outage this breaker exists for.
    Unreachable,
}

/// Durable provider-health state, one row per `(provider, model)` pair
/// (issue #871, D-A2).
///
/// The worker loop and the probe/sweeper tasks talk to this port instead of to
/// SQL, so the breaker is unit-testable against a fake and the queue stays
/// unaware of it — the claim predicate is the only place the two meet, and it
/// meets in SQL.
#[async_trait]
pub trait ProviderHealth: Send + Sync {
    /// The current verdict. A pair with no row is `closed` — never seen a
    /// failure, so nothing to hold for.
    async fn state(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<ProviderBreakerSnapshot, DomainError>;

    /// Count one **retryable** provider failure (D-A1) and open the breaker at
    /// `threshold` consecutive failures.
    ///
    /// Only retryable failures may call this: a revoked key or an entitlement
    /// 4xx is permanent (#637) and would convert one user's misconfiguration
    /// into an outage for everyone on the endpoint.
    ///
    /// When the returned decision has `opened`, the caller materializes the
    /// holds through [`AiImportQueue::hold_runnable_jobs`].
    async fn record_failure(
        &self,
        provider: LlmProvider,
        model: &str,
        threshold: u32,
    ) -> Result<BreakerDecision, DomainError>;

    /// Record that the endpoint answered a **paid call**: reset the failure
    /// count and close. When the returned decision has `closed`, the caller
    /// releases the pair's held jobs through the queue.
    async fn record_success(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<BreakerDecision, DomainError>;

    /// CAS `open → half_open` with a fresh lease, so exactly one prober runs per
    /// window. `None` when another task already holds the lease or the breaker
    /// is not open.
    async fn try_begin_probe(
        &self,
        provider: LlmProvider,
        model: &str,
        owner: &str,
    ) -> Result<Option<ProbeLease>, DomainError>;

    /// Write a probe result, **fenced to its lease**. `false` when the lease is
    /// stale (another task owns the state now) — the result is then discarded,
    /// which is the same `ensure_claim_owned` discipline every other
    /// owner-fenced write uses.
    async fn finish_probe(
        &self,
        lease: &ProbeLease,
        outcome: ProbeOutcome,
    ) -> Result<BreakerDecision, DomainError>;

    /// Every breaker that is not `closed`, for the probe task and the sweeper
    /// (bounded by the caller).
    async fn open_breakers(&self, limit: i64) -> Result<Vec<OpenBreaker>, DomainError>;
}

/// One chunk result as the store keeps it (issue #871, D-B1/D-B3).
///
/// The stored unit is the **parsed chunk result** — exactly what one paid call
/// returned — not the applied scene rows. That is what makes the resume unit
/// equal the paid call, which is the only unit that matters for cost.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StoredChunk {
    /// 0-based chunk index.
    pub chunk_index: u32,
    /// The per-chunk extraction result.
    pub payload: ScriptContext,
    /// The usage that chunk's call(s) actually consumed.
    pub usage: LlmCallUsage,
}

/// Durable per-chunk extraction results (issue #871, workstream B).
///
/// A retried attempt continues at the first chunk that never completed instead
/// of re-extracting from chunk 0: the issue's evidence is a 42-chunk document
/// that died at chunk 25 three times, i.e. the same ~25 chunks paid for three
/// times.
///
/// The port exists so `workers.rs` stays testable against a fake and the write
/// path never queries a read model.
#[async_trait]
pub trait AiImportChunkStore: Send + Sync {
    /// Every stored chunk of one job, in `chunk_index` order.
    ///
    /// Implementations MUST delete a tail that lies beyond a hole (an index that
    /// is missing while a later one exists) and log it: such a row is
    /// unreachable by construction — the merge pass is a prefix walk — so it can
    /// only ever be garbage.
    async fn load(&self, job_id: AiImportJobId) -> Result<Vec<StoredChunk>, DomainError>;

    /// Open an attempt's chunk set: compare-and-set the extraction fingerprint
    /// and drop the stored chunks when it changed (issue #871, D-B7).
    ///
    /// Implementations MUST run this in the same transaction and the same lock
    /// order as [`put`](Self::put) — job row first, chunk rows second — so an
    /// invalidation can never interleave with a chunk write from a worker that is
    /// about to lose its claim.
    ///
    /// The default reports `Compatible` for backends without a store.
    async fn begin_extraction(
        &self,
        _job_id: AiImportJobId,
        _worker_id: &str,
        _fingerprint: &ExtractionFingerprint,
        _key: &str,
    ) -> Result<ChunkSetState, DomainError> {
        Ok(ChunkSetState::Compatible)
    }

    /// Store one completed chunk, **claim-fenced**.
    ///
    /// The fence is a row lock on the job (`SELECT … FOR UPDATE`), not a
    /// predicate: under READ COMMITTED a bare `INSERT … SELECT … WHERE
    /// status = 'running'` can read the old owner and still commit after another
    /// worker reclaimed the job and invalidated the set (D-B3). Refused writes
    /// return [`DomainError::Conflict`], the same discipline as
    /// `mark_progress`/`mark_failed`.
    ///
    /// `ON CONFLICT (job_id, chunk_index) DO UPDATE` makes a chunk re-run after a
    /// lost write repair itself by overwriting, so resume stays idempotent
    /// without any per-row reservation machinery.
    async fn put(
        &self,
        job_id: AiImportJobId,
        worker_id: &str,
        extraction_key: &str,
        chunk: &StoredChunk,
    ) -> Result<(), DomainError>;

    /// Delete every stored chunk of one job (terminal transitions, GC, and the
    /// invalidation path).
    async fn clear(&self, job_id: AiImportJobId) -> Result<u64, DomainError>;
}

/// The resume cursor: the length of the **contiguous** stored prefix
/// (issue #871, D-B2).
///
/// Deliberately not `MAX(chunk_index) + 1`: over indices `0, 1, 3` that would
/// answer `4` and quietly omit chunk 2 from the preview. Deliberately not a
/// stored column either — a stored cursor can disagree with the rows after a
/// lost write, a derived one cannot.
///
/// `chunks` must be ordered by `chunk_index` (what
/// [`AiImportChunkStore::load`] returns).
#[must_use]
pub fn resume_cursor(chunks: &[StoredChunk]) -> u32 {
    let mut expected = 0u32;
    for chunk in chunks {
        if chunk.chunk_index != expected {
            break;
        }
        expected = expected.saturating_add(1);
    }
    expected
}

#[cfg(test)]
#[path = "chunk_resume_tests.rs"]
mod chunk_resume_tests;

/// The inputs of the extraction fingerprint (issue #871, D-B7).
///
/// Only what the **system** controls can invalidate a stored chunk set: the
/// document, the provider, the model, the effective prompt and the chunker. A
/// provider-side default change is deliberately out of reach — the preview's own
/// provenance stamp (`provider`/`model`, #675) covers that.
///
/// The components are kept next to the hash they produce, so an invalidation can
/// **name** what changed. A bare hash can only say *that* something did, and the
/// operator needs to know whether the restart was necessary.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExtractionFingerprint {
    /// The source document's digest — a different document is a different job,
    /// but a re-upload of the same bytes is the `dedup_key` path and shares it.
    pub document_digest: String,
    pub provider: LlmProvider,
    pub model: String,
    /// `sha256` of the prompt text actually sent: the user's **stored** prompt
    /// when one is configured, else the deployment default. Hashed rather than
    /// versioned because there is no prompt version anywhere in the system — the
    /// stored prompt is free text the user can edit.
    pub prompt_hash: String,
    /// Bumped by hand when the chunker changes what a chunk *is*. Without it a
    /// chunker change would silently resume with boundaries the new chunker
    /// never produced.
    pub chunker_version: u32,
}

impl ExtractionFingerprint {
    /// The components that differ from `previous`, in a stable order.
    ///
    /// Drives the `#871 chunk resume invalidated: <components>` log line. Empty
    /// means the sets are compatible and the resume may proceed.
    #[must_use]
    pub fn changed_components(&self, previous: &Self) -> Vec<&'static str> {
        let mut changed = Vec::new();
        if self.document_digest != previous.document_digest {
            changed.push("document_digest");
        }
        if self.provider != previous.provider {
            changed.push("provider");
        }
        if self.model != previous.model {
            changed.push("model");
        }
        if self.prompt_hash != previous.prompt_hash {
            changed.push("prompt");
        }
        if self.chunker_version != previous.chunker_version {
            changed.push("chunker_version");
        }
        changed
    }
}

/// What [`AiImportChunkStore::begin_extraction`] decided (issue #871, D-B7).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChunkSetState {
    /// The stored set was produced by the same configuration (or there was
    /// none): the attempt may resume from its contiguous prefix.
    Compatible,
    /// The set belonged to a different configuration and was deleted; the
    /// attempt starts at chunk 0. Carries the components that changed, so the
    /// caller can log `#871 chunk resume invalidated: <components>`.
    Invalidated(Vec<&'static str>),
}
