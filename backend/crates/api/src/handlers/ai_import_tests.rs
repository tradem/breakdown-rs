// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use breakdown_core::ai::{
    ApplyGateError, ApplyMapping, ApplyMappingDecision, DocumentKind, DraftScene, ScriptContext,
    SourceFormat, ensure_script_applyable, plan_scene_apply,
};
use breakdown_core::shared::{AggregateVersion, EpisodeId, UserId};
use uuid::Uuid;

use super::{ai_dedup_key, forbidden_ai_config, parse_ai_provider};

#[test]
fn reupload_dedup_key_is_stable_and_kind_specific() {
    let user = UserId::from_sub("handler-test-user");
    let other_user = UserId::from_sub("handler-test-other-user");
    let script = ai_dedup_key(&user, DocumentKind::Script, SourceFormat::Pdf, "digest");
    let same_script = ai_dedup_key(&user, DocumentKind::Script, SourceFormat::Pdf, "digest");
    let schedule = ai_dedup_key(&user, DocumentKind::Schedule, SourceFormat::Csv, "digest");
    let other = ai_dedup_key(
        &other_user,
        DocumentKind::Script,
        SourceFormat::Pdf,
        "digest",
    );
    assert_eq!(script, same_script);
    assert_ne!(script, schedule);
    // The user segment stops one user's upload from matching another user's
    // job: the same document under a different user must never dedup.
    assert_ne!(script, other);
}

#[test]
fn reupload_dedup_key_is_format_specific() {
    // Issue #221: identical bytes declared as CSV vs. PDF/plain-text route to
    // different extraction paths, so the dedup identity must include the
    // declared format — a re-upload with a different Content-Type must enqueue
    // a distinct job instead of reusing the CSV-routed one.
    let user = UserId::from_sub("handler-test-user");
    let csv = ai_dedup_key(&user, DocumentKind::Schedule, SourceFormat::Csv, "digest");
    let pdf = ai_dedup_key(&user, DocumentKind::Schedule, SourceFormat::Pdf, "digest");
    let plain = ai_dedup_key(
        &user,
        DocumentKind::Schedule,
        SourceFormat::PlainText,
        "digest",
    );
    assert_ne!(csv, pdf);
    assert_ne!(csv, plain);
    assert_ne!(pdf, plain);
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
    // Canonical keys and every curated alias must be accepted — these arms are
    // the ones most likely to be dropped in a refactor.
    for alias in [
        "openrouter_eu",
        "openrouter-eu",
        "opencode_go",
        "opencode-go",
        "openai",
        "openrouter",
        "opencode",
        "ollama",
    ] {
        assert!(parse_ai_provider(alias).is_ok(), "alias {alias} rejected");
    }
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
