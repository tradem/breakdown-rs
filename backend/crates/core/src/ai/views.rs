// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, BlockId, SeasonId, UserId};

use super::ports::LlmProvider;
use super::preview::DraftEpisode;

/// The two document kinds supported by the import pipeline.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum DocumentKind {
    Script,
    Schedule,
}

impl DocumentKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Script => "script",
            Self::Schedule => "schedule",
        }
    }
}

/// The declared format of an AI import source document, captured at the API
/// edge from the upload's `Content-Type` and persisted on the job so the
/// schedule worker can pick the extraction path without re-guessing the bytes
/// (issue #221).
///
/// Only `Csv` is parsed natively; `Pdf` and `PlainText` are routed through the
/// LLM extraction path. Scripts are always `Pdf`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum SourceFormat {
    Csv,
    Pdf,
    PlainText,
}

impl SourceFormat {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Csv => "csv",
            Self::Pdf => "pdf",
            Self::PlainText => "plain_text",
        }
    }

    /// Whether the schedule worker should use the native CSV parser. Only CSV
    /// is parsed in-process; PDF and plain text go through the LLM.
    pub const fn uses_native_csv(self) -> bool {
        matches!(self, Self::Csv)
    }
}

/// The user's preferred primary cost display metric (issue #675).
///
/// Both token and energy costs are always persisted on completed jobs, so
/// switching the preference re-renders historical job costs without
/// recalculation. `Token` is the default for every pre-existing `AiConfig`
/// (replayed events and deserialized views without the field).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum CostDisplayPreference {
    /// Primary cost figure is the token-based cost.
    #[default]
    Token,
    /// Primary cost figure is the (capped) hardware-energy cost where the
    /// provider offers it (e.g. Neuralwatt); falls back to token cost.
    Energy,
}

impl CostDisplayPreference {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Token => "token",
            Self::Energy => "energy",
        }
    }
}

/// Operational lifecycle of an AI import job.
///
/// `Failed` is the *retryable* state (a due `next_attempt_at` makes the job
/// claimable again); `DeadLetter` and `PayloadUnavailable` are terminal.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum JobStatus {
    Pending,
    Running,
    Succeeded,
    Failed,
    DeadLetter,
    /// The job's durable payload (source document or preview blob) is gone,
    /// so the work can never be redone from what is stored (issue #181).
    ///
    /// This is deliberately distinct from `DeadLetter`: a dead-lettered job
    /// exhausted its retries against a real failure, while this one has no
    /// input left to retry *with*. Retrying it could only re-discover the
    /// same absence, so a worker moves the job here immediately, bypassing
    /// the remaining retry budget, and the claim predicates never pick it up
    /// again.
    ///
    /// Only an *absent* payload leads here. Storage that is merely
    /// unreachable (`DomainError::ServiceUnavailable`) is transient and stays
    /// on the ordinary retryable path.
    PayloadUnavailable,
}

impl JobStatus {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Running => "running",
            Self::Succeeded => "succeeded",
            Self::Failed => "failed",
            Self::DeadLetter => "dead_letter",
            Self::PayloadUnavailable => "payload_unavailable",
        }
    }

    /// Whether the job will never be claimed again.
    ///
    /// `Failed` is **not** terminal: it is the backoff state of a job that is
    /// still within its retry budget. Payload retention keys off this
    /// predicate, so misclassifying `Failed` would delete the source document
    /// of a job that is still scheduled to run (issue #181).
    pub const fn is_terminal(self) -> bool {
        matches!(
            self,
            Self::Succeeded | Self::DeadLetter | Self::PayloadUnavailable
        )
    }

    /// Whether the job is terminal *because its input is gone*, and therefore
    /// cannot be resumed even by an operator-triggered retry.
    pub const fn is_non_resumable(self) -> bool {
        matches!(self, Self::PayloadUnavailable)
    }
}

/// State of a provider circuit breaker, as a **job hold** reports it
/// (issue #871, D-A4/D-A6).
///
/// `Expired` is deliberately part of this enum but **not** of the durable
/// breaker's own state: the `ai_import.provider_health.state` CHECK accepts
/// `closed`, `open` and `half_open` only. A hold that ran out of its deadline
/// keeps `state = expired` on the job row precisely so a client can tell "the
/// provider never came back" from "your retries are used up" — the two render
/// different copy and must never collapse into one.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ProviderBreakerState {
    /// The endpoint is answering; jobs of the pair are claimable.
    Closed,
    /// The endpoint failed `breaker_failure_threshold` times in a row; no job
    /// of the pair is claimed while the breaker is open.
    Open,
    /// A probe (or a paid call) is in flight for the pair; still no claims,
    /// because only the probe may end a non-`closed` state.
    HalfOpen,
    /// **Job-hold state only** (never a breaker state): the hold ran out of
    /// [`ProviderHold::hold_deadline`] and the job dead-lettered without
    /// spending a retry.
    Expired,
}

impl ProviderBreakerState {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Closed => "closed",
            Self::Open => "open",
            Self::HalfOpen => "half_open",
            Self::Expired => "expired",
        }
    }
}

/// Why a job is **waiting** on its provider, and until when (issue #871).
///
/// A held job stays [`JobStatus::Failed`] on purpose: adding a
/// `waiting_for_provider` status would have to be classified correctly in
/// `is_terminal()`, `is_non_resumable()`, the payload retention, `dev_reset`
/// and the claim predicates — plus a new ARB key, glyph and golden in the
/// client — to say what this additive field says for free. `#822`'s banner
/// already renders "provider degraded · next attempt at X"; this is the honest
/// extension of that copy.
///
/// The field is cleared by **every** other lifecycle write (claim,
/// `mark_succeeded`, `mark_failed`, `mark_payload_unavailable`, ordinary
/// dead-letter) — with exactly one exception: the hold-expiry write keeps it
/// with `state = Expired`, because that marker is the only durable signal
/// separating an expiry from a spent retry budget.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ProviderHold {
    /// The provider whose endpoint is degraded.
    pub provider: LlmProvider,
    /// The model the job was resolved against. Together with `provider` this is
    /// the breaker key (D-A1).
    pub model: String,
    /// The registered problem code that opened the hold — today always
    /// `ai-import.llm-provider-unavailable` (no new code, D-X1). The client
    /// keeps rendering its existing per-code narrative.
    pub reason_code: String,
    /// `open`/`half_open` while waiting; `expired` on the terminal expiry write.
    pub state: ProviderBreakerState,
    /// The breaker's next probe time — also this job's `next_attempt_at`.
    pub until: DateTime<Utc>,
    /// Absolute deadline of the whole hold **series** (D-C4): the job
    /// dead-letters at this instant without spending a retry. Lives on the job
    /// row (`provider_hold_series_started_at`) rather than in this struct, so a
    /// short recovery cannot restart the budget.
    pub hold_deadline: DateTime<Utc>,
    /// Chunks already paid for and stored — the resume point (D-B2). `0` in a
    /// build without the chunk store, which is honest: nothing was stored.
    pub chunks_done: u32,
}

/// Opaque identifier for an operational AI import job.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(transparent)]
pub struct AiImportJobId(pub Uuid);

impl AiImportJobId {
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }

    pub const fn from_uuid(id: Uuid) -> Self {
        Self(id)
    }

    pub const fn as_uuid(self) -> Uuid {
        self.0
    }
}

/// Identity of one **apply run** (issue #800).
///
/// The apply-run progress slot was keyed by job id alone, so two accepted
/// applies of one `succeeded` job could overwrite each other's counters, and
/// the first run to finish cleared the slot out from under the other one. The
/// run therefore names itself: the owning id travels on the wire inside
/// [`ApplyProgress`], and every run-scoped write (progress, clear, heartbeat)
/// is conditional on the run that owns the slot.
///
/// A pre-#800 payload decodes to the nil id (`serde(default)`), which never
/// owns a claim — an old payload can be *read* (and rendered) but never
/// *cleared* by a client-side or worker write.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(transparent)]
pub struct ApplyRunId(pub Uuid);

impl ApplyRunId {
    #[must_use]
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }

    #[must_use]
    pub const fn from_uuid(id: Uuid) -> Self {
        Self(id)
    }

    #[must_use]
    pub const fn as_uuid(self) -> Uuid {
        self.0
    }
}

impl Default for ApplyRunId {
    fn default() -> Self {
        Self(Uuid::nil())
    }
}

impl Default for AiImportJobId {
    fn default() -> Self {
        Self::new()
    }
}

