// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kwaipilot/kat-coder-air-v2.5 (openrouter)

//! SceneShoot projection handler: `SceneShootEvent` -> `projection_scene_shoot`.

use breakdown_core::scene_shoot::aggregate::SceneShootAggregate;
use breakdown_core::scene_shoot::events::SceneShootEvent;
use breakdown_core::shared::SceneShootId;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};

/// Idempotent projector for the `SceneShootAggregate`.
#[derive(Clone, Default, Debug)]
pub struct SceneShootProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for SceneShootProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<SceneShootAggregate, Transaction<'a, Postgres>>
    for SceneShootProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: SceneShootId,
        event: Event<SceneShootEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            SceneShootEvent::SceneShootPlanned {
                id,
                scene_id,
                shooting_day_id,
                planned_order,
                status,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_scene_shoot
                        (id, scene_id, shooting_day_id, planned_order, status, version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7)
                    ON CONFLICT (id) DO UPDATE SET
                        scene_id = EXCLUDED.scene_id,
                        shooting_day_id = EXCLUDED.shooting_day_id,
                        planned_order = EXCLUDED.planned_order,
                        status = EXCLUDED.status,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id.0)
                .bind(scene_id)
                .bind(shooting_day_id.0)
                .bind(planned_order.0)
                .bind(status.as_str())
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::SceneShootReplanned {
                id,
                planned_order,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET planned_order = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(planned_order.0)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::SceneShootStarted {
                id, start_dt, version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET start_dt = $2, status = 'InProgress', version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(start_dt)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::SceneShootActualOrderSet {
                id,
                actual_order,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET actual_order = $2,
                        status = CASE WHEN status = 'Planned' OR status = 'Scheduled'
                            THEN 'InProgress' ELSE status END,
                        version = $3,
                        updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(actual_order.0)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::SceneShootFinished {
                id, end_dt, version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET end_dt = $2, status = 'Shot', version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(end_dt)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::SceneShootSkipped { id, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET status = 'Skipped', version = $2, updated_at = $3
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::ShootDayNoteAdded {
                id,
                note_id,
                body,
                version,
                ..
            } => {
                let version = version.0 as i64;
                // Append the note to the JSONB notes array.
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET notes = notes || $2::jsonb,
                        version = $3,
                        updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(
                    serde_json::json!([{"id": note_id, "body": body}]).to_string(),
                )
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::ShootDayNoteUpdated {
                id,
                note_id,
                body,
                version,
            } => {
                let version = version.0 as i64;
                // Find and replace the note body by note_id in the JSONB array.
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET notes = (
                        SELECT jsonb_agg(
                            CASE
                                WHEN elem->>'id' = $2 THEN jsonb_build_object('id', $2, 'body', $3)
                                ELSE elem
                            END
                        )
                        FROM jsonb_array_elements(notes) AS elem
                    ),
                    version = $4,
                    updated_at = $5
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(note_id.to_string())
                .bind(&body)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::ShootDayNoteRemoved { id, note_id, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET notes = (
                        SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
                        FROM jsonb_array_elements(notes) AS elem
                        WHERE elem->>'id' != $2
                    ),
                    version = $3,
                    updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(note_id.to_string())
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::ContinuityPhotoLinked {
                id, photo_id, version,
            } => {
                let version = version.0 as i64;
                // Append photo_id to the continuity_photo_ids array.
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET continuity_photo_ids = array_append(
                            COALESCE(continuity_photo_ids, '{}'),
                            $2
                        ),
                        version = $3,
                        updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(photo_id.0)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SceneShootEvent::ContinuityPhotoUnlinked {
                id, photo_id, version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_scene_shoot
                    SET continuity_photo_ids = array_remove(
                            COALESCE(continuity_photo_ids, '{}'),
                            $2
                        ),
                        version = $3,
                        updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(photo_id.0)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}
