// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use std::collections::HashMap;

use serde::Deserialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, UserId};

use super::ports::LlmProvider;
use super::reasoning::ReasoningEffortChoice;
use super::views::{CostDisplayPreference, DocumentKind};

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateAiConfig {
    pub id: Uuid,
    pub user_id: UserId,
    pub provider: LlmProvider,
    pub assistant_model: String,
    pub image_model: Option<String>,
    pub prompts: HashMap<DocumentKind, String>,
    pub vault_key_id: String,
    /// Preferred primary cost display metric (issue #675). Defaults to
    /// [`CostDisplayPreference::Token`] for clients predating the field.
    #[serde(default)]
    pub cost_display_preference: CostDisplayPreference,
    /// Optional Decision Model slot (issue #722). All three fields are
    /// additive with `#[serde(default)]`; a request without them behaves
    /// exactly like a pre-#722 config (no scoring pass).
    #[serde(default)]
    pub decision_provider: Option<LlmProvider>,
    #[serde(default)]
    pub decision_model: Option<String>,
    #[serde(default)]
    pub decision_vault_key_id: Option<String>,
    /// Optional `reasoning_effort` for the assistant model (2026-11-20
    /// output-budget investigation). [`ReasoningEffortChoice::Auto`] — the
    /// default, and the behaviour of every configuration written before this
    /// field existed — resolves to the curated profile of the `(provider, model)`
    /// pair if one applies, else to the provider's own default. Only a pair that
    /// DECLARES the parameter may set an explicit level (see
    /// [`super::reasoning::supported_reasoning_efforts`]); the aggregate refuses
    /// the rest with `422` while the mistake is still cheap, instead of paying a
    /// `400` on every import call.
    #[serde(default)]
    pub reasoning_effort: ReasoningEffortChoice,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateAiConfig {
    pub id: Uuid,
    pub provider: LlmProvider,
    pub assistant_model: String,
    pub image_model: Option<String>,
    pub prompts: HashMap<DocumentKind, String>,
    pub vault_key_id: String,
    /// Preferred primary cost display metric (issue #675). `None` (an
    /// omitted field — e.g. an older client PATCHing other properties) keeps
    /// the aggregate's current preference instead of resetting it.
    pub cost_display_preference: Option<CostDisplayPreference>,
    /// Decision Model slot (issue #722), tri-state like
    /// `cost_display_preference`: the outer `None` (an omitted field) keeps
    /// the stored decision configuration, `Some(None)` clears it, and
    /// `Some(Some(..))` replaces it.
    #[serde(default)]
    pub decision_provider: Option<Option<LlmProvider>>,
    #[serde(default)]
    pub decision_model: Option<Option<String>>,
    #[serde(default)]
    pub decision_vault_key_id: Option<Option<String>>,
    /// `reasoning_effort`: an omitted field keeps the stored value (an older
    /// client), `Auto` resets it to the system default (the curated profile of
    /// the pair, else the provider's own default), a level replaces it.
    ///
    /// Deliberately NOT `Option<Option<..>>` (2026-11-20 investigation): the
    /// generated Dart client omits `null` fields, so an explicit `null` could
    /// never reach the server — "reset" would be unreachable from the app.
    #[serde(default)]
    pub reasoning_effort: Option<ReasoningEffortChoice>,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct RevokeAiConfig {
    pub id: Uuid,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateAiConfig {
    fn command_name() -> &'static str {
        "CreateAiConfig"
    }
}

impl kameo_es::CommandName for UpdateAiConfig {
    fn command_name() -> &'static str {
        "UpdateAiConfig"
    }
}

impl kameo_es::CommandName for RevokeAiConfig {
    fn command_name() -> &'static str {
        "RevokeAiConfig"
    }
}
