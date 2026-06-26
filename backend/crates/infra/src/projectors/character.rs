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
        let version = event.stream_version as i64;
        let updated_at = event.timestamp;

        match event.data {
            CharacterEvent::CharacterCreated {
                id,
                project_id,
                name,
                is_extra,
                is_main_character,
                measurements,
                contact_info,
                ..
            } => {
                let measurements_json = serde_json::to_value(&measurements).unwrap_or_default();
                let contact_json = serde_json::to_value(&contact_info).unwrap_or_default();

                sqlx::query(
                    r#"
                    INSERT INTO projection_character
                        (id, project_id, name, is_extra, is_main_character, measurements, contact, version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                    ON CONFLICT (id) DO UPDATE SET
                        project_id = EXCLUDED.project_id,
                        name = EXCLUDED.name,
                        is_extra = EXCLUDED.is_extra,
                        is_main_character = EXCLUDED.is_main_character,
                        measurements = EXCLUDED.measurements,
                        contact = EXCLUDED.contact,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(id)
                .bind(project_id.0)
                .bind(name)
                .bind(is_extra)
                .bind(is_main_character)
                .bind(measurements_json)
                .bind(contact_json)
                .bind(version)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            CharacterEvent::MeasurementsUpdated {
                id, measurements, ..
            } => {
                let measurements_json = serde_json::to_value(&measurements).unwrap_or_default();
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
                id, contact_info, ..
            } => {
                let contact_json = serde_json::to_value(&contact_info).unwrap_or_default();
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
