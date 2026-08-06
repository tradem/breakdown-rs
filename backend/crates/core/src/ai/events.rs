// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, UserId};

use super::ports::LlmProvider;
use super::views::DocumentKind;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum AiConfigEvent {
    Created {
        id: Uuid,
        user_id: UserId,
        provider: LlmProvider,
        assistant_model: String,
        image_model: Option<String>,
        prompts: HashMap<DocumentKind, String>,
        vault_key_id: String,
        version: AggregateVersion,
    },
    Updated {
        id: Uuid,
        provider: LlmProvider,
        assistant_model: String,
        image_model: Option<String>,
        prompts: HashMap<DocumentKind, String>,
        vault_key_id: String,
        version: AggregateVersion,
    },
    Revoked {
        id: Uuid,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for AiConfigEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::Created { .. } => "AiConfigCreated",
            Self::Updated { .. } => "AiConfigUpdated",
            Self::Revoked { .. } => "AiConfigRevoked",
        }
    }
}
