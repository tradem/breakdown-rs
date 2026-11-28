// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

use std::collections::HashMap;

use kameo_es::test_utils::GivenEntity;
use kameo_es::{Apply, Entity, Metadata};
use uuid::Uuid;

use crate::ai::vision::is_curated_vision_model;
use crate::shared::{AggregateVersion, UserId};

use super::{
    AiConfig, AiConfigError, AiConfigEvent, CostDisplayPreference, CreateAiConfig, DocumentKind,
    LlmProvider, ReasoningEffortChoice, RevokeAiConfig, UpdateAiConfig,
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
        reasoning_effort: ReasoningEffortChoice::Auto,
        cost_display_preference: CostDisplayPreference::Token,
        zdr_attested: false,
        vision_provider: None,
        vision_model: None,
        vision_vault_key_id: None,
        vision_zdr_attested: false,
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
        reasoning_effort: None,
        cost_display_preference: Some(CostDisplayPreference::Energy),
        zdr_attested: None,
        vision_provider: None,
        vision_model: None,
        vision_vault_key_id: None,
        vision_zdr_attested: None,
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
        reasoning_effort: cmd.reasoning_effort,
        zdr_attested: cmd.zdr_attested,
        vision_provider: cmd.vision_provider,
        vision_model: cmd.vision_model.clone(),
        vision_vault_key_id: cmd.vision_vault_key_id.clone(),
        vision_zdr_attested: cmd.vision_zdr_attested,
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
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
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
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
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
            reasoning_effort: None,
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
            reasoning_effort: ReasoningEffortChoice::Auto,
            cost_display_preference: None,
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
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
            reasoning_effort: ReasoningEffortChoice::Auto,
            cost_display_preference: None,
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
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
        reasoning_effort: ReasoningEffortChoice::Auto,
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
        reasoning_effort: ReasoningEffortChoice::Auto,
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
        reasoning_effort: ReasoningEffortChoice::Auto,
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
        reasoning_effort: ReasoningEffortChoice::Auto,
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
        reasoning_effort: ReasoningEffortChoice::Auto,
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
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            version: AggregateVersion::INITIAL.next(),
        }]);
    // `Some(None)` on all three fields clears the resolved slot.
    let clear = UpdateAiConfig {
        decision_provider: Some(None),
        decision_model: Some(None),
        decision_vault_key_id: Some(None),
        reasoning_effort: None,
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
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
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
    // The fixture is `liquid/d1`, the OpenRouter Decision Model that #1007
    // rotated to `liquid/d1.2`: the stored id is deliberately absent from
    // `curated_decision_model_ids(OpenRouter)` now, so a re-check of the
    // UNCHANGED stored model would reject the update and fail this test.
    let cmd = CreateAiConfig {
        decision_provider: Some(LlmProvider::OpenRouter),
        decision_model: Some("liquid/d1".into()),
        decision_vault_key_id: Some("settings-abc:decision-key".into()),
        reasoning_effort: ReasoningEffortChoice::Auto,
        ..make_create_cmd()
    };
    let id = cmd.id;
    assert!(!super::super::decision::is_curated_decision_model(
        LlmProvider::OpenRouter,
        "liquid/d1"
    ));
    // Negative direction first: the very same rotated-out id is still checked
    // and rejected on a fresh create (a CHANGED model is always curated-checked).
    AiConfig::given(vec![])
        .when(cmd.clone())
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
            decision_provider: Some(LlmProvider::OpenRouter),
            decision_model: Some("liquid/d1".into()),
            decision_vault_key_id: Some("settings-abc:decision-key".into()),
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            version: AggregateVersion::INITIAL.next(),
        }]);
}
// ---------------------------------------------------------------------------
// reasoning_effort (2026-11-20 output-budget investigation)
//
// The save-time 422: only a pair that DECLARES the parameter may name a level,
// and the model-specific value set is respected (`opencode/glm-5.3` accepts
// `low|high`, not `medium`). Refusing here is what keeps a misconfiguration from
// becoming a `400` on every single import call.
//
// `Auto` is a VALUE on the wire, not a `null`: the generated Dart client omits
// null fields, so a nullable setting could be set but never reset from the app.
// ---------------------------------------------------------------------------

