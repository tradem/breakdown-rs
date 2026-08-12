// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::sync::Arc;

use async_trait::async_trait;
use breakdown_core::error::DomainError;
use breakdown_core::settings::{CredentialVault, SecretValue, VaultBinding};
use uuid::Uuid;

/// AI-specific binding facade over the shared CredentialVault port. The
/// aggregate stores only the returned opaque `vault_key_id`; secret material
/// remains inside this edge adapter and the vault implementation.
pub struct AiCredentialResolver<V> {
    vault: Arc<V>,
}

impl<V> AiCredentialResolver<V>
where
    V: CredentialVault + 'static,
{
    pub fn new(vault: Arc<V>) -> Self {
        Self { vault }
    }

    pub async fn store_key(
        &self,
        ai_config_id: Uuid,
        secret: SecretValue,
    ) -> Result<VaultBinding, DomainError> {
        self.vault.store(ai_config_id, "ai", secret).await
    }

    pub async fn fetch_key(
        &self,
        ai_config_id: Uuid,
        vault_key_id: &str,
    ) -> Result<SecretValue, DomainError> {
        if vault_key_id.trim().is_empty() {
            return Err(DomainError::validation(
                "AI vault key reference must not be empty",
            ));
        }
        self.vault.fetch(ai_config_id, vault_key_id).await
    }

    pub async fn destroy_key(
        &self,
        ai_config_id: Uuid,
        vault_key_id: &str,
    ) -> Result<(), DomainError> {
        self.vault.destroy(ai_config_id, vault_key_id).await
    }
}

#[async_trait]
impl<V> CredentialVault for AiCredentialResolver<V>
where
    V: CredentialVault + 'static,
{
    async fn store(
        &self,
        settings_id: Uuid,
        provider: &str,
        secret: SecretValue,
    ) -> Result<VaultBinding, DomainError> {
        self.vault.store(settings_id, provider, secret).await
    }

    async fn fetch(
        &self,
        settings_id: Uuid,
        vault_key_id: &str,
    ) -> Result<SecretValue, DomainError> {
        // Route through fetch_key so the blank-key validation applies on both
        // entry points.
        self.fetch_key(settings_id, vault_key_id).await
    }

    async fn destroy(&self, settings_id: Uuid, vault_key_id: &str) -> Result<(), DomainError> {
        self.vault.destroy(settings_id, vault_key_id).await
    }

    async fn check(&self) -> Result<(), DomainError> {
        self.vault.check().await
    }
}
