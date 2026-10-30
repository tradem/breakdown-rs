// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Piece projection handler: `PieceEvent` -> `projection_piece` + repertoire,
//! details and photos.
//!
//! The piece is character-free (the character binding lives on `Outfit`), so
//! this projector writes no `character_id`. `category_name` is resolved
//! best-effort at write time (a dangling category reference stays `NULL` and
//! never fails the event). All statements are version-guarded and idempotent so
//! at-least-once redelivery cannot duplicate rows.

use super::PROJECTOR_VERSION;
use breakdown_core::piece::aggregate::PieceAggregate;
use breakdown_core::piece::events::PieceEvent;
use breakdown_core::shared::EventMetadata;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `PieceAggregate`.
#[derive(Clone, Default, Debug)]
pub struct PieceProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for PieceProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<PieceAggregate, Transaction<'a, Postgres>> for PieceProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<PieceEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            // Issue #770 (dev data reset): the delete removes the projection
            // row. Child tables hang off it with `ON DELETE CASCADE`, so a
            // single statement cleans the aggregate's own read-model surface;
            // no cross-aggregate cascade happens here on purpose (the reset
            // tool deletes children first, so every removed row is backed by a
            // real domain event).
            PieceEvent::PieceDeleted { id, .. } => {
                sqlx::query("DELETE FROM projection_piece WHERE id = $1")
                    .bind(id)
                    .execute(&mut **ctx)
                    .await?;
            }
            PieceEvent::PieceCreated {
                id,
                name,
                category_id,
                season_id,
                notes,
                details,
                photos,
                version,
            } => {
                let version = version.0 as i64;
                let category_name =
                    Self::resolve_category_name(ctx, category_id.map(|c| c.0)).await?;
                sqlx::query(
                    r#"
                    INSERT INTO projection_piece
                        (id, name, category_id, category_name, notes, version,
                         projector_version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    ON CONFLICT (id) DO UPDATE SET
                        name = EXCLUDED.name,
                        category_id = EXCLUDED.category_id,
                        category_name = EXCLUDED.category_name,
                        notes = EXCLUDED.notes,
                        version = EXCLUDED.version,
                        projector_version = EXCLUDED.projector_version,
                        updated_at = EXCLUDED.updated_at
                    WHERE projection_piece.version < EXCLUDED.version
                    "#,
                )
                .bind(id)
                .bind(&name)
                .bind(category_id.map(|c| c.0))
                .bind(category_name)
                .bind(notes)
                .bind(version)
                .bind(PROJECTOR_VERSION)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;

                // Repertoire binding: the piece joins the season's wardrobe
                // list. Idempotent via the PK; a piece created without a
                // season simply has an empty repertoire.
                if let Some(season_id) = season_id {
                    sqlx::query(
                        r#"
                        INSERT INTO projection_piece_season (piece_id, season_id)
                        VALUES ($1, $2)
                        ON CONFLICT (piece_id, season_id) DO NOTHING
                        "#,
                    )
                    .bind(id)
                    .bind(season_id)
                    .execute(&mut **ctx)
                    .await?;
                }

                for detail in details {
                    Self::upsert_detail(ctx, id, &detail).await?;
                }

                for photo_id in photos {
                    sqlx::query(
                        r#"
                        INSERT INTO projection_piece_photo (piece_id, photo_id)
                        VALUES ($1, $2)
                        ON CONFLICT (piece_id, photo_id) DO NOTHING
                        "#,
                    )
                    .bind(id)
                    .bind(photo_id)
                    .execute(&mut **ctx)
                    .await?;
                }
            }
            PieceEvent::PieceRenamed { id, name, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_piece
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
            PieceEvent::PieceAddedToSeason {
                id,
                season_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_piece_season (piece_id, season_id)
                    VALUES ($1, $2)
                    ON CONFLICT (piece_id, season_id) DO NOTHING
                    "#,
                )
                .bind(id)
                .bind(season_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            PieceEvent::PieceRemovedFromSeason {
                id,
                season_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_piece_season
                    WHERE piece_id = $1 AND season_id = $2
                    "#,
                )
                .bind(id)
                .bind(season_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            PieceEvent::PieceNotesUpdated { id, notes, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_piece
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
            PieceEvent::PieceDetailAdded {
                id,
                detail,
                version,
            } => {
                let version = version.0 as i64;
                Self::upsert_detail(ctx, id, &detail).await?;
                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            // An edit reuses the same upsert: `(piece_id, detail_id)` is the
            // conflict target, so the row is overwritten in place.
            PieceEvent::PieceDetailUpdated {
                id,
                detail,
                version,
            } => {
                let version = version.0 as i64;
                Self::upsert_detail(ctx, id, &detail).await?;
                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            PieceEvent::PieceDetailRemoved {
                id,
                detail_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_piece_detail
                    WHERE piece_id = $1 AND detail_id = $2
                    "#,
                )
                .bind(id)
                .bind(detail_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            PieceEvent::PiecePhotoLinked {
                id,
                photo_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_piece_photo (piece_id, photo_id)
                    VALUES ($1, $2)
                    ON CONFLICT (piece_id, photo_id) DO NOTHING
                    "#,
                )
                .bind(id)
                .bind(photo_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            PieceEvent::PiecePhotoUnlinked {
                id,
                photo_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_piece_photo
                    WHERE piece_id = $1 AND photo_id = $2
                    "#,
                )
                .bind(id)
                .bind(photo_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            PieceEvent::PieceCategorySet {
                id,
                category_id,
                version,
            } => {
                let version = version.0 as i64;
                // Best-effort name resolution (audit metadata never blocks):
                // a dangling reference stays `category_name = NULL`.
                let category_name =
                    Self::resolve_category_name(ctx, category_id.map(|c| c.0)).await?;
                sqlx::query(
                    r#"
                    UPDATE projection_piece
                    SET category_id = $2, category_name = $3, version = $4, updated_at = $5
                    WHERE id = $1 AND version < $4
                    "#,
                )
                .bind(id)
                .bind(category_id.map(|c| c.0))
                .bind(category_name)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}

impl PieceProjector {
    /// Upsert one description detail (`(piece_id, detail_id)` conflict target).
    async fn upsert_detail<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        piece_id: Uuid,
        detail: &breakdown_core::piece::events::PieceDetail,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO projection_piece_detail (piece_id, detail_id, subject, text)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (piece_id, detail_id) DO UPDATE SET
                subject = EXCLUDED.subject,
                text = EXCLUDED.text
            "#,
        )
        .bind(piece_id)
        .bind(detail.id)
        .bind(&detail.subject)
        .bind(&detail.text)
        .execute(&mut **ctx)
        .await?;
        Ok(())
    }

    /// Resolve a `CostumeCategory`'s name for denormalised storage. Returns
    /// `None` when the piece has no `category_id` or the category is unknown
    /// (e.g. not yet projected) — a dangling reference stays `None` and never
    /// fails the event.
    async fn resolve_category_name<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        category_id: Option<Uuid>,
    ) -> Result<Option<String>, sqlx::Error> {
        let Some(category_id) = category_id else {
            return Ok(None);
        };
        let name: Option<String> =
            sqlx::query_scalar("SELECT name FROM projection_costume_category WHERE id = $1")
                .bind(category_id)
                .fetch_optional(&mut **ctx)
                .await?;
        Ok(name)
    }

    async fn touch_parent<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        id: Uuid,
        version: i64,
        updated_at: chrono::DateTime<chrono::Utc>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            UPDATE projection_piece
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
