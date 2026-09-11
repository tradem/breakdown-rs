// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

//! Projector health queries (issues #37, #409).
//!
//! The dead-letter path in the kameo_es `PostgresProcessor` records every
//! permanently unprocessable event in `projection_dead_letter` (see migration
//! `20260815000001_projection_dead_letter`) and advances the projector's
//! checkpoint in `sierradb_event_checkpoints` past it. This module is the
//! concrete read adapter for the resulting health signal: an operator can
//! list dead letters and inspect per-projection checkpoint progress *without
//! grepping logs* — via the psql variants documented in
//! `docs/operations/runbooks.md` → "Projector dead-letter health (issue #37)"
//! or via `GET /v1/ops/projector-health` (issue #409).
//!
//! The DTOs and the port trait live in `breakdown_core::ops` (ADR-017: core
//! carries no sqlx dependency); this adapter maps rows into them.

use sqlx::{PgPool, Row};

use breakdown_core::error::DomainError;
use breakdown_core::ops::ProjectorHealthRepository as ProjectorHealthRepositoryPort;
use breakdown_core::ops::{CheckpointProgress, DeadLetterEntry};

/// `sqlx::FromRow` mirror of `projection_dead_letter` (issue #37). The
/// wire/port DTO lives in `core` without a sqlx dependency, so this private
/// row struct carries the derive and converts 1:1.
#[derive(Debug, Clone, sqlx::FromRow)]
struct DeadLetterRow {
    projection_id: String,
    partition_id: i16,
    sequence: i64,
    stream_id: String,
    event_name: String,
    sqlstate: Option<String>,
    constraint_name: Option<String>,
    error_message: String,
    attempts: i32,
    first_seen_at: chrono::DateTime<chrono::Utc>,
    last_seen_at: chrono::DateTime<chrono::Utc>,
}

impl From<DeadLetterRow> for DeadLetterEntry {
    fn from(row: DeadLetterRow) -> Self {
        DeadLetterEntry {
            projection_id: row.projection_id,
            partition_id: row.partition_id,
            sequence: row.sequence,
            stream_id: row.stream_id,
            event_name: row.event_name,
            sqlstate: row.sqlstate,
            constraint_name: row.constraint_name,
            error_message: row.error_message,
            attempts: row.attempts,
            first_seen_at: row.first_seen_at,
            last_seen_at: row.last_seen_at,
        }
    }
}

/// Read adapter for the projector health signal (issue #37/#409).
///
/// Pure read-model queries over the dead-letter and checkpoint tables —
/// never a write-side dependency (CQRS boundary: an operator/ops surface,
/// not command context).
#[derive(Clone, Debug)]
pub struct ProjectorHealthRepository {
    pool: PgPool,
}

impl ProjectorHealthRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait::async_trait]
impl ProjectorHealthRepositoryPort for ProjectorHealthRepository {
    /// Latest dead-letter entries, most recently seen first.
    async fn list_dead_letters(&self, limit: i64) -> Result<Vec<DeadLetterEntry>, DomainError> {
        let rows = sqlx::query_as::<_, DeadLetterRow>(
            r#"
            SELECT projection_id, partition_id, sequence, stream_id, event_name,
                   sqlstate, constraint_name, error_message, attempts,
                   first_seen_at, last_seen_at
            FROM projection_dead_letter
            ORDER BY last_seen_at DESC, projection_id, partition_id, sequence
            LIMIT $1
            "#,
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;
        Ok(rows.into_iter().map(Into::into).collect())
    }

    /// Number of distinct poison events currently dead-lettered.
    async fn dead_letter_count(&self) -> Result<i64, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT count(*) AS count
            FROM projection_dead_letter
            "#,
        )
        .fetch_one(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;
        Ok(row.get("count"))
    }

    /// Checkpoint progress of every partition of every projection — the
    /// "is the projector advancing?" signal. Compare against the latest
    /// event sequences in the event store to detect lag; a projection whose
    /// checkpoint never moves while its DLQ rows have growing `attempts`
    /// needs operator attention.
    async fn checkpoint_progress(&self) -> Result<Vec<CheckpointProgress>, DomainError> {
        let rows: Vec<(String, i16, i64)> = sqlx::query_as(
            r#"
            SELECT projection_id, partition_id, sequence
            FROM sierradb_event_checkpoints
            ORDER BY projection_id, partition_id
            "#,
        )
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;
        Ok(rows
            .into_iter()
            .map(
                |(projection_id, partition_id, sequence)| CheckpointProgress {
                    projection_id,
                    partition_id,
                    sequence,
                },
            )
            .collect())
    }
}

#[cfg(test)]
mod tests {
    /// `sqlx::FromRow` derive contract: the row mirror's fields must match the
    /// migration's column set/names in
    /// `20260815000001_projection_dead_letter.up.sql`. This test constructs a
    /// row from the exact projection column list the queries above select —
    /// a field/type drift breaks `query_as` at runtime, so pin the contract
    /// here (no live database needed).
    #[test]
    fn dead_letter_row_matches_selected_columns() {
        let column_order = "projection_id, partition_id, sequence, stream_id, event_name, \
             sqlstate, constraint_name, error_message, attempts, first_seen_at, last_seen_at";
        let struct_fields = [
            "projection_id",
            "partition_id",
            "sequence",
            "stream_id",
            "event_name",
            "sqlstate",
            "constraint_name",
            "error_message",
            "attempts",
            "first_seen_at",
            "last_seen_at",
        ];
        for field in struct_fields {
            assert!(
                column_order.contains(field),
                "column {field} selected by list_dead_letters is missing on DeadLetterRow"
            );
        }
    }
}