/// A Neuralwatt config, whose curated models declare all four efforts.
fn neuralwatt_create_cmd(effort: ReasoningEffortChoice) -> CreateAiConfig {
    CreateAiConfig {
        provider: LlmProvider::Neuralwatt,
        assistant_model: "glm-5.3-flash".into(),
        reasoning_effort: effort,
        ..make_create_cmd()
    }
}

/// `make_update_cmd` leaves the effort unset; this fills in the resolved value so
/// the update tests can state the expected event exactly.
fn expected_updated(id: Uuid, effort: ReasoningEffortChoice) -> AiConfigEvent {
    AiConfigEvent::Updated {
        id,
        provider: LlmProvider::OpenAI,
        assistant_model: "gpt-4o-mini".into(),
        image_model: None,
        prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
        vault_key_id: "key-456".into(),
        cost_display_preference: Some(CostDisplayPreference::Energy),
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        reasoning_effort: effort,
        zdr_attested: Some(false),
        vision_provider: None,
        vision_model: None,
        vision_vault_key_id: None,
        vision_zdr_attested: false,
        version: AggregateVersion::INITIAL.next(),
    }
}

#[test]
fn a_declared_level_is_accepted_and_carried_on_the_event() {
    let cmd = neuralwatt_create_cmd(ReasoningEffortChoice::Low);
    let expected = created_event(&cmd);
    match &expected {
        AiConfigEvent::Created {
            reasoning_effort, ..
        } => assert_eq!(*reasoning_effort, ReasoningEffortChoice::Low),
        other => panic!("helper must build a Created event, got {other:?}"),
    }
    AiConfig::given(vec![]).when(cmd).then(vec![expected]);
}

/// `eurouter/mistral-large-3` declares no `reasoning_effort`, so naming a level is
/// refused instead of silently sending an undeclared parameter.
#[test]
fn an_undeclared_parameter_is_refused_at_save_time() {
    let cmd = CreateAiConfig {
        provider: LlmProvider::EURouter,
        assistant_model: "mistral-large-3".into(),
        reasoning_effort: ReasoningEffortChoice::Low,
        ..make_create_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::ReasoningEffortUnsupported);
}

/// The value set is per model, not global: this endpoint takes `low|high|max`.
#[test]
fn a_level_outside_the_model_set_is_refused() {
    let cmd = CreateAiConfig {
        provider: LlmProvider::OpenCode,
        assistant_model: "glm-5.3".into(),
        reasoning_effort: ReasoningEffortChoice::Medium,
        ..make_create_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::ReasoningEffortUnsupported);
}

#[test]
fn a_level_inside_the_model_set_is_accepted() {
    let cmd = CreateAiConfig {
        provider: LlmProvider::OpenCode,
        assistant_model: "glm-5.3".into(),
        reasoning_effort: ReasoningEffortChoice::Low,
        ..make_create_cmd()
    };
    let expected = created_event(&cmd);
    AiConfig::given(vec![]).when(cmd).then(vec![expected]);
}

#[test]
fn auto_is_always_valid() {
    // `Auto` asks the system to decide — valid on every pair, including one that
    // declares no parameter at all (what every pre-field configuration did).
    let cmd = CreateAiConfig {
        provider: LlmProvider::EURouter,
        assistant_model: "mistral-large-3".into(),
        reasoning_effort: ReasoningEffortChoice::Auto,
        ..make_create_cmd()
    };
    let expected = created_event(&cmd);
    AiConfig::given(vec![]).when(cmd).then(vec![expected]);
}

