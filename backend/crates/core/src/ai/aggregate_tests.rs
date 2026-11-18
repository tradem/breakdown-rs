// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

use std::collections::HashMap;

use kameo_es::test_utils::GivenEntity;
use kameo_es::{Apply, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, UserId};

use super::{
    AiConfig, AiConfigError, AiConfigEvent, CostDisplayPreference, CreateAiConfig, DocumentKind,
    LlmProvider, RevokeAiConfig, UpdateAiConfig,
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
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        cost_display_preference: CostDisplayPreference::Token,
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
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        cost_display_preference: Some(CostDisplayPreference::Energy),
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
        decision_provider: cmd.decision_provider,
        decision_model: cmd.decision_model.clone(),
        decision_vault_key_id: cmd.decision_vault_key_id.clone(),
        cost_display_preference: cmd.cost_display_preference,
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
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            cost_display_preference: Some(CostDisplayPreference::Energy),
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
fn update_config_rejects_provider_mismatch_with_old_vault_key() {
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            provider: LlmProvider::Ollama, // different from Created
            vault_key_id: "key-123".into(),
            ..make_update_cmd(id, AggregateVersion::INITIAL)
        })
        .then_error(AiConfigError::ProviderMismatch);
}

#[test]
fn update_config_accepts_provider_replacement_with_new_vault_key() {
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            provider: LlmProvider::Ollama,
            vault_key_id: "key-789".into(),
            ..make_update_cmd(id, AggregateVersion::INITIAL)
        })
        .then(vec![AiConfigEvent::Updated {
            id,
            provider: LlmProvider::Ollama,
            assistant_model: "gpt-4o-mini".into(),
            image_model: None,
            prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
            vault_key_id: "key-789".into(),
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            cost_display_preference: Some(CostDisplayPreference::Energy),
            version: AggregateVersion::INITIAL.next(),
        }]);
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

// --- CostDisplayPreference (issue #675) -----------------------------------

#[test]
fn create_config_carries_energy_display_preference() {
    let mut cmd = make_create_cmd();
    cmd.cost_display_preference = CostDisplayPreference::Energy;
    let expected = created_event(&cmd);

    AiConfig::given(vec![]).when(cmd).then(vec![expected]);
}

#[test]
fn legacy_created_event_without_preference_replays_as_token() {
    // Pre-#675 event payload: no `cost_display_preference` key at all.
    let legacy = serde_json::json!({
        "Created": {
            "id": Uuid::now_v7(),
            "user_id": "legacy-user",
            "provider": "openai",
            "assistant_model": "gpt-4o",
            "image_model": null,
            "prompts": { "script": "p" },
            "vault_key_id": "key-1",
            "version": 1,
        }
    });
    let event: AiConfigEvent = serde_json::from_value(legacy)
        .unwrap_or_else(|e| panic!("legacy event must deserialize: {e}"));
    match event {
        AiConfigEvent::Created {
            cost_display_preference,
            ..
        } => assert_eq!(cost_display_preference, CostDisplayPreference::Token),
        other => panic!("wrong variant: {other:?}"),
    }
}

#[test]
fn update_with_omitted_preference_keeps_the_current_value() {
    // A PATCH that omits `cost_display_preference` (e.g. an older client
    // editing other properties) must NOT reset an existing `energy`
    // preference to `token` — the command carries `None` and the aggregate
    // keeps its current value.
    let create_cmd = make_create_cmd();
    let id = create_cmd.id;

    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            cost_display_preference: None,
            ..make_update_cmd(id, AggregateVersion::INITIAL)
        })
        .then(vec![AiConfigEvent::Updated {
            id,
            provider: LlmProvider::OpenAI,
            assistant_model: "gpt-4o-mini".into(),
            image_model: None,
            prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
            vault_key_id: "key-456".into(),
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            cost_display_preference: None,
            version: AggregateVersion::INITIAL.next(),
        }]);
}

#[test]
fn applying_updated_without_preference_keeps_energy() {
    // The APPLY side of the rule (not just the emitted event): a Created
    // with `energy` followed by an Updated whose preference is `None` must
    // leave the aggregate's `energy` preference intact — the
    // `if let Some(preference)` branch in `apply`.
    let mut create_cmd = make_create_cmd();
    create_cmd.cost_display_preference = CostDisplayPreference::Energy;

    let mut agg = AiConfig::default();
    agg.apply(created_event(&create_cmd), Metadata::default());
    agg.apply(
        AiConfigEvent::Updated {
            id: create_cmd.id,
            provider: LlmProvider::OpenAI,
            assistant_model: "gpt-4o-mini".into(),
            image_model: None,
            prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
            vault_key_id: "key-456".into(),
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            cost_display_preference: None,
            version: AggregateVersion::INITIAL.next(),
        },
        Metadata::default(),
    );

    assert_eq!(agg.cost_display_preference, CostDisplayPreference::Energy);
}

