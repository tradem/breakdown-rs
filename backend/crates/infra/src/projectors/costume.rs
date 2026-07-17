// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Costume projection handler: `CostumeEvent` -> `projection_costume` + details + photos.

use breakdown_core::costume::aggregate::CostumeAggregate;
use breakdown_core::costume::events::CostumeEvent;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `CostumeAggregate`.
#[derive(Clone, Default, Debug)]
pub struct CostumeProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for CostumeProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<CostumeAggregate, Transaction<'a, Postgres>> for CostumeProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<CostumeEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            CostumeEvent::CostumeCreated {
                id,
                character_id,
                notes,
                details,
                photos,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_costume
                        (id, character_id, notes, version, updated_at)
                    VALUES ($1, $2, $3, $4, $5)
                    ON CONFLICT (id) DO UPDATE SET
                        character_id = EXCLUDED.character_id,
                        notes = EXCLUDED.notes,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(character_id)
                .bind(notes)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;

                for detail in details {
                    sqlx::query(
                        r#"
                        INSERT INTO projection_costume_detail (costume_id, detail_id, text)
                        VALUES ($1, $2, $3)
                        ON CONFLICT (costume_id, detail_id) DO UPDATE SET
                            text = EXCLUDED.text
                        "#,
                    )
                    .bind(id)
                    .bind(detail.id)
                    .bind(detail.text)
                    .execute(&mut **ctx)
                    .await?;
                }

                for photo_id in photos {
                    sqlx::query(
                        r#"
                        INSERT INTO projection_costume_photo (costume_id, photo_id)
                        VALUES ($1, $2)
                        ON CONFLICT (costume_id, photo_id) DO NOTHING
                        "#,
                    )
                    .bind(id)
                    .bind(photo_id)
                    .execute(&mut **ctx)
                    .await?;
                }
            }
            CostumeEvent::CostumeNotesUpdated { id, notes, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_costume
                    SET notes = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(notes)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            CostumeEvent::CostumeAssignedToCharacter {
                id,
                character_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_costume
                    SET character_id = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(character_id)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            CostumeEvent::CostumeUnassigned { id, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_costume
                    SET character_id = NULL, version = $2, updated_at = $3
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            CostumeEvent::DetailAdded {
                id,
                detail,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_costume_detail (costume_id, detail_id, text)
                    VALUES ($1, $2, $3)
                    ON CONFLICT (costume_id, detail_id) DO UPDATE SET
                        text = EXCLUDED.text
                    "#,
                )
                .bind(id)
                .bind(detail.id)
                .bind(detail.text)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            CostumeEvent::DetailRemoved {
                id,
                detail_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_costume_detail
                    WHERE costume_id = $1 AND detail_id = $2
                    "#,
                )
                .bind(id)
                .bind(detail_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            CostumeEvent::PhotoLinked {
                id,
                photo_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_costume_photo (costume_id, photo_id)
                    VALUES ($1, $2)
                    ON CONFLICT (costume_id, photo_id) DO NOTHING
                    "#,
                )
                .bind(id)
                .bind(photo_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            CostumeEvent::PhotoUnlinked {
                id,
                photo_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_costume_photo
                    WHERE costume_id = $1 AND photo_id = $2
                    "#,
                )
                .bind(id)
                .bind(photo_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
        }

        Ok(())
    }
}

impl CostumeProjector {
    async fn touch_parent<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        id: Uuid,
        version: i64,
        updated_at: chrono::DateTime<chrono::Utc>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            UPDATE projection_costume
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
