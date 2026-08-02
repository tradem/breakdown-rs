// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use aggregate::SettingsAggregate;
pub use commands::{CreateCredentialBinding, RevokeCredential};
pub use error::SettingsError;
pub use events::SettingsEvent;
pub use ports::{CredentialVault, SecretValue, SettingsCommands, SettingsRepository, VaultBinding};
pub use views::{CredentialBindingState, SettingsView};