/// The extraction stage an AI import job is currently in (issue #664).
///
/// Surfaces *where* in the pipeline a running job is, so the client can show
/// something more informative than an indeterminate spinner. Never per-LLM-
/// token — it only advances at stage boundaries and completed chunks.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum AiImportStage {
    /// Extracting text from the PDF and scanning the deterministic
    /// scene/episode markers.
    #[default]
    ExtractingText,
    /// Running per-chunk LLM or CSV extraction.
    Extracting,
    /// Running the deterministic schedule-to-scene merge.
    Merging,
    /// Writing the extracted preview payload to durable object storage.
    StoringPreview,
}

impl AiImportStage {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::ExtractingText => "extracting_text",
            Self::Extracting => "extracting",
            Self::Merging => "merging",
            Self::StoringPreview => "storing_preview",
        }
    }
}

/// Live progress of a running AI import job (issue #664).
///
/// Additive and optional on [`AiImportJob`]: `None` for jobs that have not
/// reached a `mark_progress` call yet (fresh `pending` claims, retried
/// attempts before their first stage boundary — the claim SQL resets it).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct AiImportProgress {
    pub stage: AiImportStage,
    /// Chunk counter of the extraction progress. `0` is a deliberate
    /// published state — "chunking finished, the first chunk has not yet
    /// completed" (the frame emitted right after the deterministic scan) —
    /// so the schema floor is 0, not 1. For every later frame this is the
    /// 1-based index of the last **completed** chunk (`1..=chunks_total`).
    #[serde(default)]
    pub chunk: Option<u32>,
    /// Total chunks in the document (known once chunking finishes).
    #[serde(default)]
    pub chunks_total: Option<u32>,
    /// Human-readable episode labels discovered so far, in first-seen order,
    /// deduplicated (e.g. `["Ep. 3", "Ep. 4"]`). Built at zero extra LLM
    /// token cost from the deterministic `Ep.:` marker scan and per-chunk
    /// extracted `DraftEpisode` metadata — never script prose.
    #[serde(default)]
    pub episodes_seen: Vec<String>,
    /// The production block number the script's page headers state, or the
    /// model's answer when the deterministic `Block:` scan found no marker
    /// (issue #827). `None` means "the script does not state one" — never a
    /// fabricated number, and never the job's import TARGET
    /// ([`AiImportTarget::block_number`]), which is a separate fact: only
    /// because the two travel side by side can a client show "script says 2 ·
    /// importing into 1" and flag a mismatch before the apply's cross-block
    /// guard fires.
    ///
    /// Additive with `serde(default)`: frames written before the field
    /// existed deserialize as `None`, and a client then renders the import
    /// target as the associated block instead of an empty field.
    #[serde(default)]
    pub block_number: Option<i32>,
    /// When the **current attempt** was claimed (issue #762).
    ///
    /// The time anchor the counters above lack: without it a client can only
    /// run a stopwatch while its own screen stays open, and a reconnecting or
    /// restarted client can never reconstruct a rate from `chunk`/`chunks_total`
    /// alone. Every frame of one attempt carries the same value, so a client
    /// can recompute the estimate on every frame without accumulating state.
    ///
    /// Additive with `serde(default)`: frames written before the field existed
    /// deserialize as `None`, and a client then simply shows no estimate —
    /// never a fabricated one. A retry starts cleanly because the claim clears
    /// [`Self::chunk`]/[`Self::done_bytes`] and writes a fresh anchor.
    #[serde(default)]
    pub started_at: Option<DateTime<Utc>>,
    /// Source-text bytes already extracted (issue #762), summed over the
    /// **completed** chunks. `0` is a deliberate published state, mirroring
    /// [`Self::chunk`].
    ///
    /// Chunk cost is heterogeneous by an order of magnitude — one chunk is
    /// one scene and scene lengths differ wildly — so a byte denominator is a
    /// materially better ETA basis than a chunk count. Additive with
    /// `serde(default)`: `None` when the worker has no byte budget for the
    /// job (a schedule job is a single extraction unit).
    #[serde(default)]
    pub done_bytes: Option<u64>,
    /// Total source-text bytes the document splits into (issue #762), known
    /// once the deterministic chunk scan finishes. Same `serde(default)`
    /// contract as [`Self::done_bytes`]; a client prefers the byte pair when
    /// `total_bytes > 0` and falls back to the chunk counters otherwise.
    #[serde(default)]
    pub total_bytes: Option<u64>,
    /// How many chunks this attempt **resumed from** (issue #871, D-B5).
    ///
    /// `Some(n)` means "`n` chunks are already stored and paid for; this attempt
    /// continues at chunk `n + 1`". It is the honest counterpart of
    /// [`Self::chunk`], which keeps its documented meaning ("1-based index of
    /// the last completed chunk **of this attempt**") — so a resumed attempt's
    /// first frame reports `chunk = resumed_from`, and the bar does not snap
    /// back to zero.
    ///
    /// It exists because the counters alone are ambiguous: with `chunk = 25`
    /// and `resumed_from = 25`, a client that derived a rate from `chunk` alone
    /// would report "25 chunks in one second" and then declare a healthy
    /// successor chunk stalled. The client therefore computes the rate from
    /// `chunk - resumed_from` and the remaining count from `chunks_total - chunk`.
    ///
    /// Additive with `serde(default)`: pre-#871 frames read as `None`, and a
    /// client then estimates exactly as it did before — nothing is fabricated.
    #[serde(default)]
    pub resumed_from: Option<u32>,
    /// When **this frame** was written, on the server's clock (issue #762).
    ///
    /// The end of the measured interval: `written_at - started_at` is extraction
    /// time, whereas a client-side "now" also counts every second the screen
    /// was closed, backgrounded or offline — which inflates the per-unit cost
    /// and with it the estimate. A heartbeat-driven `updated_at` is no
    /// substitute (a live worker refreshes it continuously), so the stamp
    /// travels with the frame it describes.
    ///
    /// Additive with `serde(default)`: a frame written before the field existed
    /// deserializes as `None`, and a client then falls back to its own clock as
    /// it did before.
    #[serde(default)]
    pub written_at: Option<DateTime<Utc>>,
}

impl AiImportProgress {
    /// Record one episode label in first-seen order, deduplicating (issue
    /// #664). `None` episodes (chunk without a marker and without extracted
    /// episode metadata) are ignored. Pure, so the workers can accumulate
    /// across chunks/scenes and tests can assert on it.
    pub fn record_episode(&mut self, episode: Option<&DraftEpisode>) {
        let Some(label) = episode.and_then(DraftEpisode::display_label) else {
            return;
        };
        if !self.episodes_seen.contains(&label) {
            self.episodes_seen.push(label);
        }
    }

    /// Publish the byte budget of the document (issue #762), known once the
    /// deterministic chunk scan finished. Also zeroes the completed-byte
    /// counter, so the pair is never published half-set.
    pub fn set_byte_budget(&mut self, total_bytes: u64) {
        self.total_bytes = Some(total_bytes);
        self.done_bytes = Some(0);
    }

    /// Add one completed chunk's source bytes (issue #762).
    ///
    /// Saturating and clamped to [`Self::total_bytes`], so the published
    /// numerator can never overtake the denominator — a client dividing the
    /// two must never see a progress value above 1. A no-op when the job has
    /// no byte budget, which is the honest state for a single-unit job.
    pub fn record_done_bytes(&mut self, bytes: u64) {
        let Some(total) = self.total_bytes else {
            return;
        };
        let done = self.done_bytes.unwrap_or(0).saturating_add(bytes);
        self.done_bytes = Some(done.min(total));
    }
}

/// Public AI configuration view. It contains only the opaque vault reference,
/// never a key or other secret material.
///
/// The [prompts] map carries the *stored prompt texts* (the same map the
/// create/update commands accept) so the client's configured/edit form can
/// render what is persisted instead of starting from empty fields (issue
/// #490) — saving an untouched edit must not clear them.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct AiConfigView {
    pub id: Uuid,
    pub user_id: UserId,
    pub provider: LlmProvider,
    pub assistant_model: String,
    pub image_model: Option<String>,
    /// Stored prompt texts by document kind (`script`/`schedule`). Mirrors
    /// the create/update request `prompts` payload so an edit can round-trip
    /// the persisted texts. Prompts are user-authored extraction seeds, not
    /// secrets — the vault reference is the only opaque material.
    pub prompts: HashMap<DocumentKind, String>,
    pub prompt_kinds: Vec<DocumentKind>,
    /// Kinds whose extraction is driven by a **stored** prompt (design D6).
    ///
    /// A stored prompt is a snapshot taken when the configuration was written:
    /// it wins over the deployment default and therefore does **not** follow
    /// updates to `config/default_ai_prompts.toml`. That was observed live — a
    /// configuration kept the previous three-line prompt and silently ignored a
    /// hardened default, invalidating a whole test round. The surface must say
    /// so, and offer a reset (write the current text from
    /// `GET /v1/ai-import/defaults`). A kind absent here has no stored prompt
    /// and follows the deployment default on every run.
    ///
    /// Additive with `serde(default)` so an older client reading a newer view
    /// still deserialises.
    #[serde(default)]
    pub stored_prompt_kinds: Vec<DocumentKind>,
    pub vault_key_id: String,
    /// Preferred primary cost display metric (issue #675). Additive with
    /// `serde(default)`: views serialized before the field existed
    /// deserialize as `Token`.
    #[serde(default)]
    pub cost_display_preference: CostDisplayPreference,
    /// Optional Decision Model configuration (issue #722). Additive with
    /// `serde(default)`: views serialized before the fields existed
    /// deserialize with no decision model configured.
    #[serde(default)]
    pub decision_provider: Option<LlmProvider>,
    #[serde(default)]
    pub decision_model: Option<String>,
    #[serde(default)]
    pub decision_vault_key_id: Option<String>,
    pub version: AggregateVersion,
    pub revoked: bool,
}

