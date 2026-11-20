// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Replay contract for [`AiConfigEvent`] (review finding 7).
//!
//! `reasoning_effort` is an ADDITIVE event field: events persisted before it
//! existed carry no such key. A missing key must deserialize to
//! [`ReasoningEffortChoice::Auto`] — the behaviour those configurations actually
//! ran with — instead of failing. A regression here surfaces neither as a
//! compile error nor as a red aggregate test: the projector dies on
//! deserialization, the event is dead-lettered (#37) and the configuration
//! silently stops updating.

use uuid::Uuid;

use crate::ai::reasoning::ReasoningEffortChoice;
use crate::shared::AggregateVersion;

use super::{AiConfigEvent, CostDisplayPreference, DocumentKind, LlmProvider};

/// A `Created` payload exactly as a pre-field version wrote it: no
/// `reasoning_effort` key at all.
const LEGACY_CREATED_JSON: &str = r#"{
    "Created": {
        "id": "018f2b3c-4d5e-7a6b-8c9d-0e1f2a3b4c5d",
        "user_id": "legacy-user",
        "provider": "eurouter",
        "assistant_model": "mistral-large-3",
        "image_model": null,
        "prompts": {"script": "Summarize"},
        "vault_key_id": "key-123",
        "cost_display_preference": "token",
        "decision_provider": null,
        "decision_model": null,
        "decision_vault_key_id": null,
        "version": 1
    }
}"#;

/// A `Updated` payload from the same era.
const LEGACY_UPDATED_JSON: &str = r#"{
    "Updated": {
        "id": "018f2b3c-4d5e-7a6b-8c9d-0e1f2a3b4c5d",
        "provider": "eurouter",
        "assistant_model": "mistral-large-3",
        "image_model": null,
        "prompts": {"script": "New prompt"},
        "vault_key_id": "key-456",
        "cost_display_preference": null,
        "decision_provider": null,
        "decision_model": null,
        "decision_vault_key_id": null,
        "version": 2
    }
}"#;

#[test]
fn a_legacy_created_event_replays_as_auto() {
    let event: AiConfigEvent = serde_json::from_str(LEGACY_CREATED_JSON)
        .expect("a pre-`reasoning_effort` Created event must stay replayable");
    let AiConfigEvent::Created {
        provider,
        reasoning_effort,
        assistant_model,
        prompts,
        version,
        ..
    } = &event
    else {
        panic!("the fixture is a Created event, got {event:?}");
    };
    assert_eq!(*provider, LlmProvider::EURouter);
    assert_eq!(assistant_model, "mistral-large-3");
    assert_eq!(
        prompts.get(&DocumentKind::Script).map(String::as_str),
        Some("Summarize")
    );
    assert_eq!(*version, AggregateVersion::INITIAL);
    // The point: no level was ever stored for these configurations, so `Auto`
    // reproduces exactly what they ran with.
    assert_eq!(*reasoning_effort, ReasoningEffortChoice::Auto);
}

#[test]
fn a_legacy_updated_event_replays_as_auto() {
    let event: AiConfigEvent = serde_json::from_str(LEGACY_UPDATED_JSON)
        .expect("a pre-`reasoning_effort` Updated event must stay replayable");
    let AiConfigEvent::Updated {
        reasoning_effort,
        cost_display_preference,
        version,
        ..
    } = &event
    else {
        panic!("the fixture is an Updated event, got {event:?}");
    };
    assert_eq!(*reasoning_effort, ReasoningEffortChoice::Auto);
    // An absent cost preference keeps the projector's current value (the #675
    // tri-state) — the same `serde(default)` idea, and this fixture pins that
    // the two additive fields are independent.
    assert_eq!(*cost_display_preference, None);
    assert_eq!(version.0, AggregateVersion::INITIAL.0 + 1);
}

/// An explicit level round-trips unchanged — the other half of the contract: the
/// default must not swallow a level that IS present.
#[test]
fn an_explicit_level_round_trips_through_the_event_payload() {
    let created = AiConfigEvent::Created {
        id: Uuid::nil(),
        user_id: crate::shared::UserId::from_sub("round-trip"),
        provider: LlmProvider::Neuralwatt,
        assistant_model: "glm-5.3-flash".to_owned(),
        image_model: None,
        prompts: std::collections::HashMap::from([(DocumentKind::Script, "Summarize".to_owned())]),
        vault_key_id: "key-123".to_owned(),
        cost_display_preference: CostDisplayPreference::Token,
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        reasoning_effort: ReasoningEffortChoice::Minimal,
        version: AggregateVersion::INITIAL,
    };
    let json = serde_json::to_string(&created).expect("the event serializes");
    let decoded: AiConfigEvent =
        serde_json::from_str(&json).expect("the serialized event deserializes");
    assert_eq!(decoded, created);
    assert!(
        json.contains("\"reasoning_effort\":\"minimal\""),
        "the level must be persisted, not defaulted away: {json}"
    );
}
