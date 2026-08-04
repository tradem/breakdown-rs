// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

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
        .bind(mapping.aggregate_version.0 as i64)
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

fn map_mapping(row: sqlx::postgres::PgRow) -> Result<AiImportMapping, DomainError> {
    let preview_id: Uuid = row.try_get("preview_id").map_err(map_sqlx_error)?;
    let aggregate_version: i64 = row.try_get("aggregate_version").map_err(map_sqlx_error)?;
    if aggregate_version < 0 {
        return Err(DomainError::ValidationError(
            "AI mapping aggregate version cannot be negative".to_owned(),
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
    DomainError::ServiceUnavailable(format!("AI mapping database error: {error}"))
}