/// An omitted field (an older client) KEEPS the stored choice.
#[test]
fn update_keeps_the_stored_choice_when_the_field_is_omitted() {
    // The Updated event carries the AGGREGATE id, i.e. the one from Created.
    let create = make_create_cmd();
    let id = create.id;
    let created = created_event(&create);
    let update = make_update_cmd(id, AggregateVersion::INITIAL);
    AiConfig::given(vec![created])
        .when(update)
        .then(vec![expected_updated(id, ReasoningEffortChoice::Auto)]);
}

/// Issue #968: the zero-data-retention attestation is sticky unless the update
/// says otherwise. An omitted field keeps the stored attestation (an older
/// client editing the prompts must not silently re-close the vision egress
/// gate), while an explicit `Some(false)` revokes it — and the RESOLVED value
/// travels on the event so replay needs no logic.
#[test]
fn the_zdr_attestation_is_sticky_and_explicitly_revocable() {
    let mut create_cmd = make_create_cmd();
    create_cmd.zdr_attested = true;
    // Omitted (`None`) keeps the stored attestation — while the CREDENTIAL it
    // was given for is unchanged, so this update reuses `key-123`.
    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            vault_key_id: "key-123".into(),
            zdr_attested: None,
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: None,
            ..make_update_cmd(create_cmd.id, AggregateVersion::INITIAL)
        })
        .then(vec![AiConfigEvent::Updated {
            id: create_cmd.id,
            provider: LlmProvider::OpenAI,
            assistant_model: "gpt-4o-mini".into(),
            image_model: None,
            prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
            vault_key_id: "key-123".into(),
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            reasoning_effort: ReasoningEffortChoice::Auto,
            cost_display_preference: Some(CostDisplayPreference::Energy),
            zdr_attested: Some(true),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            version: AggregateVersion::INITIAL.next(),
        }]);

    // An explicit `Some(false)` revokes it — the only way it can be lost.
    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: None,
            ..make_update_cmd(create_cmd.id, AggregateVersion::INITIAL)
        })
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
            reasoning_effort: ReasoningEffortChoice::Auto,
            cost_display_preference: Some(CostDisplayPreference::Energy),
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            version: AggregateVersion::INITIAL.next(),
        }]);
}

/// The attestation is bound to the CREDENTIAL it was given for (review
/// finding on issue #968). `zdr_attested` describes one organization's `ZDR
/// Mode` switch, which nothing in this workspace can observe — so it must not
/// survive a `vault_key_id` change. An omitted field on a key-changing update
/// resolves to `false` (fail-closed) instead of being inherited, and the same
/// request can carry it over with an explicit `Some(true)`.
#[test]
fn the_zdr_attestation_does_not_survive_a_credential_change() {
    let mut create_cmd = make_create_cmd();
    create_cmd.zdr_attested = true;
    // Omitted (`None`) + a NEW vault key: the old account's attestation is
    // dropped, and the field still travels as a resolved value.
    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            vault_key_id: "key-456".into(),
            zdr_attested: None,
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: None,
            ..make_update_cmd(create_cmd.id, AggregateVersion::INITIAL)
        })
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
            reasoning_effort: ReasoningEffortChoice::Auto,
            cost_display_preference: Some(CostDisplayPreference::Energy),
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            version: AggregateVersion::INITIAL.next(),
        }]);

    // Re-attesting the replacement account in the SAME request keeps `true`.
    AiConfig::given(vec![created_event(&create_cmd)])
        .when(UpdateAiConfig {
            vault_key_id: "key-456".into(),
            zdr_attested: Some(true),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: None,
            ..make_update_cmd(create_cmd.id, AggregateVersion::INITIAL)
        })
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
            reasoning_effort: ReasoningEffortChoice::Auto,
            cost_display_preference: Some(CostDisplayPreference::Energy),
            zdr_attested: Some(true),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            version: AggregateVersion::INITIAL.next(),
        }]);
}

