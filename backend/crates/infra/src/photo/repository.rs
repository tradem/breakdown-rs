// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use async_trait::async_trait;
use breakdown_core::error::DomainError;
use breakdown_core::photo::ports::PhotoRepository;
use breakdown_core::photo::views::{PhotoVariantView, PhotoView};
use breakdown_core::shared::{AggregateVersion, PhotoId, PhotoVariant, VariantStatus};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for photo projections.
#[derive(Clone, Debug)]
pub struct PhotoRepositoryImpl {
    pool: PgPool,
}

impl PhotoRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl PhotoRepository for PhotoRepositoryImpl {
    async fn find_by_id(&self, id: PhotoId) -> Result<PhotoView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT photo_id, content_type, size_bytes, version, created_at, updated_at
            FROM projection_photo
            WHERE photo_id = $1
            "#,
        )
        .bind(id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("Photo({})", id.0)))?;

        let photo_id: Uuid = row.try_get("photo_id").map_err(map_err)?;
        let version: i64 = row.try_get("version").map_err(map_err)?;
        let exif_stripped_at: Option<DateTime<Utc>> = None; // projected from events

        // Fetch variants
        let variant_rows = sqlx::query(
            r#"
            SELECT photo_id, variant, status, size_bytes, created_at
            FROM projection_photo_variant
            WHERE photo_id = $1
            ORDER BY variant
            "#,
        )
        .bind(photo_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        let variants: Vec<PhotoVariantView> = variant_rows
            .into_iter()
            .map(|r| {
                let variant_str: String = r.try_get("variant").map_err(map_err)?;
                let status_str: String = r.try_get("status").map_err(map_err)?;
                let size_bytes: i64 = r.try_get("size_bytes").map_err(map_err)?;
                Ok(PhotoVariantView {
                    kind: parse_variant(&variant_str)?,
                    status: parse_status(&status_str)?,
                    size_bytes: size_bytes as u64,
                })
            })
            .collect::<Result<Vec<_>, DomainError>>()?;

        Ok(PhotoView {
            id: PhotoId::from_uuid(photo_id),
            content_type: row.try_get("content_type").map_err(map_err)?,
            size_bytes: row.try_get::<i64, _>("size_bytes").map_err(map_err)? as u64,
            variants,
            exif_stripped_at,
            version: AggregateVersion(version as u64),
        })
    }

    async fn list_known_ids(&self) -> Result<Vec<PhotoId>, DomainError> {
        let rows: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT photo_id FROM projection_photo
            ORDER BY photo_id
            "#,
        )
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        Ok(rows.into_iter().map(PhotoId::from_uuid).collect())
    }

    async fn count_links(&self, photo_id: PhotoId) -> Result<u64, DomainError> {
        let count: Option<i64> = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM projection_costume_photo
            WHERE photo_id = $1
            "#,
        )
        .bind(photo_id.0)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        Ok(count.unwrap_or(0) as u64)
    }
}

fn parse_variant(s: &str) -> Result<PhotoVariant, DomainError> {
    match s {
        "original" => Ok(PhotoVariant::Original),
        "thumb" => Ok(PhotoVariant::Thumb),
        "medium" => Ok(PhotoVariant::Medium),
        _ => Err(DomainError::ValidationError(format!(
            "Unknown photo variant: {s}"
        ))),
    }
}

fn parse_status(s: &str) -> Result<VariantStatus, DomainError> {
    match s {
        "pending" => Ok(VariantStatus::Pending),
        "ready" => Ok(VariantStatus::Ready),
        "failed" => Ok(VariantStatus::Failed),
        _ => Err(DomainError::ValidationError(format!(
            "Unknown variant status: {s}"
        ))),
    }
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
