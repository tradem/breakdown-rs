// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use super::PROJECTOR_VERSION;
use breakdown_core::ai::aggregate::AiConfig;
use breakdown_core::ai::events::AiConfigEvent;
use breakdown_core::shared::EventMetadata;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

#[derive(Clone, Default, Debug)]
pub struct AiConfigProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for AiConfigProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<AiConfig, Transaction<'a, Postgres>> for AiConfigProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: Uuid,
        event: Event<AiConfigEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;
        match event.data {
            AiConfigEvent::Created {
                id,
                user_id,
                provider,
                assistant_model,
                image_model,
                prompts,
                vault_key_id,
                version,
            } => {
                let prompts = serde_json::to_value(prompts).map_err(|error| {
                    sqlx::Error::Protocol(format!("cannot serialize AI prompts: {error}"))
                })?;
                sqlx::query(
                    r#"
                    INSERT INTO ai_import.projection_ai_config
                        (id, user_id, provider, assistant_model, image_model,
                         prompts, vault_key_id, revoked, version, projector_version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, FALSE, $8, $9, $10)
                    ON CONFLICT (id) DO UPDATE SET
                        user_id = EXCLUDED.user_id,
                        provider = EXCLUDED.provider,
                        assistant_model = EXCLUDED.assistant_model,
                        image_model = EXCLUDED.image_model,
                        prompts = EXCLUDED.prompts,
                        vault_key_id = EXCLUDED.vault_key_id,
                        revoked = EXCLUDED.revoked,
                        version = EXCLUDED.version,
                        projector_version = EXCLUDED.projector_version,
                        updated_at = EXCLUDED.updated_at
                    WHERE ai_import.projection_ai_config.version < EXCLUDED.version
                    "#,
                )
                .bind(id)
                .bind(user_id.as_str())
                .bind(provider.as_str())
                .bind(assistant_model)
                .bind(image_model)
                .bind(prompts)
                .bind(vault_key_id)
                .bind(i64::try_from(version.0).map_err(|error| {
                    sqlx::Error::Protocol(format!(
                        "AI config aggregate version exceeds database range: {error}"
                    ))
                })?)
                .bind(PROJECTOR_VERSION)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            AiConfigEvent::Updated {
                id,
                provider,
                assistant_model,
                image_model,
                prompts,
                vault_key_id,
                version,
            } => {
                let prompts = serde_json::to_value(prompts).map_err(|error| {
                    sqlx::Error::Protocol(format!("cannot serialize AI prompts: {error}"))
                })?;
                sqlx::query(
                    r#"
                    UPDATE ai_import.projection_ai_config
                    SET provider = $2, assistant_model = $3, image_model = $4,
                        prompts = $5, vault_key_id = $6, revoked = FALSE,
                        version = $7, updated_at = $8
                    WHERE id = $1 AND version < $7
                    "#,
                )
                .bind(id)
                .bind(provider.as_str())
                .bind(assistant_model)
                .bind(image_model)
                .bind(prompts)
                .bind(vault_key_id)
                .bind(i64::try_from(version.0).map_err(|error| {
                    sqlx::Error::Protocol(format!(
                        "AI config aggregate version exceeds database range: {error}"
                    ))
                })?)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            AiConfigEvent::Revoked { id, version } => {
                sqlx::query(
                    r#"
                    UPDATE ai_import.projection_ai_config
                    SET revoked = TRUE, version = $2, updated_at = $3
                    WHERE id = $1 AND version < $2
                    "#,
                )
                .bind(id)
                .bind(i64::try_from(version.0).map_err(|error| {
                    sqlx::Error::Protocol(format!(
                        "AI config aggregate version exceeds database range: {error}"
                    ))
                })?)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }
        Ok(())
    }
}
