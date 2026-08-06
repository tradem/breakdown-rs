// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.6-35b (neuralwatt)

//! ShootingDay projection handler: `ShootingDayEvent` -> `projection_shooting_day`.

use super::PROJECTOR_VERSION;
use breakdown_core::shared::{EventMetadata, ShootingDayId};
use breakdown_core::shooting_day::aggregate::ShootingDayAggregate;
use breakdown_core::shooting_day::events::ShootingDayEvent;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};

/// Idempotent projector for the `ShootingDayAggregate`.
#[derive(Clone, Default, Debug)]
pub struct ShootingDayProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for ShootingDayProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<ShootingDayAggregate, Transaction<'a, Postgres>>
    for ShootingDayProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: ShootingDayId,
        event: Event<ShootingDayEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            ShootingDayEvent::ShootingDayCreated {
                id,
                episode_id,
                label,
                order_key,
                date,
                source,
                version,
            } => {
                let version = version.0 as i64;
                let source_json = serde_json::to_value(&source).unwrap_or(serde_json::Value::Null);
                sqlx::query(
                    r#"
                    INSERT INTO projection_shooting_day
                        (id, episode_id, label, order_key, date, source, archived, version, projector_version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, false, $7, $8, $9)
                    ON CONFLICT (id) DO UPDATE SET
                        episode_id = EXCLUDED.episode_id,
                        label = EXCLUDED.label,
                        order_key = EXCLUDED.order_key,
                        date = EXCLUDED.date,
                        source = EXCLUDED.source,
                        version = EXCLUDED.version,
                        projector_version = EXCLUDED.projector_version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id.0)
                .bind(episode_id.0)
                .bind(label)
                .bind(order_key.0)
                .bind(date)
                .bind(source_json)
                .bind(version)
                .bind(PROJECTOR_VERSION)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            ShootingDayEvent::ShootingDayRenamed { id, label, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_shooting_day
                    SET label = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(label)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            ShootingDayEvent::ShootingDayRescheduled { id, date, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_shooting_day
                    SET date = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(date)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            ShootingDayEvent::ShootingDayReordered {
                id,
                order_key,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_shooting_day
                    SET order_key = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(order_key.0)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            ShootingDayEvent::ShootingDayArchived { id, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_shooting_day
                    SET archived = true, version = $2, updated_at = $3
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            ShootingDayEvent::ShootingDayWrapped {
                id,
                wrapped_at,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_shooting_day
                    SET wrapped_at = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id.0)
                .bind(wrapped_at)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}
