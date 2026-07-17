// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `EpisodeRepository` port.

use breakdown_core::episode::ports::EpisodeRepository;
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::error::DomainError;
use breakdown_core::shared::{AggregateVersion, BlockId, SeriesId};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for episode projections.
#[derive(Clone, Debug)]
pub struct EpisodeRepositoryImpl {
    pool: PgPool,
}

impl EpisodeRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl EpisodeRepository for EpisodeRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<EpisodeView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, block_id, series_id, number, name, version, updated_at
            FROM projection_episode
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("Episode({id})")))?;

        map_episode_row(row)
    }

    async fn list_by_block(
        &self,
        block_id: BlockId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<EpisodeView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, block_id, series_id, number, name, version, updated_at
            FROM projection_episode
            WHERE block_id = $1
            ORDER BY number
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(block_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_episode_row).collect()
    }

    async fn list_by_series(
        &self,
        series_id: SeriesId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<EpisodeView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, block_id, series_id, number, name, version, updated_at
            FROM projection_episode
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

        rows.into_iter().map(map_episode_row).collect()
    }

    async fn find_by_series_and_number(
        &self,
        series_id: SeriesId,
        number: i32,
    ) -> Result<Option<EpisodeView>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, block_id, series_id, number, name, version, updated_at
            FROM projection_episode
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
            Some(row) => Ok(Some(map_episode_row(row)?)),
            None => Ok(None),
        }
    }
}

fn map_episode_row(row: sqlx::postgres::PgRow) -> Result<EpisodeView, DomainError> {
    Ok(EpisodeView {
        id: row.try_get("id").map_err(map_err)?,
        block_id: BlockId(row.try_get("block_id").map_err(map_err)?),
        series_id: SeriesId(row.try_get("series_id").map_err(map_err)?),
        number: row.try_get("number").map_err(map_err)?,
        name: row.try_get("name").map_err(map_err)?,
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