/// `Auto` RESETS a stored level, and the reset must reach the event so the
/// projector can null the column — the direction a `null` field could never
/// express from the app.
#[test]
fn update_resets_the_level_with_an_explicit_auto() {
    let stored = AiConfigEvent::Created {
        id: Uuid::nil(),
        user_id: user_id(),
        provider: LlmProvider::Neuralwatt,
        assistant_model: "glm-5.3-flash".into(),
        image_model: None,
        prompts: HashMap::from([(DocumentKind::Script, "Summarize".into())]),
        vault_key_id: "key-123".into(),
        cost_display_preference: CostDisplayPreference::Token,
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        reasoning_effort: ReasoningEffortChoice::High,
        zdr_attested: false,
        vision_provider: None,
        vision_model: None,
        vision_vault_key_id: None,
        vision_zdr_attested: false,
        version: AggregateVersion::INITIAL,
    };
    let update = UpdateAiConfig {
        provider: LlmProvider::Neuralwatt,
        assistant_model: "glm-5.3-flash".into(),
        reasoning_effort: Some(ReasoningEffortChoice::Auto),
        ..make_update_cmd(Uuid::nil(), AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![stored])
        .when(update)
        .then(vec![AiConfigEvent::Updated {
            id: Uuid::nil(),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "glm-5.3-flash".into(),
            image_model: None,
            prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
            vault_key_id: "key-456".into(),
            cost_display_preference: Some(CostDisplayPreference::Energy),
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            version: AggregateVersion::INITIAL.next(),
        }]);
}

/// Catalogue-rotation safety: an UNCHANGED pair+level is not re-validated, so a
/// later catalogue update cannot brick a prompt-only edit of an existing
/// configuration. Mirrors the `model_unchanged` rule of the decision slot.
#[test]
fn an_unchanged_stored_level_is_not_revalidated() {
    // A stored configuration whose pair no longer declares the parameter — the
    // shape a catalogue rotation leaves behind. Only reachable by REPLAYING the
    // event (the create path would refuse it today).
    let stored = AiConfigEvent::Created {
        id: Uuid::nil(),
        user_id: user_id(),
        provider: LlmProvider::EURouter,
        assistant_model: "mistral-large-3".into(),
        image_model: None,
        prompts: HashMap::from([(DocumentKind::Script, "Summarize".into())]),
        vault_key_id: "key-123".into(),
        cost_display_preference: CostDisplayPreference::Token,
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        reasoning_effort: ReasoningEffortChoice::Low,
        zdr_attested: false,
        vision_provider: None,
        vision_model: None,
        vision_vault_key_id: None,
        vision_zdr_attested: false,
        version: AggregateVersion::INITIAL,
    };
    let update = UpdateAiConfig {
        provider: LlmProvider::EURouter,
        assistant_model: "mistral-large-3".into(),
        reasoning_effort: None,
        prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
        ..make_update_cmd(Uuid::nil(), AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![stored])
        .when(update)
        .then(vec![AiConfigEvent::Updated {
            id: Uuid::nil(),
            provider: LlmProvider::EURouter,
            assistant_model: "mistral-large-3".into(),
            image_model: None,
            prompts: HashMap::from([(DocumentKind::Script, "New prompt".into())]),
            vault_key_id: "key-456".into(),
            cost_display_preference: Some(CostDisplayPreference::Energy),
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            reasoning_effort: ReasoningEffortChoice::Low,
            zdr_attested: Some(false),
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            version: AggregateVersion::INITIAL.next(),
        }]);
}

/// A PROVIDER change re-validates even when the model id and the stored level
/// stay the same: the accepted value set comes from the provider's catalogue,
/// not from the model id. Leaving the provider out of the "unchanged" triple
/// let a PATCH through that resolved to a level the new provider does not
/// declare — the worker would then pay a `400` on every import call.
#[test]
fn a_provider_change_revalidates_an_unchanged_level() {
    // Stored on Neuralwatt, which declares `minimal` for `glm-5.3`.
    let stored = AiConfigEvent::Created {
        id: Uuid::nil(),
        user_id: user_id(),
        provider: LlmProvider::Neuralwatt,
        assistant_model: "glm-5.3".into(),
        image_model: None,
        prompts: HashMap::from([(DocumentKind::Script, "Summarize".into())]),
        vault_key_id: "key-123".into(),
        cost_display_preference: CostDisplayPreference::Token,
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        reasoning_effort: ReasoningEffortChoice::Minimal,
        zdr_attested: false,
        vision_provider: None,
        vision_model: None,
        vision_vault_key_id: None,
        vision_zdr_attested: false,
        version: AggregateVersion::INITIAL,
    };
    // Same model id, same level (omitted), but a different provider — a
    // legitimate credential hand-off with a fresh vault key. OpenCode declares
    // only `low|high` for `glm-5.3`, so `minimal` must be refused here.
    let update = UpdateAiConfig {
        provider: LlmProvider::OpenCode,
        assistant_model: "glm-5.3".into(),
        vault_key_id: "opencode-key-789".into(),
        reasoning_effort: None,
        ..make_update_cmd(Uuid::nil(), AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![stored])
        .when(update)
        .then_error(AiConfigError::ReasoningEffortUnsupported);
}

// ===========================================================================
// Issue #1013 — the Vision slot (provider/model/credential for PAGE IMAGES)
// ===========================================================================

/// A configuration whose ASSISTANT pair is text-only (`openai`/`gpt-4o`) and
/// whose vision slot points at a compliant EU provider. This is the exact
/// shape the issue exists for: the page call must be configurable
/// independently of the text call.
fn make_vision_cmd() -> CreateAiConfig {
    CreateAiConfig {
        vision_provider: Some(LlmProvider::Ovhcloud),
        vision_model: Some("qwen3-vl-30b-a3b".into()),
        vision_vault_key_id: Some("settings-abc:vision-key".into()),
        vision_zdr_attested: false,
        ..make_create_cmd()
    }
}

#[test]
fn create_config_accepts_a_compliant_vision_slot() {
    let cmd = make_vision_cmd();
    let expected = vec![created_event(&cmd)];
    AiConfig::given(vec![]).when(cmd).then(expected);
}

#[test]
fn create_config_accepts_vision_same_key_reuse_within_one_provider() {
    // Same provider for text and images: reusing the extraction key is legal
    // (the #722 same-key rule, applied to the vision slot).
    let cmd = CreateAiConfig {
        provider: LlmProvider::Ovhcloud,
        vision_provider: Some(LlmProvider::Ovhcloud),
        vision_model: Some("qwen3-vl-30b-a3b".into()),
        vision_vault_key_id: Some("key-123".into()),
        ..make_create_cmd()
    };
    let expected = vec![created_event(&cmd)];
    AiConfig::given(vec![]).when(cmd).then(expected);
}

#[test]
fn create_config_rejects_vision_same_key_reuse_across_providers() {
    // `key-123` belongs to the OpenAI extraction binding; naming it for an
    // OVHcloud vision client would authenticate against the wrong endpoint.
    let cmd = CreateAiConfig {
        vision_vault_key_id: Some("key-123".into()),
        ..make_vision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::VisionVaultKeyMismatch);
}

#[test]
fn create_config_rejects_a_non_compliant_vision_provider() {
    // `openai` is a perfectly legal TEXT provider but cannot carry page images
    // (ADR-041 D2): refused at save time, never on the first paid page.
    let cmd = CreateAiConfig {
        vision_provider: Some(LlmProvider::OpenAI),
        ..make_vision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::VisionProviderUnsupported);
}

#[test]
fn create_config_requires_the_attestation_for_an_account_zdr_provider() {
    // Nebius declares EU residency + no training, but its ZDR is an account
    // switch the code cannot observe — fail-closed until attested.
    let unattested = CreateAiConfig {
        vision_provider: Some(LlmProvider::Nebius),
        vision_model: Some("Qwen/Qwen3.8-27B".into()),
        ..make_vision_cmd()
    };
    AiConfig::given(vec![])
        .when(unattested)
        .then_error(AiConfigError::VisionProviderUnsupported);
    // …and the attestation lifts exactly that one flag.
    let attested = CreateAiConfig {
        vision_provider: Some(LlmProvider::Nebius),
        vision_model: Some("Qwen/Qwen3.8-27B".into()),
        vision_zdr_attested: true,
        ..make_vision_cmd()
    };
    let expected = vec![created_event(&attested)];
    AiConfig::given(vec![]).when(attested).then(expected);
}

#[test]
fn create_config_rejects_a_partial_vision_slot() {
    // Provider without model/key.
    let cmd = CreateAiConfig {
        vision_model: None,
        vision_vault_key_id: None,
        vision_zdr_attested: false,
        ..make_vision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::VisionProviderRequired);
    // Model without provider.
    let cmd = CreateAiConfig {
        vision_provider: None,
        vision_vault_key_id: None,
        vision_zdr_attested: false,
        ..make_vision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::VisionProviderRequired);
    // An attestation without a vision provider describes an account nothing
    // uses — refused instead of stored.
    let cmd = CreateAiConfig {
        vision_provider: None,
        vision_model: None,
        vision_vault_key_id: None,
        vision_zdr_attested: true,
        ..make_vision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::VisionProviderRequired);
}

#[test]
fn create_config_rejects_an_empty_vision_model_or_vault_key() {
    let cmd = CreateAiConfig {
        vision_model: Some("   ".into()),
        ..make_vision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::EmptyVisionModel);
    let cmd = CreateAiConfig {
        vision_vault_key_id: Some("  ".into()),
        ..make_vision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::EmptyVisionVaultKey);
}

#[test]
fn update_config_resolves_the_tri_state_vision_slot() {
    let cmd = make_vision_cmd();
    let id = cmd.id;
    // Omitted vision fields keep the stored slot; the emitted Updated event
    // carries the RESOLVED slot (mirroring the decision triple).
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
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            vision_provider: Some(LlmProvider::Ovhcloud),
            vision_model: Some("qwen3-vl-30b-a3b".into()),
            vision_vault_key_id: Some("settings-abc:vision-key".into()),
            vision_zdr_attested: false,
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            version: AggregateVersion::INITIAL.next(),
        }]);
    // `Some(None)` on all three fields clears the resolved slot — the import
    // falls back to the assistant pair, exactly as before the slot existed.
    let clear = UpdateAiConfig {
        vision_provider: Some(None),
        vision_model: Some(None),
        vision_vault_key_id: Some(None),
        vision_zdr_attested: Some(false),
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
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            version: AggregateVersion::INITIAL.next(),
        }]);
}