/// Operational job row. Preview blobs and errors are represented by opaque
/// handles/summaries; credentials and document bytes are deliberately absent.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct AiImportJob {
    pub id: AiImportJobId,
    pub user_id: UserId,
    pub document_kind: DocumentKind,
    pub source_format: SourceFormat,
    pub block_id: Option<BlockId>,
    pub dedup_key: String,
    pub document_digest: String,
    pub source_handle: String,
    /// The uploaded document's own file name, as the client picked it (issue
    /// #763). Additive with `serde(default)`: `None` for every job created
    /// before the field existed and for every upload that carried no name.
    ///
    /// The value is display metadata only — it is sanitized at the API edge
    /// (`sanitize_source_file_name`: basename, no control characters, bounded)
    /// and is deliberately **not** derived from [`Self::source_handle`], which
    /// is an opaque storage coordinate and never a name.
    #[serde(default)]
    pub source_file_name: Option<String>,
    /// The production target this job imports INTO, snapshotted at dispatch
    /// time (issue #771). `None` for every job created before the field
    /// existed (pre-#771 rows carry no target) and for any upload whose
    /// season/block read metadata could not be resolved at the API edge.
    ///
    /// The authoritative write target stays [`Self::block_id`] — the block
    /// named by the required `X-Active-Block` header, which the apply path
    /// pins itself to (the CWE-639 guard). This field exists so the visible
    /// target and the write target can be compared after the fact: the
    /// reported defect was an import that silently landed in the *previously*
    /// active season because nothing named where it would go.
    #[serde(default)]
    pub target: Option<AiImportTarget>,
    /// The provider this job is bound to, snapshotted at **enqueue** time
    /// (issue #871, D-A2b). `None` for every pre-#871 row and for an upload
    /// whose AI config could not be resolved at the API edge.
    ///
    /// The claim predicate filters on this pair, and the predicate runs
    /// *before* `resolve_config` — which is why the snapshot is refreshed at
    /// the config-change edge and re-checked (authoritatively) after the
    /// config is resolved. A `None` pair is never breaker-filtered: the honest
    /// degradation, because there is nothing to compare a breaker against.
    #[serde(default)]
    pub provider: Option<LlmProvider>,
    /// The model this job is bound to. See [`Self::provider`].
    #[serde(default)]
    pub model: Option<String>,
    pub status: JobStatus,
    pub preview_handle: Option<String>,
    pub last_error: Option<String>,
    pub retries: u32,
    pub max_retries: u32,
    /// When a retryable `failed` job becomes claimable again (issue #637).
    ///
    /// `None` for every other state: `pending`/`running` have no backoff, and
    /// a terminal job never retries. The column always existed; the wire view
    /// omitted it, so neither the UI nor operators could explain a stalled
    /// import ("why is this job not running yet?").
    #[serde(default)]
    pub next_attempt_at: Option<DateTime<Utc>>,
    /// Why this job is waiting on its provider, when it is (issue #871).
    ///
    /// `Some` while the job is **held** for a degraded `(provider, model)`
    /// pair: `retries` was deliberately not charged, no attempt row was
    /// appended, and `next_attempt_at` mirrors the breaker's probe time. A
    /// job that never reached the provider therefore never burns its retry
    /// budget.
    ///
    /// Cleared by every other lifecycle write, except the hold-expiry write —
    /// which keeps it with `state = expired` (see [`ProviderHold`]). Additive
    /// with `serde(default)`: older clients ignore the field entirely and keep
    /// rendering `#822`'s banner from `last_error`.
    #[serde(default)]
    pub provider_hold: Option<ProviderHold>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    /// Live extraction progress of a **running** job, when the worker already
    /// published it (issue #664). `None` for pending jobs, for freshly
    /// re-claimed retry attempts (the claim SQL resets stale progress) and —
    /// since issue #763 — for every terminal job: the queue clears the column
    /// in the same statement that lands `succeeded`/`dead_letter`/
    /// `payload_unavailable`, so a finished job never advertises the stage it
    /// died at (the last frame is always `storing_preview`).
    #[serde(default)]
    pub progress: Option<AiImportProgress>,
    /// Content-free operational telemetry recorded for this job (issue
    /// #675). `None` until a worker or the API apply path records telemetry;
    /// additive on the wire.
    #[serde(default)]
    pub telemetry: Option<JobTelemetrySummary>,
    /// Immutable per-import cost snapshot persisted at completion time
    /// (issue #675). Never recomputed when pricing changes later.
    #[serde(default)]
    pub cost: Option<CostBreakdown>,
    /// Per-attempt failure history, newest first (issue #637).
    ///
    /// `last_error` is overwritten by every `mark_failed`, so the reason an
    /// *earlier* attempt failed is lost. This list keeps each attempt's
    /// outcome retrievable. Populated on the single-job read
    /// (`GET /ai-import/jobs/{id}`) with the full history limit, and — since
    /// issue #822 — on the list read (`GET /ai-import/jobs`) with **the same**
    /// per-job bound, so a client derives an identical aggregate (repeated
    /// provider failures, keyed on `AiImportAttempt::code`) from either read
    /// without opening a job. A shorter list window would make the compact row
    /// undercount what the status card shows. Empty in claim contexts, and empty for a job no attempt
    /// was recorded for, so it stays additive on the wire.
    #[serde(default)]
    pub attempts: Vec<AiImportAttempt>,
    /// The episodes a successful **script** apply landed this job's rows in
    /// (issue #763), so the jobs list can name the import's target instead of
    /// only its date. Additive with `serde(default)`: empty for a job no apply
    /// has run for yet, and for a schedule apply (which merges onto the
    /// project's existing scenes and days and therefore has no single target
    /// episode).
    ///
    /// **Derived at the read edge from the durable apply mappings** (issue
    /// #864), never written by the apply path: every applied scene row owns a
    /// `projection_ai_import_mapping` row whose `aggregate_kind` is `scene`, and
    /// the scene's own `episode_id` says where it landed. An apply that commits
    /// rows therefore leaves the summary resolvable **even when the client
    /// disconnected mid-run** and no handler code ever ran to completion — the
    /// property the previous best-effort column could not offer, because a
    /// cancelled handler future simply never reached its post-apply write.
    ///
    /// Consequences of deriving instead of recording:
    ///
    /// * the `number`/`name` labels are the persisted episode's own, i.e.
    ///   authoritative rather than the request's target. A row reconciled onto
    ///   an existing scene is attributed to **that** scene's episode, not to the
    ///   episode the request named;
    /// * the list is ordered by episode number (id as the tiebreak), so two
    ///   reads of an unchanged job agree;
    /// * empty means "no **scene** row of this job is mapped to a projected
    ///   scene" — NOT "this job applied nothing". A schedule apply is the
    ///   standing example of the difference: it does commit work (shooting days,
    ///   scene-shoot links) while naming no episode, so its list is empty by
    ///   design. An empty list is also what a job no apply has run for answers,
    ///   and what an apply cancelled before its first scene commit leaves
    ///   behind.
    ///
    /// The derivation is display metadata: a failure to read it degrades to an
    /// empty list (the client renders its kind/date copy) and never makes the
    /// job unreachable — so an empty list can also mean "the derivation could
    /// not be read just now". A client therefore never treats empty as proof
    /// that no work happened, only as "no target to name".
    #[serde(default)]
    pub applied_episodes: Vec<AppliedEpisode>,
    /// What the optional Decision Model scoring pass actually did for this job
    /// (issue #767). Additive with `serde(default)`: `None` for every job
    /// recorded before the field existed, so an older client reading a newer
    /// view — and a newer client reading an older view — still deserializes.
    ///
    /// The reported defect was an import that produced no star ratings and no
    /// explanation: "no decision model configured", "the decision client could
    /// not be built", "the scoring call failed" and "the provider answered
    /// partially" all collapsed into the same empty space. The per-row rubric
    /// only explains the last two *after* a preview exists; this field is the
    /// job-level answer ("did the worker use my Decision Model at all?") that
    /// survives even when no row was ever scored.
    #[serde(default)]
    pub decision_telemetry: Option<DecisionTelemetry>,
    /// Live progress of an **apply run** for this (already `succeeded`) job
    /// (issue #762). Additive with `serde(default)`: `None` whenever no apply
    /// is in flight — for every job created before the field existed, for a
    /// preview nobody has applied yet, and again once a run has finished (the
    /// run clears the column, so a stale "applying 3/57" can never outlive its
    /// run).
    ///
    /// Advisory, so `None` alone is **not** proof that nothing is running:
    /// every progress write (the run's first one included) is best-effort — a
    /// failed write must never abort an apply — so an active run can be
    /// invisible here until the next throttled write lands, and for a whole run
    /// if the store keeps failing. A client therefore renders `None` as "no
    /// progress published", never as "idle" (issue #762).
    ///
    /// Its presence is what keeps the apply stream open: the job itself is
    /// terminal the whole time, because an apply is a POST against a job that
    /// already succeeded.
    #[serde(default)]
    pub apply_progress: Option<ApplyProgress>,
    /// Whether this preview has ever been **applied** (issue #800). Additive
    /// with `serde(default)`: `false` for a job no apply has run for yet, and
    /// for every job created before the field existed.
    ///
    /// Derived server-side from the persisted apply telemetry
    /// (`TelemetryApplyState::Applied`), never inferred from
    /// [`Self::applied_episodes`] — that summary is empty for a schedule apply
    /// by design, so it cannot answer "was this imported?". Its purpose is the
    /// honest "already imported" badge and the re-apply confirmation: a second
    /// apply stays *possible* (idempotent recovery of an interrupted run), but
    /// it must never look like a first one.
    #[serde(default)]
    pub applied: bool,
    /// Lifecycle state of this job's **apply slot** (issue #899). Additive with
    /// `serde(default)`: every pre-#899 row decodes as [`ApplyState::Idle`].
    ///
    /// This is the field a re-entering client decides from (design D5):
    /// `idle` offers an apply, `requested`/`running` means "attach to the live
    /// run" (the `POST` no longer does the work — it dispatches), and
    /// `done`/`failed` means the run is over and [`Self::apply_result`] holds
    /// what it committed. Without it, a screen that was away when the run
    /// finished had no way to learn the outcome except by re-applying.
    #[serde(default)]
    pub apply_state: ApplyState,
    /// The persisted outcome of the last apply run that **finished** (issue
    /// #899). Additive with `serde(default)`.
    ///
    /// `Some` exactly when [`Self::apply_state`] is terminal, so a client never
    /// has to distinguish "no result yet" from "a result of `idle`". A failed
    /// run carries its registered problem code here, not a prose detail — the
    /// client branches on `code` like it does for every other apply failure
    /// (ADR-031).
    #[serde(default)]
    pub apply_result: Option<ApplyRunOutcome>,
}

