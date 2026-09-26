// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-4.6-fp8 (neuralwatt)

//! AI provenance regression tests (issue #517, EU AI Act Art. 50 transparency):
//!
//! 1. Historic `SceneCreated` events — persisted *before* the additive `source`
//!    field existed — must keep deserializing (serde default `Manual`), because
//!    event replay reads every event of every stream on aggregate start.
//! 2. Historic `ShootingDaySource::AiExtracted` events with a plain numeric
//!    `confidence` must deserialize losslessly as `Some(...)`.
//! 3. A scene created through the AI worker path carries `AiExtracted`
//!    provenance (job id as `document_id`, draft ref as `external_ref`,
//!    `confidence: None` — the honest value) and the aggregate state keeps it.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)] // test code

use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::commands::CreateScene;
use breakdown_core::scene::events::{SceneEvent, SceneSource};
use breakdown_core::shared::EpisodeId;
use breakdown_core::shooting_day::events::ShootingDaySource;
use kameo_es::Command;
use serde_json::json;
use test_support::make_ctx;
use uuid::Uuid;

#[test]
fn legacy_scene_created_event_without_source_replays_as_manual() {
    let legacy = json!({
        "SceneCreated": {
            "id": Uuid::now_v7(),
            "episode_id": EpisodeId::new().0,
            "details": {
                "is_schedule_set": false,
                "summary": null,
                "script_day": null,
                "location": null,
                "mood": null,
                "scene_number": null
            },
            "assigned_characters": [],
            "version": 1
        }
    });
    let event: SceneEvent = serde_json::from_value(legacy).unwrap();
    match event {
        SceneEvent::SceneCreated { source, .. } => {
            assert_eq!(source, SceneSource::Manual);
        }
        other => panic!("unexpected event variant: {other:?}"),
    }
}

#[test]
fn legacy_shooting_day_source_with_numeric_confidence_deserializes_as_some() {
    let legacy = json!({
        "AiExtracted": {
            "document_id": Uuid::now_v7(),
            "external_ref": null,
            "confidence": 1.0
        }
    });
    let source: ShootingDaySource = serde_json::from_value(legacy).unwrap();
    match source {
        ShootingDaySource::AiExtracted { confidence, .. } => assert_eq!(confidence, Some(1.0)),
        other => panic!("unexpected source variant: {other:?}"),
    }
}

#[test]
fn ai_created_scene_keeps_ai_extracted_provenance() {
    let document_id = Uuid::now_v7();
    let events = SceneAggregate::default()
        .handle(
            CreateScene {
                id: Uuid::now_v7(),
                episode_id: EpisodeId::new(),
                series_id: None,
                details: Default::default(),
                source: SceneSource::AiExtracted {
                    document_id,
                    external_ref: Some("scene-42".to_owned()),
                    confidence: None,
                },
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1);
    let SceneEvent::SceneCreated { source, .. } = &events[0] else {
        panic!("expected SceneCreated")
    };
    assert_eq!(
        source,
        &SceneSource::AiExtracted {
            document_id,
            external_ref: Some("scene-42".to_owned()),
            confidence: None,
        }
    );

    // State rebuild keeps the provenance for the read model.
    let mut replayed = SceneAggregate::default();
    test_support::replay_events(&mut replayed, events);
    assert_eq!(
        replayed.source,
        SceneSource::AiExtracted {
            document_id,
            external_ref: Some("scene-42".to_owned()),
            confidence: None,
        }
    );
}
