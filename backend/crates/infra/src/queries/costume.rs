// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `CostumeRepository` port.

use breakdown_core::costume::ports::CostumeRepository;
use breakdown_core::costume::views::{CostumeDetailView, CostumePhotoView, CostumeView};
use breakdown_core::error::DomainError;
use breakdown_core::photo::views::PhotoVariantView;
use breakdown_core::shared::{
    AggregateVersion, CostumeCategoryId, PhotoVariant, SeasonId, VariantStatus,
};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for costume projections.
#[derive(Clone, Debug)]
pub struct CostumeRepositoryImpl {
    pool: PgPool,
}

impl CostumeRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    async fn costumefind_by_id_with_children(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, character_id, notes, version, updated_at
            FROM projection_costume
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("Costume({id})")))?;

        self.enrich(map_costume_row(row)?).await
    }

    async fn enrich(&self, view: CostumeView) -> Result<CostumeView, DomainError> {
        let details = sqlx::query(
            r#"
            SELECT detail_id, subject, category_id, category_name, text
            FROM projection_costume_detail
            WHERE costume_id = $1
            ORDER BY detail_id
            "#,
        )
        .bind(view.id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        let photos = sqlx::query(
            r#"
            SELECT cp.photo_id,
                   p.content_type,
                   p.size_bytes
            FROM projection_costume_photo cp
            LEFT JOIN projection_photo p ON p.photo_id = cp.photo_id
            WHERE cp.costume_id = $1
            ORDER BY cp.photo_id
            "#,
        )
        .bind(view.id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        let details = details
            .into_iter()
            .map(|row| {
                Ok(CostumeDetailView {
                    id: row.try_get("detail_id").map_err(map_err)?,
                    subject: row.try_get("subject").map_err(map_err)?,
                    category_id: row
                        .try_get::<Option<Uuid>, _>("category_id")
                        .map_err(map_err)?
                        .map(CostumeCategoryId),
                    category_name: row.try_get("category_name").map_err(map_err)?,
                    text: row.try_get("text").map_err(map_err)?,
                })
            })
            .collect::<Result<Vec<_>, DomainError>>()?;

        let mut enriched_photos = Vec::new();
        for row in photos {
            let photo_id: Uuid = row.try_get("photo_id").map_err(map_err)?;
            let content_type: Option<String> = row.try_get("content_type").map_err(map_err)?;
            let size_bytes: Option<i64> = row.try_get("size_bytes").map_err(map_err)?;

            // Fetch variants for this photo.
            let variant_rows = sqlx::query(
                r#"
                SELECT variant, status, size_bytes
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
                .map(|vr| {
                    let variant_str: String = vr.try_get("variant").map_err(map_err)?;
                    let status_str: String = vr.try_get("status").map_err(map_err)?;
                    let vsize: i64 = vr.try_get("size_bytes").map_err(map_err)?;
                    Ok(PhotoVariantView {
                        kind: parse_variant(&variant_str)?,
                        status: parse_status(&status_str)?,
                        size_bytes: vsize as u64,
                    })
                })
                .collect::<Result<Vec<_>, DomainError>>()?;

            enriched_photos.push(CostumePhotoView {
                id: photo_id,
                content_type: content_type.unwrap_or_default(),
                size_bytes: size_bytes.unwrap_or(0) as u64,
                variants,
            });
        }

        Ok(CostumeView {
            details,
            photos: enriched_photos,
            ..view
        })
    }
}

impl CostumeRepository for CostumeRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        self.costumefind_by_id_with_children(id).await
    }

    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CostumeView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT c.id, c.character_id, c.notes, c.version, c.updated_at
            FROM projection_costume c
            JOIN projection_character ch ON ch.id = c.character_id
            WHERE ch.season_id = $1
            ORDER BY c.updated_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(season_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter()
            .map(map_costume_row)
            .collect::<Result<Vec<_>, _>>()
    }

    async fn costumes_by_character(
        &self,
        character_id: Uuid,
    ) -> Result<Vec<CostumeView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, character_id, notes, version, updated_at
            FROM projection_costume
            WHERE character_id = $1
            ORDER BY updated_at DESC
            "#,
        )
        .bind(character_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter()
            .map(map_costume_row)
            .collect::<Result<Vec<_>, _>>()
    }

    async fn costume_with_details_photos(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        self.costumefind_by_id_with_children(id).await
    }
}

fn map_costume_row(row: sqlx::postgres::PgRow) -> Result<CostumeView, DomainError> {
    Ok(CostumeView {
        id: row.try_get("id").map_err(map_err)?,
        character_id: row.try_get("character_id").map_err(map_err)?,
        notes: row.try_get("notes").map_err(map_err)?,
        details: Vec::new(),
        photos: Vec::new(),
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
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
