// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::AggregateVersion;

/// Reference-only events for external credentials.
///
/// The submitted secret, plaintext DEK, wrapped DEK and ciphertext are
/// deliberately absent from this type. This is the CQRS/event-store boundary.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SettingsEvent {
    CredentialBound {
        id: Uuid,
        provider: String,
        vault_key_id: String,
        vault_version: u64,
        version: AggregateVersion,
    },
    CredentialRevoked {
        id: Uuid,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for SettingsEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::CredentialBound { .. } => "CredentialBound",
            Self::CredentialRevoked { .. } => "CredentialRevoked",
        }
    }
}
