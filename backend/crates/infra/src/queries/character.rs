// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `CharacterRepository` port.

use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::ports::CharacterRepository;
use breakdown_core::character::views::CharacterView;
use breakdown_core::error::DomainError;
use breakdown_core::shared::{AggregateVersion, EpisodeId, SeasonId};
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
            SELECT id, season_id, name, category,
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

    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CharacterView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, season_id, name, category,
                   measurements, contact, version, updated_at
            FROM projection_character
            WHERE season_id = $1
            ORDER BY name
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(season_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_character_row).collect()
    }

    async fn list_by_season_and_category(
        &self,
        season_id: SeasonId,
        category: CharacterCategory,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CharacterView>, DomainError> {
        let category_json = serde_json::to_value(category).unwrap_or_default();
        let rows = sqlx::query(
            r#"
            SELECT id, season_id, name, category,
                   measurements, contact, version, updated_at
            FROM projection_character
            WHERE season_id = $1 AND category = $2
            ORDER BY name
            LIMIT $3 OFFSET $4
            "#,
        )
        .bind(season_id.0)
        .bind(category_json)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_character_row).collect()
    }

    async fn appearances(&self, character_id: Uuid) -> Result<Vec<EpisodeId>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT s.episode_id
            FROM projection_scene_character sc
            JOIN projection_scene s ON s.id = sc.scene_id
            WHERE sc.character_id = $1
            ORDER BY s.episode_id
            "#,
        )
        .bind(character_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter()
            .map(|row| {
                let id: Uuid = row.try_get("episode_id").map_err(map_err)?;
                Ok(EpisodeId(id))
            })
            .collect()
    }
}

fn map_character_row(row: sqlx::postgres::PgRow) -> Result<CharacterView, DomainError> {
    let measurements_json: serde_json::Value = row.try_get("measurements").map_err(map_err)?;
    let contact_json: serde_json::Value = row.try_get("contact").map_err(map_err)?;
    let category_json: serde_json::Value = row.try_get("category").map_err(map_err)?;

    Ok(CharacterView {
        id: row.try_get("id").map_err(map_err)?,
        season_id: SeasonId(row.try_get("season_id").map_err(map_err)?),
        name: row.try_get("name").map_err(map_err)?,
        category: serde_json::from_value(category_json).unwrap_or_default(),
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
