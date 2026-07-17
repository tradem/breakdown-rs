// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Season projection handler: `SeasonEvent` -> `projection_season`.

use breakdown_core::season::aggregate::SeasonAggregate;
use breakdown_core::season::events::SeasonEvent;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `SeasonAggregate`.
#[derive(Clone, Default, Debug)]
pub struct SeasonProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for SeasonProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<SeasonAggregate, Transaction<'a, Postgres>> for SeasonProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<SeasonEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            SeasonEvent::SeasonCreated {
                id,
                series_id,
                number,
                title,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_season
                        (id, series_id, number, title, version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (id) DO UPDATE SET
                        series_id = EXCLUDED.series_id,
                        number = EXCLUDED.number,
                        title = EXCLUDED.title,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(series_id.0)
                .bind(number)
                .bind(title)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SeasonEvent::SeasonRenamed { id, title, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_season
                    SET title = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(title)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}
