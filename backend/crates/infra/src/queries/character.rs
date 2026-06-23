// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `CharacterRepository` port.

use breakdown_core::character::ports::CharacterRepository;
use breakdown_core::character::views::CharacterView;
use breakdown_core::error::DomainError;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for character projections.
#[derive(Clone, Debug)]
pub struct CharacterRepositoryImpl {
    pool: PgPool,
}

impl CharacterRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl CharacterRepository for CharacterRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<CharacterView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, project_id, name, is_extra, is_main_character,
                   measurements, contact, version, updated_at
            FROM projection_character
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("Character({id})")))?;

        map_character_row(row)
    }

    async fn list_by_project(
        &self,
        project_id: ProjectId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CharacterView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, project_id, name, is_extra, is_main_character,
                   measurements, contact, version, updated_at
            FROM projection_character
            WHERE project_id = $1
            ORDER BY name
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(project_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_character_row).collect()
    }
}

fn map_character_row(row: sqlx::postgres::PgRow) -> Result<CharacterView, DomainError> {
    let measurements_json: serde_json::Value = row.try_get("measurements").map_err(map_err)?;
    let contact_json: serde_json::Value = row.try_get("contact").map_err(map_err)?;

    Ok(CharacterView {
        id: row.try_get("id").map_err(map_err)?,
        project_id: ProjectId(row.try_get("project_id").map_err(map_err)?),
        name: row.try_get("name").map_err(map_err)?,
        is_extra: row.try_get("is_extra").map_err(map_err)?,
        is_main_character: row.try_get("is_main_character").map_err(map_err)?,
        measurements: serde_json::from_value(measurements_json).unwrap_or_default(),
        contact: serde_json::from_value(contact_json).unwrap_or_default(),
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
