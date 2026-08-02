// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use async_trait::async_trait;
use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, UserId};

use super::commands::{CreateCredentialBinding, RevokeCredential};
use super::views::SettingsView;

/// A secret value that cannot be serialized or formatted for logs and is
/// zeroized when dropped. It is accepted only by the Vault port at the API
/// boundary and is never passed to a command or event.
pub struct SecretValue(zeroize::Zeroizing<String>);

impl SecretValue {
    pub fn new(value: String) -> Self {
        Self(zeroize::Zeroizing::new(value))
    }

    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VaultBinding {
    pub vault_key_id: String,
    pub vault_version: u64,
}

#[async_trait]
pub trait CredentialVault: Send + Sync {
    async fn store(
        &self,
        settings_id: Uuid,
        provider: &str,
        secret: SecretValue,
    ) -> Result<VaultBinding, DomainError>;

    async fn fetch(
        &self,
        settings_id: Uuid,
        vault_key_id: &str,
    ) -> Result<SecretValue, DomainError>;

    async fn destroy(&self, vault_key_id: &str) -> Result<(), DomainError>;

    async fn check(&self) -> Result<(), DomainError>;
}

#[async_trait]
pub trait SettingsCommands: Send + Sync {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateCredentialBinding,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;

    async fn revoke(
        &self,
        actor: UserId,
        cmd: RevokeCredential,
    ) -> Result<AggregateVersion, DomainError>;
}

#[async_trait]
pub trait SettingsRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<SettingsView, DomainError>;
}
