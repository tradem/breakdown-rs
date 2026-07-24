// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kwaipilot/kat-coder-air-v2.5 (openrouter)

//! `sqlx`-backed implementation of the `SceneShootRepository` port.

use breakdown_core::error::DomainError;
use breakdown_core::scene_shoot::ports::SceneShootRepository;
use breakdown_core::scene_shoot::views::{SceneShootView, SerializedNote};
use breakdown_core::shared::{AggregateVersion, LexicalSortKey, SceneShootId, ShootingDayId};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for scene-shoot projections.
#[derive(Clone, Debug)]
pub struct SceneShootRepositoryImpl {
    pool: PgPool,
}

impl SceneShootRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl SceneShootRepository for SceneShootRepositoryImpl {
    async fn find_by_id(&self, id: SceneShootId) -> Result<SceneShootView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, scene_id, shooting_day_id, planned_order, actual_order,
                   start_dt, end_dt, status, notes, continuity_photo_ids,
                   version, updated_at
            FROM projection_scene_shoot
            WHERE id = $1
            "#,
        )
        .bind(id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("SceneShoot({id})")))?;

        map_scene_shoot_row(row)
    }

    async fn list_by_shooting_day(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> Result<Vec<SceneShootView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, scene_id, shooting_day_id, planned_order, actual_order,
                   start_dt, end_dt, status, notes, continuity_photo_ids,
                   version, updated_at
            FROM projection_scene_shoot
            WHERE shooting_day_id = $1
            ORDER BY COALESCE(actual_order, planned_order) ASC
            "#,
        )
        .bind(shooting_day_id.0)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_scene_shoot_row).collect()
    }

    async fn find_by_scene_and_day(
        &self,
        scene_id: Uuid,
        shooting_day_id: ShootingDayId,
    ) -> Result<SceneShootView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, scene_id, shooting_day_id, planned_order, actual_order,
                   start_dt, end_dt, status, notes, continuity_photo_ids,
                   version, updated_at
            FROM projection_scene_shoot
            WHERE scene_id = $1 AND shooting_day_id = $2
            "#,
        )
        .bind(scene_id)
        .bind(shooting_day_id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("SceneShoot(scene={scene_id}, day={shooting_day_id})")))?;

        map_scene_shoot_row(row)
    }

    async fn list_by_scene(
        &self,
        scene_id: Uuid,
    ) -> Result<Vec<SceneShootView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, scene_id, shooting_day_id, planned_order, actual_order,
                   start_dt, end_dt, status, notes, continuity_photo_ids,
                   version, updated_at
            FROM projection_scene_shoot
            WHERE scene_id = $1
            ORDER BY created_at DESC
            "#,
        )
        .bind(scene_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_scene_shoot_row).collect()
    }
}

fn map_scene_shoot_row(row: sqlx::postgres::PgRow) -> Result<SceneShootView, DomainError> {
    let id: Uuid = row.try_get("id").map_err(map_err)?;
    let scene_id: Uuid = row.try_get("scene_id").map_err(map_err)?;
    let shooting_day_id: Uuid = row.try_get("shooting_day_id").map_err(map_err)?;
    let planned_order_str: String = row.try_get("planned_order").map_err(map_err)?;
    let actual_order_str: Option<String> = row.try_get("actual_order").map_err(map_err)?;
    let start_dt: Option<DateTime<Utc>> = row.try_get("start_dt").map_err(map_err)?;
    let end_dt: Option<DateTime<Utc>> = row.try_get("end_dt").map_err(map_err)?;
    let status: String = row.try_get("status").map_err(map_err)?;
    let notes_json: serde_json::Value = row.try_get("notes").map_err(map_err)?;
    let continuity_ids: Vec<Uuid> = row.try_get("continuity_photo_ids").map_err(map_err)?;
    let version: i64 = row.try_get("version").map_err(map_err)?;
    let updated_at: DateTime<Utc> = row.try_get("updated_at").map_err(map_err)?;

    let planned_order = LexicalSortKey::new(planned_order_str)
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
    let actual_order = actual_order_str
        .map(|s| LexicalSortKey::new(s))
        .transpose()
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

    let notes: Vec<SerializedNote> = serde_json::from_value(notes_json)
        .unwrap_or_default();

    let status_enum = match status.as_str() {
        "Planned" => breakdown_core::shared::SceneShootStatus::Planned,
        "Scheduled" => breakdown_core::shared::SceneShootStatus::Scheduled,
        "InProgress" => breakdown_core::shared::SceneShootStatus::InProgress,
        "Shot" => breakdown_core::shared::SceneShootStatus::Shot,
        "Skipped" => breakdown_core::shared::SceneShootStatus::Skipped,
        other => {
            return Err(DomainError::Conflict(format!("unknown status: {other}")));
        }
    };

    let continuity_photo_ids = continuity_ids
        .into_iter()
        .map(breakdown_core::shared::PhotoId::from_uuid)
        .collect();

    Ok(SceneShootView {
        id: SceneShootId(id),
        scene_id,
        shooting_day_id: ShootingDayId(shooting_day_id),
        planned_order,
        actual_order,
        status: status_enum,
        start_dt,
        end_dt,
        notes,
        continuity_photo_ids,
        version: AggregateVersion(version as u64),
        updated_at,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
