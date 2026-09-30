// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: qwen3.6-35b (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Costume projection handler: `CostumeEvent` -> `projection_costume` + details + photos.
//!
//! Issue #543: the costume carries ONE category (`projection_costume.category_id`).
//! Legacy events with categorized details derive it via the same first-wins rule
//! the aggregate applies in `CostumeAggregate::apply` — the projection stays a
//! pure function of the events (first detail category in event order, within one
//! event: `detail_id` ASC), so aggregate and projection never diverge on a replay.
//! Legacy detail columns (`projection_costume_detail.category_id/category_name`)
//! keep being written for replay compatibility; cleanup is a later migration.

use super::PROJECTOR_VERSION;
use breakdown_core::costume::aggregate::CostumeAggregate;
use breakdown_core::costume::events::CostumeEvent;
use breakdown_core::shared::EventMetadata;
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
        event: Event<CostumeEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            CostumeEvent::CostumeCreated {
                id,
                character_id,
                season_id,
                notes,
                details,
                photos,
                version,
            } => {
                let version = version.0 as i64;
                // Replay-derivation rule (issue #543): the first detail
                // category (lowest `detail_id`) becomes the costume's
                // category while it has none. Identical to
                // `derive_category_id` in the aggregate so a replayed legacy
                // stream yields the same value in aggregate and projection.
                let derived_category = details
                    .iter()
                    .filter(|d| d.category_id.is_some())
                    .min_by_key(|d| d.id)
                    .and_then(|d| d.category_id);
                let derived_category_name =
                    Self::resolve_category_name(ctx, derived_category.map(|c| c.0)).await?;
                if let Some(category_id) = derived_category {
                    tracing::info!(
                        costume_id = %id,
                        category_id = %category_id.0,
                        "derived costume category from legacy detail event (issue #543 first-wins rule)"
                    );
                }
                sqlx::query(
                    r#"
                    INSERT INTO projection_costume
                        (id, character_id, category_id, category_name, notes, version,
                         projector_version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    ON CONFLICT (id) DO UPDATE SET
                        character_id = EXCLUDED.character_id,
                        category_id = EXCLUDED.category_id,
                        category_name = EXCLUDED.category_name,
                        notes = EXCLUDED.notes,
                        version = EXCLUDED.version,
                        projector_version = EXCLUDED.projector_version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(character_id)
                .bind(derived_category.map(|c| c.0))
                .bind(derived_category_name)
                .bind(notes)
                .bind(version)
                .bind(PROJECTOR_VERSION)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;

                // Repertoire binding (issue #453): the created costume joins
                // the season's costume stream. Idempotent via the PK; old
                // events replay with `season_id = None` and skip this.
                if let Some(season_id) = season_id {
                    sqlx::query(
                        r#"
                        INSERT INTO projection_costume_season (costume_id, season_id)
                        VALUES ($1, $2)
                        ON CONFLICT (costume_id, season_id) DO NOTHING
                        "#,
                    )
                    .bind(id)
                    .bind(season_id)
                    .execute(&mut **ctx)
                    .await?;
                }

                for detail in details {
                    let category_name =
                        Self::resolve_category_name(ctx, detail.category_id.map(|c| c.0)).await?;
                    sqlx::query(
                        r#"
                        INSERT INTO projection_costume_detail
                            (costume_id, detail_id, subject, category_id, category_name, text)
                        VALUES ($1, $2, $3, $4, $5, $6)
                        ON CONFLICT (costume_id, detail_id) DO UPDATE SET
                            subject = EXCLUDED.subject,
                            category_id = EXCLUDED.category_id,
                            category_name = EXCLUDED.category_name,
                            text = EXCLUDED.text
                        "#,
                    )
                    .bind(id)
                    .bind(detail.id)
                    .bind(&detail.subject)
                    .bind(detail.category_id.map(|c| c.0))
                    .bind(category_name)
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
                let category_name =
                    Self::resolve_category_name(ctx, detail.category_id.map(|c| c.0)).await?;
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_costume_detail
                        (costume_id, detail_id, subject, category_id, category_name, text)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (costume_id, detail_id) DO UPDATE SET
                        subject = EXCLUDED.subject,
                        category_id = EXCLUDED.category_id,
                        category_name = EXCLUDED.category_name,
                        text = EXCLUDED.text
                    "#,
                )
                .bind(id)
                .bind(detail.id)
                .bind(&detail.subject)
                .bind(detail.category_id.map(|c| c.0))
                .bind(category_name)
                .bind(detail.text)
                .execute(&mut **ctx)
                .await?;

                // Replay-derivation rule (issue #543): a categorized detail
                // fills the costume's still-empty category (first-wins —
                // `WHERE category_id IS NULL` makes the SQL deterministic in
                // event order, exactly like the aggregate's `apply`).
                if let Some(category_id) = detail.category_id {
                    let costume_category_name =
                        Self::resolve_category_name(ctx, Some(category_id.0)).await?;
                    if costume_category_name.is_none() {
                        tracing::info!(
                            costume_id = %id,
                            category_id = %category_id.0,
                            "derived costume category from a categorized detail; category not projected yet (dangling reference stays nameless)"
                        );
                    }
                    sqlx::query(
                        r#"
                        UPDATE projection_costume
                        SET category_id = $2, category_name = $3
                        WHERE id = $1 AND category_id IS NULL
                        "#,
                    )
                    .bind(id)
                    .bind(category_id.0)
                    .bind(costume_category_name)
                    .execute(&mut **ctx)
                    .await?;
                }

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            // Issue #544: an edit reuses the `DetailAdded` upsert verbatim —
            // `(costume_id, detail_id)` is the conflict target, so the row is
            // overwritten in place. No migration: the table and its unique key
            // already exist.
            //
            // Two deliberate differences from `DetailAdded`:
            // 1. no `category_name` resolution — a `DetailUpdated` can only be
            //    produced by the new PATCH route, whose wire request carries no
            //    category (issue #543 made details pure description), so
            //    `category_id` is always `None` and the detail row's vestigial
            //    category columns are nulled.
            // 2. no costume-category derivation — an edit must never change the
            //    costume's own category; only `CostumeCategorySet` and the
            //    legacy replay rule do that.
            CostumeEvent::DetailUpdated {
                id,
                detail,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_costume_detail
                        (costume_id, detail_id, subject, category_id, category_name, text)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (costume_id, detail_id) DO UPDATE SET
                        subject = EXCLUDED.subject,
                        category_id = EXCLUDED.category_id,
                        category_name = EXCLUDED.category_name,
                        text = EXCLUDED.text
                    "#,
                )
                .bind(id)
                .bind(detail.id)
                .bind(&detail.subject)
                .bind(detail.category_id.map(|c| c.0))
                .bind(None::<String>)
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
            CostumeEvent::CostumeCategorySet {
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
                    UPDATE projection_costume
                    SET category_id = $2, category_name = $3, version = $4, updated_at = $5
                    WHERE id = $1
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

impl CostumeProjector {
    /// Resolve a `CostumeCategory`'s name for denormalised storage on a detail.
    /// Returns `None` when the detail has no `category_id` or the category is
    /// unknown (e.g. not yet projected) — a dangling reference stays `None`.
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