#[test]
fn legacy_updated_event_without_preference_replays_as_none() {
    let legacy = serde_json::json!({
        "Updated": {
            "id": Uuid::now_v7(),
            "provider": "openai",
            "assistant_model": "gpt-4o-mini",
            "image_model": null,
            "prompts": { "script": "p" },
            "vault_key_id": "key-2",
            "version": 2,
        }
    });
    let event: AiConfigEvent = serde_json::from_value(legacy)
        .unwrap_or_else(|e| panic!("legacy event must deserialize: {e}"));
    match event {
        AiConfigEvent::Updated {
            cost_display_preference,
            ..
        } => assert_eq!(cost_display_preference, None),
        other => panic!("wrong variant: {other:?}"),
    }
}

#[test]
fn cost_display_preference_wire_values() {
    assert_eq!(CostDisplayPreference::Token.as_str(), "token");
    assert_eq!(CostDisplayPreference::Energy.as_str(), "energy");
    assert_eq!(
        serde_json::to_string(&CostDisplayPreference::Token).unwrap(),
        "\"token\""
    );
    assert_eq!(
        serde_json::to_string(&CostDisplayPreference::Energy).unwrap(),
        "\"energy\""
    );
    assert_eq!(
        serde_json::from_str::<CostDisplayPreference>("\"energy\"").unwrap(),
        CostDisplayPreference::Energy
    );
    assert_eq!(
        CostDisplayPreference::default(),
        CostDisplayPreference::Token
    );
}

// ===========================================================================
// Issue #722 — Decision Model configuration
// ===========================================================================

use super::super::decision::question_keys;

fn make_decision_cmd() -> CreateAiConfig {
    CreateAiConfig {
        decision_provider: Some(LlmProvider::Neuralwatt),
        decision_model: Some("clef-flash".into()),
        decision_vault_key_id: Some("settings-abc:decision-key".into()),
        ..make_create_cmd()
    }
}

#[test]
fn create_config_accepts_curated_decision_model() {
    let cmd = make_decision_cmd();
    // Accept-case: the DSL's `then(vec![..])` asserts the expected events.
    let expected = vec![created_event(&cmd)];
    AiConfig::given(vec![]).when(cmd).then(expected);
}

#[test]
fn create_config_rejects_non_decision_provider() {
    let cmd = CreateAiConfig {
        decision_provider: Some(LlmProvider::OpenAI),
        ..make_decision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::DecisionProviderUnsupported);
}

#[test]
fn create_config_rejects_partial_decision_config() {
    // Provider set without model/key → incomplete.
    let cmd = CreateAiConfig {
        decision_provider: Some(LlmProvider::Neuralwatt),
        decision_model: None,
        decision_vault_key_id: None,
        ..make_create_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::DecisionProviderRequired);
    // Model without provider → incomplete.
    let cmd = CreateAiConfig {
        decision_provider: None,
        decision_model: Some("clef-flash".into()),
        decision_vault_key_id: None,
        ..make_create_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::DecisionProviderRequired);
    // Vault key without provider → incomplete.
    let cmd = CreateAiConfig {
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: Some("k".into()),
        ..make_create_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::DecisionProviderRequired);
}

#[test]
fn create_config_rejects_uncurated_decision_model() {
    // `metis` is curated for EURouter, not Neuralwatt.
    let cmd = CreateAiConfig {
        decision_provider: Some(LlmProvider::Neuralwatt),
        decision_model: Some("metis".into()),
        ..make_decision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::DecisionModelUnknown);
    let cmd = CreateAiConfig {
        decision_model: Some("  ".into()),
        ..make_decision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::EmptyDecisionModel);
    let cmd = CreateAiConfig {
        decision_vault_key_id: Some("  ".into()),
        ..make_decision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::EmptyDecisionVaultKey);
}

