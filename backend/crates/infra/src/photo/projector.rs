// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use breakdown_core::photo::aggregate::PhotoAggregate;
use breakdown_core::photo::events::PhotoEvent;
use breakdown_core::shared::{PhotoId, PhotoVariant, VariantStatus};
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};

/// Idempotent projector for the `PhotoAggregate`.
#[derive(Clone, Default, Debug)]
pub struct PhotoProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for PhotoProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<PhotoAggregate, Transaction<'a, Postgres>> for PhotoProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: PhotoId,
        event: Event<PhotoEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            PhotoEvent::PhotoUploaded {
                id,
                content_type,
                size_bytes,
                variant_statuses,
                ..
            } => {
                // Insert the photo row.
                sqlx::query(
                    r#"
                    INSERT INTO projection_photo
                        (photo_id, content_type, size_bytes, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, $5)
                    ON CONFLICT (photo_id) DO UPDATE SET
                        content_type = EXCLUDED.content_type,
                        size_bytes = EXCLUDED.size_bytes,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id.0)
                .bind(&content_type)
                .bind(size_bytes as i64)
                .bind(updated_at)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;

                // Insert variant rows (all initially Pending).
                for (variant, status) in variant_statuses {
                    let size = if matches!(variant, PhotoVariant::Original) {
                        size_bytes as i64
                    } else {
                        0
                    };
                    sqlx::query(
                        r#"
                        INSERT INTO projection_photo_variant
                            (photo_id, variant, status, size_bytes, created_at)
                        VALUES ($1, $2, $3, $4, $5)
                        ON CONFLICT (photo_id, variant) DO UPDATE SET
                            status = EXCLUDED.status,
                            size_bytes = EXCLUDED.size_bytes
                        "#,
                    )
                    .bind(id.0)
                    .bind(variant.as_str())
                    .bind(status_as_str(status))
                    .bind(size)
                    .bind(updated_at)
                    .execute(&mut **ctx)
                    .await?;
                }
            }
            PhotoEvent::OriginalNormalized {
                id,
                new_size,
                rotated: _,
                version,
            } => {
                let version = version.0 as i64;
                // Update the original variant to Ready + new size.
                sqlx::query(
                    r#"
                    UPDATE projection_photo_variant
                    SET status = 'ready', size_bytes = $2
                    WHERE photo_id = $1 AND variant = 'original'
                    "#,
                )
                .bind(id.0)
                .bind(new_size as i64)
                .execute(&mut **ctx)
                .await?;

                // Update the photo row with the new size and exif_stripped timestamp.
                sqlx::query(
                    r#"
                    UPDATE projection_photo
                    SET size_bytes = $2, updated_at = $3
                    WHERE photo_id = $1
                    "#,
                )
                .bind(id.0)
                .bind(new_size as i64)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;

                Self::touch_photo(ctx, id, version, updated_at).await?;
            }
            PhotoEvent::VariantGenerated {
                id,
                variant,
                size_bytes,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_photo_variant
                    SET status = 'ready', size_bytes = $3
                    WHERE photo_id = $1 AND variant = $2
                    "#,
                )
                .bind(id.0)
                .bind(variant.as_str())
                .bind(size_bytes as i64)
                .execute(&mut **ctx)
                .await?;

                Self::touch_photo(ctx, id, version, updated_at).await?;
            }
            PhotoEvent::VariantFailed {
                id,
                variant,
                error: _,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_photo_variant
                    SET status = 'failed'
                    WHERE photo_id = $1 AND variant = $2
                    "#,
                )
                .bind(id.0)
                .bind(variant.as_str())
                .execute(&mut **ctx)
                .await?;

                Self::touch_photo(ctx, id, version, updated_at).await?;
            }
            PhotoEvent::PhotoDeleted { id, .. } => {
                // Delete variant rows (ON DELETE CASCADE handles this, but
                // delete explicitly for clarity).
                sqlx::query(
                    r#"
                    DELETE FROM projection_photo_variant
                    WHERE photo_id = $1
                    "#,
                )
                .bind(id.0)
                .execute(&mut **ctx)
                .await?;

                sqlx::query(
                    r#"
                    DELETE FROM projection_photo
                    WHERE photo_id = $1
                    "#,
                )
                .bind(id.0)
                .execute(&mut **ctx)
                .await?;

                // Note: projection_costume_photo rows are removed by the
                // Costume projector on PhotoUnlinked events, not here.
            }
        }

        Ok(())
    }
}

impl PhotoProjector {
    async fn touch_photo<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        id: PhotoId,
        version: i64,
        updated_at: chrono::DateTime<chrono::Utc>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            UPDATE projection_photo
            SET version = $2, updated_at = $3
            WHERE photo_id = $1
            "#,
        )
        .bind(id.0)
        .bind(version)
        .bind(updated_at)
        .execute(&mut **ctx)
        .await?;
        Ok(())
    }
}

fn status_as_str(status: VariantStatus) -> &'static str {
    match status {
        VariantStatus::Pending => "pending",
        VariantStatus::Ready => "ready",
        VariantStatus::Failed => "failed",
    }
}
