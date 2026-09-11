// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

//! Ops surface — projector health (issue #409).
//!
//! The dead-letter path in the kameo_es `PostgresProcessor` (issue #37)
//! records every permanently unprocessable event in `projection_dead_letter`
//! and advances the projector checkpoint past it. This module is the
//! **port** for reading the resulting health signal; the concrete sqlx
//! adapter is `infra::projectors::ProjectorHealthRepository` and the
//! operator-facing consumer is `GET /v1/ops/projector-health` (gated by the
//! deployment-scoped ops capability, `Role::OpsAdmin`).
//!
//! The DTOs live in `core` (like every other read-model view) so the API
//! layer can serve them on the wire directly (`ToSchema`) while `infra`
//! maps rows into them — `core` stays free of `sqlx`/`axum` (ADR-017).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::error::DomainError;

/// One durably recorded poison event (row of `projection_dead_letter`).
///
/// Wire shape of `GET /v1/ops/projector-health` → `dead_letters`.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct DeadLetterEntry {
    /// Checkpoint projection id (the aggregate category, e.g. `costume`).
    pub projection_id: String,
    /// SierraDB partition the event stream hashed into.
    pub partition_id: i16,
    /// Partition sequence of the poison event.
    pub sequence: i64,
    /// SierraDB stream id the event belongs to.
    pub stream_id: String,
    /// Recorded event type name (e.g. `CostumeAssigned`).
    pub event_name: String,
    /// Postgres SQLSTATE classifying the failure, if it carried one.
    pub sqlstate: Option<String>,
    /// Violated constraint name, if the failure carried one.
    pub constraint_name: Option<String>,
    /// Rendered error message (`Debug` of the processor error).
    pub error_message: String,
    /// How often the event was dead-lettered (replays bump, never duplicate).
    pub attempts: i32,
    pub first_seen_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
}

/// Checkpoint progress of one partition of one projection.
///
/// Wire shape of `GET /v1/ops/projector-health` → `checkpoints`.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct CheckpointProgress {
    /// Checkpoint projection id (the aggregate category, e.g. `season`).
    pub projection_id: String,
    /// SierraDB partition the projection's event streams hash into.
    pub partition_id: i16,
    /// Last flushed partition sequence (0-based; the projector is caught up
    /// through this event).
    pub sequence: i64,
}

/// Aggregate response of the projector-health read (issue #409).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ProjectorHealthSnapshot {
    /// Number of distinct poison events currently dead-lettered.
    pub dead_letter_count: i64,
    /// Latest dead-letter entries, most recently seen first (bounded by the
    /// request's `limit`).
    pub dead_letters: Vec<DeadLetterEntry>,
    /// Checkpoint progress of every partition of every projection — the
    /// "is the projector advancing?" signal.
    pub checkpoints: Vec<CheckpointProgress>,
}

/// Read port for the projector health signal (issue #37/#409).
///
/// Pure read-model queries over the dead-letter and checkpoint tables —
/// never a write-side dependency (CQRS boundary: an operator/ops surface,
/// not command context). The concrete sqlx adapter is
/// `infra::projectors::ProjectorHealthRepository`.
#[async_trait::async_trait]
pub trait ProjectorHealthRepository: Send + Sync {
    /// Latest dead-letter entries, most recently seen first.
    async fn list_dead_letters(&self, limit: i64) -> Result<Vec<DeadLetterEntry>, DomainError>;

    /// Number of distinct poison events currently dead-lettered.
    async fn dead_letter_count(&self) -> Result<i64, DomainError>;

    /// Checkpoint progress of every partition of every projection — the
    /// "is the projector advancing?" signal. A projection whose checkpoint
    /// never moves while its DLQ rows have growing `attempts` needs operator
    /// attention.
    async fn checkpoint_progress(&self) -> Result<Vec<CheckpointProgress>, DomainError>;
}
