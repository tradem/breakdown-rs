// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: grok-4.5 (opencode-go)

//! Durable report-archival job repository (`report_ops.report_job`).
//!
//! **SSOT guardrail:** this module is operational plumbing only. It records
//! *that* a backup was requested, *where* bytes were staged, and *whether*
//! the provider accepted them. It is **not** a source of business facts and
//! no domain query path imports this module.

use std::time::Duration;

use async_trait::async_trait;
use breakdown_core::reporting::{
    EnqueueArchivalRequest, EnqueueArchivalResult, ReportArchivalError, ReportArchivalQueue,
    ReportJobId, ReportJobStatus, ReportKind, ReportLocale, SnapshotIdentity,
};
use breakdown_core::shared::ShootingDayId;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Postgres, Row, Transaction};
use uuid::Uuid;

/// Default max retries before dead-letter (overridable via env).
pub const DEFAULT_MAX_RETRIES: i32 = 5;

/// A claimed / loaded job row for the worker pipeline.
#[derive(Debug, Clone)]
pub struct ReportJobRow {
    pub id: ReportJobId,
    pub dedup_key: String,
    pub kind: ReportKind,
    pub shooting_day_id: ShootingDayId,
    pub locale: ReportLocale,
    pub template_version: String,
    pub snapshot_identity: SnapshotIdentity,
    pub trigger_source: String,
    pub staged_handle: Option<String>,
    pub content_digest: Option<String>,
    pub provider_object_id: Option<String>,
    pub provider_etag: Option<String>,
    pub provider_recorded_at: Option<DateTime<Utc>>,
    pub retries: i32,
    pub max_retries: i32,
    pub status: ReportJobStatus,
    pub last_error: Option<String>,
    pub claimed_at: Option<DateTime<Utc>>,
    pub claimed_by: Option<String>,
    pub next_attempt_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// PostgreSQL-backed archival job queue + claim API.
#[derive(Clone, Debug)]
pub struct PgReportArchivalQueue {
    pool: PgPool,
    max_retries: i32,
}

impl PgReportArchivalQueue {
    /// Build against an app-role pool (DML only).
    pub fn new(pool: PgPool) -> Self {
        let max_retries = std::env::var("REPORT_BACKUP_MAX_RETRIES")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(DEFAULT_MAX_RETRIES);
        Self { pool, max_retries }
    }

    /// Access the underlying pool (for worker / recon).
    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    pub fn max_retries(&self) -> i32 {
        self.max_retries
    }

    /// Insert-or-return-existing by dedup key (static SQL + binds).
    pub async fn enqueue_job(
        &self,
        req: EnqueueArchivalRequest,
    ) -> Result<EnqueueArchivalResult, ReportArchivalError> {
        let dedup = req.dedup_key();
        let id = ReportJobId::new();
        let now = Utc::now();

        // Try insert; on unique violation, fetch the existing row.
        let inserted = sqlx::query(
            r#"
            INSERT INTO report_ops.report_job (
                id, dedup_key, kind, shooting_day_id, locale, template_version,
                snapshot_identity, trigger_source, retries, max_retries, status,
                next_attempt_at, created_at, updated_at
            ) VALUES (
                $1, $2, $3, $4, $5, $6,
                $7, $8, 0, $9, $10,
                $11, $12, $13
            )
            ON CONFLICT (dedup_key) DO NOTHING
            RETURNING id, status
            "#,
        )
        .bind(id.0)
        .bind(&dedup)
        .bind(req.kind.to_string())
        .bind(req.shooting_day_id.0)
        .bind(req.locale.as_str())
        .bind(&req.template_version)
        .bind(req.snapshot_identity.as_str())
        .bind(req.trigger.as_str())
        .bind(self.max_retries)
        .bind(ReportJobStatus::Pending.as_str())
        .bind(now)
        .bind(now)
        .bind(now)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_err)?;

        if let Some(row) = inserted {
            let job_id = ReportJobId(row.get::<Uuid, _>("id"));
            let status = parse_status(row.get::<String, _>("status"))?;
            return Ok(EnqueueArchivalResult {
                job_id,
                already_enqueued: false,
                status,
            });
        }

        // Dedup hit — return existing.
        let existing = sqlx::query(
            r#"
            SELECT id, status
            FROM report_ops.report_job
            WHERE dedup_key = $1
            "#,
        )
        .bind(&dedup)
        .fetch_one(&self.pool)
        .await
        .map_err(map_sqlx_err)?;

        Ok(EnqueueArchivalResult {
            job_id: ReportJobId(existing.get::<Uuid, _>("id")),
            already_enqueued: true,
            status: parse_status(existing.get::<String, _>("status"))?,
        })
    }

