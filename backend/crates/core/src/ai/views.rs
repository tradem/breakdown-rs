// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

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

/// Operational lifecycle of an AI import job.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum JobStatus {
    Pending,
    Running,
    Succeeded,
    Failed,
    DeadLetter,
}

impl JobStatus {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Running => "running",
            Self::Succeeded => "succeeded",
            Self::Failed => "failed",
            Self::DeadLetter => "dead_letter",
        }
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
    pub accept_as_is: Option<bool>,
    pub edit_distance: u32,
}
