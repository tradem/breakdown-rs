// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Block projection handler: `BlockEvent` -> `projection_block`.

use breakdown_core::block::aggregate::BlockAggregate;
use breakdown_core::block::events::BlockEvent;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `BlockAggregate`.
#[derive(Clone, Default, Debug)]
pub struct BlockProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for BlockProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<BlockAggregate, Transaction<'a, Postgres>> for BlockProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<BlockEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            BlockEvent::BlockCreated {
                id,
                season_id,
                series_id,
                number,
                start_date,
                end_date,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_block
                        (id, season_id, series_id, number, start_date, end_date, version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    ON CONFLICT (id) DO UPDATE SET
                        season_id = EXCLUDED.season_id,
                        series_id = EXCLUDED.series_id,
                        number = EXCLUDED.number,
                        start_date = EXCLUDED.start_date,
                        end_date = EXCLUDED.end_date,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(season_id.0)
                .bind(series_id.0)
                .bind(number)
                .bind(start_date)
                .bind(end_date)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            BlockEvent::BlockTimeSpanUpdated {
                id,
                start_date,
                end_date,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_block
                    SET start_date = $2, end_date = $3, version = $4, updated_at = $5
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(start_date)
                .bind(end_date)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}
