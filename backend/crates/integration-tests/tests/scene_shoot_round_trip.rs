// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)

//! Tier-4 round-trip integration tests for SceneShoot lifecycle and
//! ShootingDayWrapped report finality (ADR-016).
//!
//! Drives the full chain: direct EAPPEND → SierraDB → PostgresProcessor →
//! SceneShootRepository / SceneShootReportRepository asserts.

mod fixtures;

use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow, bail};
use breakdown_core::error::DomainError;
use breakdown_core::scene_shoot::events::SceneShootEvent;
use breakdown_core::scene_shoot::ports::{SceneShootReportRepository, SceneShootRepository as _};
use breakdown_core::scene_shoot::views::SceneShootView;
use breakdown_core::shared::{
    AggregateVersion, LexicalSortKey, PhotoId, SceneShootId, SceneShootStatus, ShootingDayId,
};
use breakdown_core::shooting_day::events::{ShootingDayEvent, ShootingDaySource};
use breakdown_core::shooting_day::ports::ShootingDayRepository as _;
use chrono::Utc;
use infra::projectors::{
    spawn_scene_projector, spawn_scene_shoot_projector, spawn_shooting_day_projector,
};
use infra::queries::{SceneShootReportRepositoryImpl, SceneShootRepositoryImpl};
use uuid::Uuid;

const DEADLINE: Duration = Duration::from_secs(15);
const POLL: Duration = Duration::from_millis(150);

fn encode<E: serde::Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut buf = Vec::new();
    ciborium::into_writer(event, &mut buf).map_err(|e| anyhow!("CBOR: {e}"))?;
    Ok(buf)
}

async fn eappend(
    client: &Arc<redis::Client>,
    stream: &str,
    etype: &str,
    ver: &str,
    payload: &[u8],
) -> Result<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let _: redis::Value = redis::cmd("EAPPEND")
        .arg(stream)
        .arg(etype)
        .arg("EXPECTED_VERSION")
        .arg(ver)
        .arg("PAYLOAD")
        .arg(payload)
        .arg("TIMESTAMP")
        .arg(ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {etype}: {e}"))?;
    Ok(())
}

async fn await_version(
    repo: &SceneShootRepositoryImpl,
    id: SceneShootId,
    min: u64,
) -> Result<SceneShootView> {
    let dl = Instant::now() + DEADLINE;
    loop {
        match repo.find_by_id(id).await {
            Ok(v) if v.version.0 >= min => return Ok(v),
            Ok(_) | Err(DomainError::NotFound(_)) if Instant::now() < dl => {
                tokio::time::sleep(POLL).await;
            }
            Ok(v) => bail!("lag: version {} < {min}", v.version.0),
            Err(DomainError::NotFound(_)) => bail!("not projected within deadline"),
            Err(e) => return Err(anyhow!("{e}")),
        }
    }
}

