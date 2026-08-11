// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, BlockId, UserId};

use super::ports::LlmProvider;

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

/// Public AI configuration view. It contains only the opaque vault reference,
/// never a key or other secret material.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct AiConfigView {
    pub id: Uuid,
    pub user_id: UserId,
    pub provider: LlmProvider,
    pub assistant_model: String,
    pub image_model: Option<String>,
    pub prompt_kinds: Vec<DocumentKind>,
    pub vault_key_id: String,
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
    pub status: JobStatus,
    pub preview_handle: Option<String>,
    pub last_error: Option<String>,
    pub retries: u32,
    pub max_retries: u32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
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
    /// Total latency in milliseconds.
    pub latency_total: u64,
    /// Apply outcome; `NotApplied` while the job is preview-only.
    pub apply_state: TelemetryApplyState,
}

#[cfg(test)]
#[path = "views_tests.rs"]
mod views_tests;