/// Which part of an apply run is executing (issue #762).
///
/// Coarse on purpose: the per-row counter is the progress signal, and these
/// stages only say whether rows are still being dispatched or the run is
/// closing out (the shooting-day and scene-shoot links).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ApplyStage {
    /// Rows are being dispatched (`SceneApplyPlan` order).
    #[default]
    Applying,
    /// Every row is done; the trailing work (day/scene-shoot links, telemetry)
    /// is running.
    Finalizing,
}

impl ApplyStage {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Applying => "applying",
            Self::Finalizing => "finalizing",
        }
    }
}

/// Live progress of one apply run (issue #762).
///
/// The apply used to be a pure spinner: `POST /ai-import/jobs/{id}/apply`
/// resolves the plan and awaits `ApplyWorker::apply_script` over every
/// mapping, so a 57-row preview and a 4-row preview looked identical for
/// however many minutes they took.
///
/// Written by the apply worker from the plan it already holds (never from a
/// projection read) and cleared when the run ends — including on failure — so
/// the client's stream closes on a definite event rather than on a timeout.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ApplyProgress {
    pub stage: ApplyStage,
    /// Work units completed by **this** run (rows dispatched).
    #[serde(default)]
    pub applied: u32,
    /// Work units the run planned (the plan's row count). `0` is an honest
    /// state — an empty plan still runs its trailing work — and never a
    /// divisor the client may trust blindly.
    #[serde(default)]
    pub total: u32,
    /// When this run started: the anchor an ETA needs (the same role
    /// [`AiImportProgress::started_at`] plays for extraction).
    pub started_at: DateTime<Utc>,
    /// Last write of this payload. The stream uses it to recognise a run whose
    /// process died: an abandoned run must not keep a stream open forever, so
    /// a payload older than [`ApplyProgress::STALE_AFTER`] is treated as
    /// finished. The worker **heartbeats** it while a single row is in flight
    /// (issue #800), so a slow row can no longer make a live run look dead —
    /// staleness now means "the process is gone".
    pub updated_at: DateTime<Utc>,
    /// The run this payload belongs to (issue #800). Additive with
    /// `serde(default)`: a pre-#800 payload decodes to the nil id, which never
    /// owns a claim.
    ///
    /// It is the client's **run boundary**: two frames with different
    /// `run_id`s are two runs, so a re-apply (or a reconciled retry) resets the
    /// counters and the ETA instead of looking like a jump backwards.
    #[serde(default)]
    pub run_id: ApplyRunId,
}

impl ApplyProgress {
    /// How long a silent apply run may stay "in progress".
    ///
    /// A per-row write happens at a bounded cadence, so a live run refreshes
    /// this far more often than this window; only a crashed run keeps a stale
    /// payload. The stream then emits a final `null` frame and closes instead
    /// of holding the connection forever.
    pub const STALE_AFTER: chrono::Duration = chrono::Duration::minutes(10);

    /// True when this payload is too old to describe a running apply
    /// (issue #762). Pure, so the stream's close condition is testable without
    /// a clock.
    #[must_use]
    pub fn is_stale_at(&self, now: DateTime<Utc>) -> bool {
        now.signed_duration_since(self.updated_at) > Self::STALE_AFTER
    }

    /// Fraction of the planned work that is done, clamped into `0.0..=1.0`.
    ///
    /// `0.0` for a run with no planned rows: an empty plan has no meaningful
    /// progress, and a client must render an indeterminate affordance rather
    /// than a bar that starts at 100 %.
    #[must_use]
    pub fn fraction(&self) -> f32 {
        if self.total == 0 {
            return 0.0;
        }
        let done = self.applied.min(self.total);
        #[allow(clippy::cast_precision_loss)]
        let value = done as f32 / self.total as f32;
        value
    }
}

/// Wire payload of one apply-progress frame (issue #762).
///
/// Deliberately narrower than [`AiImportJob`]: the apply does not change the
/// job row's status, so a client watching an apply needs the run's own numbers
/// and nothing else. `apply_progress: None` is the run's **end** signal.
///
/// Since issue #899 the frame also carries the run slot's own state and — once
/// the run is over — its **persisted outcome**, so a stream that the client
/// attaches to *after* the run finished still learns what committed instead of
/// only learning that nothing is running any more (design D4).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ApplyProgressFrame {
    pub job_id: AiImportJobId,
    #[serde(default)]
    pub apply_progress: Option<ApplyProgress>,
    /// Lifecycle state of the job's apply slot at the moment of this frame
    /// (issue #899). Additive with `serde(default)`: a pre-#899 frame decodes
    /// as [`ApplyState::Idle`], which is exactly what such a frame described.
    #[serde(default)]
    pub apply_state: ApplyState,
    /// The persisted outcome of the last finished run, `None` while none has
    /// finished. Additive with `serde(default)`.
    #[serde(default)]
    pub apply_result: Option<ApplyRunOutcome>,
}

/// Lifecycle state of one preview's **apply slot** (issue #899).
///
/// The apply used to have no durable state at all: "requested" was implicit in
/// "an HTTP request is in flight", so a dropped connection erased the only
/// trace that work had been asked for. This enum is that state — one slot per
/// job, written only through the owner-fenced transitions of the queue port
/// (`request_apply_run` → `mark_apply_running` → `complete_apply_run` /
/// `fail_apply_run`).
///
/// It is deliberately **not** [`crate::ai::JobStatus`]: the job is terminal
/// (`succeeded`) for the whole time an apply runs, because an apply is work
/// done *on* a finished preview.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ApplyState {
    /// No run has been asked for on this preview (the default, and what every
    /// pre-#899 row decodes as).
    #[default]
    Idle,
    /// A run was validated, claimed and persisted, but no worker has picked it
    /// up yet. This is the state a client's `POST` leaves behind — and the
    /// state a crashed replica leaves behind for the next worker to claim.
    Requested,
    /// A worker owns the slot and is executing the persisted request.
    Running,
    /// The run finished; [`AiImportJob::apply_result`] carries its outcome.
    Done,
    /// The run failed; [`AiImportJob::apply_result`] carries the registered
    /// problem code the client branches on (ADR-031).
    Failed,
}

