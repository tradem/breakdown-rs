// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::AggregateVersion;

/// Public binding state. It contains no secret material or ciphertext.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum CredentialBindingState {
    Active,
    Revoked,
    /// The reference remains known, but the live Vault binding cannot be reached.
    Unreachable,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SettingsView {
    pub id: Uuid,
    pub provider: String,
    pub vault_key_id: String,
    pub vault_version: u64,
    pub binding_state: CredentialBindingState,
    pub version: AggregateVersion,
}
