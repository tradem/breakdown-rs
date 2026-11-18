// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use serde::Deserialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::AggregateVersion;

/// Bind an already-vaulted credential to a Settings aggregate.
///
/// `vault_key_id` is an opaque reference only. This command must never be
/// extended with a secret field.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateCredentialBinding {
    pub id: Uuid,
    pub provider: String,
    pub vault_key_id: String,
    pub vault_version: u64,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct RotateCredentialBinding {
    pub id: Uuid,
    pub provider: String,
    pub vault_key_id: String,
    pub vault_version: u64,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct RevokeCredential {
    pub id: Uuid,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateCredentialBinding {
    fn command_name() -> &'static str {
        "CreateCredentialBinding"
    }
}

impl kameo_es::CommandName for RotateCredentialBinding {
    fn command_name() -> &'static str {
        "RotateCredentialBinding"
    }
}

impl kameo_es::CommandName for RevokeCredential {
    fn command_name() -> &'static str {
        "RevokeCredential"
    }
}