#[test]
fn update_config_drops_the_vision_attestation_when_the_credential_changes() {
    // The attestation describes ONE account's `ZDR Mode`. Replacing the vision
    // credential without re-asserting it resolves to `false` — and for a
    // provider whose ZDR IS that switch, the resolved slot is then refused
    // (fail-closed) instead of carrying a guarantee from a different account.
    let cmd = CreateAiConfig {
        vision_provider: Some(LlmProvider::Nebius),
        vision_model: Some("Qwen/Qwen3.8-27B".into()),
        vision_zdr_attested: true,
        ..make_vision_cmd()
    };
    let id = cmd.id;
    let replacement = UpdateAiConfig {
        vision_vault_key_id: Some(Some("settings-abc:other-vision-key".into())),
        vision_zdr_attested: None,
        ..make_update_cmd(id, AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![created_event(&cmd)])
        .when(replacement)
        .then_error(AiConfigError::VisionProviderUnsupported);
    // Re-asserting the attestation in the same request carries it over.
    let replacement = UpdateAiConfig {
        vision_vault_key_id: Some(Some("settings-abc:other-vision-key".into())),
        vision_zdr_attested: Some(true),
        ..make_update_cmd(id, AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![created_event(&cmd)])
        .when(replacement.clone())
        .then(vec![AiConfigEvent::Updated {
            id,
            provider: replacement.provider,
            assistant_model: replacement.assistant_model.clone(),
            image_model: replacement.image_model.clone(),
            prompts: replacement.prompts.clone(),
            vault_key_id: replacement.vault_key_id.clone(),
            cost_display_preference: replacement.cost_display_preference,
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            vision_provider: Some(LlmProvider::Nebius),
            vision_model: Some("Qwen/Qwen3.8-27B".into()),
            vision_vault_key_id: Some("settings-abc:other-vision-key".into()),
            vision_zdr_attested: true,
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            version: AggregateVersion::INITIAL.next(),
        }]);
}

#[test]
fn pre_1013_events_replay_without_a_vision_slot() {
    // A payload serialized before the vision fields existed deserializes to
    // "no vision slot" + no attestation — the assistant-pair fallback, which
    // is byte-identical to how those configurations behaved.
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
            vision_provider,
            vision_model,
            vision_vault_key_id,
            vision_zdr_attested,
            ..
        } => {
            assert_eq!(vision_provider, None);
            assert_eq!(vision_model, None);
            assert_eq!(vision_vault_key_id, None);
            assert!(!vision_zdr_attested);
        }
        other => panic!("expected Created, got {other:?}"),
    }
}

