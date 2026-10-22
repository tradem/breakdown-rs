// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

use std::collections::HashMap;

use kameo_es::{Apply, Command, Context, Entity, Metadata};

#[cfg(test)]
#[path = "aggregate_tests.rs"]
mod aggregate_tests;
use uuid::Uuid;

use crate::shared::{AggregateVersion, EventMetadata, UserId};

use super::commands::{CreateAiConfig, RevokeAiConfig, UpdateAiConfig};
use super::error::AiConfigError;
use super::events::AiConfigEvent;
use super::ports::LlmProvider;
use super::views::{CostDisplayPreference, DocumentKind};
use super::{decision, decision::is_decision_capable};

#[derive(Debug, Clone)]
pub struct AiConfig {
    pub id: Uuid,
    pub user_id: UserId,
    pub provider: Option<LlmProvider>,
    pub assistant_model: String,
    pub image_model: Option<String>,
    pub prompts: HashMap<DocumentKind, String>,
    pub vault_key_id: String,
    pub cost_display_preference: CostDisplayPreference,
    /// Optional Decision Model slot (issue #722): provider + model + vault
    /// key of the non-autoregressive scoring model. `None` when unset.
    pub decision_provider: Option<LlmProvider>,
    pub decision_model: Option<String>,
    pub decision_vault_key_id: Option<String>,
    pub revoked: bool,
    pub version: AggregateVersion,
}

impl Default for AiConfig {
    fn default() -> Self {
        Self {
            id: Uuid::nil(),
            user_id: UserId::from_sub(""),
            provider: None,
            assistant_model: String::new(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: String::new(),
            cost_display_preference: CostDisplayPreference::default(),
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            revoked: false,
            version: AggregateVersion::default(),
        }
    }
}

impl Entity for AiConfig {
    type ID = Uuid;
    type Event = AiConfigEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "ai_config"
    }
}

impl Apply for AiConfig {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            AiConfigEvent::Created {
                id,
                user_id,
                provider,
                assistant_model,
                image_model,
                prompts,
                vault_key_id,
                cost_display_preference,
                decision_provider,
                decision_model,
                decision_vault_key_id,
                version,
            } => {
                self.id = id;
                self.user_id = user_id;
                self.provider = Some(provider);
                self.assistant_model = assistant_model;
                self.image_model = image_model;
                self.prompts = prompts;
                self.vault_key_id = vault_key_id;
                self.cost_display_preference = cost_display_preference;
                self.decision_provider = decision_provider;
                self.decision_model = decision_model;
                self.decision_vault_key_id = decision_vault_key_id;
                self.revoked = false;
                self.version = version;
            }
            AiConfigEvent::Updated {
                provider,
                assistant_model,
                image_model,
                prompts,
                vault_key_id,
                cost_display_preference,
                decision_provider,
                decision_model,
                decision_vault_key_id,
                version,
                ..
            } => {
                self.provider = Some(provider);
                self.assistant_model = assistant_model;
                self.image_model = image_model;
                self.prompts = prompts;
                self.vault_key_id = vault_key_id;
                if let Some(preference) = cost_display_preference {
                    self.cost_display_preference = preference;
                }
                // Resolved final value (design D1): the update handler emits
                // the whole resolved slot, so the projector and replay simply
                // assign it. Pre-#722 events replay to `None` via
                // `#[serde(default)]` — the same "no decision model" state.
                self.decision_provider = decision_provider;
                self.decision_model = decision_model;
                self.decision_vault_key_id = decision_vault_key_id;
                self.revoked = false;
                self.version = version;
            }
            AiConfigEvent::Revoked { version, .. } => {
                self.revoked = true;
                self.version = version;
            }
        }
    }
}

impl Command<CreateAiConfig> for AiConfig {
    type Error = AiConfigError;