    /// Claim the next runnable job (`pending`/`failed` with due `next_attempt_at`).
    ///
    /// Uses `FOR UPDATE SKIP LOCKED` so multiple workers never claim the same row.
    pub async fn claim_next(
        &self,
        worker_id: &str,
    ) -> Result<Option<ReportJobRow>, ReportArchivalError> {
        let mut tx: Transaction<'_, Postgres> = self.pool.begin().await.map_err(map_sqlx_err)?;
        let now = Utc::now();

        let row = sqlx::query(
            r#"
            SELECT id
            FROM report_ops.report_job
            WHERE status IN ('pending', 'failed', 'staged', 'uploading')
              AND (next_attempt_at IS NULL OR next_attempt_at <= $1)
            ORDER BY created_at ASC
            FOR UPDATE SKIP LOCKED
            LIMIT 1
            "#,
        )
        .bind(now)
        .fetch_optional(&mut *tx)
        .await
        .map_err(map_sqlx_err)?;

        let Some(id_row) = row else {
            tx.commit().await.map_err(map_sqlx_err)?;
            return Ok(None);
        };
        let id: Uuid = id_row.get("id");

        sqlx::query(
            r#"
            UPDATE report_ops.report_job
            SET status = $2,
                claimed_at = $3,
                claimed_by = $4,
                updated_at = $3
            WHERE id = $1
            "#,
        )
        .bind(id)
        .bind(ReportJobStatus::Claimed.as_str())
        .bind(now)
        .bind(worker_id)
        .execute(&mut *tx)
        .await
        .map_err(map_sqlx_err)?;

        let full = load_job_tx(&mut tx, id).await?;
        tx.commit().await.map_err(map_sqlx_err)?;
        Ok(Some(full))
    }