impl ApplyState {
    /// The storage/wire spelling (`idle`, `requested`, `running`, `done`,
    /// `failed`).
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Requested => "requested",
            Self::Running => "running",
            Self::Done => "done",
            Self::Failed => "failed",
        }
    }

    /// Decode the column spelling. An unrecognised value is [`Self::Idle`]: a
    /// state machine this build cannot read must never be guessed into
    /// "running".
    #[must_use]
    pub fn from_stored(raw: &str) -> Self {
        match raw {
            "requested" => Self::Requested,
            "running" => Self::Running,
            "done" => Self::Done,
            "failed" => Self::Failed,
            _ => Self::Idle,
        }
    }

    /// Whether the run is over (successfully or not).
    #[must_use]
    pub const fn is_terminal(self) -> bool {
        matches!(self, Self::Done | Self::Failed)
    }
}

/// The counters a finished apply run leaves behind (issues #762, #899).
///
/// This is the `POST /ai-import/jobs/{id}/apply` response body of releases
/// before #899 moved it: the run now dispatches (`202 ApplyRunAccepted`) and the
/// outcome is persisted on the run slot, served by the apply stream's terminal
/// frame and by `GET /ai-import/jobs/{id}` (design D4). The type keeps the wire
/// field names it always had.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ApplyImportSummary {
    pub applied_count: u32,
    pub created_days: u32,
    pub planned_scene_shoots: u32,
    /// Figures the script apply created. A figure named by several draft rows is
    /// created once, so this is not `applied_count`-related. `0` for a schedule
    /// apply, which has no figures.
    pub created_characters: u32,
    /// Fundus pieces the script apply created — the garments of the extracted
    /// outfits.
    pub created_pieces: u32,
    /// Outfits the script apply created — one look per accepted outfit row,
    /// bound to its figure and referencing the pieces above.
    pub created_outfits: u32,
    /// Episodes the script apply created for draft episode groups the reviewer
    /// mapped to a NEW episode (issue #581). `0` for a schedule apply.
    pub created_episodes: u32,
    /// Day groups the reviewer rejected — their rows applied unscheduled
    /// (issue #706). Reported so the reviewer sees the deliberate omission,
    /// never a silent one.
    #[serde(default)]
    pub skipped_day_groups: Vec<String>,
    /// Outfit rows that were **not** fully applied, each with the reason. An
    /// apply that created a piece but could not assemble the look reports the
    /// row here while `created_pieces` still counts the pieces — a partially
    /// applied row must never look like a fully applied one.
    #[serde(default)]
    pub unapplied_outfits: Vec<super::preview::UnappliedOutfit>,
    /// The episodes THIS request dispatched rows into, each with its own row
    /// count (issue #763).
    #[serde(default)]
    pub applied_episodes: Vec<AppliedEpisode>,
}

/// What a finished apply run left on the job's run slot (issue #899, design D4).
///
/// Persisted as `apply_result` JSONB by the worker, so the outcome outlives the
/// request that asked for it: a client that re-attaches after the run finished
/// reads it off `GET /ai-import/jobs/{id}` or off the apply stream's terminal
/// frame — no second `POST` needed.
///
/// A failed run carries the **registered problem `code`** (ADR-031), never a
/// `detail`-only string, so the client's error narrative is code-driven exactly
/// like every other apply failure. The human-readable detail stays in the log.
///
/// Serialized as an **externally tagged** enum (`{"succeeded": {...}}` /
/// `{"failed": {"code": ...}}`), the same shape [`crate::ai::SceneSource`]
/// uses. That is deliberate, not cosmetic: the generated Dart client's `oneOf`
/// support decodes externally-tagged variants, so an internally tagged payload
/// (`{"outcome": …, "summary": …}`) would make `apply_result` undecodable on
/// `GET /ai-import/jobs/{id}` — the field the re-entry path depends on.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ApplyRunOutcome {
    /// The run completed and applied its plan (fully or partially — the summary
    /// reports the difference through `unapplied_outfits`).
    Succeeded(ApplyImportSummary),
    /// The run stopped on an error the client can branch on.
    Failed {
        /// Stable problem code (e.g. `ai-import.apply-missing-shooting-day-group`).
        code: String,
    },
}

impl ApplyRunOutcome {
    /// The registered problem code of a failed run, `None` for a success.
    #[must_use]
    pub fn problem_code(&self) -> Option<&str> {
        match self {
            Self::Succeeded(_) => None,
            Self::Failed { code } => Some(code),
        }
    }

    /// The persisted summary of a successful run.
    #[must_use]
    pub fn summary(&self) -> Option<&ApplyImportSummary> {
        match self {
            Self::Succeeded(summary) => Some(summary),
            Self::Failed { .. } => None,
        }
    }
}

/// The `202 Accepted` body of `POST /ai-import/jobs/{id}/apply` (issue #899,
/// design D2).
///
/// The request no longer performs the apply: it validates, claims the run slot
/// and dispatches. The counters arrive later — on the apply stream's terminal
/// frame and on `GET /ai-import/jobs/{id}` — because the run must outlive the
/// connection that started it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ApplyRunAccepted {
    /// The identity of the run the slot now owns. Every progress frame of this
    /// run carries it, so a client can tell "my run" from a later one.
    pub run_id: ApplyRunId,
    /// The run's stage at dispatch time (always `applying`; it exists so the
    /// descriptor stays additive if a later stage becomes dispatchable).
    pub stage: ApplyStage,
    /// When the run was claimed — the anchor the client renders and the value a
    /// re-attaching client compares against the frames it receives.
    pub started_at: DateTime<Utc>,
    /// The slot state at the moment of the answer (always
    /// [`ApplyState::Requested`]). Explicit rather than implied, so a client
    /// reads the re-entry state machine off one shape.
    pub apply_state: ApplyState,
}

/// The apply-run slot of one job: who owns it, how many runs have started, and
/// what the current owner last published (issue #800).
///
/// Why a read of its own instead of reading it off [`AiImportJob`]: the apply
/// stream must be able to tell **"no run ever started"** from **"a run started
/// and already ended"**. The payload alone cannot say that — a run that starts
/// and clears between two re-reads leaves `None` behind, which is exactly the
/// frame a client interpreted as a dropped connection (#800 #2). `seq` is the
/// missing fact: it is bumped on every claim and **never** cleared, so a
/// non-zero delta since the subscriber's baseline *is* proof that a run
/// happened.
///
/// `owner` is the run holding the slot right now. It is cleared together with
/// the payload, so `owner: None` + a seq delta means "that run is over", while
/// `owner: Some(_)` + no payload (yet) means "a run is live but has published
/// nothing" — two states a job-id-keyed slot could not distinguish.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ApplyRunState {
    /// The run that currently owns the slot; `None` when no run is live.
    pub owner: Option<ApplyRunId>,
    /// Monotonic run counter of this job: bumped on every claim, never cleared.
    pub seq: i64,
    /// What the owning run last published; `None` before its first write and
    /// after it cleared the slot.
    pub progress: Option<ApplyProgress>,
    /// When the owning run **took the slot** (issues #863): the instant the
    /// claim granted it, stamped by that claim and by nothing else.
    ///
    /// It exists because the single-flight claim's steal predicate already
    /// judges an owner that has published **nothing** by an owner-scoped stamp
    /// (`OR (apply_progress IS NULL AND COALESCE(apply_claim_at, updated_at) <
    /// cutoff)`), and the refusal had no way to report the stamp that decision
    /// was made on — so a run that died before its first frame was unageable on
    /// the wire (#805 left that open; #863 closes it).
    ///
    /// Deliberately **not** the job row's `updated_at`, which is the tempting
    /// shortcut: that column is bumped by every run-scoped write, including a
    /// PREVIOUS apply's post-apply write, which can land after the next claim
    /// and would then describe the new owner as fresher than it is — understating
    /// a dead run's silence by that gap and delaying the steal by the same
    /// amount (issue #863 review). An owner-scoped column cannot be moved by
    /// anyone else's write.
    ///
    /// `None` when the slot reports no claim instant (a claim made before the
    /// column existed, or an adapter that cannot report it): the refusal then
    /// reports no age at all rather than inventing one.
    pub owner_claimed_at: Option<DateTime<Utc>>,
    /// Lifecycle state of the slot (issue #899) — the fact that turns "no
    /// payload" into three distinguishable answers: nothing was ever asked for
    /// ([`ApplyState::Idle`]), a run is queued or live
    /// ([`ApplyState::Requested`]/[`ApplyState::Running`]) and its owner may
    /// simply not have published yet, or the run is over
    /// ([`ApplyState::Done`]/[`ApplyState::Failed`]) and [`Self::result`] says
    /// what it left behind.
    ///
    /// Before it existed the stream had to infer "a run happened" from the
    /// monotonic counter and had no way to deliver an outcome to a client that
    /// arrived late — the defect #899 fixes.
    pub state: ApplyState,
    /// The persisted outcome of the run that finished on this slot, `None`
    /// while no run has finished (issue #899, design D4).
    pub result: Option<ApplyRunOutcome>,
}

