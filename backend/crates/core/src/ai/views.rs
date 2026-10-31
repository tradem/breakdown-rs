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
    /// (`GET /ai-import/jobs/{id}`); empty in list/claim contexts where the
    /// history is not fetched, so it is additive on the wire.
    #[serde(default)]
    pub attempts: Vec<AiImportAttempt>,
    /// The episodes a successful **script** apply landed this job's rows in
    /// (issue #763), so the jobs list can name the import's target instead of
    /// only its date. Additive with `serde(default)`: empty for a job no apply
    /// has run for yet, and for a schedule apply (which merges onto the
    /// project's existing scenes and days and therefore has no single target
    /// episode). Written by the apply path from the plan and target data it
    /// already holds.
    ///
    /// The summary is written by the applies that actually dispatched rows, and
    /// merged per episode: a re-apply of an already-applied preview contributes
    /// nothing (a confirmed row is not re-attributed to the retry's target), so
    /// the earlier entries survive. It is best-effort by design (the scene rows
    /// are already committed), so an empty list also means "no apply has written
    /// a summary" — a client renders its kind/date copy either way. An entry
    /// only carries `number`/`name` when they are authoritative for that
    /// episode's persisted location.
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
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct AiImportTarget {
    /// The season the imported rows land in (the owning season of the job's
    /// block).
    pub season_id: SeasonId,
    /// The season's production-global number.
    pub season_number: i32,
    /// The block's production-global number (the block itself is
    /// [`AiImportJob::block_id`]).
    pub block_number: i32,
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
    /// Its production-global number (the identity a user speaks in), when the
    /// apply path knew it. `None` is honest absence — never `0`, never a number
    /// read back from a projection the write path must not consult.
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
    /// `error_summary` (issue #639).
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
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct EnergyCostBreakdown {
    pub energy_millijoules: u64,
    pub rate_nano_per_kwh: i64,
    /// Uncapped energy cost (`mJ × rate / 3.6e9`, half-up rounded).
    pub raw_energy_nano: i64,
    /// The cost that counts: `min(raw_energy_nano, token_cost.total_nano)`
    /// when the provider caps energy by token cost (Neuralwatt surge
    /// protection), otherwise `raw_energy_nano`.
    pub effective_capped_nano: i64,
    /// Whether the token-cost cap reduced the figure.
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
    /// Priced token cost of this component, `None` when unpriced.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_cost_nano: Option<i64>,
    /// Priced effective energy cost of this component (`min(raw, token)` when
    /// the provider caps energy by token cost), `None` when unpriced.
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
