// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Tier-4 round-trip integration tests (ADR-014 / ADR-015 / ADR-016).
//!
//! These tests drive the full live chain against ephemeral containers:
//!
//! ```text
//! command → SierraDB event persisted → PostgresProcessor catches up
//!         → read via *Repository adapter asserts the projection row
//! ```
//!
//! They start **both** a SierraDB container (`tqwewe/sierradb:0.3.1`, via
//! `infra::testing::spawn_sierradb`) and a Postgres container
//! (`infra::testing::spawn_postgres`), reuse the real `kameo_es`
//! `CommandService` + `PostgresProcessor` projectors, and handle the
//! eventual-consistency lag between the event store and the projection with a
//! bounded-retry poll.
//!
//! Requirements: Docker (or a compatible container runtime) and network access
//! to pull the SierraDB image. Excluded from `cargo-mutants` (`.mutants.toml`).

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use breakdown_core::error::DomainError;
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::commands::{AssignCharacter, CreateScene};
use breakdown_core::scene::events::{SceneDetails, SceneEvent};
use breakdown_core::scene::ports::SceneCommands as _;
use breakdown_core::scene::ports::SceneRepository as _;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use chrono::Utc;
use infra::event_store::SceneCommandsImpl;
use infra::queries::SceneRepositoryImpl;
use kameo_es::command_service::CommandService;
use uuid::Uuid;