impl ApplyRunState {
    /// Whether a run started (or ended) since `baseline_seq` was observed.
    ///
    /// This is the fact the apply stream was missing: `true` means the client's
    /// "nothing started yet, keep waiting" and "the run already ended" are
    /// distinguishable even when no frame was ever emitted for that run.
    #[must_use]
    pub const fn advanced_since(&self, baseline_seq: i64) -> bool {
        self.seq > baseline_seq
    }

    /// How long the owning run has been silent at `now` — the ONE definition of
    /// the age a `409 ai-import.apply-in-flight` reports (issues #805, #863).
    ///
    /// The fallback order is the claim's own steal order, so the verdict a
    /// client derives and the decision the server makes cannot disagree:
    ///
    /// 1. the payload's `updated_at` once the owner published a frame — the
    ///    column the claim compares then
    ///    (`(apply_progress->>'updated_at')::timestamptz < cutoff`);
    /// 2. otherwise [`Self::owner_claimed_at`] — the column the claim compares
    ///    while `apply_progress IS NULL`, which is what makes a run that died
    ///    **before its first published frame** ageable at all;
    /// 3. otherwise `None`: nothing to age. Zero would claim "just wrote" for a
    ///    run that never reported anything.
    ///
    /// A future stamp (clock skew between the writer and this reader) is clamped
    /// to zero: a negative age is not a fact, and the client would render it as
    /// "just now" anyway.
    #[must_use]
    pub fn owner_silence_at(&self, now: DateTime<Utc>) -> Option<chrono::Duration> {
        let last_write = match (&self.progress, self.owner) {
            (Some(progress), _) => progress.updated_at,
            // An unpublished owner is aged by its OWN claim instant — the same
            // column the steal predicate reads for this state.
            (None, Some(_)) => self.owner_claimed_at?,
            // No run owns the slot: there is no owner to age.
            (None, None) => return None,
        };
        Some(
            now.signed_duration_since(last_write)
                .max(chrono::Duration::zero()),
        )
    }
}

/// The production target an AI import writes into, snapshotted at dispatch
/// (issue #771).
///
/// A job's authoritative write target is the block in `X-Active-Block`; the
/// season follows from that block. Nothing on the wire named the target, so a
/// client could only *believe* it knew where its rows would land — the reported
/// defect was a freshly created season whose import silently went into the
/// previous season's block. This snapshot records WHERE the upload declared it
/// was going, resolved at the API edge from the read models (`GET
/// /v1/blocks/{id}` + `GET /v1/seasons/{id}`) — never invented, and never from
/// a second projection lookup inside the write path (CQRS boundary: the
/// handler is the legitimate consumer).
///
/// The numbers are the production-global identities a user speaks in
/// (`Season {n}` / `Block {n}`); they are display metadata, so a failed season
/// read degrades the whole snapshot to `None` rather than blocking the upload.
///
/// Since issue #829 the target may name a season **without** a block: an upload
/// is allowed to omit `X-Active-Block` and declare only `X-Declared-Season`, in
/// which case the job starts block-less and the block is attached later
/// (`PUT /v1/ai-import/jobs/{id}/target`). The season pair is then always
/// known while [`Self::block_number`] stays `None` until the attach.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct AiImportTarget {
    /// The season the imported rows land in (the owning season of the job's
    /// block, or the declared season of a block-less upload).
    pub season_id: SeasonId,
    /// The season's production-global number.
    pub season_number: i32,
    /// The block's production-global number (the block itself is
    /// [`AiImportJob::block_id`]). `None` means "no target block chosen yet"
    /// (issue #829) — honest absence, never `0` and never a placeholder.
    pub block_number: Option<i32>,
}

/// The body of `PUT /v1/ai-import/jobs/{id}/target` (issue #829).
///
/// One field on purpose: the attach names the block to write into, and the
/// server derives everything else it stores (the block's number for the visible
/// snapshot, its season for the authorization check). A client cannot smuggle in
/// a season, a number or a job identity — those are server-resolved.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct AiImportTargetRequest {
    /// The block this job's rows will land in. Set once: repeating the same
    /// block is a `200` no-op, a different one is refused.
    pub block_id: crate::shared::BlockId,
}

/// One target episode of an applied AI-import preview (issue #763).
///
/// The `applied_count` is the number of scene rows **this** job wrote into the
/// episode, so a multi-episode import can be read at a glance instead of being
/// summed up by the reader.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct AppliedEpisode {
    /// The episode the rows were applied into.
    pub id: Uuid,
    /// Its production-global number (the identity a user speaks in). `None` is
    /// honest absence — never `0`. Since issue #864 the entry is derived from the
    /// read model, so the number is the persisted episode's own when the episode
    /// row is known to the projection.
    pub number: Option<i32>,
    /// Its title, when the episode has one. `None` is honest absence — an
    /// untitled episode renders by number alone.
    pub name: Option<String>,
    /// Scene rows applied into this episode.
    pub applied_count: u32,
}

/// One recorded execution attempt of an AI import job (issue #637).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct AiImportAttempt {
    /// 1-based attempt number, matching the job's `retries` after the attempt.
    pub attempt_no: u32,
    /// Job status the attempt left the job in (`failed`, `dead_letter` or
    /// `payload_unavailable`).
    pub status: JobStatus,
    /// Failure summary, same text `last_error` carried for that attempt.
    pub error_summary: Option<String>,
    /// Stable problem `code` of the failure (ADR-031 D2), e.g.
    /// `dependency.auth-failed`; `None` when the writer recorded no typed
    /// error. Lets a client localize the reason without parsing
    /// `error_summary` (issue #639) — and, since issue #822, attribute the
    /// failure to its dependency: `ai-import.llm-provider-unavailable` is
    /// emitted only by the LLM provider path, while
    /// `domain.service-unavailable` (mapping DB, pricing read model, payload
    /// storage) deliberately names no specific dependency. A consecutive run
    /// of the provider code is what a client aggregates into a degraded state;
    /// the free-form `error_summary` never participates.
    #[serde(default)]
    pub code: Option<String>,
    /// Whether the attempt was classified as retryable.
    pub retryable: bool,
    /// When the attempt was recorded.
    pub created_at: DateTime<Utc>,
}

/// Whether an import job ever reached the apply step, and with what outcome.
///
/// Jobs that stay preview-only are recorded as `NotApplied` so their
/// `edit_distance` is explicitly NULL rather than a misleading `0` — an
/// applied job that needed no user edits legitimately records
/// `edit_distance = 0`. Acceptance and edit-rate calculations SHALL exclude
/// `NotApplied` jobs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum TelemetryApplyState {
    #[default]
    NotApplied,
    Applied {
        /// True when the preview was applied without any user edits or
        /// uncertainty resolutions.
        accept_as_is: bool,
        /// Content-free count of user resolutions/edits at apply time.
        edit_distance: u32,
    },
}

impl TelemetryApplyState {
    /// The `accept_as_is` value for persistence: `None` for `NotApplied`.
    pub const fn accept_as_is(self) -> Option<bool> {
        match self {
            Self::NotApplied => None,
            Self::Applied { accept_as_is, .. } => Some(accept_as_is),
        }
    }

    /// The `edit_distance` value for persistence: `None` for `NotApplied`.
    pub const fn edit_distance(self) -> Option<u32> {
        match self {
            Self::NotApplied => None,
            Self::Applied { edit_distance, .. } => Some(edit_distance),
        }
    }
}

