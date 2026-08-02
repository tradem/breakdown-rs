// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use breakdown_core::settings::aggregate::SettingsAggregate;
use breakdown_core::settings::events::SettingsEvent;
use breakdown_core::shared::EventMetadata;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

#[derive(Clone, Default, Debug)]
pub struct SettingsProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for SettingsProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<SettingsAggregate, Transaction<'a, Postgres>> for SettingsProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<SettingsEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;
        match event.data {
            SettingsEvent::CredentialBound {
                id,
                provider,
                vault_key_id,
                vault_version,
                version,
            } => {
                sqlx::query(
                    r#"
                    INSERT INTO projection_settings
                        (id, provider, vault_key_id, vault_version, binding_state, version, updated_at)
                    VALUES ($1, $2, $3, $4, 'active', $5, $6)
                    ON CONFLICT (id) DO UPDATE SET
                        provider = EXCLUDED.provider,
                        vault_key_id = EXCLUDED.vault_key_id,
                        vault_version = EXCLUDED.vault_version,
                        binding_state = EXCLUDED.binding_state,
                        version = EXCLUDED.version,
                        updated_at = EXCLUDED.updated_at
                    WHERE projection_settings.version < EXCLUDED.version
                    "#,
                )
                .bind(id)
                .bind(provider)
                .bind(vault_key_id)
                .bind(vault_version as i64)
                .bind(version.0 as i64)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SettingsEvent::CredentialRevoked { id, version } => {
                sqlx::query(
                    r#"
                    UPDATE projection_settings
                    SET binding_state = 'revoked', version = $2, updated_at = $3
                    WHERE id = $1 AND version < $2
                    "#,
                )
                .bind(id)
                .bind(version.0 as i64)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }
        Ok(())
    }
}
