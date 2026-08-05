// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use breakdown_core::ai::{
    ApplyGateError, ApplyMapping, ApplyMappingDecision, DocumentKind, DraftScene, ScriptContext,
    ensure_script_applyable, plan_scene_apply,
};
use breakdown_core::shared::{AggregateVersion, EpisodeId, UserId};
use uuid::Uuid;

use super::{ai_dedup_key, forbidden_ai_config, parse_ai_provider};

#[test]
fn reupload_dedup_key_is_stable_and_kind_specific() {
    let user = UserId::from_sub("handler-test-user");
    let script = ai_dedup_key(&user, DocumentKind::Script, "digest");
    let same_script = ai_dedup_key(&user, DocumentKind::Script, "digest");
    let schedule = ai_dedup_key(&user, DocumentKind::Schedule, "digest");
    assert_eq!(script, same_script);
    assert_ne!(script, schedule);
}

#[test]
fn unauthorized_response_is_forbidden() {
    assert_eq!(forbidden_ai_config().0, axum::http::StatusCode::FORBIDDEN);
}

#[test]
fn provider_parser_rejects_unknown_values() {
    assert!(parse_ai_provider("not-a-provider").is_err());
    assert!(parse_ai_provider("neuralwatt").is_ok());
    assert!(parse_ai_provider("eurouter").is_ok());
}

#[test]
fn apply_gate_rejects_open_uncertainties() {
    let preview = ScriptContext {
        scenes: vec![DraftScene::default()],
        uncertainties: vec![breakdown_core::ai::Uncertainty {
            scene_index: 0,
            field: "location".to_owned(),
            note: "unclear".to_owned(),
            suggested_value: None,
        }],
        ..ScriptContext::default()
    };
    assert!(matches!(
        ensure_script_applyable(&preview),
        Err(ApplyGateError::OpenUncertainties(1))
    ));
}

#[test]
fn crash_retry_mapping_plans_update_instead_of_duplicate_create() {
    let aggregate_id = Uuid::now_v7();
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "scene-1".to_owned(),
            ..DraftScene::default()
        }],
        ..ScriptContext::default()
    };
    let plan = plan_scene_apply(
        &preview,
        &[ApplyMapping {
            draft_ref: "scene-1".to_owned(),
            decision: ApplyMappingDecision::Update {
                aggregate_id,
                version: AggregateVersion::INITIAL,
            },
        }],
        EpisodeId::new(),
        None,
    )
    .expect("mapped retry is valid in test");
    assert!(matches!(
        plan.as_slice(),
        [breakdown_core::ai::SceneApplyCommand::Update(command)]
            if command.id == aggregate_id
    ));
}