/// Content-free operational telemetry captured for an import job.
#[derive(Debug, Clone, Default, Serialize, Deserialize, ToSchema)]
pub struct Telemetry {
    pub provider: Option<LlmProvider>,
    pub model: Option<String>,
    pub doc_kind: Option<DocumentKind>,
    pub chunk_count: u32,
    pub tokens_in: u64,
    pub tokens_out: u64,
    /// Prompt tokens served from the provider's cache (issue #675).
    /// `#[serde(default)]`: additive on any persisted/wire payload.
    #[serde(default)]
    pub cached_tokens_in: u64,
    /// Hardware energy reported by the provider (e.g. Neuralwatt), in
    /// millijoules, accumulated across all chunks and retries (issue #675).
    /// `#[serde(default)]`: additive on any persisted/wire payload.
    #[serde(default)]
    pub energy_millijoules: u64,
    /// Total latency in milliseconds.
    pub latency_total: u64,
    /// Immutable cost snapshot computed at completion (issue #675). `None`
    /// while the job is still running; persisted alongside the telemetry
    /// counters by the completion write.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cost: Option<CostBreakdown>,
    /// Apply outcome; `NotApplied` while the job is preview-only.
    pub apply_state: TelemetryApplyState,
    /// Scene headings the deterministic scan detected for a script job (issue
    /// #758) — the chunk count after duplicate-heading merging. `0` for
    /// schedule jobs (which have no scene headings) and for pre-#758 rows.
    #[serde(default)]
    pub scenes_detected: u32,
    /// Preview rows the extraction model returned for a script job (issue
    /// #758), summed over all chunks and excluding rows rebuilt from document
    /// metadata. `scenes_detected > scenes_extracted` is the shortfall the
    /// reviewer must be able to see.
    #[serde(default)]
    pub scenes_extracted: u32,
    /// Preview rows the worker rebuilt from the deterministic heading because
    /// their chunk produced no rows at all (issue #758). `0` on a healthy run
    /// and for schedule jobs.
    #[serde(default)]
    pub scenes_synthesized: u32,
    /// The Decision Model scoring outcome (issue #767), written by the same
    /// completion write as the counters above. Additive: `None` on rows no
    /// worker recorded it for — including every pre-#767 row — so a reader
    /// renders "not recorded" instead of guessing an outcome.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision: Option<DecisionTelemetry>,
}

// ===========================================================================
// Model pricing and per-import cost transparency (issue #675)
// ===========================================================================

/// Currency of a pricing entry and of a computed cost snapshot. Rates and
/// totals are always in the *native* currency reported by the provider
/// catalog — there is no conversion between USD and EUR (design D2).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "UPPERCASE")]
pub enum Currency {
    Usd,
    Eur,
}

impl Currency {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Usd => "USD",
            Self::Eur => "EUR",
        }
    }
}

/// Where a pricing row came from. `CuratedSeed` rows are written by the SQL
/// migration so freshly booted, offline deployments have deterministic
/// pricing; the refresh worker overwrites them with `ProviderLive` (provider
/// `/models` endpoints) or `ModelsDev` (`models.dev/api.json`) rows.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum PricingSource {
    CuratedSeed,
    ProviderLive,
    ModelsDev,
}

/// One model's pricing snapshot in integer nano-currency units ($10^{-9}$ of
/// the currency unit: `1_000_000_000 = 1.00 USD/EUR`). Rates are per
/// 1,000,000 tokens. Optional slots stay `None` when the provider does not
/// offer the dimension — never a fabricated zero (issue #675).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ModelPricing {
    pub currency: Currency,
    pub input_nano_per_million: i64,
    pub output_nano_per_million: i64,
    /// Rate for cache-hit prompt tokens, when the provider reports one.
    /// Absent means cached tokens are billed at the plain input rate.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cached_input_nano_per_million: Option<i64>,
    /// Energy billing rate (e.g. Neuralwatt at `$10.00 / kWh` =
    /// `10_000_000_000` nano-USD per kWh), when the provider offers it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub energy_nano_per_kwh: Option<i64>,
    /// Neuralwatt surge-protection cap: the energy cost never exceeds the
    /// token cost of the same call.
    #[serde(default)]
    pub energy_capped_by_token: bool,
    /// Rate per 1,000,000 image-output tokens (e.g. Gemini *Nano Banana*:
    /// one 1024×1024 image consumes 1,290 image-output tokens). #673 slot.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_output_nano_per_million: Option<i64>,
    /// Alternative flat per-image rate. #673 slot; never combined with
    /// `image_output_nano_per_million` by a cost computation.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_nano_per_unit: Option<i64>,
    pub pricing_source: PricingSource,
    /// When this price was captured. A completed job's persisted cost
    /// snapshot never changes when newer prices arrive.
    pub price_as_of: DateTime<Utc>,
}

/// Whether a job's cost could be computed honestly.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum CostStatus {
    /// Pricing was found for `(provider, model)`; breakdowns are populated.
    Known,
    /// The job invoked an LLM whose pricing is not in the read model (e.g.
    /// Ollama or an unpriced custom model). Breakdowns stay `None` — the UI
    /// renders localized "Unknown", never `0`.
    Unknown,
    /// The job never invoked an LLM (native CSV schedule import,
    /// deterministic merge).
    NotApplicable,
}

/// Token-based cost of the **extraction** component of one import, in
/// nano-units. Rates are the snapshot rates active at completion time.
///
/// Since issue #768 the counts are extraction-only: Decision-Model calls are
/// accumulated into their own [`DecisionCostBreakdown`] and priced with the
/// Decision Model's rate card, never folded in here.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct TokenCostBreakdown {
    pub tokens_in: u64,
    pub tokens_out: u64,
    pub cached_tokens_in: u64,
    pub input_rate_nano_per_million: i64,
    pub output_rate_nano_per_million: i64,
    /// Snapshot cache-hit rate; `None` when the catalog had none (cached
    /// tokens are then billed at the plain input rate).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cached_input_rate_nano_per_million: Option<i64>,
    /// `uncached_input + cached_input + output` cost, half-up rounded to
    /// nano-units, as one total.
    pub total_nano: i64,
}

/// Hardware-energy cost of the **extraction** component of one import, in
/// nano-units. Populated only when the job recorded energy telemetry for the
/// extraction calls and the extraction model carries an energy rate.
///
/// Decision-Model energy is reported (and priced) on
/// [`DecisionCostBreakdown`] instead (issue #768).
///
/// Every figure sums the job's **requests**, each capped on its own (issue
/// #794): a provider that caps energy by token cost does so per request, so
/// `effective_capped_nano = Σ_calls min(raw_i, token_i)`. Capping the summed
/// figures instead would report `min(Σ raw_i, Σ token_i)`, an upper bound that
/// can only overstate what was billed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct EnergyCostBreakdown {
    pub energy_millijoules: u64,
    pub rate_nano_per_kwh: i64,
    /// Uncapped energy cost, summed over the requests (`Σ_i mJ_i × rate / 3.6e9`,
    /// each term half-up rounded).
    pub raw_energy_nano: i64,
    /// The cost that counts: `Σ_calls min(raw_i, token_i)` when the provider caps
    /// energy by token cost (Neuralwatt surge protection, applied per request),
    /// otherwise `raw_energy_nano`.
    pub effective_capped_nano: i64,
    /// Whether the token-cost cap reduced **any** of the requests.
    pub capped_by_token_cost: bool,
}

/// Image-generation cost of one import (#673 extensibility slot). Always
/// `None` for script/schedule text imports.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ImageCostBreakdown {
    /// Number of generated images.
    pub images: u64,
    /// Image-output tokens consumed (the per-token billing path).
    pub image_output_tokens: u64,
    /// Snapshot of the flat per-image rate, when that billing kind applies.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_nano_per_unit: Option<i64>,
    /// Snapshot of the per-million-token rate, when that billing kind applies.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_output_rate_nano_per_million: Option<i64>,
    pub total_nano: i64,
}

/// The **Decision-Model** component of a job's cost snapshot (issue #768).
///
/// A job's Decision Model may be a different provider/model than its extraction
/// model (split billing, #722/#723). Its usage is accumulated separately and
/// priced from **its own** `ai_model_pricing` row — never folded into the
/// extraction component and never costed at the extraction rates.
///
/// The usage counts are recorded whether or not the component could be priced,
/// so an unpriced Decision Model still states how much it consumed. The priced
/// fields stay `None` when [`Self::status`] is [`CostStatus::Unknown`] — the
/// honest-unknown rule of #675, applied per component: no fabricated rate, no
/// substituted extraction rate, no `0`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct DecisionCostBreakdown {
    pub provider: LlmProvider,
    pub model: String,
    /// `Known` when the component's `(provider, model)` had a pricing row at
    /// completion; `Unknown` otherwise. `NotApplicable` never occurs: the
    /// component exists only for a job that issued a Decision-Model call.
    pub status: CostStatus,
    pub tokens_in: u64,
    pub tokens_out: u64,
    pub cached_tokens_in: u64,
    pub energy_millijoules: u64,
    /// Currency of the component's own rate card (design D2: no conversion).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub currency: Option<Currency>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price_as_of: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pricing_source: Option<PricingSource>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_rate_nano_per_million: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_rate_nano_per_million: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cached_input_rate_nano_per_million: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub energy_rate_nano_per_kwh: Option<i64>,
    /// Priced token cost of this component, `None` when unpriced. Priced once
    /// over the component's summed tokens (not per request).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_cost_nano: Option<i64>,
    /// Priced effective energy cost of this component, `None` when unpriced.
    /// Summed over the component's **requests**, each capped on its own when the
    /// provider caps energy by token cost: `Σ_calls min(raw_i, token_i)` (issue
    /// #794).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub energy_cost_nano: Option<i64>,
}

