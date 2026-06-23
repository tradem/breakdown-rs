// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `CalculationRepository` port.

use breakdown_core::calculation::ports::CalculationRepository;
use breakdown_core::calculation::views::{CalculationItemView, CalculationView};
use breakdown_core::error::DomainError;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for calculation projections.
#[derive(Clone, Debug)]
pub struct CalculationRepositoryImpl {
    pool: PgPool,
}

impl CalculationRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    async fn calculation_with_items(&self, id: Uuid) -> Result<CalculationView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, project_id, header, version, updated_at
            FROM projection_calculation
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("Calculation({id})")))?;

        let mut view = map_calculation_row(row)?;
        view.items = self.items_for(id).await?;
        Ok(view)
    }

    async fn items_for(
        &self,
        calculation_id: Uuid,
    ) -> Result<Vec<CalculationItemView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT item_id, name, quantity::text AS quantity, unit_price::text AS unit_price, is_paid
            FROM projection_calculation_item
            WHERE calculation_id = $1
            ORDER BY item_id
            "#,
        )
        .bind(calculation_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter()
            .map(|row| {
                let quantity: String = row.try_get("quantity").map_err(map_err)?;
                let unit_price: String = row.try_get("unit_price").map_err(map_err)?;
                Ok(CalculationItemView {
                    id: row.try_get("item_id").map_err(map_err)?,
                    name: row.try_get("name").map_err(map_err)?,
                    quantity: quantity.parse().unwrap_or_default(),
                    unit_price: unit_price.parse().unwrap_or_default(),
                    is_paid: row.try_get("is_paid").map_err(map_err)?,
                })
            })
            .collect::<Result<Vec<_>, DomainError>>()
    }
}

impl CalculationRepository for CalculationRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<CalculationView, DomainError> {
        self.calculation_with_items(id).await
    }

    async fn list_by_project(
        &self,
        project_id: ProjectId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CalculationView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, project_id, header, version, updated_at
            FROM projection_calculation
            WHERE project_id = $1
            ORDER BY updated_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(project_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter()
            .map(map_calculation_row)
            .collect::<Result<Vec<_>, _>>()
    }

    async fn calculation_with_items(&self, id: Uuid) -> Result<CalculationView, DomainError> {
        self.calculation_with_items(id).await
    }
}

fn map_calculation_row(row: sqlx::postgres::PgRow) -> Result<CalculationView, DomainError> {
    let header_json: serde_json::Value = row.try_get("header").map_err(map_err)?;
    Ok(CalculationView {
        id: row.try_get("id").map_err(map_err)?,
        project_id: ProjectId(row.try_get("project_id").map_err(map_err)?),
        header: serde_json::from_value(header_json).unwrap_or_default(),
        items: Vec::new(),
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