    /// Mark job as staged with handle + digest (after Garage put).
    pub async fn mark_staged(
        &self,
        id: ReportJobId,
        staged_handle: &str,
        content_digest: &str,
    ) -> Result<(), ReportArchivalError> {
        let now = Utc::now();
        sqlx::query(
            r#"
            UPDATE report_ops.report_job
            SET status = $2,
                staged_handle = $3,
                content_digest = $4,
                updated_at = $5,
                last_error = NULL
            WHERE id = $1
            "#,
        )
        .bind(id.0)
        .bind(ReportJobStatus::Staged.as_str())
        .bind(staged_handle)
        .bind(content_digest)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_err)?;
        Ok(())
    }

    /// Mark external upload in flight.
    pub async fn mark_uploading(&self, id: ReportJobId) -> Result<(), ReportArchivalError> {
        let now = Utc::now();
        sqlx::query(
            r#"
            UPDATE report_ops.report_job
            SET status = $2, updated_at = $3
            WHERE id = $1
            "#,
        )
        .bind(id.0)
        .bind(ReportJobStatus::Uploading.as_str())
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_err)?;
        Ok(())
    }

    /// Persist provider outcome and mark succeeded.
    pub async fn mark_succeeded(
        &self,
        id: ReportJobId,
        provider_object_id: &str,
        provider_etag: Option<&str>,
    ) -> Result<(), ReportArchivalError> {
        let now = Utc::now();
        sqlx::query(
            r#"
            UPDATE report_ops.report_job
            SET status = $2,
                provider_object_id = $3,
                provider_etag = $4,
                provider_recorded_at = $5,
                updated_at = $5,
                last_error = NULL,
                claimed_at = NULL,
                claimed_by = NULL
            WHERE id = $1
            "#,
        )
        .bind(id.0)
        .bind(ReportJobStatus::Succeeded.as_str())
        .bind(provider_object_id)
        .bind(provider_etag)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_err)?;
        Ok(())
    }

    /// Record a failure; dead-letter when retries exhausted.
    pub async fn mark_failure(
        &self,
        id: ReportJobId,
        error_summary: &str,
        backoff: Duration,
    ) -> Result<ReportJobStatus, ReportArchivalError> {
        let now = Utc::now();
        // Read current retries under a short transaction.
        let mut tx = self.pool.begin().await.map_err(map_sqlx_err)?;
        let row = sqlx::query(
            r#"
            SELECT retries, max_retries
            FROM report_ops.report_job
            WHERE id = $1
            FOR UPDATE
            "#,
        )
        .bind(id.0)
        .fetch_one(&mut *tx)
        .await
        .map_err(map_sqlx_err)?;

        let retries: i32 = row.get("retries");
        let max_retries: i32 = row.get("max_retries");
        let next_retries = retries + 1;
        let summary = truncate_error(error_summary);

        let status = if next_retries >= max_retries {
            ReportJobStatus::DeadLetter
        } else {
            ReportJobStatus::Failed
        };

        let next_attempt = if status == ReportJobStatus::Failed {
            Some(now + chrono::Duration::from_std(backoff).unwrap_or(chrono::Duration::seconds(30)))
        } else {
            None
        };

        sqlx::query(
            r#"
            UPDATE report_ops.report_job
            SET status = $2,
                retries = $3,
                last_error = $4,
                next_attempt_at = $5,
                updated_at = $6,
                claimed_at = NULL,
                claimed_by = NULL
            WHERE id = $1
            "#,
        )
        .bind(id.0)
        .bind(status.as_str())
        .bind(next_retries)
        .bind(&summary)
        .bind(next_attempt)
        .bind(now)
        .execute(&mut *tx)
        .await
        .map_err(map_sqlx_err)?;

        tx.commit().await.map_err(map_sqlx_err)?;
        Ok(status)
    }

    /// Mark permanently failed (e.g. render bounds) without retry.
    pub async fn mark_terminal_failure(
        &self,
        id: ReportJobId,
        error_summary: &str,
    ) -> Result<(), ReportArchivalError> {
        let now = Utc::now();
        sqlx::query(
            r#"
            UPDATE report_ops.report_job
            SET status = $2,
                last_error = $3,
                updated_at = $4,
                claimed_at = NULL,
                claimed_by = NULL,
                next_attempt_at = NULL
            WHERE id = $1
            "#,
        )
        .bind(id.0)
        .bind(ReportJobStatus::DeadLetter.as_str())
        .bind(truncate_error(error_summary))
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_err)?;
        Ok(())
    }

    /// Clear staged handle after successful retention.
    pub async fn clear_staged_handle(&self, id: ReportJobId) -> Result<(), ReportArchivalError> {
        let now = Utc::now();
        sqlx::query(
            r#"
            UPDATE report_ops.report_job
            SET staged_handle = NULL, updated_at = $2
            WHERE id = $1
            "#,
        )
        .bind(id.0)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_err)?;
        Ok(())
    }

    /// Load a job by id.
    pub async fn load(&self, id: ReportJobId) -> Result<Option<ReportJobRow>, ReportArchivalError> {
        let row = sqlx::query(
            r#"
            SELECT
                id, dedup_key, kind, shooting_day_id, locale, template_version,
                snapshot_identity, trigger_source, staged_handle, content_digest,
                provider_object_id, provider_etag, provider_recorded_at,
                retries, max_retries, status, last_error,
                claimed_at, claimed_by, next_attempt_at, created_at, updated_at
            FROM report_ops.report_job
            WHERE id = $1
            "#,
        )
        .bind(id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_err)?;

        row.map(map_job_row).transpose()
    }

    /// Jobs stranded in `claimed` longer than `stale_after` (crash recovery).
    pub async fn list_stale_claims(
        &self,
        stale_after: Duration,
    ) -> Result<Vec<ReportJobRow>, ReportArchivalError> {
        let cutoff = Utc::now()
            - chrono::Duration::from_std(stale_after).unwrap_or(chrono::Duration::minutes(15));
        let rows = sqlx::query(
            r#"
            SELECT
                id, dedup_key, kind, shooting_day_id, locale, template_version,
                snapshot_identity, trigger_source, staged_handle, content_digest,
                provider_object_id, provider_etag, provider_recorded_at,
                retries, max_retries, status, last_error,
                claimed_at, claimed_by, next_attempt_at, created_at, updated_at
            FROM report_ops.report_job
            WHERE status = 'claimed'
              AND claimed_at IS NOT NULL
              AND claimed_at < $1
            "#,
        )
        .bind(cutoff)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_err)?;

        rows.into_iter().map(map_job_row).collect()
    }

    /// Succeeded jobs that still hold a staged handle (retention candidates).
    pub async fn list_succeeded_with_staging(
        &self,
    ) -> Result<Vec<ReportJobRow>, ReportArchivalError> {
        let rows = sqlx::query(
            r#"
            SELECT
                id, dedup_key, kind, shooting_day_id, locale, template_version,
                snapshot_identity, trigger_source, staged_handle, content_digest,
                provider_object_id, provider_etag, provider_recorded_at,
                retries, max_retries, status, last_error,
                claimed_at, claimed_by, next_attempt_at, created_at, updated_at
            FROM report_ops.report_job
            WHERE status = 'succeeded'
              AND staged_handle IS NOT NULL
            "#,
        )
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_err)?;

        rows.into_iter().map(map_job_row).collect()
    }

    /// Release a stale claim back to `pending`/`staged` so another worker can pick it up.
    pub async fn release_stale_claim(&self, id: ReportJobId) -> Result<(), ReportArchivalError> {
        let now = Utc::now();
        sqlx::query(
            r#"
            UPDATE report_ops.report_job
            SET status = CASE
                    WHEN staged_handle IS NOT NULL THEN 'staged'
                    ELSE 'pending'
                END,
                claimed_at = NULL,
                claimed_by = NULL,
                next_attempt_at = $2,
                updated_at = $2
            WHERE id = $1
              AND status = 'claimed'
            "#,
        )
        .bind(id.0)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_err)?;
        Ok(())
    }
}

