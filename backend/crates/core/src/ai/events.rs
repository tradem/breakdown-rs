// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, UserId};

use super::ports::LlmProvider;
use super::reasoning::ReasoningEffortChoice;
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
        /// Optional Decision Model configuration (issue #722): the provider
        /// hosting the non-autoregressive decision model, the model ID, and
        /// the vaulted API-key binding (same-key reuse or a separate
        /// credential for split billing). `#[serde(default)]` keeps pre-#722
        /// events replayable: they deserialize with no decision model.
        #[serde(default)]
        decision_provider: Option<LlmProvider>,
        /// The curated decision model ID (e.g. `clef-flash`).
        #[serde(default)]
        decision_model: Option<String>,
        /// The vault key reference of the decision provider credential.
        #[serde(default)]
        decision_vault_key_id: Option<String>,
        /// Requested `reasoning_effort` (2026-11-20 investigation).
        /// `#[serde(default)]` keeps older events replayable: they deserialize
        /// to `Auto`, i.e. the behaviour those configurations ran with.
        #[serde(default)]
        reasoning_effort: ReasoningEffortChoice,
        /// Operator attestation that the provider account has zero data
        /// retention enabled (issue #968). `#[serde(default)]` keeps older
        /// events replayable: they deserialize to `false`, i.e. an unattested
        /// account, which is exactly how those configurations behaved.
        #[serde(default)]
        zdr_attested: bool,
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
        /// Optional Decision Model configuration (issue #722).
        /// `#[serde(default)]` keeps pre-#722 events replayable: they
        /// deserialize with no decision model configured.
        #[serde(default)]
        decision_provider: Option<LlmProvider>,
        /// See [`AiConfigEvent::Created::decision_model`].
        #[serde(default)]
        decision_model: Option<String>,
        /// See [`AiConfigEvent::Created::decision_vault_key_id`].
        #[serde(default)]
        decision_vault_key_id: Option<String>,
        /// The RESOLVED choice after the update, so replay and the projector
        /// simply assign it.
        #[serde(default)]
        reasoning_effort: ReasoningEffortChoice,
        /// The RESOLVED attestation after the update (issue #968): `None` = the
        /// update did not touch it (replayed older events deserialize to `None`
        /// and leave the current value in place), `Some(false)` revokes it.
        #[serde(default)]
        zdr_attested: Option<bool>,
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

#[cfg(test)]
#[path = "events_tests.rs"]
mod events_tests;
