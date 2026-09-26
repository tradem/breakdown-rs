// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.6-35b (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Scene projection handler: `SceneEvent` -> `projection_scene` + `projection_scene_character`.

use super::PROJECTOR_VERSION;
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::events::SceneEvent;
use breakdown_core::shared::EventMetadata;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `SceneAggregate`.
#[derive(Clone, Default, Debug)]
pub struct SceneProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for SceneProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<SceneAggregate, Transaction<'a, Postgres>> for SceneProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<SceneEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            SceneEvent::SceneCreated {
                id,
                episode_id,
                details,
                assigned_characters,
                source,
                version,
            } => {
                let version = version.0 as i64;
                let source_json =
                    serde_json::to_value(&source).map_err(|_e| sqlx::Error::ColumnDecode {
                        index: "source".to_owned(),
                        source: Box::new(std::io::Error::other(
                            "SceneSource failed to serialize to projection JSON",
                        )),
                    })?;
                sqlx::query(
                    r#"
                    INSERT INTO projection_scene
                        (id, episode_id, scene_number, location, mood, is_schedule_set, summary, script_day, source, version, projector_version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                    ON CONFLICT (id) DO UPDATE SET
                        episode_id = EXCLUDED.episode_id,
                        scene_number = EXCLUDED.scene_number,
                        location = EXCLUDED.location,
                        mood = EXCLUDED.mood,
                        is_schedule_set = EXCLUDED.is_schedule_set,
                        summary = EXCLUDED.summary,
                        script_day = EXCLUDED.script_day,
                        source = EXCLUDED.source,
                        version = EXCLUDED.version,
                        projector_version = EXCLUDED.projector_version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(episode_id.0)
                .bind(details.scene_number.map(|n| n as i32))
                .bind(details.location)
                .bind(details.mood)
                .bind(details.is_schedule_set)
                .bind(details.summary)
                .bind(details.script_day)
                .bind(source_json)
                .bind(version)
                .bind(PROJECTOR_VERSION)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;

                for character_id in assigned_characters {
                    sqlx::query(
                        r#"
                        INSERT INTO projection_scene_character (scene_id, character_id, version)
                        VALUES ($1, $2, $3)
                        ON CONFLICT (scene_id, character_id) DO UPDATE SET
                            version = EXCLUDED.version
                        "#,
                    )
                    .bind(id)
                    .bind(character_id)
                    .bind(version)
                    .execute(&mut **ctx)
                    .await?;
                }
            }
            SceneEvent::SceneDetailsUpdated {
                id,
                details,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_scene
                    SET scene_number = $2,
                        location = $3,
                        mood = $4,
                        is_schedule_set = $5,
                        summary = $6,
                        script_day = $7,
                        version = $8,
                        updated_at = $9
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(details.scene_number.map(|n| n as i32))
                .bind(details.location)
                .bind(details.mood)
                .bind(details.is_schedule_set)
                .bind(details.summary)
                .bind(details.script_day)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneEvent::CharacterAssigned {
                id,
                character_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_scene_character (scene_id, character_id, version)
                    VALUES ($1, $2, $3)
                    ON CONFLICT (scene_id, character_id) DO UPDATE SET
                        version = EXCLUDED.version
                    "#,
                )
                .bind(id)
                .bind(character_id)
                .bind(version)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            SceneEvent::CharacterRemoved {
                id,
                character_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_scene_character
                    WHERE scene_id = $1 AND character_id = $2
                    "#,
                )
                .bind(id)
                .bind(character_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            SceneEvent::ShootingDayScheduled {
                id,
                shooting_day_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_scene_shooting_day (scene_id, shooting_day_id, version)
                    VALUES ($1, $2, $3)
                    ON CONFLICT (scene_id, shooting_day_id) DO UPDATE SET
                        version = EXCLUDED.version
                    "#,
                )
                .bind(id)
                .bind(shooting_day_id.0)
                .bind(version)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            SceneEvent::ShootingDayUnscheduled {
                id,
                shooting_day_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_scene_shooting_day
                    WHERE scene_id = $1 AND shooting_day_id = $2
                    "#,
                )
                .bind(id)
                .bind(shooting_day_id.0)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
        }

        Ok(())
    }
}

impl SceneProjector {
    async fn touch_parent<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        id: Uuid,
        version: i64,
        updated_at: chrono::DateTime<chrono::Utc>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            UPDATE projection_scene
            SET version = $2, updated_at = $3
            WHERE id = $1
            "#,
        )
        .bind(id)
        .bind(version)
        .bind(updated_at)
        .execute(&mut **ctx)
        .await?;
        Ok(())
    }
}
