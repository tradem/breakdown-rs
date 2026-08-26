// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use std::collections::HashMap;

use kameo_es::Entity;
use kameo_es::test_utils::GivenEntity;
use uuid::Uuid;

use crate::shared::{AggregateVersion, UserId};

use super::{
    AiConfig, AiConfigError, AiConfigEvent, CreateAiConfig, DocumentKind, LlmProvider,
    RevokeAiConfig, UpdateAiConfig,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn user_id() -> UserId {
    UserId::from_sub("test-user")
}

fn make_create_cmd() -> CreateAiConfig {
    CreateAiConfig {
        id: Uuid::now_v7(),
        user_id: user_id(),
        provider: LlmProvider::OpenAI,
        assistant_model: "gpt-4o".into(),
        image_model: Some("dall-e-3".into()),
        prompts: HashMap::from([(DocumentKind::Script, "Summarize".into())]),
        vault_key_id: "key-123".into(),
    }
}

fn make_update_cmd(id: Uuid, version: AggregateVersion) -> UpdateAiConfig {
    UpdateAiConfig {
        id,
        provider: LlmProvider::OpenAI,
        assistant_model: "gpt-4o-mini".into(),
        image_model: None,
        prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
        vault_key_id: "key-456".into(),
        version,
    }
}

fn created_event(cmd: &CreateAiConfig) -> AiConfigEvent {
    AiConfigEvent::Created {
        id: cmd.id,
        user_id: cmd.user_id.clone(),
        provider: cmd.provider,
        assistant_model: cmd.assistant_model.clone(),
        image_model: cmd.image_model.clone(),
        prompts: cmd.prompts.clone(),
        vault_key_id: cmd.vault_key_id.clone(),
        version: AggregateVersion::INITIAL,
    }
}

// ===========================================================================
// P3.2 — AI-Aggregate: Event-Count-Assertions
// ===========================================================================

// --- CreateAiConfig -------------------------------------------------------

#[test]
fn create_config_emits_single_created_event() {
    let cmd = make_create_cmd();
    let expected = created_event(&cmd);

    AiConfig::given(vec![]).when(cmd).then(vec![expected]);
}

#[test]
fn create_config_rejects_empty_model() {
    let cmd = CreateAiConfig {
        assistant_model: "  ".into(),
        ..make_create_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::EmptyModel);
}

#[test]
fn create_config_rejects_empty_vault_key() {
    let cmd = CreateAiConfig {
        vault_key_id: "  ".into(),
        ..make_create_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::EmptyVaultKey);
}

#[test]
fn create_config_rejects_empty_prompt() {
    let cmd = CreateAiConfig {
        prompts: HashMap::from([(DocumentKind::Script, "  ".into())]),
        ..make_create_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::EmptyPrompt);
}

// --- UpdateAiConfig -------------------------------------------------------

#[test]
fn update_config_emits_single_updated_event() {
    let create_cmd = make_create_cmd();
    let update_cmd = make_update_cmd(create_cmd.id, AggregateVersion::INITIAL);

    AiConfig::given(vec![created_event(&create_cmd)])
        .when(update_cmd)
        .then(vec![AiConfigEvent::Updated {
            id: create_cmd.id,
            provider: LlmProvider::OpenAI,
            assistant_model: "gpt-4o-mini".into(),
            image_model: None,
            prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
            vault_key_id: "key-456".into(),
            version: AggregateVersion::INITIAL.next(),
        }]);
}

#[test]
fn update_config_rejects_if_revoked() {
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![
        created_event(&create_cmd),
        AiConfigEvent::Revoked {
            id,
            version: AggregateVersion::INITIAL.next(),
        },
    ])
    .when(make_update_cmd(id, AggregateVersion::INITIAL.next()))
    .then_error(AiConfigError::AlreadyRevoked);
}

#[test]
fn update_config_rejects_provider_mismatch() {
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            provider: LlmProvider::Ollama, // different from Created
            ..make_update_cmd(id, AggregateVersion::INITIAL)
        })
        .then_error(AiConfigError::ProviderMismatch);
}

#[test]
fn update_config_rejects_version_mismatch() {
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            version: AggregateVersion::INITIAL.next(), // wrong version
            ..make_update_cmd(id, AggregateVersion::INITIAL)
        })
        .then_error(AiConfigError::VersionMismatch {
            expected: AggregateVersion::INITIAL.next(),
            actual: AggregateVersion::INITIAL,
        });
}

#[test]
fn update_config_rejects_empty_model() {
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            assistant_model: "  ".into(),
            ..make_update_cmd(id, AggregateVersion::INITIAL)
        })
        .then_error(AiConfigError::EmptyModel);
}

// --- RevokeAiConfig -------------------------------------------------------

#[test]
fn revoke_config_emits_single_revoked_event() {
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![created_event(&create_cmd)])
        .when(RevokeAiConfig {
            id,
            version: AggregateVersion::INITIAL,
        })
        .then(vec![AiConfigEvent::Revoked {
            id,
            version: AggregateVersion::INITIAL.next(),
        }]);
}

#[test]
fn revoke_config_rejects_if_not_created() {
    AiConfig::given(vec![])
        .when(RevokeAiConfig {
            id: Uuid::now_v7(),
            version: AggregateVersion::INITIAL,
        })
        .then_error(AiConfigError::NotFound);
}

#[test]
fn revoke_config_rejects_if_already_revoked() {
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![
        created_event(&create_cmd),
        AiConfigEvent::Revoked {
            id,
            version: AggregateVersion::INITIAL.next(),
        },
    ])
    .when(RevokeAiConfig {
        id,
        version: AggregateVersion::INITIAL.next(),
    })
    .then_error(AiConfigError::AlreadyRevoked);
}

#[test]
fn revoke_config_rejects_version_mismatch() {
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![created_event(&create_cmd)])
        .when(RevokeAiConfig {
            id,
            version: AggregateVersion::INITIAL.next(), // wrong version
        })
        .then_error(AiConfigError::VersionMismatch {
            expected: AggregateVersion::INITIAL.next(),
            actual: AggregateVersion::INITIAL,
        });
}

// --- Aggregate Entity tests -----------------------------------------------

#[test]
fn ai_config_category_is_ai_config() {
    assert_eq!(AiConfig::category(), "ai_config");
}
