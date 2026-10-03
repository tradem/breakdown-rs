// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

//! Projection + read-model round trip for scene costume beats (issue #546).
//!
//! Pins: (a) all four projector branches persist/repair exactly the beat
//! rows and leave surviving orders untouched on removal, (b) the
//! `PRIMARY KEY (scene_id, character_id, "order")` rules out two costumes
//! at one position (structural backstop), (c) the FK cascade deletes the
//! beats when the scene row disappears, (d) aggregate state and
//! `SceneView.costume_beats` agree for the same event stream (the `on
//! change` case: two costumes for one character, in order), and (e) the
//! query enrichment resolves character names best-effort (`None` on a
//! projection miss — never an error).

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
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::shared::{AggregateVersion, EpisodeId};
use chrono::{DateTime, Utc};
use infra::projectors::SceneProjector;
use infra::queries::SceneRepositoryImpl;
use kameo_es::event_handler::EntityEventHandler;
use kameo_es::{Apply, Entity, Event, EventType, Metadata, StreamId};
use uuid::Uuid;

async fn project(
    pool: &sqlx::PgPool,
    scene_id: Uuid,
    event: SceneEvent,
    now: DateTime<Utc>,
) -> Result<()> {
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
        timestamp: now,
    };
    let mut tx = pool.begin().await?;
    SceneProjector
        .handle(&mut tx, scene_id, kameo_event)
        .await?;
    tx.commit().await?;
    Ok(())
}

#[tokio::test]
async fn beat_events_project_and_read_back_in_order() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let coat = Uuid::now_v7();
    let shirt = Uuid::now_v7();
    let now = Utc::now();

    let events = vec![
        SceneEvent::SceneCreated {
            id: scene_id,
            episode_id,
            details: SceneDetails::default(),
            assigned_characters: vec![character_id],
            version: AggregateVersion::INITIAL,
            source: SceneSource::Manual,
        },
        // The `on change` case: two costumes for the same character, in order.
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id,
            costume_id: coat,
            order: 0,
            note: Some("Mantel".into()),
            version: AggregateVersion(2),
        },
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id,
            costume_id: shirt,
            order: 1,
            note: None,
            version: AggregateVersion(3),
        },
        // In-place edit never renumbers.
        SceneEvent::CostumeBeatUpdated {
            id: scene_id,
            character_id,
            order: 0,
            costume_id: coat,
            note: Some("Mantel, naß".into()),
            version: AggregateVersion(4),
        },
    ];

    for event in events {
        project(&pool, scene_id, event, now).await?;
    }

    let repo = SceneRepositoryImpl::new(pool.clone());
    let view = repo.find_by_id(scene_id).await?;

    assert_eq!(view.costume_beats.len(), 2);
    assert_eq!(view.costume_beats[0].character_id, character_id);
    assert_eq!(view.costume_beats[0].costume_id, coat);
    assert_eq!(view.costume_beats[0].order, 0);
    assert_eq!(view.costume_beats[0].note.as_deref(), Some("Mantel, naß"));
    assert_eq!(view.costume_beats[1].costume_id, shirt);
    assert_eq!(view.costume_beats[1].order, 1);

    // Enrichment is best-effort: no projection_character / projection_costume
    // rows were seeded, so the names resolve to None without failing.
    assert_eq!(view.costume_beats[0].character_name, None);
    assert_eq!(view.costume_beats[0].costume_category_name, None);

    Ok(())
}

