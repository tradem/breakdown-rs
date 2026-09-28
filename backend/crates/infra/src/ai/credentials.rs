// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::sync::Arc;

use async_trait::async_trait;
use breakdown_core::error::DomainError;
use breakdown_core::settings::{CredentialVault, SecretValue, VaultBinding};
use uuid::Uuid;

use crate::vault::settings_id_from_binding_key;

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
        _ai_config_id: Uuid,
        vault_key_id: &str,
    ) -> Result<SecretValue, DomainError> {
        if vault_key_id.trim().is_empty() {
            return Err(DomainError::validation(
                "AI vault key reference must not be empty",
            ));
        }
        // The binding key names the SETTINGS credential that owns the secret
        // (the provider key is stored there, ADR-027) — not the AI config that
        // merely references it. Passing the AI-config id made
        // `validate_binding_key` compare `settings-<ai-config-id>` against
        // `settings-<settings-id>`, so every read of a stored provider key
        // failed with "invalid credential Vault key reference" and each AI
        // import job died retrying on it. The owner id is recovered from the
        // key reference itself; a malformed reference fails closed.
        let owner = settings_id_from_binding_key(vault_key_id).ok_or_else(|| {
            DomainError::validation("AI vault key reference does not name a settings credential")
        })?;
        self.vault.fetch(owner, vault_key_id).await
    }

    pub async fn destroy_key(
        &self,
        _ai_config_id: Uuid,
        vault_key_id: &str,
    ) -> Result<(), DomainError> {
        let owner = settings_id_from_binding_key(vault_key_id).ok_or_else(|| {
            DomainError::validation("AI vault key reference does not name a settings credential")
        })?;
        self.vault.destroy(owner, vault_key_id).await
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
