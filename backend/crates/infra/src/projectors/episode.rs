// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Episode projection handler: `EpisodeEvent` -> `projection_episode`.

use breakdown_core::episode::aggregate::EpisodeAggregate;
use breakdown_core::episode::events::EpisodeEvent;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `EpisodeAggregate`.
#[derive(Clone, Default, Debug)]
pub struct EpisodeProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for EpisodeProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<EpisodeAggregate, Transaction<'a, Postgres>> for EpisodeProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<EpisodeEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            EpisodeEvent::EpisodeCreated {
                id,
                block_id,
                series_id,
                number,
                name,
                version,
            } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    INSERT INTO projection_episode
                        (id, block_id, series_id, number, name, version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7)
                    ON CONFLICT (id) DO UPDATE SET
                        block_id = EXCLUDED.block_id,
                        series_id = EXCLUDED.series_id,
                        number = EXCLUDED.number,
                        name = EXCLUDED.name,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(block_id.0)
                .bind(series_id.0)
                .bind(number)
                .bind(name)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            EpisodeEvent::EpisodeRenamed { id, name, version } => {
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_episode
                    SET name = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(name)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}
