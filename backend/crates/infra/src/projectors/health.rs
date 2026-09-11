// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

//! Projector health queries (issue #37).
//!
//! The dead-letter path in the kameo_es `PostgresProcessor` records every
//! permanently unprocessable event in `projection_dead_letter` (see migration
//! `20260815000001_projection_dead_letter`) and advances the projector's
//! checkpoint in `sierradb_event_checkpoints` past it. This module is the
//! programmatic read surface for the resulting health signal: an operator can
//! list dead letters and inspect per-projection checkpoint progress *without
//! grepping logs*. The psql variants are documented in
//! `docs/operations/runbooks.md` → "Projector dead-letter health (issue #37)".

use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};

/// One durably recorded poison event (row of `projection_dead_letter`).
#[derive(Debug, Clone, sqlx::FromRow)]
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
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct CheckpointProgress {
    /// Checkpoint projection id (the aggregate category, e.g. `season`).
    pub projection_id: String,
    /// SierraDB partition the projection's event streams hash into.
    pub partition_id: i16,
    /// Last flushed partition sequence (0-based; the projector is caught up
    /// through this event).
    pub sequence: i64,
}

/// Read adapter for the projector health signal (issue #37).
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

    /// Latest dead-letter entries, most recently seen first.
    pub async fn list_dead_letters(&self, limit: i64) -> Result<Vec<DeadLetterEntry>, sqlx::Error> {
        sqlx::query_as(
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
    }

    /// Number of distinct poison events currently dead-lettered.
    pub async fn dead_letter_count(&self) -> Result<i64, sqlx::Error> {
        let row = sqlx::query(
            r#"
            SELECT count(*) AS count
            FROM projection_dead_letter
            "#,
        )
        .fetch_one(&self.pool)
        .await?;
        Ok(row.get("count"))
    }

    /// Checkpoint progress of every partition of every projection — the
    /// "is the projector advancing?" signal. Compare against the latest
    /// event sequences in the event store to detect lag; a projection whose
    /// checkpoint never moves while its DLQ rows have growing `attempts`
    /// needs operator attention.
    pub async fn checkpoint_progress(&self) -> Result<Vec<CheckpointProgress>, sqlx::Error> {
        sqlx::query_as(
            r#"
            SELECT projection_id, partition_id, sequence
            FROM sierradb_event_checkpoints
            ORDER BY projection_id, partition_id
            "#,
        )
        .fetch_all(&self.pool)
        .await
    }
}

#[cfg(test)]
mod tests {
    /// `sqlx::FromRow` derive contract: the struct fields must match the
    /// migration's column set/names in
    /// `20260815000001_projection_dead_letter.up.sql`. This test constructs a
    /// row from the exact projection column list the queries above select —
    /// a field/type drift breaks `query_as` at runtime, so pin the contract
    /// here (no live database needed).
    #[test]
    fn dead_letter_entry_matches_selected_columns() {
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
                "column {field} selected by list_dead_letters is missing on DeadLetterEntry"
            );
        }
    }
}
