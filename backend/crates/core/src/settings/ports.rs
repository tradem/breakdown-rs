// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use subtle::ConstantTimeEq;
use uuid::Uuid;
use zeroize::Zeroize;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, UserId};

use super::commands::{CreateCredentialBinding, RevokeCredential, RotateCredentialBinding};
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

impl std::fmt::Debug for SecretValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SecretValue(<redacted>)")
    }
}

/// Provider-specific GDrive material that is allowed to exist only between
/// the API edge and the Vault port. It deliberately has no `Debug`, `Serialize`
/// or response-schema implementation.
pub struct GDriveCredentialBundle {
    client_id: SecretValue,
    client_secret: SecretValue,
    refresh_token: SecretValue,
    root_folder_id: Option<String>,
}

impl GDriveCredentialBundle {
    pub fn try_new(
        client_id: String,
        client_secret: String,
        refresh_token: String,
        root_folder_id: Option<String>,
    ) -> Result<Self, DomainError> {
        let client_id = normalize_required(client_id)?;
        let client_secret = normalize_required(client_secret)?;
        let refresh_token = normalize_required(refresh_token)?;
        let root_folder_id = root_folder_id
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        Ok(Self {
            client_id: SecretValue::new(client_id),
            client_secret: SecretValue::new(client_secret),
            refresh_token: SecretValue::new(refresh_token),
            root_folder_id,
        })
    }

    pub fn client_id(&self) -> &str {
        self.client_id.as_str()
    }

    pub fn client_secret(&self) -> &str {
        self.client_secret.as_str()
    }

    pub fn refresh_token(&self) -> &str {
        self.refresh_token.as_str()
    }

    pub fn root_folder_id(&self) -> Option<&str> {
        self.root_folder_id.as_deref()
    }

    pub fn has_same_material(&self, other: &Self) -> bool {
        self.client_id() == other.client_id()
            && self
                .client_secret()
                .as_bytes()
                .ct_eq(other.client_secret().as_bytes())
                .into()
            && self
                .refresh_token()
                .as_bytes()
                .ct_eq(other.refresh_token().as_bytes())
                .into()
            && self.root_folder_id() == other.root_folder_id()
    }

    /// Encode only for the Vault port; callers must not persist or log the
    /// returned value.
    pub fn into_secret_value(self) -> Result<SecretValue, DomainError> {
        let mut wire = GDriveCredentialWire {
            client_id: self.client_id.as_str().to_owned(),
            client_secret: self.client_secret.as_str().to_owned(),
            refresh_token: self.refresh_token.as_str().to_owned(),
            root_folder_id: self.root_folder_id.clone(),
        };
        let encoded = serde_json::to_string(&wire).map_err(|_| {
            DomainError::ServiceUnavailable("failed to encode GDrive credential".into())
        });
        wire.zeroize();
        encoded.map(SecretValue::new)
    }

    /// Decode only at the Vault boundary.
    pub fn from_secret_value(secret: SecretValue) -> Result<Self, DomainError> {
        let mut wire: GDriveCredentialWire =
            serde_json::from_str(secret.as_str()).map_err(|_| {
                DomainError::ServiceUnavailable("invalid GDrive credential in Vault".into())
            })?;
        let client_id = std::mem::take(&mut wire.client_id);
        let client_secret = std::mem::take(&mut wire.client_secret);
        let refresh_token = std::mem::take(&mut wire.refresh_token);
        let root_folder_id = wire.root_folder_id.take();
        wire.zeroize();
        Self::try_new(client_id, client_secret, refresh_token, root_folder_id)
    }
}

#[derive(Serialize, Deserialize)]
struct GDriveCredentialWire {
    client_id: String,
    client_secret: String,
    refresh_token: String,
    root_folder_id: Option<String>,
}

impl Zeroize for GDriveCredentialWire {
    fn zeroize(&mut self) {
        self.client_id.zeroize();
        self.client_secret.zeroize();
        self.refresh_token.zeroize();
        if let Some(root) = &mut self.root_folder_id {
            root.zeroize();
        }
    }
}

impl Drop for GDriveCredentialWire {
    fn drop(&mut self) {
        self.zeroize();
    }
}

fn normalize_required(value: String) -> Result<String, DomainError> {
    let normalized = value.trim().to_owned();
    let mut value = value;
    value.zeroize();
    if normalized.is_empty() {
        return Err(DomainError::ValidationError(
            "GDrive client_id, client_secret and refresh_token must not be empty".into(),
        ));
    }
    Ok(normalized)
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

    /// Store the complete GDrive bundle as one Vault binding. The default
    /// implementation keeps existing provider-neutral fakes compatible while
    /// ensuring the bundle never crosses into a command or event.
    async fn store_gdrive(
        &self,
        settings_id: Uuid,
        bundle: GDriveCredentialBundle,
    ) -> Result<VaultBinding, DomainError> {
        self.store(settings_id, "gdrive", bundle.into_secret_value()?)
            .await
    }

    /// Fetch and decode a complete GDrive bundle from a Vault binding.
    async fn fetch_gdrive(
        &self,
        settings_id: Uuid,
        vault_key_id: &str,
    ) -> Result<GDriveCredentialBundle, DomainError> {
        let secret = self.fetch(settings_id, vault_key_id).await?;
        GDriveCredentialBundle::from_secret_value(secret)
    }

    async fn destroy(&self, settings_id: Uuid, vault_key_id: &str) -> Result<(), DomainError>;

    async fn check(&self) -> Result<(), DomainError>;
}

#[async_trait]
pub trait SettingsCommands: Send + Sync {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateCredentialBinding,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;

    async fn rotate(
        &self,
        actor: UserId,
        cmd: RotateCredentialBinding,
    ) -> Result<AggregateVersion, DomainError>;

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
