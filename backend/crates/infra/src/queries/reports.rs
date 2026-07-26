// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! sqlx-backed implementation of the `SceneShootReportRepository` port.

use breakdown_core::error::DomainError;
use breakdown_core::scene_shoot::ports::SceneShootReportRepository;
use breakdown_core::scene_shoot::views::{
    DispoRow, SerializedNote, ShootDayRow, SollIstDiffRow, SollIstReport,
};
use breakdown_core::shared::SceneShootStatus;
use breakdown_core::shared::{LexicalSortKey, PhotoId, ShootingDayId};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for shoot-day reports.
#[derive(Clone, Debug)]
pub struct SceneShootReportRepositoryImpl {
    pool: PgPool,
}

impl SceneShootReportRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl SceneShootReportRepository for SceneShootReportRepositoryImpl {
    async fn dispo_report(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> Result<Vec<DispoRow>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT ss.planned_order, ss.scene_id,
                   s.scene_number, s.script_day, s.location, s.mood, s.summary
            FROM projection_scene_shoot ss
            LEFT JOIN projection_scene s ON s.id = ss.scene_id
            WHERE ss.shooting_day_id = $1
            ORDER BY ss.planned_order ASC
            "#,
        )
        .bind(shooting_day_id.0)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter()
            .map(|row| {
                let order_str: String = row.try_get("planned_order").map_err(map_err)?;
                Ok(DispoRow {
                    planned_order: LexicalSortKey::new(order_str)
                        .map_err(|e| DomainError::Conflict(e.to_string()))?,
                    scene_id: row.try_get("scene_id").map_err(map_err)?,
                    scene_number: row
                        .try_get::<Option<i32>, _>("scene_number")
                        .map_err(map_err)?
                        .map(|v| v as u32),
                    script_day: row.try_get("script_day").map_err(map_err)?,
                    location: row.try_get("location").map_err(map_err)?,
                    mood: row.try_get("mood").map_err(map_err)?,
                    summary: row.try_get("summary").map_err(map_err)?,
                })
            })
            .collect()
    }

    async fn shoot_day_report(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> Result<Vec<ShootDayRow>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT ss.actual_order, ss.scene_id, ss.status, ss.start_dt, ss.end_dt,
                   ss.notes, ss.continuity_photo_ids,
                   s.scene_number, s.script_day, s.location
            FROM projection_scene_shoot ss
            LEFT JOIN projection_scene s ON s.id = ss.scene_id
            WHERE ss.shooting_day_id = $1
            ORDER BY ss.actual_order ASC NULLS LAST
            "#,
        )
        .bind(shooting_day_id.0)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_shoot_day_row).collect()
    }

    async fn soll_ist_report(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> Result<SollIstReport, DomainError> {
        // Check wrapped_at for finality.
        let wrapped_at: Option<chrono::DateTime<chrono::Utc>> = sqlx::query_scalar(
            r#"
            SELECT wrapped_at
            FROM projection_shooting_day
            WHERE id = $1
            "#,
        )
        .bind(shooting_day_id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .flatten();

        let is_final = wrapped_at.is_some();

        // Fetch all scene-shoots for this day with their scene details.
        let rows = sqlx::query(
            r#"
            SELECT ss.scene_id, ss.planned_order, ss.actual_order, ss.status,
                   ss.start_dt, ss.end_dt,
                   s.scene_number, s.script_day, s.location
            FROM projection_scene_shoot ss
            LEFT JOIN projection_scene s ON s.id = ss.scene_id
            WHERE ss.shooting_day_id = $1
            ORDER BY ss.planned_order ASC
            "#,
        )
        .bind(shooting_day_id.0)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        // Collect scene_ids for reshoot candidate check.
        let scene_ids: Vec<Uuid> = rows
            .iter()
            .map(|r| r.try_get::<Uuid, _>("scene_id").unwrap())
            .collect();

        // For each scene, check if it has a Shot record on a *different* day.
        let reshot_scenes: Vec<Uuid> = if !scene_ids.is_empty() {
            sqlx::query_scalar(
                r#"
                SELECT DISTINCT ss2.scene_id
                FROM projection_scene_shoot ss2
                WHERE ss2.scene_id = ANY($1)
                  AND ss2.shooting_day_id != $2
                  AND ss2.status = 'Shot'
                "#,
            )
            .bind(&scene_ids)
            .bind(shooting_day_id.0)
            .fetch_all(&self.pool)
            .await
            .map_err(|e| DomainError::Conflict(e.to_string()))?
        } else {
            vec![]
        };

        let diff_rows: Vec<SollIstDiffRow> = rows
            .into_iter()
            .map(|row| {
                let scene_id: Uuid = row.try_get("scene_id").map_err(map_err)?;
                let planned_str: String = row.try_get("planned_order").map_err(map_err)?;
                let actual_str: Option<String> = row.try_get("actual_order").map_err(map_err)?;
                let status_str: String = row.try_get("status").map_err(map_err)?;
                let start_dt: Option<chrono::DateTime<chrono::Utc>> =
                    row.try_get("start_dt").map_err(map_err)?;

                let planned_order = Some(
                    LexicalSortKey::new(planned_str)
                        .map_err(|e| DomainError::Conflict(e.to_string()))?,
                );
                let actual_order = actual_str
                    .map(LexicalSortKey::new)
                    .transpose()
                    .map_err(|e| DomainError::Conflict(e.to_string()))?;

                let status = parse_status(&status_str)?;
                let is_skipped = status == SceneShootStatus::Skipped;
                let missing = actual_order.is_none()
                    && start_dt.is_none()
                    && status != SceneShootStatus::Shot;
                let moved = match (&planned_order, &actual_order) {
                    (Some(p), Some(a)) => p != a,
                    _ => false,
                };
                let reshot_candidate = reshot_scenes.contains(&scene_id);

                Ok(SollIstDiffRow {
                    scene_id,
                    scene_number: row
                        .try_get::<Option<i32>, _>("scene_number")
                        .map_err(map_err)?
                        .map(|v| v as u32),
                    script_day: row.try_get("script_day").map_err(map_err)?,
                    location: row.try_get("location").map_err(map_err)?,
                    planned_order,
                    actual_order,
                    moved,
                    missing,
                    skipped: is_skipped,
                    reshot_candidate,
                })
            })
            .collect::<Result<Vec<_>, DomainError>>()?;

        Ok(SollIstReport {
            rows: diff_rows,
            is_final,
        })
    }
}

fn parse_status(s: &str) -> Result<SceneShootStatus, DomainError> {
    match s {
        "Planned" => Ok(SceneShootStatus::Planned),
        "Scheduled" => Ok(SceneShootStatus::Scheduled),
        "InProgress" => Ok(SceneShootStatus::InProgress),
        "Shot" => Ok(SceneShootStatus::Shot),
        "Skipped" => Ok(SceneShootStatus::Skipped),
        other => Err(DomainError::Conflict(format!("unknown status: {other}"))),
    }
}

fn map_shoot_day_row(row: sqlx::postgres::PgRow) -> Result<ShootDayRow, DomainError> {
    let actual_str: Option<String> = row.try_get("actual_order").map_err(map_err)?;
    let actual_order = actual_str
        .map(LexicalSortKey::new)
        .transpose()
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
    let status_str: String = row.try_get("status").map_err(map_err)?;
    let status = parse_status(&status_str)?;
    let notes_json: serde_json::Value = row.try_get("notes").map_err(map_err)?;
    let notes: Vec<SerializedNote> = serde_json::from_value(notes_json).unwrap_or_default();
    let continuity_ids: Vec<Uuid> = row.try_get("continuity_photo_ids").map_err(map_err)?;

    Ok(ShootDayRow {
        actual_order,
        scene_id: row.try_get("scene_id").map_err(map_err)?,
        scene_number: row
            .try_get::<Option<i32>, _>("scene_number")
            .map_err(map_err)?
            .map(|v| v as u32),
        script_day: row.try_get("script_day").map_err(map_err)?,
        location: row.try_get("location").map_err(map_err)?,
        status,
        start_dt: row.try_get("start_dt").map_err(map_err)?,
        end_dt: row.try_get("end_dt").map_err(map_err)?,
        notes,
        continuity_photo_ids: continuity_ids.into_iter().map(PhotoId::from_uuid).collect(),
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::Conflict(e.to_string())
}
