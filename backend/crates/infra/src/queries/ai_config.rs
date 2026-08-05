// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use breakdown_core::ai::{AiConfigRepository, AiConfigView, DocumentKind, LlmProvider};
use breakdown_core::error::DomainError;
use breakdown_core::shared::{AggregateVersion, UserId};
use sqlx::{PgPool, Row};
use std::collections::HashMap;
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct AiConfigRepositoryImpl {
    pool: PgPool,
}

impl AiConfigRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait::async_trait]
impl AiConfigRepository for AiConfigRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<AiConfigView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, user_id, provider, assistant_model, image_model,
                   prompts, vault_key_id, revoked, version
            FROM ai_import.projection_ai_config
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?
        .ok_or_else(|| DomainError::NotFound(format!("AiConfig({id})")))?;

        let provider = parse_provider(row.try_get("provider").map_err(map_sqlx_error)?)?;
        let prompts: HashMap<DocumentKind, String> = row
            .try_get::<serde_json::Value, _>("prompts")
            .map_err(map_sqlx_error)
            .and_then(|value| {
                serde_json::from_value(value).map_err(|error| {
                    DomainError::ValidationError(format!("invalid AI prompt projection: {error}"))
                })
            })?;
        let mut prompt_kinds: Vec<_> = prompts.keys().copied().collect();
        prompt_kinds.sort_by_key(|kind| kind.as_str());
        Ok(AiConfigView {
            id: row.try_get("id").map_err(map_sqlx_error)?,
            user_id: UserId::from_sub(
                row.try_get::<String, _>("user_id")
                    .map_err(map_sqlx_error)?,
            ),
            provider,
            assistant_model: row.try_get("assistant_model").map_err(map_sqlx_error)?,
            image_model: row.try_get("image_model").map_err(map_sqlx_error)?,
            prompt_kinds,
            vault_key_id: row.try_get("vault_key_id").map_err(map_sqlx_error)?,
            version: {
                let raw: i64 = row.try_get("version").map_err(map_sqlx_error)?;
                if raw < 0 {
                    return Err(map_sqlx_error(sqlx::Error::Protocol(
                        "AI config aggregate version cannot be negative".to_owned(),
                    )));
                }
                AggregateVersion(raw as u64)
            },
            revoked: row.try_get("revoked").map_err(map_sqlx_error)?,
        })
    }
}

fn parse_provider(value: String) -> Result<LlmProvider, DomainError> {
    match value.as_str() {
        "openai" => Ok(LlmProvider::OpenAI),
        "openrouter" => Ok(LlmProvider::OpenRouter),
        "eurouter" | "openrouter_eu" => Ok(LlmProvider::EURouter),
        "neuralwatt" => Ok(LlmProvider::Neuralwatt),
        "opencode-go" => Ok(LlmProvider::OpenCodeGo),
        "opencode" => Ok(LlmProvider::OpenCode),
        "ollama" => Ok(LlmProvider::Ollama),
        other => Err(DomainError::ValidationError(format!(
            "unknown AI provider projection {other}"
        ))),
    }
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    DomainError::ServiceUnavailable(format!("AI config database error: {error}"))
}
