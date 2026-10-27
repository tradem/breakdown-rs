// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Outfit projection handler: `OutfitEvent` -> `projection_outfit` + pieces
//! and photos.
//!
//! `projection_outfit_piece` deliberately holds **no** foreign key to
//! `projection_piece`: stream replay order across aggregates is not guaranteed,
//! and a missing piece row must never poison the projector (the read model
//! resolves the piece data best-effort). `position` is taken from the event so
//! the projector never has to derive ordering from projection state. All
//! statements are version-guarded and idempotent.

use super::PROJECTOR_VERSION;
use breakdown_core::outfit::aggregate::OutfitAggregate;
use breakdown_core::outfit::events::OutfitEvent;
use breakdown_core::shared::EventMetadata;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `OutfitAggregate`.
#[derive(Clone, Default, Debug)]
pub struct OutfitProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for OutfitProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<OutfitAggregate, Transaction<'a, Postgres>> for OutfitProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<OutfitEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            OutfitEvent::OutfitCreated {
                id,
                character_id,
                name,
                piece_ids,
                photos,
                notes,
                version,
            } => {
                let version = version.0 as i64;
                Self::upsert_outfit(
                    ctx,
                    id,
                    character_id,
                    None,
                    &name,
                    &notes,
                    version,
                    updated_at,
                )
                .await?;

                for (position, piece_id) in piece_ids.iter().enumerate() {
                    let position = i32::try_from(position).unwrap_or(i32::MAX);
                    Self::insert_piece(ctx, id, *piece_id, position).await?;
                }

                for photo_id in photos {
                    sqlx::query(
                        r#"
                        INSERT INTO projection_outfit_photo (outfit_id, photo_id)
                        VALUES ($1, $2)
                        ON CONFLICT (outfit_id, photo_id) DO NOTHING
                        "#,
                    )
                    .bind(id)
                    .bind(photo_id)
                    .execute(&mut **ctx)
                    .await?;
                }
            }
            OutfitEvent::OutfitVariantCreated {
                id,
                source_outfit_id,
                character_id,
                name,
                piece_ids,
                photos,
                notes,
                version,
            } => {
                let version = version.0 as i64;
                Self::upsert_outfit(
                    ctx,
                    id,
                    character_id,
                    Some(source_outfit_id),
                    &name,
                    &notes,
                    version,
                    updated_at,
                )
                .await?;

                for (position, piece_id) in piece_ids.iter().enumerate() {
                    let position = i32::try_from(position).unwrap_or(i32::MAX);
                    Self::insert_piece(ctx, id, *piece_id, position).await?;
                }

                for photo_id in photos {
                    sqlx::query(
                        r#"
                        INSERT INTO projection_outfit_photo (outfit_id, photo_id)
                        VALUES ($1, $2)
                        ON CONFLICT (outfit_id, photo_id) DO NOTHING
                        "#,
                    )
                    .bind(id)
                    .bind(photo_id)
                    .execute(&mut **ctx)
                    .await?;
                }
            }
            OutfitEvent::OutfitRenamed { id, name, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_outfit
                    SET name = $2, version = $3, updated_at = $4
                    WHERE id = $1 AND version < $3
                    "#,
                )
                .bind(id)
                .bind(name)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            OutfitEvent::OutfitNotesUpdated { id, notes, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_outfit
                    SET notes = $2, version = $3, updated_at = $4
                    WHERE id = $1 AND version < $3
                    "#,
                )
                .bind(id)
                .bind(notes)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            OutfitEvent::OutfitPieceAdded {
                id,
                piece_id,
                position,
                version,
            } => {
                let version = version.0 as i64;
                let position = i32::try_from(position).unwrap_or(i32::MAX);
                Self::insert_piece(ctx, id, piece_id, position).await?;
                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            OutfitEvent::OutfitPieceRemoved {
                id,
                piece_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_outfit_piece
                    WHERE outfit_id = $1 AND piece_id = $2
                    "#,
                )
                .bind(id)
                .bind(piece_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            OutfitEvent::OutfitPhotoLinked {
                id,
                photo_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_outfit_photo (outfit_id, photo_id)
                    VALUES ($1, $2)
                    ON CONFLICT (outfit_id, photo_id) DO NOTHING
                    "#,
                )
                .bind(id)
                .bind(photo_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            OutfitEvent::OutfitPhotoUnlinked {
                id,
                photo_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_outfit_photo
                    WHERE outfit_id = $1 AND photo_id = $2
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

impl OutfitProjector {
    #[allow(clippy::too_many_arguments)]
    async fn upsert_outfit<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        id: Uuid,
        character_id: Uuid,
        variant_of: Option<Uuid>,
        name: &str,
        notes: &str,
        version: i64,
        updated_at: chrono::DateTime<chrono::Utc>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO projection_outfit
                (id, character_id, name, variant_of, notes, version,
                 projector_version, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (id) DO UPDATE SET
                character_id = EXCLUDED.character_id,
                name = EXCLUDED.name,
                variant_of = EXCLUDED.variant_of,
                notes = EXCLUDED.notes,
                version = EXCLUDED.version,
                projector_version = EXCLUDED.projector_version,
                updated_at = EXCLUDED.updated_at
            WHERE projection_outfit.version < EXCLUDED.version
            "#,
        )
        .bind(id)
        .bind(character_id)
        .bind(name)
        .bind(variant_of)
        .bind(notes)
        .bind(version)
        .bind(PROJECTOR_VERSION)
        .bind(updated_at)
        .execute(&mut **ctx)
        .await?;
        Ok(())
    }

    async fn insert_piece<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        outfit_id: Uuid,
        piece_id: Uuid,
        position: i32,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO projection_outfit_piece (outfit_id, piece_id, position)
            VALUES ($1, $2, $3)
            ON CONFLICT (outfit_id, piece_id) DO NOTHING
            "#,
        )
        .bind(outfit_id)
        .bind(piece_id)
        .bind(position)
        .execute(&mut **ctx)
        .await?;
        Ok(())
    }

    async fn touch_parent<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        id: Uuid,
        version: i64,
        updated_at: chrono::DateTime<chrono::Utc>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            UPDATE projection_outfit
            SET version = $2, updated_at = $3
            WHERE id = $1 AND version < $2
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
