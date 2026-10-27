// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! `sqlx`-backed implementation of the `CharacterRepository` port.

use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::ports::CharacterRepository;
use breakdown_core::character::views::{
    AppearanceOutfitView, CharacterAppearanceView, CharacterView,
};
use breakdown_core::error::DomainError;
use breakdown_core::error_registry::CHARACTER_NOT_FOUND;
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
        .map_err(|e| DomainError::conflict(e.to_string()))?
        .ok_or(DomainError::NotFound {
            code: &CHARACTER_NOT_FOUND,
            resource: "character",
            id,
        })?;

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
        .map_err(|e| DomainError::conflict(e.to_string()))?;

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
        .map_err(|e| DomainError::conflict(e.to_string()))?;

        rows.into_iter().map(map_character_row).collect()
    }

    async fn character_appearances(
        &self,
        character_id: Uuid,
    ) -> Result<Vec<CharacterAppearanceView>, DomainError> {
        // Issue #621: script-order appearances of one character, each carrying
        // that character's own ordered outfit beats. `scene_number` is
        // episode-local, so the order is episode number first, then scene
        // number (`episode.number` is NOT NULL; the LEFT JOIN + NULLS LAST only
        // guards a lagging episode projection, which must not drop the scene).
        // The outfit list is a correlated scalar subquery keyed on
        // `(scene_id, character_id)` so the one-to-many join cannot multiply
        // the scene rows (issue #550 pattern); `COALESCE` keeps a scene with no
        // beat for this character as an empty list. `s.id` is the deterministic
        // tie-break.
        let rows = sqlx::query(
            r#"
            SELECT
                s.id AS scene_id,
                s.episode_id,
                s.scene_number,
                s.summary,
                COALESCE((
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'outfit_id', psoa.outfit_id,
                            'outfit_name', o.name,
                            'variant_of', o.variant_of,
                            'order', psoa."order",
                            'note', psoa.note
                        ) ORDER BY psoa."order"
                    )
                    FROM projection_scene_outfit_assignment psoa
                    LEFT JOIN projection_outfit o ON o.id = psoa.outfit_id
                    WHERE psoa.scene_id = s.id AND psoa.character_id = $1
                ), '[]'::jsonb) AS outfits
            FROM projection_scene_character psc
            JOIN projection_scene s ON s.id = psc.scene_id
            LEFT JOIN projection_episode e ON e.id = s.episode_id
            WHERE psc.character_id = $1
            ORDER BY e.number NULLS LAST, s.episode_id, s.scene_number NULLS LAST, s.id
            "#,
        )
        .bind(character_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::conflict(e.to_string()))?;

        rows.into_iter().map(map_appearance_row).collect()
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

fn map_appearance_row(row: sqlx::postgres::PgRow) -> Result<CharacterAppearanceView, DomainError> {
    let outfits_json: serde_json::Value = row.try_get("outfits").map_err(map_err)?;
    let outfits: Vec<AppearanceOutfitView> =
        serde_json::from_value(outfits_json.clone()).map_err(|e| {
            DomainError::internal(format!(
                "failed to deserialize character appearance outfits from projection row: {e}; json={outfits_json}"
            ))
        })?;
    let scene_number: Option<i32> = row.try_get("scene_number").map_err(map_err)?;

    Ok(CharacterAppearanceView {
        scene_id: row.try_get("scene_id").map_err(map_err)?,
        episode_id: EpisodeId(row.try_get("episode_id").map_err(map_err)?),
        scene_number: scene_number.map(|n| n as u32),
        synopsis: row.try_get("summary").map_err(map_err)?,
        outfits,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::conflict(e.to_string())
}