    fn handle(
        &self,
        cmd: CreateAiConfig,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        validate_fields(
            cmd.assistant_model.as_str(),
            cmd.vault_key_id.as_str(),
            &cmd.prompts,
        )?;
        validate_decision_config(
            cmd.decision_provider,
            cmd.decision_model.as_deref(),
            cmd.decision_vault_key_id.as_deref(),
        )?;
        Ok(vec![AiConfigEvent::Created {
            id: cmd.id,
            user_id: cmd.user_id,
            provider: cmd.provider,
            assistant_model: cmd.assistant_model,
            image_model: cmd.image_model,
            prompts: cmd.prompts,
            vault_key_id: cmd.vault_key_id,
            cost_display_preference: cmd.cost_display_preference,
            decision_provider: cmd.decision_provider,
            decision_model: cmd.decision_model,
            decision_vault_key_id: cmd.decision_vault_key_id,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<UpdateAiConfig> for AiConfig {
    type Error = AiConfigError;

    fn handle(
        &self,
        cmd: UpdateAiConfig,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        let current_provider = self.provider.ok_or(AiConfigError::NotFound)?;
        if self.revoked {
            return Err(AiConfigError::AlreadyRevoked);
        }
        // A provider change is a credential hand-off, not a relabeling of the
        // existing binding. Keep the invariant that the old vault key cannot
        // be paired with a new provider; the client supplies a different,
        // provider-bound vault key for the replacement.
        if current_provider != cmd.provider && cmd.vault_key_id == self.vault_key_id {
            return Err(AiConfigError::ProviderMismatch);
        }
        if cmd.version != self.version {
            return Err(AiConfigError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        validate_fields(
            cmd.assistant_model.as_str(),
            cmd.vault_key_id.as_str(),
            &cmd.prompts,
        )?;
        // Tri-state resolution (see `UpdateAiConfig`): an omitted field keeps
        // the stored slot value, `Some(None)` clears it. The resolved triple
        // is validated as a whole, so a partial update cannot leave the
        // configuration half-set (e.g. a provider without a model).
        let decision_provider = cmd.decision_provider.unwrap_or(self.decision_provider);
        let decision_model = cmd
            .decision_model
            .unwrap_or_else(|| self.decision_model.clone());
        let decision_vault_key_id = cmd
            .decision_vault_key_id
            .unwrap_or_else(|| self.decision_vault_key_id.clone());
        validate_decision_config(
            decision_provider,
            decision_model.as_deref(),
            decision_vault_key_id.as_deref(),
        )?;
        Ok(vec![AiConfigEvent::Updated {
            id: self.id,
            provider: cmd.provider,
            assistant_model: cmd.assistant_model,
            image_model: cmd.image_model,
            prompts: cmd.prompts,
            vault_key_id: cmd.vault_key_id,
            cost_display_preference: cmd.cost_display_preference,
            decision_provider,
            decision_model,
            decision_vault_key_id,
            version: self.version.next(),
        }])
    }
}

impl Command<RevokeAiConfig> for AiConfig {
    type Error = AiConfigError;

    fn handle(
        &self,
        cmd: RevokeAiConfig,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.provider.is_none() {
            return Err(AiConfigError::NotFound);
        }
        if self.revoked {
            return Err(AiConfigError::AlreadyRevoked);
        }
        if cmd.version != self.version {
            return Err(AiConfigError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        Ok(vec![AiConfigEvent::Revoked {
            id: self.id,
            version: self.version.next(),
        }])
    }
}

fn validate_fields(
    assistant_model: &str,
    vault_key_id: &str,
    prompts: &HashMap<DocumentKind, String>,
) -> Result<(), AiConfigError> {
    if assistant_model.trim().is_empty() {
        return Err(AiConfigError::EmptyModel);
    }
    if vault_key_id.trim().is_empty() {
        return Err(AiConfigError::EmptyVaultKey);
    }
    if prompts.values().any(|prompt| prompt.trim().is_empty()) {
        return Err(AiConfigError::EmptyPrompt);
    }
    Ok(())
}

/// Validate the optional Decision Model slot as a whole (issue #722): either
/// every field is unset, or a decision-capable provider, a non-empty curated
/// model ID and a non-empty vault key reference are all present.
fn validate_decision_config(
    provider: Option<LlmProvider>,
    model: Option<&str>,
    vault_key_id: Option<&str>,
) -> Result<(), AiConfigError> {
    let (Some(provider), Some(model), Some(vault_key_id)) = (provider, model, vault_key_id) else {
        // Partially set is always invalid — including a provider without a
        // model/key: the worker could not build a scoring client.
        if provider.is_some() || model.is_some() || vault_key_id.is_some() {
            return Err(AiConfigError::DecisionProviderRequired);
        }
        return Ok(());
    };
    if !is_decision_capable(provider) {
        return Err(AiConfigError::DecisionProviderUnsupported);
    }
    if model.trim().is_empty() {
        return Err(AiConfigError::EmptyDecisionModel);
    }
    if !decision::is_curated_decision_model(provider, model) {
        return Err(AiConfigError::DecisionModelUnknown);
    }
    if vault_key_id.trim().is_empty() {
        return Err(AiConfigError::EmptyDecisionVaultKey);
    }
    Ok(())
}
