// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `SeasonRepository` port.

use breakdown_core::error::DomainError;
use breakdown_core::season::ports::SeasonRepository;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, SeriesId};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for season projections.
#[derive(Clone, Debug)]
pub struct SeasonRepositoryImpl {
    pool: PgPool,
}

impl SeasonRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl SeasonRepository for SeasonRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<SeasonView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, series_id, number, title, version, updated_at
            FROM projection_season
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("Season({id})")))?;

        map_season_row(row)
    }

    async fn list_by_series(
        &self,
        series_id: SeriesId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<SeasonView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, series_id, number, title, version, updated_at
            FROM projection_season
            WHERE series_id = $1
            ORDER BY number
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(series_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_season_row).collect()
    }

    async fn find_by_series_and_number(
        &self,
        series_id: SeriesId,
        number: i32,
    ) -> Result<Option<SeasonView>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, series_id, number, title, version, updated_at
            FROM projection_season
            WHERE series_id = $1 AND number = $2
            LIMIT 1
            "#,
        )
        .bind(series_id.0)
        .bind(number)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        match row {
            Some(row) => Ok(Some(map_season_row(row)?)),
            None => Ok(None),
        }
    }
}

fn map_season_row(row: sqlx::postgres::PgRow) -> Result<SeasonView, DomainError> {
    Ok(SeasonView {
        id: row.try_get("id").map_err(map_err)?,
        series_id: SeriesId(row.try_get("series_id").map_err(map_err)?),
        number: row.try_get("number").map_err(map_err)?,
        title: row.try_get("title").map_err(map_err)?,
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
