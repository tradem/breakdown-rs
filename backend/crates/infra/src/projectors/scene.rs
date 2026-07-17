// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Scene projection handler: `SceneEvent` -> `projection_scene` + `projection_scene_character`.

use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::events::SceneEvent;
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
        event: Event<SceneEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            SceneEvent::SceneCreated {
                id,
                episode_id,
                details,
                assigned_characters,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_scene
                        (id, episode_id, scene_number, location, mood, is_schedule_set, version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    ON CONFLICT (id) DO UPDATE SET
                        episode_id = EXCLUDED.episode_id,
                        scene_number = EXCLUDED.scene_number,
                        location = EXCLUDED.location,
                        mood = EXCLUDED.mood,
                        is_schedule_set = EXCLUDED.is_schedule_set,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(episode_id.0)
                .bind(details.scene_number.map(|n| n as i32))
                .bind(details.location)
                .bind(details.mood)
                .bind(details.is_schedule_set)
                .bind(version)
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
                        version = $6,
                        updated_at = $7
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(details.scene_number.map(|n| n as i32))
                .bind(details.location)
                .bind(details.mood)
                .bind(details.is_schedule_set)
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