#[tokio::test]
async fn beat_removal_keeps_surviving_orders_and_clear_deletes_all() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let now = Utc::now();

    for event in [
        SceneEvent::SceneCreated {
            id: scene_id,
            episode_id,
            details: SceneDetails::default(),
            assigned_characters: vec![character_id],
            version: AggregateVersion::INITIAL,
            source: SceneSource::Manual,
        },
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id,
            costume_id: Uuid::now_v7(),
            order: 0,
            note: None,
            version: AggregateVersion(2),
        },
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id,
            costume_id: Uuid::now_v7(),
            order: 1,
            note: None,
            version: AggregateVersion(3),
        },
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id,
            costume_id: Uuid::now_v7(),
            order: 2,
            note: None,
            version: AggregateVersion(4),
        },
        // Remove the middle beat: exactly one row goes.
        SceneEvent::CostumeBeatRemoved {
            id: scene_id,
            character_id,
            order: 1,
            version: AggregateVersion(5),
        },
    ] {
        project(&pool, scene_id, event, now).await?;
    }

    let repo = SceneRepositoryImpl::new(pool.clone());
    let view = repo.find_by_id(scene_id).await?;
    let mut orders: Vec<u32> = view.costume_beats.iter().map(|b| b.order).collect();
    orders.sort_unstable();
    assert_eq!(orders, vec![0, 2], "surviving orders must be untouched");

    // Clear: all remaining rows of the character go.
    project(
        &pool,
        scene_id,
        SceneEvent::CostumeBeatsCleared {
            id: scene_id,
            character_id,
            version: AggregateVersion(6),
        },
        now,
    )
    .await?;
    let view = repo.find_by_id(scene_id).await?;
    assert!(view.costume_beats.is_empty());

    Ok(())
}

#[tokio::test]
async fn projection_primary_key_rules_out_duplicate_position() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let now = Utc::now();

    project(
        &pool,
        scene_id,
        SceneEvent::SceneCreated {
            id: scene_id,
            episode_id,
            details: SceneDetails::default(),
            assigned_characters: vec![character_id],
            version: AggregateVersion::INITIAL,
            source: SceneSource::Manual,
        },
        now,
    )
    .await?;
    project(
        &pool,
        scene_id,
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id,
            costume_id: Uuid::now_v7(),
            order: 0,
            note: None,
            version: AggregateVersion(2),
        },
        now,
    )
    .await?;

    // A second beat at the same (scene, character, order) violates the
    // structural backstop — the aggregate would never emit this, but the
    // table must reject it regardless.
    let duplicate = sqlx::query(
        r#"
        INSERT INTO projection_scene_costume_assignment
            (scene_id, character_id, "order", costume_id, note, version)
        VALUES ($1, $2, 0, $3, NULL, 99)
        "#,
    )
    .bind(scene_id)
    .bind(character_id)
    .bind(Uuid::now_v7())
    .execute(&pool)
    .await;

    assert!(
        duplicate.is_err(),
        "PK (scene_id, character_id, order) must reject a duplicate position"
    );

    Ok(())
}

#[tokio::test]
async fn scene_row_deletion_cascades_to_beats() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let now = Utc::now();

    for event in [
        SceneEvent::SceneCreated {
            id: scene_id,
            episode_id,
            details: SceneDetails::default(),
            assigned_characters: vec![character_id],
            version: AggregateVersion::INITIAL,
            source: SceneSource::Manual,
        },
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id,
            costume_id: Uuid::now_v7(),
            order: 0,
            note: None,
            version: AggregateVersion(2),
        },
    ] {
        project(&pool, scene_id, event, now).await?;
    }

    sqlx::query("DELETE FROM projection_scene WHERE id = $1")
        .bind(scene_id)
        .execute(&pool)
        .await?;

    let remaining: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*) FROM projection_scene_costume_assignment WHERE scene_id = $1
        "#,
    )
    .bind(scene_id)
    .fetch_one(&pool)
    .await?;

    assert_eq!(remaining, 0, "FK cascade must delete the beat rows");

    Ok(())
}

