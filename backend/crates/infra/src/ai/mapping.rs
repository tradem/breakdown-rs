// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)

use breakdown_core::ai::{
    AiImportJobId, AiImportMapping, AiImportMappingRepository, PRIMARY_ORDINAL,
};
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
        aggregate_kind: &str,
        ordinal: i32,
    ) -> Result<Option<AiImportMapping>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version
            FROM ai_import.projection_ai_import_mapping
            WHERE preview_id = $1 AND draft_ref = $2
              AND aggregate_kind = $3 AND ordinal = $4
            "#,
        )
        .bind(preview_id.as_uuid())
        .bind(draft_ref)
        .bind(aggregate_kind)
        .bind(ordinal)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        row.map(map_mapping).transpose()
    }

    async fn reserve(&self, mapping: AiImportMapping) -> Result<AiImportMapping, DomainError> {
        // Insert-if-absent on the full row key. A competing apply (or a retry
        // after a crashed confirm) gets the *winning* row back unchanged, so
        // both attempts drive the same aggregate id — `ON CONFLICT DO UPDATE`
        // with a no-op set is how the winning row is returned by the same
        // statement (a bare `DO NOTHING` would return no row at all).
        let row = sqlx::query(
            r#"
            INSERT INTO ai_import.projection_ai_import_mapping
                (preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (preview_id, draft_ref, aggregate_kind, ordinal) DO UPDATE
                SET aggregate_kind = ai_import.projection_ai_import_mapping.aggregate_kind
            RETURNING preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version
            "#,
        )
            .bind(mapping.preview_id.as_uuid())
            .bind(&mapping.draft_ref)
            .bind(&mapping.aggregate_kind)
            .bind(mapping.ordinal)
            .bind(mapping.aggregate_id)
            .bind(version_to_db(mapping.aggregate_version)?)
            .fetch_optional(&self.pool)
            .await
            .map_err(map_sqlx_error)?;
        match row {
            Some(row) => map_mapping(row),
            // The row vanished between conflict and return (a concurrent
            // delete). Re-read rather than invent: the caller must drive the
            // winner's id, never the id it proposed.
            None => self
                .find(
                    mapping.preview_id,
                    &mapping.draft_ref,
                    &mapping.aggregate_kind,
                    mapping.ordinal,
                )
                .await?
                .ok_or_else(|| {
                    DomainError::service_unavailable(
                        "AI mapping reservation vanished after conflict",
                    )
                }),
        }
    }

    async fn insert(&self, mapping: AiImportMapping) -> Result<(), DomainError> {
        // Monotonic advance only: a late duplicate (or a stale retry that still
        // holds a reservation's version 0) must never roll a confirmed row
        // back. The `WHERE` belongs to the `DO UPDATE`, not the statement, so a
        // non-advancing write simply affects zero rows.
        sqlx::query(
            r#"
            INSERT INTO ai_import.projection_ai_import_mapping
                (preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (preview_id, draft_ref, aggregate_kind, ordinal) DO UPDATE
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
        .bind(mapping.ordinal)
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
        // Every kind is returned — scene, character and costume rows included —
        // in a stable order, so a re-import of an updated document can re-suggest
        // the prior mapping for each of them (task 4.3).
        let rows = sqlx::query(
            r#"
            SELECT preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version
            FROM ai_import.projection_ai_import_mapping
            WHERE preview_id = $1
            ORDER BY draft_ref, aggregate_kind, ordinal
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
    let ordinal: i32 = row.try_get("ordinal").map_err(map_sqlx_error)?;
    if ordinal < PRIMARY_ORDINAL {
        // A negative ordinal would be unreadable by every `find` the apply
        // performs, so surface the corruption instead of carrying it.
        return Err(DomainError::validation(
            "AI mapping ordinal cannot be negative",
        ));
    }
    Ok(AiImportMapping {
        preview_id: AiImportJobId::from_uuid(preview_id),
        draft_ref: row.try_get("draft_ref").map_err(map_sqlx_error)?,
        aggregate_kind: row.try_get("aggregate_kind").map_err(map_sqlx_error)?,
        ordinal,
        aggregate_id: row.try_get("aggregate_id").map_err(map_sqlx_error)?,
        aggregate_version: breakdown_core::shared::AggregateVersion(aggregate_version as u64),
    })
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    // The mapping table is operational state, not business truth; a database
    // failure is always retryable from the caller's point of view.
    tracing::error!(%error, "AI mapping database error");
    DomainError::service_unavailable("AI mapping database error")
}
