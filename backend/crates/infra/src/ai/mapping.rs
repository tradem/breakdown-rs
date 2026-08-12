// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)

use breakdown_core::ai::{AiImportJobId, AiImportMapping, AiImportMappingRepository};
use breakdown_core::error::DomainError;
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct PgAiImportMappingRepository {
    pool: PgPool,
}

impl PgAiImportMappingRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait::async_trait]
impl AiImportMappingRepository for PgAiImportMappingRepository {
    async fn find(
        &self,
        preview_id: AiImportJobId,
        draft_ref: &str,
    ) -> Result<Option<AiImportMapping>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT preview_id, draft_ref, aggregate_kind, aggregate_id, aggregate_version
            FROM ai_import.projection_ai_import_mapping
            WHERE preview_id = $1 AND draft_ref = $2
            "#,
        )
        .bind(preview_id.as_uuid())
        .bind(draft_ref)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        row.map(map_mapping).transpose()
    }

    async fn reserve(&self, mapping: AiImportMapping) -> Result<AiImportMapping, DomainError> {
        // Insert-if-absent + RETURNING the winning row in one statement.
        // The degenerate `DO UPDATE SET aggregate_kind = <itself>` (rather
        // than `DO NOTHING`) is deliberate: only an actually-updated row is
        // visible to RETURNING, so `DO NOTHING` would return nothing on
        // conflict and force a second round trip that races with a concurrent
        // confirm. Self-assignment changes no value while still yielding the
        // durable row — ours, or the one a previous attempt
        // reserved/confirmed (issue #179).
        let row = sqlx::query(
            r#"
            INSERT INTO ai_import.projection_ai_import_mapping
                (preview_id, draft_ref, aggregate_kind, aggregate_id, aggregate_version)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (preview_id, draft_ref) DO UPDATE
                SET aggregate_kind = ai_import.projection_ai_import_mapping.aggregate_kind
            RETURNING preview_id, draft_ref, aggregate_kind, aggregate_id, aggregate_version
            "#,
        )
        .bind(mapping.preview_id.as_uuid())
        .bind(&mapping.draft_ref)
        .bind(&mapping.aggregate_kind)
        .bind(mapping.aggregate_id)
        .bind(version_to_db(mapping.aggregate_version)?)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        match row {
            Some(row) => map_mapping(row),
            // Defensive: the statement above always returns a row. Fall back
            // to an explicit read rather than assuming it (no unwrap/expect in
            // production paths, AGENTS.md §3).
            None => self
                .find(mapping.preview_id, &mapping.draft_ref)
                .await?
                .ok_or_else(|| {
                    DomainError::service_unavailable(
                        "AI mapping reservation vanished after conflict",
                    )
                }),
        }
    }

    async fn insert(&self, mapping: AiImportMapping) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            INSERT INTO ai_import.projection_ai_import_mapping
                (preview_id, draft_ref, aggregate_kind, aggregate_id, aggregate_version)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (preview_id, draft_ref) DO UPDATE
            SET aggregate_kind = EXCLUDED.aggregate_kind,
                aggregate_id = EXCLUDED.aggregate_id,
                aggregate_version = EXCLUDED.aggregate_version,
                updated_at = now()
            WHERE ai_import.projection_ai_import_mapping.aggregate_version
                < EXCLUDED.aggregate_version
            "#,
        )
        .bind(mapping.preview_id.as_uuid())
        .bind(&mapping.draft_ref)
        .bind(&mapping.aggregate_kind)
        .bind(mapping.aggregate_id)
        .bind(version_to_db(mapping.aggregate_version)?)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn list_by_preview(
        &self,
        preview_id: AiImportJobId,
    ) -> Result<Vec<AiImportMapping>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT preview_id, draft_ref, aggregate_kind, aggregate_id, aggregate_version
            FROM ai_import.projection_ai_import_mapping
            WHERE preview_id = $1
            ORDER BY draft_ref
            "#,
        )
        .bind(preview_id.as_uuid())
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        rows.into_iter().map(map_mapping).collect()
    }
}

/// Checked `u64 -> i64` conversion: an `as` cast would silently wrap above
/// `i64::MAX` and persist a negative row that the read path rejects
/// (`map_mapping`) — fail loudly instead.
fn version_to_db(version: breakdown_core::shared::AggregateVersion) -> Result<i64, DomainError> {
    i64::try_from(version.0).map_err(|error| {
        DomainError::validation(format!(
            "AI mapping aggregate version exceeds database range: {error}"
        ))
    })
}

fn map_mapping(row: sqlx::postgres::PgRow) -> Result<AiImportMapping, DomainError> {
    let preview_id: Uuid = row.try_get("preview_id").map_err(map_sqlx_error)?;
    let aggregate_version: i64 = row.try_get("aggregate_version").map_err(map_sqlx_error)?;
    if aggregate_version < 0 {
        return Err(DomainError::validation(
            "AI mapping aggregate version cannot be negative",
        ));
    }
    Ok(AiImportMapping {
        preview_id: AiImportJobId::from_uuid(preview_id),
        draft_ref: row.try_get("draft_ref").map_err(map_sqlx_error)?,
        aggregate_kind: row.try_get("aggregate_kind").map_err(map_sqlx_error)?,
        aggregate_id: row.try_get("aggregate_id").map_err(map_sqlx_error)?,
        aggregate_version: breakdown_core::shared::AggregateVersion(aggregate_version as u64),
    })
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    // Log the raw error (with bound values) internally; the HTTP-facing message
    // must not leak SQL details or bound values (CWE-209).
    tracing::error!(%error, "AI mapping database error");
    DomainError::service_unavailable("AI mapping database error")
}
