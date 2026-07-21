// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `CostumeCategoryRepository` port.

use breakdown_core::costume_category::ports::CostumeCategoryRepository;
use breakdown_core::costume_category::views::CostumeCategoryView;
use breakdown_core::error::DomainError;
use breakdown_core::shared::{AggregateVersion, LexicalSortKey, SeasonId};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for costume-category projections.
#[derive(Clone, Debug)]
pub struct CostumeCategoryRepositoryImpl {
    pool: PgPool,
}

impl CostumeCategoryRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl CostumeCategoryRepository for CostumeCategoryRepositoryImpl {
    async fn list_by_season(
        &self,
        season_id: SeasonId,
    ) -> Result<Vec<CostumeCategoryView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, season_id, name, order_key, archived, version, updated_at
            FROM projection_costume_category
            WHERE season_id = $1 AND archived = false
            ORDER BY order_key ASC
            "#,
        )
        .bind(season_id.0)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_category_row).collect()
    }

    async fn count_for_season(&self, season_id: SeasonId) -> Result<i64, DomainError> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM projection_costume_category WHERE season_id = $1
            "#,
        )
        .bind(season_id.0)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
        Ok(count)
    }

    async fn find_by_id(&self, id: Uuid) -> Result<CostumeCategoryView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, season_id, name, order_key, archived, version, updated_at
            FROM projection_costume_category
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("CostumeCategory({id})")))?;

        map_category_row(row)
    }
}

fn map_category_row(row: sqlx::postgres::PgRow) -> Result<CostumeCategoryView, DomainError> {
    let id: Uuid = row.try_get("id").map_err(map_err)?;
    let season_id: Uuid = row.try_get("season_id").map_err(map_err)?;
    let name: String = row.try_get("name").map_err(map_err)?;
    let order_key: String = row.try_get("order_key").map_err(map_err)?;
    let archived: bool = row.try_get("archived").map_err(map_err)?;
    let version: i64 = row.try_get("version").map_err(map_err)?;
    let updated_at: DateTime<Utc> = row.try_get("updated_at").map_err(map_err)?;

    let order_key =
        LexicalSortKey::new(order_key).map_err(|e| DomainError::Conflict(e.to_string()))?;

    Ok(CostumeCategoryView {
        id,
        season_id: SeasonId(season_id),
        name,
        order_key,
        archived,
        version: AggregateVersion(version as u64),
        updated_at,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
