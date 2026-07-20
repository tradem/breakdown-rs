// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `BlockRepository` port.

use breakdown_core::block::ports::BlockRepository;
use breakdown_core::block::views::BlockView;
use breakdown_core::error::DomainError;
use breakdown_core::shared::{AggregateVersion, SeasonId, SeriesId};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for block projections.
#[derive(Clone, Debug)]
pub struct BlockRepositoryImpl {
    pool: PgPool,
}

impl BlockRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl BlockRepository for BlockRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<BlockView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, season_id, series_id, number, start_date, end_date, version, updated_at
            FROM projection_block
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("Block({id})")))?;

        map_block_row(row)
    }

    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<BlockView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, season_id, series_id, number, start_date, end_date, version, updated_at
            FROM projection_block
            WHERE season_id = $1
            ORDER BY number
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(season_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_block_row).collect()
    }

    async fn find_by_series_and_number(
        &self,
        series_id: SeriesId,
        number: i32,
    ) -> Result<Option<BlockView>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, season_id, series_id, number, start_date, end_date, version, updated_at
            FROM projection_block
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
            Some(row) => Ok(Some(map_block_row(row)?)),
            None => Ok(None),
        }
    }
}

fn map_block_row(row: sqlx::postgres::PgRow) -> Result<BlockView, DomainError> {
    Ok(BlockView {
        id: row.try_get("id").map_err(map_err)?,
        season_id: SeasonId(row.try_get("season_id").map_err(map_err)?),
        series_id: SeriesId(row.try_get("series_id").map_err(map_err)?),
        number: row.try_get("number").map_err(map_err)?,
        start_date: row.try_get("start_date").map_err(map_err)?,
        end_date: row.try_get("end_date").map_err(map_err)?,
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