/// Seed the FK-required parent rows for a scene and shooting_day.
async fn seed_parents(pool: &sqlx::PgPool, scene_id: Uuid, day_id: ShootingDayId) -> Result<()> {
    let ep = Uuid::now_v7();
    sqlx::query(
        r#"INSERT INTO projection_scene
            (id,episode_id,scene_number,location,mood,is_schedule_set,summary,script_day,version,updated_at)
        VALUES ($1,$2,1,'loc','mood',false,NULL,NULL,1,now())
        ON CONFLICT (id) DO NOTHING"#,
    )
    .bind(scene_id)
    .bind(ep)
    .execute(pool)
    .await?;
    sqlx::query(
        r#"INSERT INTO projection_shooting_day
            (id,episode_id,label,order_key,date,source,archived,wrapped_at,version,updated_at)
        VALUES ($1,$2,'Day 1','a',NULL,'{"Manual":null}'::jsonb,false,NULL,1,now())
        ON CONFLICT (id) DO NOTHING"#,
    )
    .bind(day_id.0)
    .bind(ep)
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// 9.1  plan → start → finish round-trip
// ---------------------------------------------------------------------------

#[tokio::test]
async fn scene_shoot_lifecycle_round_trip() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (client, _conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _scene_proj = spawn_scene_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _sd_proj = spawn_shooting_day_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _ss_proj = spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    let repo = SceneShootRepositoryImpl::new(pool.clone());

    let shoot_id = SceneShootId::new();
    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();
    let stream = format!("scene_shoot-{}", shoot_id.0);

    seed_parents(&pool, scene_id, day_id).await?;

    // 1. Plan
    let planned = SceneShootEvent::SceneShootPlanned {
        id: shoot_id,
        scene_id,
        shooting_day_id: day_id,
        planned_order: LexicalSortKey::new("001").unwrap(),
        status: SceneShootStatus::Planned,
        version: AggregateVersion(1),
    };
    eappend(
        &client,
        &stream,
        "SceneShootPlanned",
        "EMPTY",
        &encode(&planned)?,
    )
    .await?;
    let v = await_version(&repo, shoot_id, 1).await?;
    assert_eq!(v.status, SceneShootStatus::Planned);

    // 2. Start
    let started = SceneShootEvent::SceneShootStarted {
        id: shoot_id,
        start_dt: Utc::now(),
        version: AggregateVersion(2),
    };
    eappend(
        &client,
        &stream,
        "SceneShootStarted",
        "0",
        &encode(&started)?,
    )
    .await?;
    let v = await_version(&repo, shoot_id, 2).await?;
    assert_eq!(v.status, SceneShootStatus::InProgress);
    assert!(v.start_dt.is_some());

    // 3. Finish
    let finished = SceneShootEvent::SceneShootFinished {
        id: shoot_id,
        end_dt: Utc::now(),
        version: AggregateVersion(3),
    };
    eappend(
        &client,
        &stream,
        "SceneShootFinished",
        "1",
        &encode(&finished)?,
    )
    .await?;
    let v = await_version(&repo, shoot_id, 3).await?;
    assert_eq!(v.status, SceneShootStatus::Shot);
    assert!(v.end_dt.is_some());

    Ok(())
}

// ---------------------------------------------------------------------------
// 9.1 (cont.)  plan → note → continuity photo
// ---------------------------------------------------------------------------

#[tokio::test]
async fn scene_shoot_notes_and_continuity_round_trip() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (client, _conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _scene_proj = spawn_scene_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _sd_proj = spawn_shooting_day_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _ss_proj = spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    let repo = SceneShootRepositoryImpl::new(pool.clone());

    let shoot_id = SceneShootId::new();
    let scene_id = Uuid::now_v7();
    let day_id = ShootingDayId::new();
    let stream = format!("scene_shoot-{}", shoot_id.0);

    seed_parents(&pool, scene_id, day_id).await?;

    // Plan
    let planned = SceneShootEvent::SceneShootPlanned {
        id: shoot_id,
        scene_id,
        shooting_day_id: day_id,
        planned_order: LexicalSortKey::new("001").unwrap(),
        status: SceneShootStatus::Planned,
        version: AggregateVersion(1),
    };
    eappend(
        &client,
        &stream,
        "SceneShootPlanned",
        "EMPTY",
        &encode(&planned)?,
    )
    .await?;
    await_version(&repo, shoot_id, 1).await?;

    // Add note
    let note_id = Uuid::now_v7();
    let note_added = SceneShootEvent::ShootDayNoteAdded {
        id: shoot_id,
        note_id,
        body: "hello".into(),
        author: None,
        version: AggregateVersion(2),
    };
    eappend(
        &client,
        &stream,
        "ShootDayNoteAdded",
        "0",
        &encode(&note_added)?,
    )
    .await?;
    let v = await_version(&repo, shoot_id, 2).await?;
    assert_eq!(v.notes.len(), 1);
    assert_eq!(v.notes[0].body, "hello");

    // Link continuity photo
    let photo_id = PhotoId::new();
    let linked = SceneShootEvent::ContinuityPhotoLinked {
        id: shoot_id,
        photo_id,
        version: AggregateVersion(3),
    };
    eappend(
        &client,
        &stream,
        "ContinuityPhotoLinked",
        "1",
        &encode(&linked)?,
    )
    .await?;
    let v = await_version(&repo, shoot_id, 3).await?;
    assert_eq!(v.continuity_photo_ids.len(), 1);
    assert_eq!(v.continuity_photo_ids[0], photo_id);

    Ok(())
}

// ---------------------------------------------------------------------------
// 9.4  ShootingDayWrapped flips report `final` flag
// ---------------------------------------------------------------------------

#[tokio::test]
async fn wrapped_shooting_day_flips_report_final() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (client, _conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _scene_proj = spawn_scene_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _sd_proj = spawn_shooting_day_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _ss_proj = spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    let sd_repo = infra::queries::ShootingDayRepositoryImpl::new(pool.clone());
    let ss_repo = SceneShootRepositoryImpl::new(pool.clone());
    let report_repo = SceneShootReportRepositoryImpl::new(pool.clone());

    let day_id = ShootingDayId::new();
    let scene_id = Uuid::now_v7();
    let ep = Uuid::now_v7();

    // Seed shooting_day
    let sd_stream = format!("shooting_day-{}", day_id.0);
    let sd_created = ShootingDayEvent::ShootingDayCreated {
        id: day_id,
        episode_id: breakdown_core::shared::EpisodeId::from_uuid(ep),
        label: Some("Day 1".into()),
        order_key: LexicalSortKey::new("a").unwrap(),
        date: None,
        source: ShootingDaySource::Manual,
        version: AggregateVersion::INITIAL,
    };
    eappend(
        &client,
        &sd_stream,
        "ShootingDayCreated",
        "EMPTY",
        &encode(&sd_created)?,
    )
    .await?;
    // Wait for projection
    let dl = Instant::now() + DEADLINE;
    loop {
        if sd_repo.find_by_id(day_id).await.is_ok() {
            break;
        }
        if Instant::now() > dl {
            bail!("shooting_day not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    // Seed scene (for FK)
    let scene_stream = format!("scene-{}", scene_id);
    let scene_created = breakdown_core::scene::events::SceneEvent::SceneCreated {
        id: scene_id,
        episode_id: breakdown_core::shared::EpisodeId::from_uuid(ep),
        details: breakdown_core::scene::events::SceneDetails {
            scene_number: Some(1),
            location: Some("loc".into()),
            mood: Some("mood".into()),
            is_schedule_set: false,
            summary: None,
            script_day: None,
        },
        assigned_characters: vec![],
        version: AggregateVersion::INITIAL,
    };
    eappend(
        &client,
        &scene_stream,
        "SceneCreated",
        "EMPTY",
        &encode(&scene_created)?,
    )
    .await?;
    let dl = Instant::now() + DEADLINE;
    loop {
        if sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM projection_scene WHERE id = $1)",
        )
        .bind(scene_id)
        .fetch_one(&pool)
        .await?
        {
            break;
        }
        if Instant::now() > dl {
            bail!("scene not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    // Plan a scene shoot
    let shoot_id = SceneShootId::new();
    let ss_stream = format!("scene_shoot-{}", shoot_id.0);
    let planned = SceneShootEvent::SceneShootPlanned {
        id: shoot_id,
        scene_id,
        shooting_day_id: day_id,
        planned_order: LexicalSortKey::new("001").unwrap(),
        status: SceneShootStatus::Planned,
        version: AggregateVersion(1),
    };
    eappend(
        &client,
        &ss_stream,
        "SceneShootPlanned",
        "EMPTY",
        &encode(&planned)?,
    )
    .await?;
    await_version(&ss_repo, shoot_id, 1).await?;

    // Before wrap: report is NOT final
    let report = report_repo.soll_ist_report(day_id).await?;
    assert!(!report.is_final, "before wrap, report should not be final");
    assert_eq!(report.rows.len(), 1);

    // Wrap the shooting day
    let wrapped = ShootingDayEvent::ShootingDayWrapped {
        id: day_id,
        wrapped_at: Utc::now(),
        version: AggregateVersion(1),
    };
    eappend(
        &client,
        &sd_stream,
        "ShootingDayWrapped",
        "0",
        &encode(&wrapped)?,
    )
    .await?;
    // Wait for projection
    let dl = Instant::now() + DEADLINE;
    loop {
        if let Ok(v) = sd_repo.find_by_id(day_id).await
            && v.wrapped_at.is_some()
        {
            break;
        }
        if Instant::now() > dl {
            bail!("wrapped_at not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    // After wrap: report IS final
    let report = report_repo.soll_ist_report(day_id).await?;
    assert!(report.is_final, "after wrap, report should be final");

    Ok(())
}