#[test]
fn update_config_resolves_tri_state_decision_slot() {
    let cmd = make_decision_cmd();
    let id = cmd.id;
    // The `Given` builder consumes itself, so each assertion rebuilds it.
    // Omitted decision fields keep the stored slot: the emitted Updated event
    // carries the resolved (kept) configuration.
    let kept = UpdateAiConfig {
        assistant_model: "gpt-4o-mini".into(),
        ..make_update_cmd(id, AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![created_event(&cmd)])
        .when(kept.clone())
        .then(vec![AiConfigEvent::Updated {
            id,
            provider: kept.provider,
            assistant_model: kept.assistant_model.clone(),
            image_model: kept.image_model.clone(),
            prompts: kept.prompts.clone(),
            vault_key_id: kept.vault_key_id.clone(),
            cost_display_preference: kept.cost_display_preference,
            decision_provider: Some(LlmProvider::Neuralwatt),
            decision_model: Some("clef-flash".into()),
            decision_vault_key_id: Some("settings-abc:decision-key".into()),
            version: AggregateVersion::INITIAL.next(),
        }]);
    // `Some(None)` on all three fields clears the resolved slot.
    let clear = UpdateAiConfig {
        decision_provider: Some(None),
        decision_model: Some(None),
        decision_vault_key_id: Some(None),
        ..make_update_cmd(id, AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![created_event(&cmd)])
        .when(clear.clone())
        .then(vec![AiConfigEvent::Updated {
            id,
            provider: clear.provider,
            assistant_model: clear.assistant_model.clone(),
            image_model: clear.image_model.clone(),
            prompts: clear.prompts.clone(),
            vault_key_id: clear.vault_key_id.clone(),
            cost_display_preference: clear.cost_display_preference,
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            version: AggregateVersion::INITIAL.next(),
        }]);
}

#[test]
fn update_config_validates_the_resolved_decision_slot() {
    let cmd = make_decision_cmd();
    let id = cmd.id;
    // Clearing only the provider while the model stays → incomplete.
    let partial = UpdateAiConfig {
        decision_provider: Some(None),
        ..make_update_cmd(id, AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![created_event(&cmd)])
        .when(partial)
        .then_error(AiConfigError::DecisionProviderRequired);
    // Swapping to an uncurated model is rejected.
    let uncurated = UpdateAiConfig {
        decision_model: Some(Some("not-a-model".into())),
        ..make_update_cmd(id, AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![created_event(&cmd)])
        .when(uncurated)
        .then_error(AiConfigError::DecisionModelUnknown);
}

#[test]
fn pre_722_events_replay_without_decision_config() {
    // A payload serialized before the fields existed (no decision_* keys)
    // deserializes with all three `None` — backward-compatible replay.
    let payload = serde_json::json!({
        "Created": {
            "id": Uuid::now_v7(),
            "user_id": "test-user",
            "provider": "openai",
            "assistant_model": "m",
            "image_model": null,
            "prompts": {},
            "vault_key_id": "k",
            "cost_display_preference": "token",
            "version": 1
        }
    });
    let event: AiConfigEvent = serde_json::from_value(payload).unwrap();
    match event {
        AiConfigEvent::Created {
            decision_provider,
            decision_model,
            decision_vault_key_id,
            ..
        } => {
            assert_eq!(decision_provider, None);
            assert_eq!(decision_model, None);
            assert_eq!(decision_vault_key_id, None);
        }
        other => panic!("wrong variant: {other:?}"),
    }
}

#[test]
fn decision_question_keys_are_stable() {
    // Telemetry contract for the 0.5.x APO loop — renames break it.
    assert_eq!(question_keys::CHARACTERS_COMPLETE, "characters_complete");
    assert_eq!(question_keys::COSTUMES_COMPLETE, "costumes_complete");
    assert_eq!(
        question_keys::SCENE_METADATA_ACCURACY,
        "scene_metadata_accuracy"
    );
    assert_eq!(question_keys::SYNOPSIS_GROUNDED, "synopsis_grounded");
    assert_eq!(
        question_keys::SYNOPSIS_CONCISE_NO_DIALOGUE,
        "synopsis_concise_no_dialogue"
    );
    assert_eq!(
        question_keys::SYNOPSIS_COSTUME_AND_DEPT_RELEVANCE,
        "synopsis_costume_and_dept_relevance"
    );
    assert_eq!(
        question_keys::DAY_ASSIGNMENT_CONSISTENT,
        "day_assignment_consistent"
    );
}

#[test]
fn update_with_an_unchanged_rotated_model_is_accepted() {
    // Catalog-rotation safety (issue #722 review): a model that was curated
    // when the config was written but has since been rotated OUT of the
    // catalog must not brick unrelated updates — a prompt-only edit that
    // omits the decision fields resolves to the stored (no-longer-curated)
    // model and is accepted.
    let cmd = CreateAiConfig {
        decision_provider: Some(LlmProvider::Neuralwatt),
        decision_model: Some("clef".into()),
        decision_vault_key_id: Some("settings-abc:decision-key".into()),
        ..make_create_cmd()
    };
    let id = cmd.id;
    // Simulate a rotation: `clef` no longer curated for Neuralwatt would
    // fail a CHANGED model — but the omitted fields keep it, so the update
    // is accepted. (Assert the negative direction first: the same model on
    // a fresh create is still checked.)
    assert!(!super::super::decision::is_curated_decision_model(
        LlmProvider::EURouter,
        "clef"
    ));
    let rotated_to_eurouter = CreateAiConfig {
        decision_provider: Some(LlmProvider::EURouter),
        decision_model: Some("clef".into()),
        decision_vault_key_id: Some("settings-abc:decision-key".into()),
        ..make_create_cmd()
    };
    AiConfig::given(vec![])
        .when(rotated_to_eurouter)
        .then_error(AiConfigError::DecisionModelUnknown);

    // Prompt-only update with the stored (rotated) model untouched → ok.
    let update = UpdateAiConfig {
        assistant_model: "gpt-4o-mini".into(),
        ..make_update_cmd(id, AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![created_event(&cmd)])
        .when(update)
        .then(vec![AiConfigEvent::Updated {
            id,
            provider: LlmProvider::OpenAI,
            assistant_model: "gpt-4o-mini".into(),
            image_model: None,
            prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
            vault_key_id: "key-456".into(),
            cost_display_preference: Some(CostDisplayPreference::Energy),
            decision_provider: Some(LlmProvider::Neuralwatt),
            decision_model: Some("clef".into()),
            decision_vault_key_id: Some("settings-abc:decision-key".into()),
            version: AggregateVersion::INITIAL.next(),
        }]);
}
