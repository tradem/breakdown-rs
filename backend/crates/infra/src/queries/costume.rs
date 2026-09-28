// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: longcat-2.0 (opencode-go)

//! `sqlx`-backed implementation of the `CostumeRepository` port.

use breakdown_core::costume::ports::CostumeRepository;
use breakdown_core::costume::views::{CostumeDetailView, CostumePhotoView, CostumeView};
use breakdown_core::error::DomainError;
use breakdown_core::error_registry::COSTUME_NOT_FOUND;
use breakdown_core::photo::views::PhotoVariantView;
use breakdown_core::shared::{
    AggregateVersion, CostumeCategoryId, PhotoVariant, SeasonId, VariantStatus,
};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use std::collections::HashMap;
use uuid::Uuid;

/// PostgreSQL read adapter for costume projections.
#[derive(Clone, Debug)]
pub struct CostumeRepositoryImpl {
    pool: PgPool,
}

impl CostumeRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    async fn costumefind_by_id_with_children(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, character_id, category_id, category_name, notes, version, updated_at
            FROM projection_costume
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?
        .ok_or(DomainError::NotFound {
            code: &COSTUME_NOT_FOUND,
            resource: "costume",
            id,
        })?;

        self.enrich(map_costume_row(row)?).await
    }

    async fn enrich(&self, view: CostumeView) -> Result<CostumeView, DomainError> {
        let details = sqlx::query(
            r#"
            SELECT detail_id, subject, text
            FROM projection_costume_detail
            WHERE costume_id = $1
            ORDER BY detail_id
            "#,
        )
        .bind(view.id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let photos = sqlx::query(
            r#"
            SELECT cp.photo_id,
                   p.content_type,
                   p.size_bytes
            FROM projection_costume_photo cp
            LEFT JOIN projection_photo p ON p.photo_id = cp.photo_id
            WHERE cp.costume_id = $1
            ORDER BY cp.photo_id
            "#,
        )
        .bind(view.id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let details = details
            .into_iter()
            .map(|row| {
                Ok(CostumeDetailView {
                    id: row.try_get("detail_id").map_err(map_err)?,
                    subject: row.try_get("subject").map_err(map_err)?,
                    text: row.try_get("text").map_err(map_err)?,
                })
            })
            .collect::<Result<Vec<_>, DomainError>>()?;

        let mut enriched_photos = Vec::new();
        for row in photos {
            let photo_id: Uuid = row.try_get("photo_id").map_err(map_err)?;
            let content_type: Option<String> = row.try_get("content_type").map_err(map_err)?;
            let size_bytes: Option<i64> = row.try_get("size_bytes").map_err(map_err)?;

            // Fetch variants for this photo.
            let variant_rows = sqlx::query(
                r#"
                SELECT variant, status, size_bytes
                FROM projection_photo_variant
                WHERE photo_id = $1
                ORDER BY variant
                "#,
            )
            .bind(photo_id)
            .fetch_all(&self.pool)
            .await
            .map_err(|e| DomainError::internal(e.to_string()))?;

            let variants: Vec<PhotoVariantView> = variant_rows
                .into_iter()
                .map(|vr| {
                    let variant_str: String = vr.try_get("variant").map_err(map_err)?;
                    let status_str: String = vr.try_get("status").map_err(map_err)?;
                    let vsize: i64 = vr.try_get("size_bytes").map_err(map_err)?;
                    Ok(PhotoVariantView {
                        kind: parse_variant(&variant_str)?,
                        status: parse_status(&status_str)?,
                        size_bytes: vsize as u64,
                    })
                })
                .collect::<Result<Vec<_>, DomainError>>()?;

            enriched_photos.push(CostumePhotoView {
                id: photo_id,
                content_type: content_type.unwrap_or_default(),
                size_bytes: size_bytes.unwrap_or(0) as u64,
                variants,
            });
        }

        // Fully specified (no `..view` spread) so a deleted field is a
        // compile error, not a surviving mutant (issue #307).
        Ok(CostumeView {
            id: view.id,
            character_id: view.character_id,
            category_id: view.category_id,
            category_name: view.category_name,
            notes: view.notes,
            details,
            photos: enriched_photos,
            version: view.version,
            updated_at: view.updated_at,
        })
    }
    /// Batched counterpart of [`Self::enrich`] for a whole page of costumes.
    ///
    /// Three queries for the entire page — details, photos, and the variants
    /// of every referenced photo — instead of one round trip per costume plus
    /// one per photo (`enrich` does 1 + 2N for an N-costume page). The rows
    /// keep their input order and any costume without children simply gets
    /// empty vectors.
    async fn enrich_many(&self, views: Vec<CostumeView>) -> Result<Vec<CostumeView>, DomainError> {
        if views.is_empty() {
            return Ok(views);
        }
        let costume_ids: Vec<Uuid> = views.iter().map(|v| v.id).collect();

        let detail_rows = sqlx::query(
            r#"
            SELECT costume_id, detail_id, subject, text
            FROM projection_costume_detail
            WHERE costume_id = ANY($1)
            ORDER BY costume_id, detail_id
            "#,
        )
        .bind(&costume_ids)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let mut details_by_costume: HashMap<Uuid, Vec<CostumeDetailView>> = HashMap::new();
        for row in detail_rows {
            let costume_id: Uuid = row.try_get("costume_id").map_err(map_err)?;
            let detail = CostumeDetailView {
                id: row.try_get("detail_id").map_err(map_err)?,
                subject: row.try_get("subject").map_err(map_err)?,
                text: row.try_get("text").map_err(map_err)?,
            };
            details_by_costume
                .entry(costume_id)
                .or_default()
                .push(detail);
        }

        let photo_rows = sqlx::query(
            r#"
            SELECT cp.costume_id, cp.photo_id,
                   p.content_type,
                   p.size_bytes
            FROM projection_costume_photo cp
            LEFT JOIN projection_photo p ON p.photo_id = cp.photo_id
            WHERE cp.costume_id = ANY($1)
            ORDER BY cp.costume_id, cp.photo_id
            "#,
        )
        .bind(&costume_ids)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        let mut costume_of_photo: HashMap<Uuid, Uuid> = HashMap::new();
        let mut photo_ids: Vec<Uuid> = Vec::with_capacity(photo_rows.len());
        for row in &photo_rows {
            let costume_id: Uuid = row.try_get("costume_id").map_err(map_err)?;
            let photo_id: Uuid = row.try_get("photo_id").map_err(map_err)?;
            costume_of_photo.insert(photo_id, costume_id);
            photo_ids.push(photo_id);
        }

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

        let mut photos_by_costume: HashMap<Uuid, Vec<CostumePhotoView>> = HashMap::new();
        for row in photo_rows {
            let photo_id: Uuid = row.try_get("photo_id").map_err(map_err)?;
            let costume_id = costume_of_photo
                .get(&photo_id)
                .copied()
                .ok_or_else(|| DomainError::internal("photo without costume binding"))?;
            let content_type: Option<String> = row.try_get("content_type").map_err(map_err)?;
            let size_bytes: Option<i64> = row.try_get("size_bytes").map_err(map_err)?;
            photos_by_costume
                .entry(costume_id)
                .or_default()
                .push(CostumePhotoView {
                    id: photo_id,
                    content_type: content_type.unwrap_or_default(),
                    size_bytes: size_bytes.unwrap_or(0) as u64,
                    variants: variants_by_photo.remove(&photo_id).unwrap_or_default(),
                });
        }

        Ok(views
            .into_iter()
            .map(|view| CostumeView {
                details: details_by_costume.remove(&view.id).unwrap_or_default(),
                photos: photos_by_costume.remove(&view.id).unwrap_or_default(),
                ..view
            })
            .collect())
    }
}

impl CostumeRepository for CostumeRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        self.costumefind_by_id_with_children(id).await
    }

    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CostumeView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT c.id, c.character_id, c.category_id, c.category_name, c.notes, c.version, c.updated_at
            FROM projection_costume c
            LEFT JOIN projection_character ch ON ch.id = c.character_id
            WHERE ch.season_id = $1
               OR EXISTS (
                    SELECT 1 FROM projection_costume_season cs
                    WHERE cs.costume_id = c.id AND cs.season_id = $1
               )
            ORDER BY c.updated_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(season_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        // The list route MUST carry the same child collections as the detail
        // route. `map_costume_row` leaves `details`/`photos` empty, and every
        // list-backed surface renders them: the wardrobe tile picks its
        // thumbnail from `CostumeView.photos`, the editor renders `details`.
        // Without enrichment here those surfaces could never show a photo or a
        // costume detail — the placeholder was the only reachable state, no
        // matter how often the client refetched (the list route has no cache
        // or projector-lag excuse: it simply carried no data).
        //
        // Batched on purpose: THREE queries for the whole page (details,
        // photos, variants) instead of `enrich`'s per-costume + per-photo
        // round trips, which would be 1 + 2N queries for an N-row page.
        let views = rows
            .into_iter()
            .map(map_costume_row)
            .collect::<Result<Vec<_>, _>>()?;
        self.enrich_many(views).await
    }

    async fn costumes_by_character(
        &self,
        character_id: Uuid,
    ) -> Result<Vec<CostumeView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT id, character_id, category_id, category_name, notes, version, updated_at
            FROM projection_costume
            WHERE character_id = $1
            ORDER BY updated_at DESC
            "#,
        )
        .bind(character_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        rows.into_iter()
            .map(map_costume_row)
            .collect::<Result<Vec<_>, _>>()
    }

    async fn costume_with_details_photos(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        self.costumefind_by_id_with_children(id).await
    }

    /// Repertoire seasons of a costume (issue #453 binding, read by issue
    /// #532). Ordered by `season_id` so the result is deterministic for the
    /// m:n case — callers must not treat it as a single season.
    async fn repertoire_seasons(&self, costume_id: Uuid) -> Result<Vec<SeasonId>, DomainError> {
        let rows: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT season_id
            FROM projection_costume_season
            WHERE costume_id = $1
            ORDER BY season_id
            "#,
        )
        .bind(costume_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        Ok(rows.into_iter().map(SeasonId).collect())
    }
}

fn map_costume_row(row: sqlx::postgres::PgRow) -> Result<CostumeView, DomainError> {
    Ok(CostumeView {
        id: row.try_get("id").map_err(map_err)?,
        character_id: row.try_get("character_id").map_err(map_err)?,
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
    })
}

fn map_err(e: sqlx::Error) -> DomainError {
    DomainError::internal(e.to_string())
}

fn parse_variant(s: &str) -> Result<PhotoVariant, DomainError> {
    match s {
        "original" => Ok(PhotoVariant::Original),
        "thumb" => Ok(PhotoVariant::Thumb),
        "medium" => Ok(PhotoVariant::Medium),
        _ => Err(DomainError::internal(format!("Unknown photo variant: {s}"))),
    }
}

fn parse_status(s: &str) -> Result<VariantStatus, DomainError> {
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

    /// Kills the `delete match arm "…" in parse_variant` mutants: each known
    /// variant string must map to its `PhotoVariant`, and an unknown string
    /// must error rather than silently falling through.
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
