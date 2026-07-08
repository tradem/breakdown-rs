// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Calculation projection handler: `CalculationEvent` -> `projection_calculation` + items.

use breakdown_core::calculation::aggregate::CalculationAggregate;
use breakdown_core::calculation::events::CalculationEvent;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `CalculationAggregate`.
#[derive(Clone, Default, Debug)]
pub struct CalculationProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for CalculationProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<CalculationAggregate, Transaction<'a, Postgres>>
    for CalculationProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<CalculationEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            CalculationEvent::CalculationCreated {
                id,
                project_id,
                header,
                items,
                version,
            } => {
                let header_json = serde_json::to_value(&header).unwrap_or_default();
                let version = version.0 as i64;

                sqlx::query(
                    r#"
                    INSERT INTO projection_calculation
                        (id, project_id, header, version, updated_at)
                    VALUES ($1, $2, $3, $4, $5)
                    ON CONFLICT (id) DO UPDATE SET
                        project_id = EXCLUDED.project_id,
                        header = EXCLUDED.header,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(project_id.0)
                .bind(header_json)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;

                for item in items {
                    upsert_calculation_item(ctx, id, &item).await?;
                }
            }
            CalculationEvent::HeaderInfoUpdated {
                id,
                header,
                version,
            } => {
                let header_json = serde_json::to_value(&header).unwrap_or_default();
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_calculation
                    SET header = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(header_json)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            CalculationEvent::CalculationItemAdded { id, item, version } => {
                let version = version.0 as i64;
                upsert_calculation_item(ctx, id, &item).await?;
                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            CalculationEvent::CalculationItemUpdated { id, item, version } => {
                let version = version.0 as i64;
                upsert_calculation_item(ctx, id, &item).await?;
                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            CalculationEvent::CalculationItemRemoved {
                id,
                item_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    DELETE FROM projection_calculation_item
                    WHERE calculation_id = $1 AND item_id = $2
                    "#,
                )
                .bind(id)
                .bind(item_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            CalculationEvent::ItemMarkedAsPaid {
                id,
                item_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_calculation_item
                    SET is_paid = true
                    WHERE calculation_id = $1 AND item_id = $2
                    "#,
                )
                .bind(id)
                .bind(item_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
            CalculationEvent::ItemMarkedAsUnpaid {
                id,
                item_id,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_calculation_item
                    SET is_paid = false
                    WHERE calculation_id = $1 AND item_id = $2
                    "#,
                )
                .bind(id)
                .bind(item_id)
                .execute(&mut **ctx)
                .await?;

                Self::touch_parent(ctx, id, version, updated_at).await?;
            }
        }

        Ok(())
    }
}

impl CalculationProjector {
    async fn touch_parent<'b>(
        ctx: &mut Transaction<'b, Postgres>,
        id: Uuid,
        version: i64,
        updated_at: chrono::DateTime<chrono::Utc>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            UPDATE projection_calculation
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

async fn upsert_calculation_item<'b>(
    ctx: &mut Transaction<'b, Postgres>,
    calculation_id: Uuid,
    item: &breakdown_core::calculation::events::CalculationItem,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO projection_calculation_item
            (calculation_id, item_id, name, quantity, unit_price, is_paid)
        VALUES ($1, $2, $3, $4::numeric, $5::numeric, $6)
        ON CONFLICT (calculation_id, item_id) DO UPDATE SET
            name = EXCLUDED.name,
            quantity = EXCLUDED.quantity,
            unit_price = EXCLUDED.unit_price,
            is_paid = EXCLUDED.is_paid
        "#,
    )
    .bind(calculation_id)
    .bind(item.id)
    .bind(item.name.clone())
    .bind(item.quantity.to_string())
    .bind(item.unit_price.to_string())
    .bind(item.is_paid)
    .execute(&mut **ctx)
    .await?;
    Ok(())
}
