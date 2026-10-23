// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

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
                cost_display_preference,
                decision_provider,
                decision_model,
                decision_vault_key_id,
                version,
            } => {
                let prompts = serde_json::to_value(prompts).map_err(|error| {
                    sqlx::Error::Protocol(format!("cannot serialize AI prompts: {error}"))
                })?;
                sqlx::query(
                    r#"
                    INSERT INTO ai_import.projection_ai_config
                        (id, user_id, provider, assistant_model, image_model,
                         prompts, vault_key_id, cost_display_preference,
                         decision_provider, decision_model, decision_vault_key_id,
                         revoked, version, projector_version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, FALSE, $12, $13, $14)
                    ON CONFLICT (id) DO UPDATE SET
                        user_id = EXCLUDED.user_id,
                        provider = EXCLUDED.provider,
                        assistant_model = EXCLUDED.assistant_model,
                        image_model = EXCLUDED.image_model,
                        prompts = EXCLUDED.prompts,
                        vault_key_id = EXCLUDED.vault_key_id,
                        cost_display_preference = EXCLUDED.cost_display_preference,
                        decision_provider = EXCLUDED.decision_provider,
                        decision_model = EXCLUDED.decision_model,
                        decision_vault_key_id = EXCLUDED.decision_vault_key_id,
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
                .bind(cost_display_preference.as_str())
                // Decision Model slot (issue #722): all three are nullable;
                // a pre-#722 event replays to NULL/NULL/NULL.
                .bind(decision_provider.map(|p| p.as_str().to_owned()))
                .bind(decision_model)
                .bind(decision_vault_key_id)
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
                cost_display_preference,
                decision_provider,
                decision_model,
                decision_vault_key_id,
                version,
            } => {
                let prompts = serde_json::to_value(prompts).map_err(|error| {
                    sqlx::Error::Protocol(format!("cannot serialize AI prompts: {error}"))
                })?;
                sqlx::query(
                    r#"
                    UPDATE ai_import.projection_ai_config
                    SET provider = $2, assistant_model = $3, image_model = $4,
                        prompts = $5, vault_key_id = $6,
                        cost_display_preference = COALESCE($7, cost_display_preference),
                        decision_provider = $8, decision_model = $9,
                        decision_vault_key_id = $10,
                        revoked = FALSE,
                        version = $11, updated_at = $12
                    WHERE id = $1 AND version < $11
                    "#,
                )
                .bind(id)
                .bind(provider.as_str())
                .bind(assistant_model)
                .bind(image_model)
                .bind(prompts)
                .bind(vault_key_id)
                // `None` = the update did not touch the preference — keep the
                // currently projected value instead of overwriting it.
                .bind(
                    cost_display_preference
                        .as_ref()
                        .map(|preference| preference.as_str()),
                )
                // Decision Model slot (issue #722): the aggregate emits the
                // whole resolved triple, so the projection simply assigns it
                // (NULLs included — the slot was cleared).
                .bind(decision_provider.map(|p| p.as_str().to_owned()))
                .bind(decision_model)
                .bind(decision_vault_key_id)
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
