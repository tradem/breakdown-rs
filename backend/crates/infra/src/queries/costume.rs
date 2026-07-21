// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `CostumeRepository` port.

use breakdown_core::costume::ports::CostumeRepository;
use breakdown_core::costume::views::{CostumeDetailView, CostumePhotoView, CostumeView};
use breakdown_core::error::DomainError;
use breakdown_core::shared::{AggregateVersion, CostumeCategoryId, SeasonId};
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
            SELECT photo_id
            FROM projection_costume_photo
            WHERE costume_id = $1
            ORDER BY photo_id
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

        let photos = photos
            .into_iter()
            .map(|row| {
                Ok(CostumePhotoView {
                    id: row.try_get("photo_id").map_err(map_err)?,
                })
            })
            .collect::<Result<Vec<_>, DomainError>>()?;

        Ok(CostumeView {
            details,
            photos,
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
