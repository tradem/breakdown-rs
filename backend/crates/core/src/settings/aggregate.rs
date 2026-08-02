// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EventMetadata};

use super::commands::{CreateCredentialBinding, RevokeCredential};
use super::error::SettingsError;
use super::events::SettingsEvent;
use super::views::CredentialBindingState;

#[derive(Debug, Clone, Default)]
pub struct SettingsAggregate {
    pub id: Uuid,
    pub provider: String,
    pub vault_key_id: String,
    pub vault_version: u64,
    pub binding_state: Option<CredentialBindingState>,
    pub version: AggregateVersion,
}

impl Entity for SettingsAggregate {
    type ID = Uuid;
    type Event = SettingsEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "settings"
    }
}

impl Apply for SettingsAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            SettingsEvent::CredentialBound {
                id,
                provider,
                vault_key_id,
                vault_version,
                version,
            } => {
                self.id = id;
                self.provider = provider;
                self.vault_key_id = vault_key_id;
                self.vault_version = vault_version;
                self.binding_state = Some(CredentialBindingState::Active);
                self.version = version;
            }
            SettingsEvent::CredentialRevoked { version, .. } => {
                self.binding_state = Some(CredentialBindingState::Revoked);
                self.version = version;
            }
        }
    }
}

impl Command<CreateCredentialBinding> for SettingsAggregate {
    type Error = SettingsError;

    fn handle(
        &self,
        cmd: CreateCredentialBinding,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.provider.trim().is_empty() {
            return Err(SettingsError::EmptyProvider);
        }
        if cmd.vault_key_id.trim().is_empty() {
            return Err(SettingsError::EmptyVaultKey);
        }
        Ok(vec![SettingsEvent::CredentialBound {
            id: cmd.id,
            provider: cmd.provider,
            vault_key_id: cmd.vault_key_id,
            vault_version: cmd.vault_version,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<RevokeCredential> for SettingsAggregate {
    type Error = SettingsError;

    fn handle(
        &self,
        cmd: RevokeCredential,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.binding_state.is_none() {
            return Err(SettingsError::NotFound);
        }
        if self.binding_state == Some(CredentialBindingState::Revoked) {
            return Err(SettingsError::AlreadyRevoked);
        }
        if cmd.version != self.version {
            return Err(SettingsError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        Ok(vec![SettingsEvent::CredentialRevoked {
            id: self.id,
            version: self.version.next(),
        }])
    }
}
