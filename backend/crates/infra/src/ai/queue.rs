// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId, AiImportQueue,
    DocumentKind, JobStatus, Telemetry,
};
use breakdown_core::error::DomainError;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct PgAiImportQueue {
    pool: PgPool,
}

impl PgAiImportQueue {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}

#[async_trait::async_trait]
impl AiImportQueue for PgAiImportQueue {
    async fn enqueue(
        &self,
        request: AiImportEnqueueRequest,
    ) -> Result<AiImportEnqueueResult, DomainError> {
        let result = sqlx::query(
            r#"
            INSERT INTO ai_import.ai_import_job
                (id, user_id, document_kind, block_id, dedup_key, document_digest, source_handle)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (user_id, dedup_key) DO NOTHING
            "#,
        )
        .bind(request.id.as_uuid())
        .bind(request.user_id.as_str())
        .bind(request.document_kind.as_str())
        .bind(request.block_id.map(|block_id| block_id.0))
        .bind(&request.dedup_key)
        .bind(&request.document_digest)
        .bind(&request.source_handle)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;

        let row = sqlx::query(
            r#"
            SELECT id
            FROM ai_import.ai_import_job
            WHERE user_id = $1 AND dedup_key = $2
            "#,
        )
        .bind(request.user_id.as_str())
        .bind(&request.dedup_key)
        .fetch_one(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let id = AiImportJobId::from_uuid(row.try_get::<Uuid, _>("id").map_err(map_sqlx_error)?);
        if result.rows_affected() == 1 {
            Ok(AiImportEnqueueResult::Enqueued(id))
        } else {
            Ok(AiImportEnqueueResult::Existing(id))
        }
    }

    async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
        let row = sqlx::query(
            r#"
            WITH next_job AS (
                SELECT id
                FROM ai_import.ai_import_job
                WHERE status = 'pending'
                   OR (status = 'failed' AND
                       (next_attempt_at IS NULL OR next_attempt_at <= now()))
                ORDER BY created_at, id
                FOR UPDATE SKIP LOCKED
                LIMIT 1
            )
            UPDATE ai_import.ai_import_job AS job
            SET status = 'running', updated_at = now()
            FROM next_job
            WHERE job.id = next_job.id
            RETURNING job.*
            "#,
        )
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        row.map(map_job_row).transpose()
    }

