// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! CostumeCategory projection handler: `CostumeCategoryEvent` -> `projection_costume_category`
//! (+ denormalised `category_name` refresh on `projection_costume_detail`).

use breakdown_core::costume_category::aggregate::CostumeCategoryAggregate;
use breakdown_core::costume_category::events::CostumeCategoryEvent;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `CostumeCategoryAggregate`.
#[derive(Clone, Default, Debug)]
pub struct CostumeCategoryProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for CostumeCategoryProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<CostumeCategoryAggregate, Transaction<'a, Postgres>>
    for CostumeCategoryProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<CostumeCategoryEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            CostumeCategoryEvent::CostumeCategoryCreated {
                id,
                season_id,
                name,
                order_key,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_costume_category
                        (id, season_id, name, order_key, archived, version, updated_at)
                    VALUES ($1, $2, $3, $4, false, $5, $6)
                    ON CONFLICT (id) DO UPDATE SET
                        season_id = EXCLUDED.season_id,
                        name = EXCLUDED.name,
                        order_key = EXCLUDED.order_key,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(season_id.0)
                .bind(name)
                .bind(order_key.0)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            CostumeCategoryEvent::CostumeCategoryRenamed { id, name, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_costume_category
                    SET name = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(name.clone())
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;

                // Refresh the denormalised name on every referencing detail.
                sqlx::query(
                    r#"
                    UPDATE projection_costume_detail
                    SET category_name = $1
                    WHERE category_id = $2
                    "#,
                )
                .bind(name)
                .bind(id)
                .execute(&mut **ctx)
                .await?;
            }
            CostumeCategoryEvent::CostumeCategoryReordered { id, order_key, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_costume_category
                    SET order_key = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(order_key.0)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            CostumeCategoryEvent::CostumeCategoryArchived { id, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_costume_category
                    SET archived = true, version = $2, updated_at = $3
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
                // Historical detail references keep their last-known
                // `category_name`; we deliberately do NOT null them out.
            }
        }

        Ok(())
    }
}
