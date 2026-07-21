// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Tier-4 round-trip integration tests for the ShootingDay aggregate and the
//! Scene ↔ ShootingDay scheduling link (ADR-014 / ADR-015 / ADR-016).
//!
//! These tests drive the full live chain against ephemeral containers:
//!
//! ```text
//! direct EAPPEND → SierraDB event persisted → PostgresProcessor catches up
//!              → read via ShootingDayRepository / SceneRepository asserts projection rows
//! ```
//!
//! SierraDB v0.3.1 has a single-node topology issue where `ESCAN` (used by
//! `kameo_es`'s `EntityActor::resync_with_db`) returns `PartitionUnavailable`.
//! To work around this, we append events directly via `EAPPEND` (which goes
//! through the write path) instead of using the `kameo_es` `CommandService`.
//! The projector subscription picks up the event regardless of how it was
//! written, so the full `SierraDB → projector → Postgres projection` chain
//! is still exercised.
//!
//! Requirements: Docker (or a compatible container runtime) and network access
//! to pull the SierraDB image. Excluded from `cargo-mutants` (`.mutants.toml`).

mod fixtures;

use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow, bail};
use breakdown_core::error::DomainError;
use breakdown_core::scene::events::{SceneDetails, SceneEvent};
use breakdown_core::scene::ports::SceneRepository as _;
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{AggregateVersion, EpisodeId, LexicalSortKey, ShootingDayId};
use breakdown_core::shooting_day::events::{ShootingDayEvent, ShootingDaySource};
use breakdown_core::shooting_day::ports::ShootingDayRepository as _;
use breakdown_core::shooting_day::views::ShootingDayView;
use chrono::Utc;
use infra::queries::{SceneRepositoryImpl, ShootingDayRepositoryImpl};
use uuid::Uuid;

/// Bounded-retry window for the projector to catch up (ADR-015 eventual
/// consistency). Generous enough for a cold projector subscription on a local
/// container; failures report the lag explicitly rather than a bare assertion.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

fn encode_event<E: serde::Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut payload = Vec::new();
    ciborium::into_writer(event, &mut payload).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    Ok(payload)
}

async fn eappend(
    redis_client: &Arc<redis::Client>,
    stream_id: &str,
    event_type: &str,
    expected_version: &str,
    payload: &[u8],
) -> Result<()> {
    let mut conn = redis_client.get_multiplexed_tokio_connection().await?;
    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let _: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_type)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {event_type} failed: {e}"))?;
    Ok(())
}