#[test]
fn create_config_rejects_an_uncurated_vision_model_for_a_verified_catalogue() {
    // OVHcloud publishes a verified vision catalogue, so a model outside it is
    // refused at save time instead of failing on the first page.
    let cmd = CreateAiConfig {
        vision_provider: Some(LlmProvider::Ovhcloud),
        vision_model: Some("gpt-4o".into()),
        ..make_vision_cmd()
    };
    AiConfig::given(vec![])
        .when(cmd)
        .then_error(AiConfigError::VisionModelUnknown);
}

#[test]
fn a_vision_model_is_revalidated_only_when_it_changes() {
    // A stored model that has since left the curated catalogue must not brick an
    // unrelated edit — the worker still accepts it and the egress gate still
    // applies at runtime. Only a CHANGED model is checked against the catalogue.
    // `Qwen2.5-VL-72B-Instruct` is in OVHcloud's own catalogue but deliberately
    // NOT curated here ("Being retired"), so it stands in for a model that was
    // rotated out of the catalogue after this configuration was saved.
    let stale_model = "Qwen2.5-VL-72B-Instruct";
    assert!(
        !is_curated_vision_model(LlmProvider::Ovhcloud, stale_model),
        "the seeded model must be uncurated for this test to prove anything"
    );
    let created = CreateAiConfig {
        vision_provider: Some(LlmProvider::Ovhcloud),
        vision_model: Some(stale_model.into()),
        ..make_vision_cmd()
    };
    let id = created.id;
    // Keep the slot untouched: accepted even though the model is "old".
    let keep = UpdateAiConfig {
        assistant_model: "gpt-4o-mini".into(),
        ..make_update_cmd(id, AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![created_event(&created)])
        .when(keep.clone())
        .then(vec![AiConfigEvent::Updated {
            id,
            provider: keep.provider,
            assistant_model: keep.assistant_model.clone(),
            image_model: keep.image_model.clone(),
            prompts: keep.prompts.clone(),
            vault_key_id: keep.vault_key_id.clone(),
            cost_display_preference: keep.cost_display_preference,
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            vision_provider: Some(LlmProvider::Ovhcloud),
            vision_model: Some(stale_model.into()),
            vision_vault_key_id: Some("settings-abc:vision-key".into()),
            vision_zdr_attested: false,
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: Some(false),
            version: AggregateVersion::INITIAL.next(),
        }]);
    // Changing it to an uncurated ID is refused.
    let swap = UpdateAiConfig {
        vision_model: Some(Some("not-a-vision-model".into())),
        ..make_update_cmd(id, AggregateVersion::INITIAL)
    };
    AiConfig::given(vec![created_event(&created)])
        .when(swap)
        .then_error(AiConfigError::VisionModelUnknown);
}
