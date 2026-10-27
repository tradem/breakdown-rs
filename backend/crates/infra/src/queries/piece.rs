// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! `sqlx`-backed implementation of the `PieceRepository` port.
//!
//! `PieceView.photos` merges the piece's directly linked photos with the
//! photos linked to any outfit containing the piece (fitting photos are
//! usually taken at outfit level), deduplicated by photo id.

use breakdown_core::error::DomainError;
use breakdown_core::error_registry::PIECE_NOT_FOUND;
use breakdown_core::photo::views::PhotoVariantView;
use breakdown_core::piece::ports::PieceRepository;
use breakdown_core::piece::views::{PieceDetailView, PiecePhotoView, PieceView};
use breakdown_core::shared::{
    AggregateVersion, CostumeCategoryId, PhotoVariant, SeasonId, VariantStatus,
};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use std::collections::HashMap;
use uuid::Uuid;

/// PostgreSQL read adapter for piece projections.
#[derive(Clone, Debug)]
pub struct PieceRepositoryImpl {
    pool: PgPool,
}

impl PieceRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    async fn piece_find_by_id_with_children(&self, id: Uuid) -> Result<PieceView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, name, category_id, category_name, notes, version, updated_at
            FROM projection_piece
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?
        .ok_or(DomainError::NotFound {
            code: &PIECE_NOT_FOUND,
            resource: "piece",
            id,
        })?;

        self.enrich(map_piece_row(row)?).await
    }

    async fn enrich(&self, view: PieceView) -> Result<PieceView, DomainError> {
        let details = sqlx::query(
            r#"
            SELECT detail_id, subject, text
            FROM projection_piece_detail
            WHERE piece_id = $1
            ORDER BY detail_id
            "#,
        )
        .bind(view.id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let photo_rows = sqlx::query(
            r#"
            SELECT up.photo_id,
                   p.content_type,
                   p.size_bytes
            FROM (
                SELECT photo_id FROM projection_piece_photo WHERE piece_id = $1
                UNION
                SELECT op.photo_id
                FROM projection_outfit_photo op
                JOIN projection_outfit_piece opi ON opi.outfit_id = op.outfit_id
                WHERE opi.piece_id = $1
            ) up
            LEFT JOIN projection_photo p ON p.photo_id = up.photo_id
            ORDER BY up.photo_id
            "#,
        )
        .bind(view.id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let details = details
            .into_iter()
            .map(|row| {
                Ok(PieceDetailView {
                    id: row.try_get("detail_id").map_err(map_err)?,
                    subject: row.try_get("subject").map_err(map_err)?,
                    text: row.try_get("text").map_err(map_err)?,
                })
            })
            .collect::<Result<Vec<_>, DomainError>>()?;

        let photos = self.enrich_photos(photo_rows).await?;

        let season_ids = sqlx::query_scalar(
            r#"
            SELECT season_id
            FROM projection_piece_season
            WHERE piece_id = $1
            ORDER BY season_id
            "#,
        )
        .bind(view.id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        // Fully specified (no `..view` spread) so a deleted field is a
        // compile error, not a surviving mutant (issue #307).
        Ok(PieceView {
            id: view.id,
            name: view.name,
            category_id: view.category_id,
            category_name: view.category_name,
            notes: view.notes,
            details,
            photos,
            version: view.version,
            updated_at: view.updated_at,
            season_ids,
        })
    }

    /// Attach variant metadata to a list of photo rows (id, content_type,
    /// size_bytes). Shared by the single-piece and the batched path.
    async fn enrich_photos(
        &self,
        photo_rows: Vec<sqlx::postgres::PgRow>,
    ) -> Result<Vec<PiecePhotoView>, DomainError> {
        let photo_ids: Vec<Uuid> = photo_rows
            .iter()
            .map(|row| row.try_get("photo_id").map_err(map_err))
            .collect::<Result<Vec<_>, DomainError>>()?;

        let mut variants_by_photo: HashMap<Uuid, Vec<PhotoVariantView>> = HashMap::new();
        if !photo_ids.is_empty() {
            let variant_rows = sqlx::query(
                r#"
                SELECT photo_id, variant, status, size_bytes
                FROM projection_photo_variant
                WHERE photo_id = ANY($1)
                ORDER BY photo_id, variant
                "#,
            )
            .bind(&photo_ids)
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
        }

        let mut photos = Vec::with_capacity(photo_rows.len());
        for row in photo_rows {
            let photo_id: Uuid = row.try_get("photo_id").map_err(map_err)?;
            let content_type: Option<String> = row.try_get("content_type").map_err(map_err)?;
            let size_bytes: Option<i64> = row.try_get("size_bytes").map_err(map_err)?;
            photos.push(PiecePhotoView {
                id: photo_id,
                content_type: content_type.unwrap_or_default(),
                size_bytes: size_bytes.unwrap_or(0) as u64,
                variants: variants_by_photo.remove(&photo_id).unwrap_or_default(),
            });
        }
        Ok(photos)
    }

    /// Batched counterpart of [`Self::enrich`] for a whole page of pieces:
    /// details, photos and the photo variants of the entire page in a fixed
    /// number of round trips.
    async fn enrich_many(&self, views: Vec<PieceView>) -> Result<Vec<PieceView>, DomainError> {
        if views.is_empty() {
            return Ok(views);
        }
        let piece_ids: Vec<Uuid> = views.iter().map(|v| v.id).collect();

        let detail_rows = sqlx::query(
            r#"
            SELECT piece_id, detail_id, subject, text
            FROM projection_piece_detail
            WHERE piece_id = ANY($1)
            ORDER BY piece_id, detail_id
            "#,
        )
        .bind(&piece_ids)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let mut details_by_piece: HashMap<Uuid, Vec<PieceDetailView>> = HashMap::new();
        for row in detail_rows {
            let piece_id: Uuid = row.try_get("piece_id").map_err(map_err)?;
            let detail = PieceDetailView {
                id: row.try_get("detail_id").map_err(map_err)?,
                subject: row.try_get("subject").map_err(map_err)?,
                text: row.try_get("text").map_err(map_err)?,
            };
            details_by_piece.entry(piece_id).or_default().push(detail);
        }

        let photo_rows = sqlx::query(
            r#"
            SELECT up.piece_id, up.photo_id,
                   p.content_type,
                   p.size_bytes
            FROM (
                SELECT piece_id, photo_id FROM projection_piece_photo WHERE piece_id = ANY($1)
                UNION
                SELECT opi.piece_id, op.photo_id
                FROM projection_outfit_photo op
                JOIN projection_outfit_piece opi ON opi.outfit_id = op.outfit_id
                WHERE opi.piece_id = ANY($1)
            ) up
            LEFT JOIN projection_photo p ON p.photo_id = up.photo_id
            ORDER BY up.piece_id, up.photo_id
            "#,
        )
        .bind(&piece_ids)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let row_piece_ids = photo_rows
            .iter()
            .map(|row| row.try_get::<Uuid, _>("piece_id").map_err(map_err))
            .collect::<Result<Vec<_>, DomainError>>()?;
        let photos = self.enrich_photos(photo_rows).await?;
        let mut photos_by_piece: HashMap<Uuid, Vec<PiecePhotoView>> = HashMap::new();
        for (piece_id, photo) in row_piece_ids.into_iter().zip(photos) {
            photos_by_piece.entry(piece_id).or_default().push(photo);
        }

        let season_rows = sqlx::query(
            r#"
            SELECT piece_id, season_id
            FROM projection_piece_season
            WHERE piece_id = ANY($1)
            ORDER BY piece_id, season_id
            "#,
        )
        .bind(&piece_ids)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let mut seasons_by_piece: HashMap<Uuid, Vec<Uuid>> = HashMap::new();
        for row in season_rows {
            let piece_id: Uuid = row.try_get("piece_id").map_err(map_err)?;
            let season_id: Uuid = row.try_get("season_id").map_err(map_err)?;
            seasons_by_piece
                .entry(piece_id)
                .or_default()
                .push(season_id);
        }

        // Fully specified (no `..view` spread) so a deleted field is a
        // compile error instead of a silent fallback to the un-enriched base
        // view (mutation hardening, issue #585).
        Ok(views
            .into_iter()
            .map(|view| PieceView {
                id: view.id,
                name: view.name,
                category_id: view.category_id,
                category_name: view.category_name,
                notes: view.notes,
                details: details_by_piece.remove(&view.id).unwrap_or_default(),
                photos: photos_by_piece.remove(&view.id).unwrap_or_default(),
                version: view.version,
                updated_at: view.updated_at,
                season_ids: seasons_by_piece.remove(&view.id).unwrap_or_default(),
            })
            .collect())
    }
}

impl PieceRepository for PieceRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<PieceView, DomainError> {
        self.piece_find_by_id_with_children(id).await
    }

    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<PieceView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT p.id, p.name, p.category_id, p.category_name, p.notes, p.version, p.updated_at
            FROM projection_piece p
            JOIN projection_piece_season ps ON ps.piece_id = p.id
            WHERE ps.season_id = $1
            ORDER BY p.updated_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(season_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        // The list route carries the same child collections as the detail
        // route: the wardrobe tile picks its thumbnail from `PieceView.photos`
        // and the editor renders `details`.
        let views = rows
            .into_iter()
            .map(map_piece_row)
            .collect::<Result<Vec<_>, DomainError>>()?;
        self.enrich_many(views).await
    }

    async fn piece_with_details_photos(&self, id: Uuid) -> Result<PieceView, DomainError> {
        self.piece_find_by_id_with_children(id).await
    }

    /// Repertoire seasons of a piece. Ordered by `season_id` so the result is
    /// deterministic for the m:n case — callers must not treat it as a single
    /// season.
    async fn repertoire_seasons(&self, piece_id: Uuid) -> Result<Vec<SeasonId>, DomainError> {
        let rows: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT season_id
            FROM projection_piece_season
            WHERE piece_id = $1
            ORDER BY season_id
            "#,
        )
        .bind(piece_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        Ok(rows.into_iter().map(SeasonId).collect())
    }
}

fn map_piece_row(row: sqlx::postgres::PgRow) -> Result<PieceView, DomainError> {
    Ok(PieceView {
        id: row.try_get("id").map_err(map_err)?,
        name: row.try_get("name").map_err(map_err)?,
        category_id: row
            .try_get::<Option<Uuid>, _>("category_id")
            .map_err(map_err)?
            .map(CostumeCategoryId),
        category_name: row.try_get("category_name").map_err(map_err)?,
        notes: row.try_get("notes").map_err(map_err)?,
        details: Vec::new(),
        photos: Vec::new(),
        version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_err)? as u64),
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(map_err)?,
        // Filled by `enrich`/`enrich_many`; the base row query carries no
        // repertoire.
        season_ids: Vec::new(),
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::internal(e.to_string())
}

pub(crate) fn parse_variant(s: &str) -> Result<PhotoVariant, DomainError> {
    match s {
        "original" => Ok(PhotoVariant::Original),
        "thumb" => Ok(PhotoVariant::Thumb),
        "medium" => Ok(PhotoVariant::Medium),
        _ => Err(DomainError::internal(format!("Unknown photo variant: {s}"))),
    }
}

pub(crate) fn parse_status(s: &str) -> Result<VariantStatus, DomainError> {
    match s {
        "pending" => Ok(VariantStatus::Pending),
        "ready" => Ok(VariantStatus::Ready),
        "failed" => Ok(VariantStatus::Failed),
        _ => Err(DomainError::internal(format!(
            "Unknown variant status: {s}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    // Test code lifts the workspace clippy panics/unwrap lints via
    // `#![cfg_attr(test, allow(...))]` in `crates/infra/src/lib.rs`.

    use breakdown_core::shared::{PhotoVariant, VariantStatus};

    use super::*;

    /// Kills the `delete match arm "…" in parse_variant` mutants.
    #[test]
    fn parse_variant_maps_all_three_variants() {
        assert_eq!(
            parse_variant("original").expect("original"),
            PhotoVariant::Original
        );
        assert_eq!(parse_variant("thumb").expect("thumb"), PhotoVariant::Thumb);
        assert_eq!(
            parse_variant("medium").expect("medium"),
            PhotoVariant::Medium
        );
    }

    #[test]
    fn parse_variant_rejects_unknown_string() {
        assert!(parse_variant("originals").is_err());
        assert!(parse_variant("").is_err());
    }

    /// Kills the `delete match arm "…" in parse_status` mutants.
    #[test]
    fn parse_status_maps_all_three_statuses() {
        assert_eq!(
            parse_status("pending").expect("pending"),
            VariantStatus::Pending
        );
        assert_eq!(parse_status("ready").expect("ready"), VariantStatus::Ready);
        assert_eq!(
            parse_status("failed").expect("failed"),
            VariantStatus::Failed
        );
    }

    #[test]
    fn parse_status_rejects_unknown_string() {
        assert!(parse_status("readyy").is_err());
        assert!(parse_status("").is_err());
    }
}
