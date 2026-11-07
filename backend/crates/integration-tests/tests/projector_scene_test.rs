// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod fixtures;

use anyhow::Result;
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::events::{SceneDetails, SceneEvent, SceneSource};
use breakdown_core::shared::{AggregateVersion, EpisodeId};
use chrono::Utc;
use infra::projectors::SceneProjector;
use kameo_es::event_handler::EntityEventHandler;
use kameo_es::{Entity, EventType};
use kameo_es::{Event, Metadata, StreamId};
use sqlx::Row;
use uuid::Uuid;

#[tokio::test]
async fn scene_created_event_projects_to_projection_scene() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let details = SceneDetails {
        scene_score: None,
        synopsis_score: None,
        scene_number: Some(42),
        location: Some("Berlin".into()),
        mood: Some("dark".into()),
        is_schedule_set: true,
        summary: None,
        script_day: None,
    };
    let event = SceneEvent::SceneCreated {
        id: scene_id,
        episode_id,
        details: details.clone(),
        assigned_characters: vec![Uuid::now_v7()],
        version: AggregateVersion::INITIAL,
        source: SceneSource::Manual,
    };

    let mut tx = pool.begin().await?;
    let kameo_event = Event {
        id: Uuid::now_v7(),
        partition_key: Uuid::now_v7(),
        partition_id: 0,
        transaction_id: Uuid::now_v7(),
        partition_sequence: 1,
        stream_version: 1,
        stream_id: StreamId::new_from_parts(SceneAggregate::category(), scene_id),
        name: event.event_type().to_string(),
        data: event,
        metadata: Metadata::default(),
        timestamp: Utc::now(),
    };

    SceneProjector
        .handle(&mut tx, scene_id, kameo_event)
        .await?;
    tx.commit().await?;

    let row = sqlx::query("SELECT * FROM projection_scene WHERE id = $1")
        .bind(scene_id)
        .fetch_one(&pool)
        .await?;

    assert_eq!(row.try_get::<Uuid, _>("id")?, scene_id);
    assert_eq!(row.try_get::<Uuid, _>("episode_id")?, episode_id.0);
    assert_eq!(row.try_get::<i32, _>("scene_number")?, 42);
    assert_eq!(row.try_get::<String, _>("location")?, "Berlin");
    assert_eq!(row.try_get::<String, _>("mood")?, "dark");
    assert!(row.try_get::<bool, _>("is_schedule_set")?);
    assert_eq!(row.try_get::<i64, _>("version")?, 1);
    // An unscored scene (manual create, or the best-effort scoring pass
    // failed) projects NULL — the honest absence, never a fabricated value
    // (issue #834).
    assert_eq!(row.try_get::<Option<f64>, _>("scene_score")?, None);
    assert_eq!(row.try_get::<Option<f64>, _>("synopsis_score")?, None);

    let character_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_scene_character WHERE scene_id = $1")
            .bind(scene_id)
            .fetch_one(&pool)
            .await?;
    assert_eq!(character_count, 1);

    Ok(())
}

/// A scored AI-apply create projects the Decision-Model scores (issue #834),
/// and a later `SceneDetailsUpdated` PRESERVES them — a detail edit must not
/// erase the recorded provenance (re-scoring is out of scope for #834).
#[tokio::test]
async fn scene_scores_persist_on_create_and_survive_details_update() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let scored = SceneDetails {
        scene_score: Some(0.82),
        synopsis_score: Some(0.41),
        scene_number: Some(7),
        location: Some("Set B".into()),
        mood: Some("Tag".into()),
        is_schedule_set: false,
        summary: Some("TL;DR".into()),
        script_day: Some("1. Spieltag".into()),
    };
    let create = SceneEvent::SceneCreated {
        id: scene_id,
        episode_id,
        details: scored,
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
        source: SceneSource::AiExtracted {
            document_id: Uuid::now_v7(),
            external_ref: Some("scene-7".into()),
            confidence: None,
        },
    };

    let mut tx = pool.begin().await?;
    SceneProjector
        .handle(
            &mut tx,
            scene_id,
            Event {
                id: Uuid::now_v7(),
                partition_key: Uuid::now_v7(),
                partition_id: 0,
                transaction_id: Uuid::now_v7(),
                partition_sequence: 1,
                stream_version: 1,
                stream_id: StreamId::new_from_parts(SceneAggregate::category(), scene_id),
                name: create.event_type().to_string(),
                data: create,
                metadata: Metadata::default(),
                timestamp: Utc::now(),
            },
        )
        .await?;
    tx.commit().await?;

    let row = sqlx::query("SELECT scene_score, synopsis_score FROM projection_scene WHERE id = $1")
        .bind(scene_id)
        .fetch_one(&pool)
        .await?;
    // The f32 domain values upcast losslessly into the double-precision
    // columns; compare against the same upcast.
    assert_eq!(
        row.try_get::<Option<f64>, _>("scene_score")?,
        Some(0.82f32 as f64)
    );
    assert_eq!(
        row.try_get::<Option<f64>, _>("synopsis_score")?,
        Some(0.41f32 as f64)
    );

    // A details update carries the scores in the payload (the command
    // echoes the read DTO) but the projector must NOT overwrite the
    // persisted provenance with the client-echoed values.
    let edited = SceneDetails {
        scene_score: None,
        synopsis_score: None,
        scene_number: Some(8),
        location: Some("Set C".into()),
        mood: None,
        is_schedule_set: false,
        summary: Some("Umschrieben".into()),
        script_day: None,
    };
    let update = SceneEvent::SceneDetailsUpdated {
        id: scene_id,
        details: edited,
        version: AggregateVersion(2),
    };
    let mut tx = pool.begin().await?;
    SceneProjector
        .handle(
            &mut tx,
            scene_id,
            Event {
                id: Uuid::now_v7(),
                partition_key: Uuid::now_v7(),
                partition_id: 0,
                transaction_id: Uuid::now_v7(),
                partition_sequence: 2,
                stream_version: 2,
                stream_id: StreamId::new_from_parts(SceneAggregate::category(), scene_id),
                name: update.event_type().to_string(),
                data: update,
                metadata: Metadata::default(),
                timestamp: Utc::now(),
            },
        )
        .await?;
    tx.commit().await?;

    let row = sqlx::query("SELECT scene_score, synopsis_score, location, scene_number FROM projection_scene WHERE id = $1")
        .bind(scene_id)
        .fetch_one(&pool)
        .await?;
    // Scores preserved, the edited fields applied.
    assert_eq!(
        row.try_get::<Option<f64>, _>("scene_score")?,
        Some(0.82f32 as f64)
    );
    assert_eq!(
        row.try_get::<Option<f64>, _>("synopsis_score")?,
        Some(0.41f32 as f64)
    );
    assert_eq!(row.try_get::<String, _>("location")?, "Set C");
    assert_eq!(row.try_get::<i32, _>("scene_number")?, 8);

    Ok(())
}
