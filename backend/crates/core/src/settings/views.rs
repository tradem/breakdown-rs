// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, UserId};

/// Public binding state. It contains no secret material or ciphertext.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum CredentialBindingState {
    Active,
    Revoked,
    /// The reference remains known, but the live Vault binding cannot be reached.
    Unreachable,
}

/// Reference view of an external credential binding. It contains no secret
/// material or ciphertext.
///
/// `owner` is the identity that bound the credential, recovered by the
/// projector from `EventMetadata.actor` (issue #552). `None` for legacy rows
/// projected before the column existed — the AI-config API edge treats an
/// unknown owner as "not owned by the caller" (fail closed). Recovery is
/// re-projection only (runbook §10); rotation deliberately does not backfill.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SettingsView {
    pub id: Uuid,
    pub provider: String,
    pub vault_key_id: String,
    pub vault_version: u64,
    pub binding_state: CredentialBindingState,
    pub version: AggregateVersion,
    /// Authenticated principal (`OIDC sub`) that created/owns the binding.
    /// `None` only for legacy rows awaiting re-projection or rotation backfill.
    pub owner: Option<UserId>,
}
