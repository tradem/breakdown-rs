// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, UserId};

use super::ports::LlmProvider;
use super::views::{CostDisplayPreference, DocumentKind};

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
        /// Preferred primary cost display metric (issue #675).
        /// `#[serde(default)]` keeps pre-#675 events replayable: they
        /// deserialize as `CostDisplayPreference::Token`.
        #[serde(default)]
        cost_display_preference: CostDisplayPreference,
        version: AggregateVersion,
    },
    Updated {
        id: Uuid,
        provider: LlmProvider,
        assistant_model: String,
        image_model: Option<String>,
        prompts: HashMap<DocumentKind, String>,
        vault_key_id: String,
        /// See [`AiConfigEvent::Created`]. `None` = the update did not touch
        /// the preference (replayed older events deserialize to `None` via
        /// `#[serde(default)]` and leave the current value in place).
        #[serde(default)]
        cost_display_preference: Option<CostDisplayPreference>,
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
