// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use async_trait::async_trait;
use breakdown_core::error::DomainError;
use breakdown_core::settings::ports::SettingsRepository;
use breakdown_core::settings::views::{CredentialBindingState, SettingsView};
use breakdown_core::shared::AggregateVersion;
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct SettingsRepositoryImpl {
    pool: PgPool,
}

impl SettingsRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl SettingsRepository for SettingsRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<SettingsView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, provider, vault_key_id, vault_version, binding_state, version
            FROM projection_settings
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|err| DomainError::Conflict(err.to_string()))?
        .ok_or_else(|| DomainError::NotFound(format!("Settings({id})")))?;

        let state: String = row
            .try_get("binding_state")
            .map_err(|err| DomainError::Conflict(err.to_string()))?;
        let binding_state = match state.as_str() {
            "active" => CredentialBindingState::Active,
            "revoked" => CredentialBindingState::Revoked,
            other => {
                return Err(DomainError::Conflict(format!(
                    "invalid binding state: {other}"
                )));
            }
        };
        Ok(SettingsView {
            id: row.try_get("id").map_err(map_error)?,
            provider: row.try_get("provider").map_err(map_error)?,
            vault_key_id: row.try_get("vault_key_id").map_err(map_error)?,
            vault_version: row.try_get::<i64, _>("vault_version").map_err(map_error)? as u64,
            binding_state,
            version: AggregateVersion(row.try_get::<i64, _>("version").map_err(map_error)? as u64),
        })
    }
}

fn map_error(err: sqlx::Error) -> DomainError {
    DomainError::Conflict(err.to_string())
}
