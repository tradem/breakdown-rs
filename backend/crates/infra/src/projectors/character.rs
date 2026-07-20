// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Character projection handler: `CharacterEvent` -> `projection_character`.

use breakdown_core::character::aggregate::CharacterAggregate;
use breakdown_core::character::events::CharacterEvent;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Idempotent projector for the `CharacterAggregate`.
#[derive(Clone, Default, Debug)]
pub struct CharacterProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for CharacterProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<CharacterAggregate, Transaction<'a, Postgres>> for CharacterProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<CharacterEvent, ()>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            CharacterEvent::CharacterCreated {
                id,
                season_id,
                name,
                category,
                measurements,
                contact_info,
                version,
            } => {
                let measurements_json = serde_json::to_value(&measurements).unwrap_or_default();
                let contact_json = serde_json::to_value(&contact_info).unwrap_or_default();
                let category_json = serde_json::to_value(category).unwrap_or_default();
                let version = version.0 as i64;

                sqlx::query(
                    r#"
                    INSERT INTO projection_character
                        (id, season_id, name, category, measurements, contact, version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    ON CONFLICT (id) DO UPDATE SET
                        season_id = EXCLUDED.season_id,
                        name = EXCLUDED.name,
                        category = EXCLUDED.category,
                        measurements = EXCLUDED.measurements,
                        contact = EXCLUDED.contact,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(season_id.0)
                .bind(name)
                .bind(category_json)
                .bind(measurements_json)
                .bind(contact_json)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            CharacterEvent::MeasurementsUpdated {
                id,
                measurements,
                version,
            } => {
                let measurements_json = serde_json::to_value(&measurements).unwrap_or_default();
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_character
                    SET measurements = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(measurements_json)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            CharacterEvent::ContactInfoUpdated {
                id,
                contact_info,
                version,
            } => {
                let contact_json = serde_json::to_value(&contact_info).unwrap_or_default();
                let version = version.0 as i64;
                sqlx::query(
                    r#"
                    UPDATE projection_character
                    SET contact = $2, version = $3, updated_at = $4
                    WHERE id = $1
                    "#,
                )
                .bind(id)
                .bind(contact_json)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}
