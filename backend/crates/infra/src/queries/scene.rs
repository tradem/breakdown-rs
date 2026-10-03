// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

//! `sqlx`-backed implementation of the `SceneRepository` port.

use breakdown_core::error::DomainError;
use breakdown_core::error_registry::SCENE_NOT_FOUND;
use breakdown_core::scene::events::SceneSource;
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::scene::views::{SceneCostumeBeatView, SceneView};
use breakdown_core::shared::{AggregateVersion, EpisodeId, ShootingDayId};
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

    /// Test-only access to the underlying pool (e.g. for Tier-4 round-trip
    /// tests that need to open transactions against the same pool the read
    /// adapter uses). Only compiled when the `test-support` feature is on
    /// (integration-tests crate); never in default builds.
    #[cfg(feature = "test-support")]
    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}

/// Issue #550: the scene queries used to join `projection_scene_character`
/// and `projection_scene_shooting_day` side-by-side and aggregate each list
/// with a bare `array_agg`. Two independent one-to-many joins multiply
/// (`c·d` rows; `c·c·d` in `scenes_by_character`), so every element was
/// repeated once per multiplied row and `assigned_characters` /
/// `shooting_day_ids` came back duplicated. Both pivots have composite
/// primary keys that already rule out duplicate rows, so the queries below
/// read the lists through correlated scalar subqueries instead: fan-out-free
/// by construction, with no `array_agg(DISTINCT …)` band-aid over a broken
/// join, and no `GROUP BY`.
impl SceneRepository for SceneRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<SceneView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT
                s.id,
                s.episode_id,
                s.scene_number,
                s.location,
                s.mood,
                s.is_schedule_set,
                s.summary,
                s.script_day,
                s.source,
                s.version,
                s.updated_at,
                COALESCE((
                    SELECT array_agg(psc.character_id ORDER BY psc.character_id)
                    FROM projection_scene_character psc
                    WHERE psc.scene_id = s.id
                ), ARRAY[]::uuid[]) AS assigned_characters,
                COALESCE((
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'character_id', psca.character_id,
                            'character_name', ch.name,
                            'costume_id', psca.costume_id,
                            'costume_category_id', co.category_id,
                            'costume_category_name', co.category_name,
                            'order', psca."order",
                            'note', psca.note
                        ) ORDER BY psca.character_id, psca."order"
                    )
                    FROM projection_scene_costume_assignment psca
                    LEFT JOIN projection_character ch ON ch.id = psca.character_id
                    LEFT JOIN projection_costume co ON co.id = psca.costume_id
                    WHERE psca.scene_id = s.id
                ), '[]'::jsonb) AS costume_beats,
                COALESCE((
                    SELECT array_agg(pssd.shooting_day_id ORDER BY pssd.shooting_day_id)
                    FROM projection_scene_shooting_day pssd
                    WHERE pssd.scene_id = s.id
                ), ARRAY[]::uuid[]) AS shooting_day_ids
            FROM projection_scene s
            WHERE s.id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::conflict(e.to_string()))?
        .ok_or(DomainError::NotFound {
            code: &SCENE_NOT_FOUND,
            resource: "scene",
            id,
        })?;

        map_scene_row(row)
    }

    async fn list_by_episode(
        &self,
        episode_id: EpisodeId,
        limit: i64,
        offset: i64,
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
                s.script_day,
                s.source,
                s.version,
                s.updated_at,
                COALESCE((
                    SELECT array_agg(psc.character_id ORDER BY psc.character_id)
                    FROM projection_scene_character psc
                    WHERE psc.scene_id = s.id
                ), ARRAY[]::uuid[]) AS assigned_characters,
                COALESCE((
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'character_id', psca.character_id,
                            'character_name', ch.name,
                            'costume_id', psca.costume_id,
                            'costume_category_id', co.category_id,
                            'costume_category_name', co.category_name,
                            'order', psca."order",
                            'note', psca.note
                        ) ORDER BY psca.character_id, psca."order"
                    )
                    FROM projection_scene_costume_assignment psca
                    LEFT JOIN projection_character ch ON ch.id = psca.character_id
                    LEFT JOIN projection_costume co ON co.id = psca.costume_id
                    WHERE psca.scene_id = s.id
                ), '[]'::jsonb) AS costume_beats,
                COALESCE((
                    SELECT array_agg(pssd.shooting_day_id ORDER BY pssd.shooting_day_id)
                    FROM projection_scene_shooting_day pssd
                    WHERE pssd.scene_id = s.id
                ), ARRAY[]::uuid[]) AS shooting_day_ids
            FROM projection_scene s
            WHERE s.episode_id = $1
            ORDER BY s.scene_number, s.updated_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(episode_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::conflict(e.to_string()))?;

        rows.into_iter().map(map_scene_row).collect()
    }

    async fn scenes_by_character(&self, character_id: Uuid) -> Result<Vec<SceneView>, DomainError> {
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
                s.script_day,
                s.source,
                s.version,
                s.updated_at,
                COALESCE((
                    SELECT array_agg(psc.character_id ORDER BY psc.character_id)
                    FROM projection_scene_character psc
                    WHERE psc.scene_id = s.id
                ), ARRAY[]::uuid[]) AS assigned_characters,
                COALESCE((
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'character_id', psca.character_id,
                            'character_name', ch.name,
                            'costume_id', psca.costume_id,
                            'costume_category_id', co.category_id,
                            'costume_category_name', co.category_name,
                            'order', psca."order",
                            'note', psca.note
                        ) ORDER BY psca.character_id, psca."order"
                    )
                    FROM projection_scene_costume_assignment psca
                    LEFT JOIN projection_character ch ON ch.id = psca.character_id
                    LEFT JOIN projection_costume co ON co.id = psca.costume_id
                    WHERE psca.scene_id = s.id
                ), '[]'::jsonb) AS costume_beats,
                COALESCE((
                    SELECT array_agg(pssd.shooting_day_id ORDER BY pssd.shooting_day_id)
                    FROM projection_scene_shooting_day pssd
                    WHERE pssd.scene_id = s.id
                ), ARRAY[]::uuid[]) AS shooting_day_ids
            FROM projection_scene s
            WHERE EXISTS (
                SELECT 1 FROM projection_scene_character psc
                WHERE psc.scene_id = s.id AND psc.character_id = $1
            )
            ORDER BY s.scene_number, s.updated_at DESC
            "#,
        )
        .bind(character_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::conflict(e.to_string()))?;

        rows.into_iter().map(map_scene_row).collect()
    }
}