#[tokio::test]
async fn aggregate_state_and_read_model_agree_for_the_same_beat_stream() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let other = Uuid::now_v7();
    let costume_a = Uuid::now_v7();
    let costume_b = Uuid::now_v7();
    let costume_c = Uuid::now_v7();
    let now = Utc::now();

    let events = vec![
        SceneEvent::SceneCreated {
            id: scene_id,
            episode_id,
            details: SceneDetails::default(),
            assigned_characters: vec![character_id, other],
            version: AggregateVersion::INITIAL,
            source: SceneSource::Manual,
        },
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id,
            costume_id: costume_a,
            order: 0,
            note: None,
            version: AggregateVersion(2),
        },
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id,
            costume_id: costume_b,
            order: 1,
            note: None,
            version: AggregateVersion(3),
        },
        SceneEvent::CostumeBeatAdded {
            id: scene_id,
            character_id: other,
            costume_id: costume_c,
            order: 0,
            note: None,
            version: AggregateVersion(4),
        },
    ];

    let mut expected_state = SceneAggregate::default();
    for event in events {
        project(&pool, scene_id, event.clone(), now).await?;
        Apply::apply(&mut expected_state, event, Metadata::default());
    }

    let repo = SceneRepositoryImpl::new(pool.clone());
    let view = repo.find_by_id(scene_id).await?;

    let mut agg_beats = expected_state.costume_beats.clone();
    agg_beats.sort_by_key(|b| (b.character_id, b.order));
    let mut view_beats: Vec<(Uuid, u32, Uuid)> = view
        .costume_beats
        .iter()
        .map(|b| (b.character_id, b.order, b.costume_id))
        .collect();
    view_beats.sort();

    assert_eq!(
        agg_beats
            .iter()
            .map(|b| (b.character_id, b.order, b.costume_id))
            .collect::<Vec<_>>(),
        view_beats,
        "aggregate and read model disagree on costume beats"
    );

    Ok(())
}

/// Version-guard redelivery (tasks.md 2.5): the four beat branches are
/// guarded by `guard_parent` (claim the parent version with
/// `UPDATE … WHERE version < $2` first). An at-least-once redelivery of the
/// same event — or of a STALE add after a later removal — must skip the
/// mutation: a replayed add can never recreate a removed beat, and a
/// redelivered add never duplicates a row.
#[tokio::test]
async fn beat_projector_redelivery_is_idempotent_under_guard_parent() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;

    let episode_id = EpisodeId::new();
    let scene_id = Uuid::now_v7();
    let character_id = Uuid::now_v7();
    let now = Utc::now();
    let create = SceneEvent::SceneCreated {
        id: scene_id,
        episode_id,
        details: SceneDetails::default(),
        assigned_characters: vec![character_id],
        version: AggregateVersion::INITIAL,
        source: SceneSource::Manual,
    };
    let add = SceneEvent::CostumeBeatAdded {
        id: scene_id,
        character_id,
        costume_id: Uuid::now_v7(),
        order: 0,
        note: Some("Mantel".into()),
        version: AggregateVersion(2),
    };
    for event in [&create, &add] {
        project(&pool, scene_id, event.clone(), now).await?;
    }

    // Redeliver both events verbatim (at-least-once): the projection keeps
    // exactly one beat row and the parent version stays at the newest seen.
    for event in [&create, &add] {
        project(&pool, scene_id, event.clone(), now).await?;
    }
    let repo = SceneRepositoryImpl::new(pool.clone());
    let view = repo.find_by_id(scene_id).await?;
    assert_eq!(view.costume_beats.len(), 1, "redelivery must not duplicate");
    let parent_version: i64 =
        sqlx::query_scalar("SELECT version FROM projection_scene WHERE id = $1")
            .bind(scene_id)
            .fetch_one(&pool)
            .await?;
    assert_eq!(parent_version, 2);

    // Clear (v3), then redeliver the STALE add (v2): guard_parent claims the
    // parent version first, so the stale add is skipped — the removed beat
    // stays removed.
    project(
        &pool,
        scene_id,
        SceneEvent::CostumeBeatsCleared {
            id: scene_id,
            character_id,
            version: AggregateVersion(3),
        },
        now,
    )
    .await?;
    project(&pool, scene_id, add, now).await?;
    let view = repo.find_by_id(scene_id).await?;
    assert!(
        view.costume_beats.is_empty(),
        "a replayed stale add must not recreate a removed beat"
    );
    let parent_version: i64 =
        sqlx::query_scalar("SELECT version FROM projection_scene WHERE id = $1")
            .bind(scene_id)
            .fetch_one(&pool)
            .await?;
    assert_eq!(parent_version, 3);

    Ok(())
}
