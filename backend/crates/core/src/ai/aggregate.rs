// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

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
use super::views::DocumentKind;

#[derive(Debug, Clone)]
pub struct AiConfig {
    pub id: Uuid,
    pub user_id: UserId,
    pub provider: Option<LlmProvider>,
    pub assistant_model: String,
    pub image_model: Option<String>,
    pub prompts: HashMap<DocumentKind, String>,
    pub vault_key_id: String,
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
                version,
            } => {
                self.id = id;
                self.user_id = user_id;
                self.provider = Some(provider);
                self.assistant_model = assistant_model;
                self.image_model = image_model;
                self.prompts = prompts;
                self.vault_key_id = vault_key_id;
                self.revoked = false;
                self.version = version;
            }
            AiConfigEvent::Updated {
                provider,
                assistant_model,
                image_model,
                prompts,
                vault_key_id,
                version,
                ..
            } => {
                self.provider = Some(provider);
                self.assistant_model = assistant_model;
                self.image_model = image_model;
                self.prompts = prompts;
                self.vault_key_id = vault_key_id;
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
        Ok(vec![AiConfigEvent::Created {
            id: cmd.id,
            user_id: cmd.user_id,
            provider: cmd.provider,
            assistant_model: cmd.assistant_model,
            image_model: cmd.image_model,
            prompts: cmd.prompts,
            vault_key_id: cmd.vault_key_id,
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
        if current_provider != cmd.provider {
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
        Ok(vec![AiConfigEvent::Updated {
            id: self.id,
            provider: cmd.provider,
            assistant_model: cmd.assistant_model,
            image_model: cmd.image_model,
            prompts: cmd.prompts,
            vault_key_id: cmd.vault_key_id,
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
