// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::collections::HashMap;

use serde::Deserialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, UserId};

use super::ports::LlmProvider;
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
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateAiConfig {
    pub id: Uuid,
    pub provider: LlmProvider,
    pub assistant_model: String,
    pub image_model: Option<String>,
    pub prompts: HashMap<DocumentKind, String>,
    pub vault_key_id: String,
    /// Preferred primary cost display metric (issue #675). Defaults to
    /// [`CostDisplayPreference::Token`] for clients predating the field.
    #[serde(default)]
    pub cost_display_preference: CostDisplayPreference,
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
