// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
use super::PROJECTOR_VERSION;
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
        // The binding owner is the authenticated principal that dispatched the
        // credential command, carried in the persisted event metadata — never
        // in the event data itself (issue #552). `None` only for legacy events
        // written before actor metadata existed; the AI-config API edge fails
        // closed on an unknown owner.
        let owner = event
            .metadata
            .data
            .as_ref()
            .and_then(|m| m.actor.as_ref())
            .map(|user| user.as_str().to_owned());
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
                        (id, provider, vault_key_id, vault_version, binding_state, version, projector_version, owner, updated_at)
                    VALUES ($1, $2, $3, $4, 'active', $5, $6, $7, $8)
                    ON CONFLICT (id) DO UPDATE SET
                        provider = EXCLUDED.provider,
                        vault_key_id = EXCLUDED.vault_key_id,
                        vault_version = EXCLUDED.vault_version,
                        binding_state = EXCLUDED.binding_state,
                        version = EXCLUDED.version,
                        projector_version = EXCLUDED.projector_version,
                        owner = EXCLUDED.owner,
                        updated_at = EXCLUDED.updated_at
                    WHERE projection_settings.version < EXCLUDED.version
                    "#,
                )
                .bind(id)
                .bind(provider)
                .bind(vault_key_id)
                .bind(vault_version as i64)
                .bind(version.0 as i64)
                .bind(PROJECTOR_VERSION)
                .bind(owner.clone())
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            SettingsEvent::CredentialRotated {
                id,
                provider,
                vault_key_id,
                vault_version,
                version,
            } => {
                // The owner of a binding is immutable: it is recorded exactly once,
                // from the bind event's actor metadata (issue #552). Rotation only
                // refreshes the key. Deliberately NO backfill here — the rotating
                // actor is not verified against the binding owner by the settings
                // rotate/revoke handlers (credential-role gate only), so a COALESCE
                // backfill would let ANY credential-role member claim a legacy
                // NULL-owner binding by rotating it. Legacy owners recover via
                // re-projection only (runbook §10, issue #552 review).
                sqlx::query(
                    r#"
            UPDATE projection_settings
            SET provider = $2,
                vault_key_id = $3,
                vault_version = $4,
                binding_state = 'active',
                version = $5,
                updated_at = $6
            WHERE id = $1 AND version < $5
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