async fn await_shooting_day_found(
    repo: &ShootingDayRepositoryImpl,
    id: ShootingDayId,
) -> Result<ShootingDayView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(id).await {
            Ok(view) => return Ok(view),
            Err(DomainError::NotFound(_)) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound(_)) => {
                bail!(
                    "projection lag: ShootingDay({id}) not projected within {PROJECTION_DEADLINE:?}"
                );
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

async fn await_shooting_day_list(
    repo: &ShootingDayRepositoryImpl,
    episode_id: EpisodeId,
    min_len: usize,
) -> Result<Vec<ShootingDayView>> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.list_by_episode(episode_id).await {
            Ok(views) if views.len() >= min_len => return Ok(views),
            Ok(_) if Instant::now() < deadline => tokio::time::sleep(POLL_INTERVAL).await,
            Ok(_) => bail!(
                "projection lag: list_by_episode({episode_id:?}) did not reach {min_len} rows \
                 within {PROJECTION_DEADLINE:?}"
            ),
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

async fn await_shooting_day_archived(
    repo: &ShootingDayRepositoryImpl,
    id: ShootingDayId,
) -> Result<ShootingDayView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(id).await {
            Ok(view) if view.archived => return Ok(view),
            Ok(_) if Instant::now() < deadline => tokio::time::sleep(POLL_INTERVAL).await,
            Ok(_) => bail!(
                "projection lag: ShootingDay({id}) did not become archived within {PROJECTION_DEADLINE:?}"
            ),
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

async fn await_scene_found(repo: &SceneRepositoryImpl, scene_id: Uuid) -> Result<SceneView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(scene_id).await {
            Ok(view) => return Ok(view),
            Err(DomainError::NotFound(_)) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound(_)) => {
                bail!(
                    "projection lag: Scene({scene_id}) not projected within {PROJECTION_DEADLINE:?}"
                );
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

/// Poll `find_by_id` until the scene projection version reaches at least
/// `min_version`. Used after `ShootingDayScheduled`/`ShootingDayUnscheduled`,
/// which bump the scene version via `touch_parent`.
#[allow(dead_code)]
async fn await_scene_version(
    repo: &SceneRepositoryImpl,
    scene_id: Uuid,
    min_version: AggregateVersion,
) -> Result<SceneView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(scene_id).await {
            Ok(view) if view.version >= min_version => return Ok(view),
            Ok(_) if Instant::now() < deadline => tokio::time::sleep(POLL_INTERVAL).await,
            Ok(_) => bail!(
                "projection lag: Scene({scene_id}) version did not reach {min_version:?} within {PROJECTION_DEADLINE:?}"
            ),
            Err(DomainError::NotFound(_)) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound(_)) => {
                bail!(
                    "projection lag: Scene({scene_id}) not projected within {PROJECTION_DEADLINE:?}"
                );
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

/// Poll `find_by_id` until the scene's `shooting_day_ids` contains `sd_id`.
///
/// The Scene and ShootingDay projectors run independently, so the scheduling
/// link can lag the scene version bump; wait for the link itself, not the
/// version, to avoid a spurious race.
async fn await_scene_links(
    repo: &SceneRepositoryImpl,
    scene_id: Uuid,
    sd_id: ShootingDayId,
) -> Result<SceneView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(scene_id).await {
            Ok(view) if view.shooting_day_ids.iter().any(|s| *s == sd_id) => return Ok(view),
            Ok(_) if Instant::now() < deadline => tokio::time::sleep(POLL_INTERVAL).await,
            Ok(_) => bail!(
                "projection lag: Scene({scene_id}) did not link ShootingDay({sd_id}) within {PROJECTION_DEADLINE:?}"
            ),
            Err(DomainError::NotFound(_)) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound(_)) => {
                bail!(
                    "projection lag: Scene({scene_id}) not projected within {PROJECTION_DEADLINE:?}"
                );
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

async fn await_scenes_by_shooting_day(
    repo: &ShootingDayRepositoryImpl,
    shooting_day_id: ShootingDayId,
    min_len: usize,
) -> Result<Vec<SceneView>> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.scenes_by_shooting_day(shooting_day_id).await {
            Ok(views) if views.len() >= min_len => return Ok(views),
            Ok(_) if Instant::now() < deadline => tokio::time::sleep(POLL_INTERVAL).await,
            Ok(_) => bail!(
                "projection lag: scenes_by_shooting_day({shooting_day_id:?}) did not reach {min_len} \
                 rows within {PROJECTION_DEADLINE:?}"
            ),
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

/// 6.1 — CreateShootingDay → projector → list-by-episode ordered.
#[tokio::test]
async fn eappend_shooting_day_created_round_trips_into_list() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _sd_ref =
        infra::projectors::spawn_shooting_day_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let repo = ShootingDayRepositoryImpl::new(pool.clone());

    let id = ShootingDayId::new();
    let episode_id = EpisodeId::new();
    let stream_id = format!("shooting_day-{id}");

    let created = ShootingDayEvent::ShootingDayCreated {
        id,
        episode_id,
        label: Some("Day 1 — Penthouse".into()),
        order_key: LexicalSortKey("a".into()),
        date: Some(Utc::now().date_naive()),
        source: ShootingDaySource::Manual,
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&created)?;
    eappend(
        &redis_client,
        &stream_id,
        "ShootingDayCreated",
        "EMPTY",
        &payload,
    )
    .await?;

    // find_by_id resolves.
    let view = await_shooting_day_found(&repo, id).await?;
    assert_eq!(view.id, id);
    assert_eq!(view.episode_id, episode_id);
    assert_eq!(view.label, Some("Day 1 — Penthouse".into()));
    assert_eq!(view.order_key, LexicalSortKey("a".into()));
    assert!(!view.archived);
    assert_eq!(view.version, AggregateVersion::INITIAL);

    // list-by-episode returns it (ordered by order_key).
    let list = await_shooting_day_list(&repo, episode_id, 1).await?;
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].id, id);

    Ok(())
}

/// 6.2 — ScheduleSceneOnShootingDay → join table → reverse query returns the Scene.
#[tokio::test]
async fn eappend_schedule_scene_links_join_and_reverse_query() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _sd_ref =
        infra::projectors::spawn_shooting_day_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let scene_repo = SceneRepositoryImpl::new(pool.clone());
    let sd_repo = ShootingDayRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    let scene_stream = format!("scene-{scene_id}");

    // Create the scene.
    let scene_created = SceneEvent::SceneCreated {
        id: scene_id,
        episode_id,
        details: SceneDetails {
            scene_number: Some(7),
            location: Some("Berlin".into()),
            mood: Some("dark".into()),
            is_schedule_set: true,
            summary: None,
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&scene_created)?;
    eappend(
        &redis_client,
        &scene_stream,
        "SceneCreated",
        "EMPTY",
        &payload,
    )
    .await?;
    let scene = await_scene_found(&scene_repo, scene_id).await?;
    assert!(scene.shooting_day_ids.is_empty());

    // Create the shooting day.
    let sd_id = ShootingDayId::new();
    let sd_stream = format!("shooting_day-{sd_id}");
    let sd_created = ShootingDayEvent::ShootingDayCreated {
        id: sd_id,
        episode_id,
        label: Some("Day 2 — Rooftop".into()),
        order_key: LexicalSortKey("b".into()),
        date: Some(Utc::now().date_naive()),
        source: ShootingDaySource::Manual,
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&sd_created)?;
    eappend(
        &redis_client,
        &sd_stream,
        "ShootingDayCreated",
        "EMPTY",
        &payload,
    )
    .await?;
    await_shooting_day_found(&sd_repo, sd_id).await?;

    // Schedule the scene onto the shooting day (ShootingDayScheduled on the SCENE stream).
    let scheduled = SceneEvent::ShootingDayScheduled {
        id: scene_id,
        shooting_day_id: sd_id,
        version: AggregateVersion(1),
    };
    let payload = encode_event(&scheduled)?;
    eappend(
        &redis_client,
        &scene_stream,
        "ShootingDayScheduled",
        "0",
        &payload,
    )
    .await?;

    // Scene view gains the shooting_day_id once the projector applies
    // ShootingDayScheduled. The Scene and ShootingDay projectors run
    // independently, so the link may lag the version bump; poll for the link
    // itself rather than the version.
    let scene = await_scene_links(&scene_repo, scene_id, sd_id).await?;
    assert_eq!(scene.shooting_day_ids, vec![sd_id]);

    // Reverse query returns the scene.
    let scenes = await_scenes_by_shooting_day(&sd_repo, sd_id, 1).await?;
    assert_eq!(scenes.len(), 1);
    assert_eq!(scenes[0].id, scene_id);

    // list-by-episode still returns the (non-archived) shooting day.
    let list = sd_repo.list_by_episode(episode_id).await?;
    assert!(list.iter().any(|v| v.id == sd_id));

    Ok(())
}

/// 6.3 — ArchiveShootingDay while still referenced: the scene link is retained
/// and the day is hidden from list-by-episode but still resolvable by id.
#[tokio::test]
async fn eappend_archive_while_referenced_hides_from_picker_keeps_link() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _scene_ref =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _sd_ref =
        infra::projectors::spawn_shooting_day_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let scene_repo = SceneRepositoryImpl::new(pool.clone());
    let sd_repo = ShootingDayRepositoryImpl::new(pool.clone());

    let scene_id = Uuid::now_v7();
    let episode_id = EpisodeId::new();
    let scene_stream = format!("scene-{scene_id}");

    let scene_created = SceneEvent::SceneCreated {
        id: scene_id,
        episode_id,
        details: SceneDetails {
            scene_number: Some(3),
            location: Some("Studio".into()),
            mood: Some("neutral".into()),
            is_schedule_set: false,
            summary: None,
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&scene_created)?;
    eappend(
        &redis_client,
        &scene_stream,
        "SceneCreated",
        "EMPTY",
        &payload,
    )
    .await?;
    await_scene_found(&scene_repo, scene_id).await?;

    let sd_id = ShootingDayId::new();
    let sd_stream = format!("shooting_day-{sd_id}");
    let sd_created = ShootingDayEvent::ShootingDayCreated {
        id: sd_id,
        episode_id,
        label: Some("Day 9 — Studio".into()),
        order_key: LexicalSortKey("m".into()),
        date: Some(Utc::now().date_naive()),
        source: ShootingDaySource::Manual,
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&sd_created)?;
    eappend(
        &redis_client,
        &sd_stream,
        "ShootingDayCreated",
        "EMPTY",
        &payload,
    )
    .await?;
    await_shooting_day_found(&sd_repo, sd_id).await?;

    // Link the scene to the shooting day (wait for the scheduled event to project).
    let scheduled = SceneEvent::ShootingDayScheduled {
        id: scene_id,
        shooting_day_id: sd_id,
        version: AggregateVersion(1),
    };
    let payload = encode_event(&scheduled)?;
    eappend(
        &redis_client,
        &scene_stream,
        "ShootingDayScheduled",
        "0",
        &payload,
    )
    .await?;
    let scene = await_scene_links(&scene_repo, scene_id, sd_id).await?;
    assert_eq!(scene.shooting_day_ids, vec![sd_id]);

    // Archive the shooting day.
    let archived = ShootingDayEvent::ShootingDayArchived {
        id: sd_id,
        version: AggregateVersion(1),
    };
    let payload = encode_event(&archived)?;
    eappend(
        &redis_client,
        &sd_stream,
        "ShootingDayArchived",
        "0",
        &payload,
    )
    .await?;

    // The day becomes archived (still resolvable by id).
    let archived_view = await_shooting_day_archived(&sd_repo, sd_id).await?;
    assert!(archived_view.archived);

    // The scene link is retained (archiving does not cascade-remove the FK).
    let scene = scene_repo.find_by_id(scene_id).await?;
    assert_eq!(scene.shooting_day_ids, vec![sd_id]);

    // The day is hidden from the scheduling picker (archived excluded).
    let list = sd_repo.list_by_episode(episode_id).await?;
    assert!(
        !list.iter().any(|v| v.id == sd_id),
        "archived day must be excluded from list"
    );

    // The reverse query still resolves the linked scene.
    let scenes = sd_repo.scenes_by_shooting_day(sd_id).await?;
    assert_eq!(scenes.len(), 1);
    assert_eq!(scenes[0].id, scene_id);

    Ok(())
}

/// 6.4 — Reorder with midpoint: a day inserted between two existing days lands
/// in the correct position when ordered by `order_key`.
///
/// The aggregate-level invariant ("exactly one `ShootingDayReordered` event,
/// siblings untouched") is covered by the domain unit test (task 2.8). This
/// integration test exercises the fractional-order `LexicalSortKey` value
/// end-to-end through SierraDB → projector → repository ordering.
#[tokio::test]
async fn eappend_reorder_with_midpoint_orders_projection() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _sd_ref =
        infra::projectors::spawn_shooting_day_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let repo = ShootingDayRepositoryImpl::new(pool.clone());
    let episode_id = EpisodeId::new();

    let a = ShootingDayId::new();
    let b = ShootingDayId::new();
    let c = ShootingDayId::new();

    let order_a = LexicalSortKey("a".into());
    let order_b = LexicalSortKey("b".into());
    let order_mid = LexicalSortKey::midpoint(&order_a, &order_b)
        .expect("midpoint must exist between 'a' and 'b'");

    // 'a' first.
    let a_created = ShootingDayEvent::ShootingDayCreated {
        id: a,
        episode_id,
        label: Some("A".into()),
        order_key: order_a.clone(),
        date: None,
        source: ShootingDaySource::Manual,
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&a_created)?;
    eappend(
        &redis_client,
        &format!("shooting_day-{a}"),
        "ShootingDayCreated",
        "EMPTY",
        &payload,
    )
    .await?;

    // 'b' second.
    let b_created = ShootingDayEvent::ShootingDayCreated {
        id: b,
        episode_id,
        label: Some("B".into()),
        order_key: order_b.clone(),
        date: None,
        source: ShootingDaySource::Manual,
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&b_created)?;
    eappend(
        &redis_client,
        &format!("shooting_day-{b}"),
        "ShootingDayCreated",
        "EMPTY",
        &payload,
    )
    .await?;

    // 'c' inserted between them via a midpoint order_key.
    let c_created = ShootingDayEvent::ShootingDayCreated {
        id: c,
        episode_id,
        label: Some("C (midpoint)".into()),
        order_key: order_mid.clone(),
        date: None,
        source: ShootingDaySource::Manual,
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&c_created)?;
    eappend(
        &redis_client,
        &format!("shooting_day-{c}"),
        "ShootingDayCreated",
        "EMPTY",
        &payload,
    )
    .await?;

    let list = await_shooting_day_list(&repo, episode_id, 3).await?;
    assert_eq!(list.len(), 3, "all three days must be projected");

    // Ordering is by order_key: A < midpoint(C) < B.
    assert_eq!(list[0].id, a, "first must be A (order 'a')");
    assert_eq!(list[1].id, c, "middle must be C (midpoint)");
    assert_eq!(list[2].id, b, "last must be B (order 'b')");
    assert_eq!(list[0].order_key, order_a);
    assert_eq!(list[1].order_key, order_mid);
    assert_eq!(list[2].order_key, order_b);

    Ok(())
}
