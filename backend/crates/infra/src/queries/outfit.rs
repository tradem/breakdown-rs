// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! `sqlx`-backed implementation of the `OutfitRepository` port.
//!
//! `season_id` and `character_name` are resolved by joining
//! `projection_outfit.character_id -> projection_character`; a projection miss
//! leaves them `None` and never fails the read (derived metadata must never
//! block a lookup). Piece metadata inside `pieces` is best-effort for the same
//! reason — `projection_outfit_piece` holds no FK to `projection_piece`.

use breakdown_core::error::DomainError;
use breakdown_core::error_registry::OUTFIT_NOT_FOUND;
use breakdown_core::outfit::ports::OutfitRepository;
use breakdown_core::outfit::views::{OutfitPieceView, OutfitView};
use breakdown_core::shared::AggregateVersion;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use std::collections::HashMap;
use uuid::Uuid;

use super::piece::{parse_status, parse_variant};
use breakdown_core::photo::views::PhotoVariantView;

/// PostgreSQL read adapter for outfit projections.
#[derive(Clone, Debug)]
pub struct OutfitRepositoryImpl {
    pool: PgPool,
}

impl OutfitRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    async fn enrich(&self, view: OutfitView) -> Result<OutfitView, DomainError> {
        let piece_rows = sqlx::query(
            r#"
            SELECT op.piece_id, op.position, p.name, p.category_id, p.category_name
            FROM projection_outfit_piece op
            LEFT JOIN projection_piece p ON p.id = op.piece_id
            WHERE op.outfit_id = $1
            ORDER BY op.position, op.piece_id
            "#,
        )
        .bind(view.id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let photo_rows = sqlx::query(
            r#"
            SELECT op.photo_id, p.content_type, p.size_bytes
            FROM projection_outfit_photo op
            LEFT JOIN projection_photo p ON p.photo_id = op.photo_id
            WHERE op.outfit_id = $1
            ORDER BY op.photo_id
            "#,
        )
        .bind(view.id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let mut pieces = Vec::with_capacity(piece_rows.len());
        let mut piece_ids = Vec::with_capacity(piece_rows.len());
        for row in piece_rows {
            let piece_id: Uuid = row.try_get("piece_id").map_err(map_err)?;
            piece_ids.push(piece_id);
            pieces.push(OutfitPieceView {
                piece_id,
                name: row.try_get("name").map_err(map_err)?,
                category_id: row.try_get("category_id").map_err(map_err)?,
                category_name: row.try_get("category_name").map_err(map_err)?,
                position: row.try_get("position").map_err(map_err)?,
            });
        }

        let photo_ids: Vec<Uuid> = photo_rows
            .iter()
            .map(|row| row.try_get("photo_id").map_err(map_err))
            .collect::<Result<Vec<_>, DomainError>>()?;
        let variants = self.variants_by_photo(&photo_ids).await?;
        let photos = photo_rows
            .into_iter()
            .map(|row| {
                let photo_id: Uuid = row.try_get("photo_id").map_err(map_err)?;
                let content_type: Option<String> = row.try_get("content_type").map_err(map_err)?;
                let size_bytes: Option<i64> = row.try_get("size_bytes").map_err(map_err)?;
                Ok(breakdown_core::outfit::views::OutfitPhotoView {
                    id: photo_id,
                    content_type: content_type.unwrap_or_default(),
                    size_bytes: size_bytes.unwrap_or(0) as u64,
                    variants: variants.get(&photo_id).cloned().unwrap_or_default(),
                })
            })
            .collect::<Result<Vec<_>, DomainError>>()?;

        // Fully specified (no `..view` spread) so a deleted field is a
        // compile error, not a surviving mutant.
        Ok(OutfitView {
            id: view.id,
            character_id: view.character_id,
            character_name: view.character_name,
            season_id: view.season_id,
            name: view.name,
            variant_of: view.variant_of,
            piece_ids,
            pieces,
            notes: view.notes,
            photos,
            version: view.version,
            updated_at: view.updated_at,
        })
    }

    async fn variants_by_photo(
        &self,
        photo_ids: &[Uuid],
    ) -> Result<HashMap<Uuid, Vec<PhotoVariantView>>, DomainError> {
        let mut variants_by_photo: HashMap<Uuid, Vec<PhotoVariantView>> = HashMap::new();
        if photo_ids.is_empty() {
            return Ok(variants_by_photo);
        }
        let variant_rows = sqlx::query(
            r#"
            SELECT photo_id, variant, status, size_bytes
            FROM projection_photo_variant
            WHERE photo_id = ANY($1)
            ORDER BY photo_id, variant
            "#,
        )
        .bind(photo_ids)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        for row in variant_rows {
            let photo_id: Uuid = row.try_get("photo_id").map_err(map_err)?;
            let variant_str: String = row.try_get("variant").map_err(map_err)?;
            let status_str: String = row.try_get("status").map_err(map_err)?;
            let size_bytes: i64 = row.try_get("size_bytes").map_err(map_err)?;
            variants_by_photo
                .entry(photo_id)
                .or_default()
                .push(PhotoVariantView {
                    kind: parse_variant(&variant_str)?,
                    status: parse_status(&status_str)?,
                    size_bytes: size_bytes as u64,
                });
        }
        Ok(variants_by_photo)
    }
}

impl OutfitRepository for OutfitRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<OutfitView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT o.id, o.character_id, o.name, o.variant_of, o.notes, o.version,
                   o.updated_at, ch.name AS character_name, ch.season_id
            FROM projection_outfit o
            LEFT JOIN projection_character ch ON ch.id = o.character_id
            WHERE o.id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?
        .ok_or(DomainError::NotFound {
            code: &OUTFIT_NOT_FOUND,
            resource: "outfit",
            id,
        })?;

        self.enrich(map_outfit_row(row)?).await
    }

    async fn list_by_character(&self, character_id: Uuid) -> Result<Vec<OutfitView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT o.id, o.character_id, o.name, o.variant_of, o.notes, o.version,
                   o.updated_at, ch.name AS character_name, ch.season_id
            FROM projection_outfit o
            LEFT JOIN projection_character ch ON ch.id = o.character_id
            WHERE o.character_id = $1
            ORDER BY o.updated_at DESC
            "#,
        )
        .bind(character_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let mut views = Vec::with_capacity(rows.len());
        for row in rows {
            views.push(self.enrich(map_outfit_row(row)?).await?);
        }
        Ok(views)
    }
}

fn map_outfit_row(row: sqlx::postgres::PgRow) -> Result<OutfitView, DomainError> {
    Ok(OutfitView {
        id: row.try_get("id").map_err(map_err)?,
        character_id: row.try_get("character_id").map_err(map_err)?,
        character_name: row.try_get("character_name").map_err(map_err)?,
        season_id: row.try_get("season_id").map_err(map_err)?,
        name: row.try_get("name").map_err(map_err)?,
        variant_of: row.try_get("variant_of").map_err(map_err)?,
        // Filled by `enrich` — the base row query carries no children.
        piece_ids: Vec::new(),
        pieces: Vec::new(),
        notes: row.try_get("notes").map_err(map_err)?,
        photos: Vec::new(),
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::internal(e.to_string())
}
