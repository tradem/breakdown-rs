// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! sqlx-backed implementation of the `SceneShootReportRepository` port.

use breakdown_core::error::DomainError;
use breakdown_core::scene_shoot::ports::SceneShootReportRepository;
use breakdown_core::scene_shoot::views::{
    AggregateSollIstDiffRow, AggregateSollIstReport, DispoRow, SerializedNote, ShootDayRow,
    SollIstDiffRow, SollIstReport,
};
use breakdown_core::shared::SceneShootStatus;
use breakdown_core::shared::{EpisodeId, LexicalSortKey, PhotoId, SeasonId, ShootingDayId};
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
        .map_err(|e| DomainError::conflict(e.to_string()))?;

        rows.into_iter()
            .map(|row| {
                let order_str: String = row.try_get("planned_order").map_err(map_err)?;
                Ok(DispoRow {
                    planned_order: LexicalSortKey::new(order_str)
                        .map_err(|e| DomainError::conflict(e.to_string()))?,
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
        .map_err(|e| DomainError::conflict(e.to_string()))?;

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
        .map_err(|e| DomainError::conflict(e.to_string()))?
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
        .map_err(|e| DomainError::conflict(e.to_string()))?;

        // Collect scene_ids for reshoot candidate check.
        let scene_ids: Vec<Uuid> = rows
            .iter()
            .map(|r: &sqlx::postgres::PgRow| {
                r.try_get::<Uuid, _>("scene_id")
                    .map_err(|e| anyhow::anyhow!("Failed to read scene_id: {e}"))
            })
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| DomainError::conflict(e.to_string()))?;

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
            .map_err(|e| DomainError::conflict(e.to_string()))?
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
                        .map_err(|e| DomainError::conflict(e.to_string()))?,
                );
                let actual_order = actual_str
                    .map(LexicalSortKey::new)
                    .transpose()
                    .map_err(|e| DomainError::conflict(e.to_string()))?;

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

    async fn season_soll_ist_report(
        &self,
        season_id: SeasonId,
    ) -> Result<AggregateSollIstReport, DomainError> {
        // Day summary: non-archived days of the season, wrapped-vs-total.
        // `count(*)` always returns exactly one row (zero scopes yield 0/0,
        // never vacuous finality — issue #571 decision 3).
        let summary = sqlx::query(
            r#"
            SELECT count(*)::BIGINT AS total,
                   count(*) FILTER (WHERE d.wrapped_at IS NOT NULL)::BIGINT AS wrapped
            FROM projection_shooting_day d
            JOIN projection_episode e ON e.id = d.episode_id
            JOIN projection_block b ON b.id = e.block_id
            WHERE b.season_id = $1 AND d.archived = false
            "#,
        )
        .bind(season_id.0)
        .fetch_one(&self.pool)
        .await
        .map_err(map_err)?;
        let total = summary.try_get::<i64, _>("total").map_err(map_err)?;
        let wrapped = summary.try_get::<i64, _>("wrapped").map_err(map_err)?;

        // All scene-shoot rows of the season, day-scoped flags applied per row.
        let rows = sqlx::query(
            r#"
            SELECT ss.scene_id, ss.planned_order, ss.actual_order, ss.status,
                   ss.start_dt, ss.end_dt,
                   s.scene_number, s.script_day, s.location,
                   ss.shooting_day_id, d.label AS shooting_day_label
            FROM projection_scene_shoot ss
            JOIN projection_shooting_day d ON d.id = ss.shooting_day_id
            LEFT JOIN projection_scene s ON s.id = ss.scene_id
            JOIN projection_episode e ON e.id = d.episode_id
            JOIN projection_block b ON b.id = e.block_id
            WHERE b.season_id = $1 AND d.archived = false
            ORDER BY d.order_key ASC, ss.planned_order ASC
            "#,
        )
        .bind(season_id.0)
        .fetch_all(&self.pool)
        .await
        .map_err(map_err)?;

        build_aggregate_report(rows, total, wrapped)
    }

    async fn episode_soll_ist_report(
        &self,
        episode_id: EpisodeId,
    ) -> Result<AggregateSollIstReport, DomainError> {
        // Day summary: non-archived days of the episode (see season method).
        let summary = sqlx::query(
            r#"
            SELECT count(*)::BIGINT AS total,
                   count(*) FILTER (WHERE d.wrapped_at IS NOT NULL)::BIGINT AS wrapped
            FROM projection_shooting_day d
            WHERE d.episode_id = $1 AND d.archived = false
            "#,
        )
        .bind(episode_id.0)
        .fetch_one(&self.pool)
        .await
        .map_err(map_err)?;
        let total = summary.try_get::<i64, _>("total").map_err(map_err)?;
        let wrapped = summary.try_get::<i64, _>("wrapped").map_err(map_err)?;

        // All scene-shoot rows of the episode.
        let rows = sqlx::query(
            r#"
            SELECT ss.scene_id, ss.planned_order, ss.actual_order, ss.status,
                   ss.start_dt, ss.end_dt,
                   s.scene_number, s.script_day, s.location,
                   ss.shooting_day_id, d.label AS shooting_day_label
            FROM projection_scene_shoot ss
            JOIN projection_shooting_day d ON d.id = ss.shooting_day_id
            LEFT JOIN projection_scene s ON s.id = ss.scene_id
            WHERE d.episode_id = $1 AND d.archived = false
            ORDER BY d.order_key ASC, ss.planned_order ASC
            "#,
        )
        .bind(episode_id.0)
        .fetch_all(&self.pool)
        .await
        .map_err(map_err)?;

        build_aggregate_report(rows, total, wrapped)
    }
}

/// Assemble the aggregate report from fetched row rows.
///
/// `reshot_candidate` is computed **from the fetched set itself**: the set is
/// precisely the report scope, so a scene has a `Shot` record on another day
/// *within the scope* iff another fetched row says so. `is_final` follows the
/// issue-#571 decision: at least one non-archived day AND every one wrapped.
fn build_aggregate_report(
    rows: Vec<sqlx::postgres::PgRow>,
    total: i64,
    wrapped: i64,
) -> Result<AggregateSollIstReport, DomainError> {
    // (scene_id, status == Shot) pairs for the reshot check, skipping the
    // row's own day at comparison time.
    let shot_pairs: Vec<(Uuid, Uuid)> = rows
        .iter()
        .filter_map(|r| {
            let status: String = r.try_get("status").ok()?;
            if status != "Shot" {
                return None;
            }
            Some((
                r.try_get::<Uuid, _>("scene_id").ok()?,
                r.try_get::<Uuid, _>("shooting_day_id").ok()?,
            ))
        })
        .collect();

    let diff_rows: Vec<AggregateSollIstDiffRow> = rows
        .into_iter()
        .map(|row| {
            let scene_id: Uuid = row.try_get("scene_id").map_err(map_err)?;
            let shooting_day_id: Uuid = row.try_get("shooting_day_id").map_err(map_err)?;
            let shooting_day_label: Option<String> =
                row.try_get("shooting_day_label").map_err(map_err)?;
            let planned_str: String = row.try_get("planned_order").map_err(map_err)?;
            let actual_str: Option<String> = row.try_get("actual_order").map_err(map_err)?;
            let status_str: String = row.try_get("status").map_err(map_err)?;
            let start_dt: Option<chrono::DateTime<chrono::Utc>> =
                row.try_get("start_dt").map_err(map_err)?;

            let planned_order = Some(
                LexicalSortKey::new(planned_str)
                    .map_err(|e| DomainError::conflict(e.to_string()))?,
            );
            let actual_order = actual_str
                .map(LexicalSortKey::new)
                .transpose()
                .map_err(|e| DomainError::conflict(e.to_string()))?;

            let status = parse_status(&status_str)?;
            let is_skipped = status == SceneShootStatus::Skipped;
            let missing =
                actual_order.is_none() && start_dt.is_none() && status != SceneShootStatus::Shot;
            let moved = match (&planned_order, &actual_order) {
                (Some(p), Some(a)) => p != a,
                _ => false,
            };
            let reshot_candidate = shot_pairs
                .iter()
                .any(|(s, d)| *s == scene_id && *d != shooting_day_id);

            Ok(AggregateSollIstDiffRow {
                scene_id,
                shooting_day_id: ShootingDayId::from_uuid(shooting_day_id),
                shooting_day_label,
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

    let total = u32::try_from(total).unwrap_or(u32::MAX); // sat-guard: i64→u32
    let wrapped = u32::try_from(wrapped).unwrap_or(u32::MAX);
    let is_final = total >= 1 && wrapped == total;
    Ok(AggregateSollIstReport {
        rows: diff_rows,
        is_final,
        total_shooting_days: total,
        wrapped_shooting_days: wrapped,
    })
}

fn parse_status(s: &str) -> Result<SceneShootStatus, DomainError> {
    match s {
        "Planned" => Ok(SceneShootStatus::Planned),
        "Scheduled" => Ok(SceneShootStatus::Scheduled),
        "InProgress" => Ok(SceneShootStatus::InProgress),
        "Shot" => Ok(SceneShootStatus::Shot),
        "Skipped" => Ok(SceneShootStatus::Skipped),
        other => Err(DomainError::conflict(format!("unknown status: {other}"))),
    }
}

fn map_shoot_day_row(row: sqlx::postgres::PgRow) -> Result<ShootDayRow, DomainError> {
    let actual_str: Option<String> = row.try_get("actual_order").map_err(map_err)?;
    let actual_order = actual_str
        .map(LexicalSortKey::new)
        .transpose()
        .map_err(|e| DomainError::conflict(e.to_string()))?;
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
    DomainError::conflict(e.to_string())
}