fn map_scene_row(row: sqlx::postgres::PgRow) -> Result<SceneView, DomainError> {
    let costume_beats_json: serde_json::Value = row.try_get("costume_beats").map_err(map_err)?;
    let costume_beats: Vec<SceneCostumeBeatView> =
        serde_json::from_value(costume_beats_json.clone()).map_err(|e| {
            DomainError::conflict(format!(
                "failed to deserialize scene costume beats from projection row: {e}; json={costume_beats_json}"
            ))
        })?;
    let scene_number: Option<i32> = row.try_get("scene_number").map_err(map_err)?;
    let summary: Option<String> = row.try_get("summary").map_err(map_err)?;
    let script_day: Option<String> = row.try_get("script_day").map_err(map_err)?;
    let shooting_day_ids: Vec<Uuid> = row.try_get("shooting_day_ids").map_err(map_err)?;
    let source_json: serde_json::Value = row.try_get("source").map_err(map_err)?;
    let source = serde_json::from_value::<SceneSource>(source_json.clone()).map_err(|e| {
        DomainError::conflict(format!(
            "failed to deserialize scene provenance from projection row: {e}; json={source_json}"
        ))
    })?;
    Ok(SceneView {
        id: row.try_get("id").map_err(map_err)?,
        episode_id: EpisodeId(row.try_get("episode_id").map_err(map_err)?),
        scene_number: scene_number.map(|n| n as u32),
        location: row.try_get("location").map_err(map_err)?,
        mood: row.try_get("mood").map_err(map_err)?,
        is_schedule_set: row.try_get("is_schedule_set").map_err(map_err)?,
        summary,
        script_day,
        shooting_day_ids: shooting_day_ids.into_iter().map(ShootingDayId).collect(),
        assigned_characters: row.try_get("assigned_characters").map_err(map_err)?,
        costume_beats,
        source: Some(source),
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::conflict(e.to_string())
}