/// Bounded-retry window for the projector to catch up (ADR-015 eventual
/// consistency). Generous enough for a cold projector subscription on a local
/// container; failures report the lag explicitly rather than a bare assertion.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// Wait until `find_by_id` resolves to a projection row, retrying on
/// `NotFound` for [`PROJECTION_DEADLINE`]. Other errors surface immediately.
async fn await_scene_projection(
    repo: &SceneRepositoryImpl,
    scene_id: Uuid,
) -> Result<breakdown_core::scene::views::SceneView> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(scene_id).await {
            Ok(view) => return Ok(view),
            Err(DomainError::NotFound(_)) if std::time::Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound(_)) => {
                bail!(
                    "projection lag: Scene({scene_id}) not projected within {PROJECTION_DEADLINE:?} \
                     — the PostgresProcessor did not catch up in time"
                );
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

/// Boot the full two-tier runtime: Postgres pool + SierraDB `CommandService` +
/// the four `PostgresProcessor` projectors (mirrors `main.rs`).
///
/// The projector spawn functions each start a background subscription task that
/// holds its own `ActorRef` clone, so the returned actor refs can be dropped
/// immediately — the projectors keep running for the lifetime of the test (and
/// are torn down when the container guards dropped by the caller go away).
async fn boot_two_tiers() -> Result<(SceneCommandsImpl, SceneRepositoryImpl)> {
    let (pool, _pg) = infra::testing::spawn_postgres().await?;
    let (redis_client, _sierra) = infra::testing::spawn_sierradb().await?;

    // Live write path: CommandService over RESP3 (ADR-015 / ADR-016).
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let cmd_service = CommandService::new(conn);

    // Spawn all four projectors so the full `main.rs` boot is exercised. The
    // returned `ActorRef`s are intentionally dropped — the background streams
    // own clones and keep the actors alive.
    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _character_ref =
        infra::projectors::spawn_character_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;
    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _calculation_ref =
        infra::projectors::spawn_calculation_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let write = SceneCommandsImpl::new(cmd_service);
    let read = SceneRepositoryImpl::new(pool);
    Ok((write, read))
}

#[tokio::test]
async fn create_scene_round_trips_into_projection() -> Result<()> {
    let (write, read) = boot_two_tiers().await?;

    let scene_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let details = SceneDetails {
        scene_number: Some(7),
        location: Some("Berlin".into()),
        mood: Some("dark".into()),
        is_schedule_set: true,
    };

    // 1. Dispatch the command through the real CommandService (SierraDB write path).
    let (returned_id, version) = write
        .create(CreateScene {
            id: scene_id,
            project_id,
            details: details.clone(),
        })
        .await
        .map_err(|e| anyhow!("CreateScene failed: {e:?}"))?;

    assert_eq!(returned_id, scene_id);
    assert_eq!(version, AggregateVersion::INITIAL);

    // 2. Wait for the PostgresProcessor to catch up (eventual consistency).
    let view = await_scene_projection(&read, scene_id).await?;

    // 3. Assert the projection row matches the command's UUIDv7 id, project id, version.
    assert_eq!(view.id, scene_id);
    assert_eq!(view.project_id, project_id);
    assert_eq!(view.scene_number, Some(7));
    assert_eq!(view.location.as_deref(), Some("Berlin"));
    assert_eq!(view.mood.as_deref(), Some("dark"));
    assert!(view.is_schedule_set);
    assert_eq!(view.version, AggregateVersion::INITIAL);
    assert!(view.assigned_characters.is_empty());
    assert!(view.updated_at <= Utc::now());

    Ok(())
}

#[tokio::test]
async fn assign_character_is_idempotent_under_redelivery() -> Result<()> {
    use breakdown_core::scene::ports::SceneRepository as _;
    use kameo_es::event_handler::EntityEventHandler;
    use kameo_es::{Entity, Event, EventType, Metadata, StreamId};

    let (write, read) = boot_two_tiers().await?;

    // --- Live create + assign through the real tiers ---
    let scene_id = Uuid::now_v7();
    let project_id = ProjectId::new();
    let character_id = Uuid::now_v7();

    write
        .create(CreateScene {
            id: scene_id,
            project_id,
            details: SceneDetails {
                scene_number: Some(1),
                ..Default::default()
            },
        })
        .await
        .map_err(|e| anyhow!("CreateScene failed: {e:?}"))?;

    let v1 = await_scene_projection(&read, scene_id).await?.version;
    assert_eq!(v1, AggregateVersion::INITIAL);

    let v2 = write
        .assign_character(AssignCharacter {
            id: scene_id,
            character_id,
            version: v1,
        })
        .await
        .map_err(|e| anyhow!("AssignCharacter failed: {e:?}"))?;
    assert_eq!(v2, AggregateVersion(2));

    // Wait for the projector to apply CharacterAssigned.
    let assigned = await_scene_projection(&read, scene_id).await?;
    assert_eq!(assigned.version, AggregateVersion(2));
    assert_eq!(assigned.assigned_characters, vec![character_id]);

    // --- Simulate at-least-once redelivery of the same CharacterAssigned event ---
    // The projector must be idempotent: re-applying the event must NOT create a
    // duplicate `projection_scene_character` row nor bump the version. We
    // re-deliver via the same `EntityEventHandler` the live projector uses,
    // against the real Postgres projection. `assigned_characters` is an
    // `array_agg` over `projection_scene_character`, so a leaked duplicate row
    // would surface as `[character_id, character_id]`.
    let redelivered = Event {
        id: Uuid::now_v7(),
        partition_key: Uuid::now_v7(),
        partition_id: 0,
        transaction_id: Uuid::now_v7(),
        partition_sequence: 2,
        stream_version: 2,
        stream_id: StreamId::new_from_parts(SceneAggregate::category(), scene_id),
        name: SceneEvent::CharacterAssigned {
            id: scene_id,
            character_id,
            version: AggregateVersion(2),
        }
        .event_type()
        .to_string(),
        data: SceneEvent::CharacterAssigned {
            id: scene_id,
            character_id,
            version: AggregateVersion(2),
        },
        metadata: Metadata::default(),
        timestamp: Utc::now(),
    };

    // The read adapter exposes the pool through its public `Clone`-friendly
    // constructor; obtain a writable handle by re-deriving the pool from the
    // repository's own pool via a second adapter is not possible, so re-deliver
    // through a fresh transaction acquired from the repository's underlying pool
    // exposed by the `SceneRepositoryImpl::pool()` test helper.
    for _ in 0..2 {
        let mut tx = infra::testing::scene_repo_pool(&read).begin().await?;
        infra::projectors::SceneProjector
            .handle(&mut tx, scene_id, redelivered.clone())
            .await?;
        tx.commit().await?;
    }

    // Idempotent: still exactly one character in the aggregate's view, version unchanged at 2.
    let after = read
        .find_by_id(scene_id)
        .await
        .map_err(|e| anyhow!("{e:?}"))?;
    assert_eq!(after.version, AggregateVersion(2));
    assert_eq!(
        after.assigned_characters,
        vec![character_id],
        "projector leaked a duplicate character row under redelivery"
    );

    Ok(())
}