#[async_trait]
impl ReportArchivalQueue for PgReportArchivalQueue {
    async fn enqueue(
        &self,
        req: EnqueueArchivalRequest,
    ) -> Result<EnqueueArchivalResult, ReportArchivalError> {
        self.enqueue_job(req).await
    }

    async fn get(
        &self,
        job_id: ReportJobId,
    ) -> Result<Option<EnqueueArchivalResult>, ReportArchivalError> {
        Ok(self.load(job_id).await?.map(|row| EnqueueArchivalResult {
            job_id: row.id,
            already_enqueued: true,
            status: row.status,
        }))
    }
}

async fn load_job_tx(
    tx: &mut Transaction<'_, Postgres>,
    id: Uuid,
) -> Result<ReportJobRow, ReportArchivalError> {
    let row = sqlx::query(
        r#"
        SELECT
            id, dedup_key, kind, shooting_day_id, locale, template_version,
            snapshot_identity, trigger_source, staged_handle, content_digest,
            provider_object_id, provider_etag, provider_recorded_at,
            retries, max_retries, status, last_error,
            claimed_at, claimed_by, next_attempt_at, created_at, updated_at
        FROM report_ops.report_job
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_one(&mut **tx)
    .await
    .map_err(map_sqlx_err)?;
    map_job_row(row)
}

fn map_job_row(row: sqlx::postgres::PgRow) -> Result<ReportJobRow, ReportArchivalError> {
    let kind_str: String = row.get("kind");
    let kind = parse_kind(&kind_str)?;
    let locale_str: String = row.get("locale");
    let locale = ReportLocale::new(locale_str).map_err(|e| ReportArchivalError::Internal {
        detail: e.to_string(),
    })?;
    let status = parse_status(row.get::<String, _>("status"))?;

    Ok(ReportJobRow {
        id: ReportJobId(row.get("id")),
        dedup_key: row.get("dedup_key"),
        kind,
        shooting_day_id: ShootingDayId(row.get("shooting_day_id")),
        locale,
        template_version: row.get("template_version"),
        snapshot_identity: SnapshotIdentity::new(row.get::<String, _>("snapshot_identity")),
        trigger_source: row.get("trigger_source"),
        staged_handle: row.get("staged_handle"),
        content_digest: row.get("content_digest"),
        provider_object_id: row.get("provider_object_id"),
        provider_etag: row.get("provider_etag"),
        provider_recorded_at: row.get("provider_recorded_at"),
        retries: row.get("retries"),
        max_retries: row.get("max_retries"),
        status,
        last_error: row.get("last_error"),
        claimed_at: row.get("claimed_at"),
        claimed_by: row.get("claimed_by"),
        next_attempt_at: row.get("next_attempt_at"),
        created_at: row.get("created_at"),
        updated_at: row.get("updated_at"),
    })
}

fn parse_status(s: String) -> Result<ReportJobStatus, ReportArchivalError> {
    ReportJobStatus::parse(&s).ok_or_else(|| ReportArchivalError::Internal {
        detail: format!("unknown job status: {s}"),
    })
}

fn parse_kind(s: &str) -> Result<ReportKind, ReportArchivalError> {
    match s {
        "dispo" => Ok(ReportKind::Dispo),
        "shoot-day" => Ok(ReportKind::ShootDay),
        "planned-vs-actual" => Ok(ReportKind::PlannedVsActual),
        other => Err(ReportArchivalError::Internal {
            detail: format!("unknown report kind: {other}"),
        }),
    }
}

fn map_sqlx_err(e: sqlx::Error) -> ReportArchivalError {
    // Never include raw driver messages that might echo bound values.
    match &e {
        sqlx::Error::Database(db) if db.constraint() == Some("report_job_shooting_day_fk") => {
            ReportArchivalError::ShootingDayNotFound
        }
        sqlx::Error::RowNotFound => ReportArchivalError::Internal {
            detail: "row not found".into(),
        },
        _ => ReportArchivalError::Internal {
            detail: "database error".into(),
        },
    }
}

fn truncate_error(s: &str) -> String {
    const MAX: usize = 256;
    let mut out = s.chars().take(MAX).collect::<String>();
    // Belt-and-suspenders: never keep credential-ish content in last_error.
    let lower = out.to_ascii_lowercase();
    for needle in ["secret", "password", "token", "bearer ", "akia"] {
        if lower.contains(needle) {
            return "redacted error".into();
        }
    }
    if s.chars().count() > MAX {
        out.push('…');
    }
    out
}