/// Whether a job's total figure could be computed honestly (issue #768).
///
/// The per-import snapshot has more than one component once a Decision Model is
/// used. A number is only offered when every recorded component is priced in
/// **one** currency; otherwise the priced parts stay visible and the total is
/// explicitly refused rather than misreported.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum CostTotalStatus {
    /// Every recorded component is priced in one currency: `total_nano` is the
    /// sum the user pays.
    Known,
    /// At least one recorded component has no pricing row (or the pricing read
    /// model was unavailable). The priced components render, `total_nano` is
    /// `None` — no partial sum is presented as the total.
    Incomplete,
    /// The components are priced in different currencies. Design D2 bans
    /// currency conversion, so no sum is honest.
    MixedCurrency,
    /// Nothing was priced — also the `#[serde(default)]` value, so a snapshot
    /// recorded before this field existed never claims a total it cannot carry.
    #[default]
    Unknown,
}

/// The figure the user pays: the sum over a job's priced cost components
/// (issue #768). `total_nano` is present exactly when [`Self::status`] is
/// [`CostTotalStatus::Known`].
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct CostTotal {
    pub status: CostTotalStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub currency: Option<Currency>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total_nano: Option<i64>,
}

/// Immutable per-import cost snapshot persisted on a completed job (design
/// D4). Honesty rule: `Known` populates breakdowns; `Unknown` and
/// `NotApplicable` leave them `None` — never a fabricated zero.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct CostBreakdown {
    pub status: CostStatus,
    /// Present only for `Known` snapshots.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub currency: Option<Currency>,
    /// Price snapshot timestamp of the pricing row used for computation.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price_as_of: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pricing_source: Option<PricingSource>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_cost: Option<TokenCostBreakdown>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub energy_cost: Option<EnergyCostBreakdown>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_cost: Option<ImageCostBreakdown>,
    /// The **Decision-Model** component (issue #768): `Some` iff the job issued
    /// at least one Decision-Model call, so its usage is not lost and its rates
    /// are visibly its own. Additive — `None` on every pre-#768 snapshot and on
    /// every job that ran no scoring pass.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision: Option<DecisionCostBreakdown>,
    /// The figure the user pays, summed over the priced components (issue
    /// #768). Additive with `serde(default)`: a pre-#768 snapshot reports
    /// `status = "unknown"` and carries no total rather than a guessed sum.
    #[serde(default)]
    pub total: CostTotal,
}

impl CostBreakdown {
    /// Snapshot for a job whose `(provider, model)` has no pricing entry:
    /// `status = "unknown"`, all breakdowns `None` — never zero.
    pub fn unknown() -> Self {
        Self {
            status: CostStatus::Unknown,
            currency: None,
            price_as_of: None,
            pricing_source: None,
            token_cost: None,
            energy_cost: None,
            image_cost: None,
            decision: None,
            total: CostTotal::default(),
        }
    }

    /// Snapshot for a job that never invoked an LLM (native CSV schedule
    /// import, deterministic merge).
    pub fn not_applicable() -> Self {
        Self {
            status: CostStatus::NotApplicable,
            currency: None,
            price_as_of: None,
            pricing_source: None,
            token_cost: None,
            energy_cost: None,
            image_cost: None,
            // A job that never invoked an LLM has no Decision-Model component
            // and nothing to total (issue #768).
            decision: None,
            total: CostTotal::default(),
        }
    }
}

/// Telemetry summary as exposed on the `AiImportJob` wire view (issue #675).
/// `None` until the worker records telemetry; additive on the wire.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct JobTelemetrySummary {
    pub provider: Option<LlmProvider>,
    pub model: Option<String>,
    pub doc_kind: Option<DocumentKind>,
    pub chunk_count: u32,
    pub tokens_in: u64,
    pub tokens_out: u64,
    pub cached_tokens_in: u64,
    pub energy_millijoules: u64,
    pub latency_total_ms: u64,
    /// Scene headings the deterministic scan detected (issue #758): the count
    /// the *document* states, as opposed to the preview rows the model
    /// produced. Additive with `serde(default)`; `0` for schedule jobs.
    #[serde(default)]
    pub scenes_detected: u32,
    /// Preview rows the extraction model returned (issue #758). A client can
    /// explain a short preview by comparing this with `scenes_detected` instead
    /// of guessing.
    #[serde(default)]
    pub scenes_extracted: u32,
    /// Preview rows rebuilt from the deterministic heading because their chunk
    /// returned no rows (issue #758). A nonzero value names the degradation.
    #[serde(default)]
    pub scenes_synthesized: u32,
}

/// What the Decision Model scoring pass did for one import job (issue #767).
///
/// Server-derived truth, written by the worker in the same completion write as
/// the extraction telemetry (owner-fenced) — never inferred by a client and
/// never fabricated when the pass could not run.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct DecisionTelemetry {
    /// The provider the job *resolved* for scoring. `Some` for every outcome
    /// except [`DecisionOutcome::SkippedNoConfig`] and
    /// [`DecisionOutcome::SkippedNotApplicable`] — a job whose configuration
    /// named a provider names it here even when the client could not be built,
    /// so "did my config reach the worker?" is answerable after the fact.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider: Option<LlmProvider>,
    /// The decision model id the job resolved for scoring. Same presence rules
    /// as [`Self::provider`].
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    pub outcome: DecisionOutcome,
    /// Rows this job's scoring pass left without a score. `0` unless the
    /// outcome is [`DecisionOutcome::ScoringFailed`].
    ///
    /// The pass is unit-based, so "row" means the granularity that unit could
    /// count: a **preview row** of a failed script chunk (that row also carries
    /// the honest `scoring_failed` rubric), and — for the single-request
    /// schedule pass, which has no per-row rubric — every **schedule row that
    /// carried a day label**, i.e. every row that had an assignment to score.
    /// A partially failed chunk leaves the successful rows scored and only
    /// counts the failures; an unlabelled schedule row had nothing to score and
    /// is never counted.
    #[serde(default)]
    pub failed_rows: u32,
}

/// The outcome class of one job's Decision Model scoring pass (issue #767).
/// The wire values are stable and additive: a client localizes its own copy
/// per variant and never parses a free-text reason.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum DecisionOutcome {
    /// A decision configuration resolved, its client was built, and every
    /// scoring request answered — preview rows may carry scores.
    Ran,
    /// No decision configuration resolved for this job (the triple was never
    /// stored, or it was cleared before the worker resolved it). The import
    /// ran without a scoring pass.
    ///
    /// "Resolved" is deliberately not "claimed": the worker resolves the
    /// configuration after the claimed job's source is loaded, so a
    /// configuration cleared in between is reported here.
    SkippedNoConfig,
    /// A decision configuration resolved but its client could not be built
    /// (credential fetch or transport failure). The import ran without a
    /// scoring pass — best-effort by contract, never fatal.
    ClientUnavailable,
    /// The pass ran and at least one unit produced no score: its request failed
    /// after the bounded quick retry, or it answered without the answer its
    /// rows needed. Those rows degrade to no score, and a chunk's rows keep an
    /// honest `scoring_failed` rubric.
    ScoringFailed,
    /// The job had nothing to score: a native CSV schedule was parsed from the
    /// production tool's own text, so no model produced the rows.
    SkippedNotApplicable,
}

impl From<&Telemetry> for JobTelemetrySummary {
    fn from(t: &Telemetry) -> Self {
        Self {
            provider: t.provider,
            model: t.model.clone(),
            doc_kind: t.doc_kind,
            chunk_count: t.chunk_count,
            tokens_in: t.tokens_in,
            tokens_out: t.tokens_out,
            cached_tokens_in: t.cached_tokens_in,
            energy_millijoules: t.energy_millijoules,
            latency_total_ms: t.latency_total,
            scenes_detected: t.scenes_detected,
            scenes_extracted: t.scenes_extracted,
            scenes_synthesized: t.scenes_synthesized,
        }
    }
}

#[cfg(test)]
#[path = "views_tests.rs"]
mod views_tests;
