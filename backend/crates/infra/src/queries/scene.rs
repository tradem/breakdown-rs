// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `SceneRepository` port.

use breakdown_core::error::DomainError;
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for scene projections.
#[derive(Clone, Debug)]
pub struct SceneRepositoryImpl {
    pool: PgPool,
}

impl SceneRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Test-only access to the underlying pool (e.g. for Tier-4 round-trip tests
    /// that need to open transactions against the same pool the read adapter
    /// uses). Only compiled under the `testing` feature.
    #[cfg(feature = "testing")]
    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}

impl SceneRepository for SceneRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<SceneView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT
                s.id,
                s.project_id,
                s.scene_number,
                s.location,
                s.mood,
                s.is_schedule_set,
                s.version,
                s.updated_at,
                COALESCE(array_agg(sc.character_id) FILTER (WHERE sc.character_id IS NOT NULL), ARRAY[]::uuid[]) AS assigned_characters
            FROM projection_scene s
            LEFT JOIN projection_scene_character sc ON sc.scene_id = s.id
            WHERE s.id = $1
            GROUP BY s.id
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("Scene({id})")))?;

        map_scene_row(row)
    }

    async fn list_by_project(
        &self,
        project_id: ProjectId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<SceneView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT
                s.id,
                s.project_id,
                s.scene_number,
                s.location,
                s.mood,
                s.is_schedule_set,
                s.version,
                s.updated_at,
                COALESCE(array_agg(sc.character_id) FILTER (WHERE sc.character_id IS NOT NULL), ARRAY[]::uuid[]) AS assigned_characters
            FROM projection_scene s
            LEFT JOIN projection_scene_character sc ON sc.scene_id = s.id
            WHERE s.project_id = $1
            GROUP BY s.id
            ORDER BY s.scene_number, s.updated_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(project_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_scene_row).collect()
    }

    async fn scenes_by_character(&self, character_id: Uuid) -> Result<Vec<SceneView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT
                s.id,
                s.project_id,
                s.scene_number,
                s.location,
                s.mood,
                s.is_schedule_set,
                s.version,
                s.updated_at,
                COALESCE(array_agg(sc2.character_id) FILTER (WHERE sc2.character_id IS NOT NULL), ARRAY[]::uuid[]) AS assigned_characters
            FROM projection_scene s
            JOIN projection_scene_character sc ON sc.scene_id = s.id AND sc.character_id = $1
            LEFT JOIN projection_scene_character sc2 ON sc2.scene_id = s.id
            GROUP BY s.id
            ORDER BY s.scene_number, s.updated_at DESC
            "#,
        )
        .bind(character_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_scene_row).collect()
    }
}

fn map_scene_row(row: sqlx::postgres::PgRow) -> Result<SceneView, DomainError> {
    let scene_number: Option<i32> = row.try_get("scene_number").map_err(map_err)?;
    Ok(SceneView {
        id: row.try_get("id").map_err(map_err)?,
        project_id: ProjectId(row.try_get("project_id").map_err(map_err)?),
        scene_number: scene_number.map(|n| n as u32),
        location: row.try_get("location").map_err(map_err)?,
        mood: row.try_get("mood").map_err(map_err)?,
        is_schedule_set: row.try_get("is_schedule_set").map_err(map_err)?,
        assigned_characters: row.try_get("assigned_characters").map_err(map_err)?,
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