    async fn claim_next_kind(
        &self,
        _worker_id: &str,
        kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError> {
        let row = sqlx::query(
            r#"
            WITH next_job AS (
                SELECT id
                FROM ai_import.ai_import_job
                WHERE document_kind = $1
                  AND (status = 'pending'
                   OR (status = 'failed' AND
                       (next_attempt_at IS NULL OR next_attempt_at <= now())))
                ORDER BY created_at, id
                FOR UPDATE SKIP LOCKED
                LIMIT 1
            )
            UPDATE ai_import.ai_import_job AS job
            SET status = 'running', updated_at = now()
            FROM next_job
            WHERE job.id = next_job.id
            RETURNING job.*
            "#,
        )
        .bind(kind.as_str())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        row.map(map_job_row).transpose()
    }

    async fn get(&self, id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT *
            FROM ai_import.ai_import_job
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        row.map(map_job_row).transpose()
    }

    async fn mark_running(&self, id: AiImportJobId) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET status = 'running', updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn mark_succeeded(
        &self,
        id: AiImportJobId,
        preview_handle: &str,
    ) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET status = 'succeeded', preview_handle = $2,
                last_error = NULL, next_attempt_at = NULL, updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .bind(preview_handle)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn mark_failed(
        &self,
        id: AiImportJobId,
        error_summary: &str,
        retryable: bool,
    ) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET retries = retries + 1,
                status = CASE
                    WHEN $3 AND retries + 1 < max_retries THEN 'failed'
                    ELSE 'dead_letter'
                END,
                last_error = LEFT($2, 1000),
                next_attempt_at = CASE
                    WHEN $3 AND retries + 1 < max_retries THEN now() + interval '1 minute'
                    ELSE NULL
                END,
                updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .bind(error_summary)
        .bind(retryable)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn record_telemetry(
        &self,
        id: AiImportJobId,
        telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET provider = $2, model = $3, chunk_count = $4,
                tokens_in = $5, tokens_out = $6, latency_total_ms = $7,
                accept_as_is = $8, edit_distance = $9, updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(id.as_uuid())
        .bind(telemetry.provider.map(|provider| provider.as_str()))
        .bind(telemetry.model)
        .bind(i32::try_from(telemetry.chunk_count).map_err(|error| {
            DomainError::ValidationError(format!("AI chunk count exceeds database range: {error}"))
        })?)
        .bind(i64::try_from(telemetry.tokens_in).map_err(|error| {
            DomainError::ValidationError(format!(
                "AI input token count exceeds database range: {error}"
            ))
        })?)
        .bind(i64::try_from(telemetry.tokens_out).map_err(|error| {
            DomainError::ValidationError(format!(
                "AI output token count exceeds database range: {error}"
            ))
        })?)
        .bind(i64::try_from(telemetry.latency_total).map_err(|error| {
            DomainError::ValidationError(format!("AI latency exceeds database range: {error}"))
        })?)
        .bind(telemetry.accept_as_is)
        .bind(i32::try_from(telemetry.edit_distance).map_err(|error| {
            DomainError::ValidationError(format!(
                "AI edit distance exceeds database range: {error}"
            ))
        })?)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }
}

fn map_job_row(row: sqlx::postgres::PgRow) -> Result<AiImportJob, DomainError> {
    let kind = parse_document_kind(row.try_get("document_kind").map_err(map_sqlx_error)?)?;
    let status = parse_status(row.try_get("status").map_err(map_sqlx_error)?)?;
    let id: Uuid = row.try_get("id").map_err(map_sqlx_error)?;
    let user_id = row
        .try_get::<String, _>("user_id")
        .map_err(map_sqlx_error)?;
    let created_at: DateTime<Utc> = row.try_get("created_at").map_err(map_sqlx_error)?;
    let updated_at: DateTime<Utc> = row.try_get("updated_at").map_err(map_sqlx_error)?;
    Ok(AiImportJob {
        id: AiImportJobId::from_uuid(id),
        user_id: breakdown_core::shared::UserId::from_sub(user_id),
        document_kind: kind,
        block_id: row
            .try_get::<Option<Uuid>, _>("block_id")
            .map_err(map_sqlx_error)?
            .map(breakdown_core::shared::BlockId::from_uuid),
        dedup_key: row.try_get("dedup_key").map_err(map_sqlx_error)?,
        document_digest: row.try_get("document_digest").map_err(map_sqlx_error)?,
        source_handle: row.try_get("source_handle").map_err(map_sqlx_error)?,
        status,
        preview_handle: row.try_get("preview_handle").map_err(map_sqlx_error)?,
        last_error: row.try_get("last_error").map_err(map_sqlx_error)?,
        retries: row
            .try_get::<i32, _>("retries")
            .map_err(map_sqlx_error)?
            .max(0) as u32,
        max_retries: row
            .try_get::<i32, _>("max_retries")
            .map_err(map_sqlx_error)?
            .max(0) as u32,
        created_at,
        updated_at,
    })
}

fn parse_document_kind(value: String) -> Result<DocumentKind, DomainError> {
    match value.as_str() {
        "script" => Ok(DocumentKind::Script),
        "schedule" => Ok(DocumentKind::Schedule),
        other => Err(DomainError::ValidationError(format!(
            "unknown AI document kind {other}"
        ))),
    }
}

fn parse_status(value: String) -> Result<JobStatus, DomainError> {
    match value.as_str() {
        "pending" => Ok(JobStatus::Pending),
        "running" => Ok(JobStatus::Running),
        "succeeded" => Ok(JobStatus::Succeeded),
        "failed" => Ok(JobStatus::Failed),
        "dead_letter" => Ok(JobStatus::DeadLetter),
        other => Err(DomainError::ValidationError(format!(
            "unknown AI job status {other}"
        ))),
    }
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    DomainError::ServiceUnavailable(format!("AI import database error: {error}"))
}
