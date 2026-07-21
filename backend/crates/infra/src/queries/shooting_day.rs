// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `ShootingDayRepository` port.

use breakdown_core::error::DomainError;
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{AggregateVersion, EpisodeId, LexicalSortKey, ShootingDayId};
use breakdown_core::shooting_day::events::ShootingDaySource;
use breakdown_core::shooting_day::ports::ShootingDayRepository;
use breakdown_core::shooting_day::views::ShootingDayView;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for shooting-day projections.
#[derive(Clone, Debug)]
pub struct ShootingDayRepositoryImpl {
    pool: PgPool,
}

impl ShootingDayRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl ShootingDayRepository for ShootingDayRepositoryImpl {
    async fn find_by_id(&self, id: ShootingDayId) -> Result<ShootingDayView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, episode_id, label, order_key, date, source, archived, version, updated_at
            FROM projection_shooting_day
            WHERE id = $1
            "#,
        )
        .bind(id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("ShootingDay({id})")))?;

        map_shooting_day_row(row)
    }

    async fn list_by_episode(
        &self,
        episode_id: EpisodeId,
    ) -> Result<Vec<ShootingDayView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, episode_id, label, order_key, date, source, archived, version, updated_at
            FROM projection_shooting_day
            WHERE episode_id = $1 AND archived = false
            ORDER BY order_key ASC
            "#,
        )
        .bind(episode_id.0)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_shooting_day_row).collect()
    }

    async fn scenes_by_shooting_day(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> Result<Vec<SceneView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT
                s.id,
                s.episode_id,
                s.scene_number,
                s.location,
                s.mood,
                s.is_schedule_set,
                s.summary,
                s.version,
                s.updated_at,
                COALESCE(array_agg(sc.character_id) FILTER (WHERE sc.character_id IS NOT NULL), ARRAY[]::uuid[]) AS assigned_characters,
                COALESCE(array_agg(ssd.shooting_day_id) FILTER (WHERE ssd.shooting_day_id IS NOT NULL), ARRAY[]::uuid[]) AS shooting_day_ids
            FROM projection_scene s
            JOIN projection_scene_shooting_day link ON link.scene_id = s.id AND link.shooting_day_id = $1
            LEFT JOIN projection_scene_character sc ON sc.scene_id = s.id
            LEFT JOIN projection_scene_shooting_day ssd ON ssd.scene_id = s.id
            GROUP BY s.id
            ORDER BY s.scene_number, s.updated_at DESC
            "#,
        )
        .bind(shooting_day_id.0)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_scene_view_row).collect()
    }
}

fn map_shooting_day_row(row: sqlx::postgres::PgRow) -> Result<ShootingDayView, DomainError> {
    let id: Uuid = row.try_get("id").map_err(map_err)?;
    let episode_id: Uuid = row.try_get("episode_id").map_err(map_err)?;
    let label: Option<String> = row.try_get("label").map_err(map_err)?;
    let order_key: String = row.try_get("order_key").map_err(map_err)?;
    let date: Option<chrono::NaiveDate> = row.try_get("date").map_err(map_err)?;
    let source_json: serde_json::Value = row.try_get("source").map_err(map_err)?;
    let archived: bool = row.try_get("archived").map_err(map_err)?;
    let version: i64 = row.try_get("version").map_err(map_err)?;
    let updated_at: DateTime<Utc> = row.try_get("updated_at").map_err(map_err)?;

    let order_key =
        LexicalSortKey::new(order_key).map_err(|e| DomainError::Conflict(e.to_string()))?;
    let source = serde_json::from_value::<ShootingDaySource>(source_json)
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

    Ok(ShootingDayView {
        id: ShootingDayId(id),
        episode_id: EpisodeId(episode_id),
        label,
        order_key,
        date,
        source,
        archived,
        version: AggregateVersion(version as u64),
        updated_at,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}

/// Map a `projection_scene` row (joined via the scheduling link table) to a
/// `SceneView`. Mirrors `SceneRepositoryImpl`'s mapper.
fn map_scene_view_row(row: sqlx::postgres::PgRow) -> Result<SceneView, DomainError> {
    let scene_number: Option<i32> = row.try_get("scene_number").map_err(map_err)?;
    let summary: Option<String> = row.try_get("summary").map_err(map_err)?;
    let shooting_day_ids: Vec<Uuid> = row.try_get("shooting_day_ids").map_err(map_err)?;
    Ok(SceneView {
        id: row.try_get("id").map_err(map_err)?,
        episode_id: EpisodeId(row.try_get("episode_id").map_err(map_err)?),
        scene_number: scene_number.map(|n| n as u32),
        location: row.try_get("location").map_err(map_err)?,
        mood: row.try_get("mood").map_err(map_err)?,
        is_schedule_set: row.try_get("is_schedule_set").map_err(map_err)?,
        summary,
        shooting_day_ids: shooting_day_ids.into_iter().map(ShootingDayId).collect(),
        assigned_characters: row.try_get("assigned_characters").map_err(map_err)?,
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}
