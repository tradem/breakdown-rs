// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
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
use breakdown_core::scene::events::SceneSource;
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
            Ok(_) | Err(DomainError::NotFound { .. }) if Instant::now() < dl => {
                tokio::time::sleep(POLL).await;
            }
            Ok(v) => bail!("lag: version {} < {min}", v.version.0),
            Err(DomainError::NotFound { .. }) => bail!("not projected within deadline"),
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
        source: SceneSource::Manual,
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

// ---------------------------------------------------------------------------
// 9.5  Aggregated Soll-Ist report — episode/season scope (issue #571)
// ---------------------------------------------------------------------------

use breakdown_core::block::events::BlockEvent;
use breakdown_core::episode::events::EpisodeEvent;
use breakdown_core::season::events::SeasonEvent;
use breakdown_core::shared::{BlockId, EpisodeId, SeasonId, SeriesId};

/// Poll an `EXISTS` probe until true, or fail after deadline.
///
/// `sql` is passed **as a literal at every call site** (the
/// no-string-interpolation-SQL hard rule explicitly whitelists this safe
/// pattern; the identifiers are hardcoded, values are bound).
async fn await_exists(pool: &sqlx::PgPool, sql: &'static str, id: Uuid) -> Result<()> {
    let dl = Instant::now() + DEADLINE;
    loop {
        let exists: bool = sqlx::query_scalar::<_, bool>(sql)
            .bind(id)
            .fetch_one(pool)
            .await?;
        if exists {
            return Ok(());
        }
        if Instant::now() > dl {
            bail!("exists probe failed within deadline: {sql} (id {id})");
        }
        tokio::time::sleep(POLL).await;
    }
}

#[tokio::test]
async fn aggregate_soll_ist_report_episode_and_season_scopes() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (client, _conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _season_proj = infra::projectors::spawn_season_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _block_proj = infra::projectors::spawn_block_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _episode_proj = infra::projectors::spawn_episode_projector(
        pool.clone(),
        Arc::clone(&client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
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

    let report_repo = SceneShootReportRepositoryImpl::new(pool.clone());
    let sd_repo = infra::queries::ShootingDayRepositoryImpl::new(pool.clone());
    let ss_repo = SceneShootRepositoryImpl::new(pool.clone());

    // Hierarchy: one series, one season, one block, two episodes.
    let series_id = SeriesId::new();
    let season_id = SeasonId::new();
    let block_id = BlockId::new();
    let ep1 = EpisodeId::new();
    let ep2 = EpisodeId::new();

    eappend(
        &client,
        &format!("season-{}", season_id.0),
        "SeasonCreated",
        "EMPTY",
        &encode(&SeasonEvent::SeasonCreated {
            id: season_id.0,
            series_id,
            number: 1,
            title: Some("Agg Season".into()),
            version: AggregateVersion::INITIAL,
        })?,
    )
    .await?;
    await_exists(
        &pool,
        "SELECT EXISTS(SELECT 1 FROM projection_season WHERE id = $1)",
        season_id.0,
    )
    .await?;

    eappend(
        &client,
        &format!("block-{}", block_id.0),
        "BlockCreated",
        "EMPTY",
        &encode(&BlockEvent::BlockCreated {
            id: block_id.0,
            season_id,
            series_id,
            number: 1,
            start_date: None,
            end_date: None,
            version: AggregateVersion::INITIAL,
        })?,
    )
    .await?;
    await_exists(
        &pool,
        "SELECT EXISTS(SELECT 1 FROM projection_block WHERE id = $1)",
        block_id.0,
    )
    .await?;

    for (id, number) in [(ep1, 1), (ep2, 2)] {
        eappend(
            &client,
            &format!("episode-{}", id.0),
            "EpisodeCreated",
            "EMPTY",
            &encode(&EpisodeEvent::EpisodeCreated {
                id: id.0,
                block_id,
                series_id,
                number,
                name: Some("Agg Episode".into()),
                version: AggregateVersion::INITIAL,
            })?,
        )
        .await?;
        await_exists(
            &pool,
            "SELECT EXISTS(SELECT 1 FROM projection_episode WHERE id = $1)",
            id.0,
        )
        .await?;
    }

    // Scenes (needed as the FK target of the scene_shoot projection).
    let scene_x = Uuid::now_v7();
    let scene_y = Uuid::now_v7();
    for (sid, number) in [(scene_x, 1), (scene_y, 2)] {
        eappend(
            &client,
            &format!("scene-{}", sid),
            "SceneCreated",
            "EMPTY",
            &encode(&breakdown_core::scene::events::SceneEvent::SceneCreated {
                id: sid,
                episode_id: ep1,
                details: breakdown_core::scene::events::SceneDetails {
                    scene_number: Some(number),
                    location: Some("loc".into()),
                    mood: None,
                    is_schedule_set: false,
                    summary: None,
                    script_day: None,
                },
                assigned_characters: vec![],
                version: AggregateVersion::INITIAL,
                source: SceneSource::Manual,
            })?,
        )
        .await?;
        await_exists(
            &pool,
            "SELECT EXISTS(SELECT 1 FROM projection_scene WHERE id = $1)",
            sid,
        )
        .await?;
    }

    // Days: d1 (ep1, shot day), d2 (ep1, skip day), d3 (ep2, untouched),
    // d4 (ep1, archived → excluded everywhere).
    let day1 = ShootingDayId::new();
    let day2 = ShootingDayId::new();
    let day3 = ShootingDayId::new();
    let day4 = ShootingDayId::new();
    for (id, ep, key, label) in [
        (day1, ep1, "a", "Tageins"),
        (day2, ep1, "b", "Tagzwei"),
        (day3, ep2, "c", "Tagdrei"),
        (day4, ep1, "d", "Tagvier"),
    ] {
        eappend(
            &client,
            &format!("shooting_day-{id}"),
            "ShootingDayCreated",
            "EMPTY",
            &encode(&ShootingDayEvent::ShootingDayCreated {
                id,
                episode_id: ep,
                label: Some(label.into()),
                order_key: LexicalSortKey::new(key).unwrap(),
                date: None,
                source: ShootingDaySource::Manual,
                version: AggregateVersion::INITIAL,
            })?,
        )
        .await?;
        await_exists(
            &pool,
            "SELECT EXISTS(SELECT 1 FROM projection_shooting_day WHERE id = $1)",
            id.0,
        )
        .await?;
    }

    // Scene shoots: X shot on d1, Y planned on d1, X planned on d2 (missing).
    let ss1 = SceneShootId::new();
    let ss2 = SceneShootId::new();
    let ss3 = SceneShootId::new();
    eappend(
        &client,
        &format!("scene_shoot-{}", ss1.0),
        "SceneShootPlanned",
        "EMPTY",
        &encode(&SceneShootEvent::SceneShootPlanned {
            id: ss1,
            scene_id: scene_x,
            shooting_day_id: day1,
            planned_order: LexicalSortKey::new("001").unwrap(),
            status: SceneShootStatus::Planned,
            version: AggregateVersion(1),
        })?,
    )
    .await?;
    eappend(
        &client,
        &format!("scene_shoot-{}", ss2.0),
        "SceneShootPlanned",
        "EMPTY",
        &encode(&SceneShootEvent::SceneShootPlanned {
            id: ss2,
            scene_id: scene_y,
            shooting_day_id: day1,
            planned_order: LexicalSortKey::new("002").unwrap(),
            status: SceneShootStatus::Planned,
            version: AggregateVersion(1),
        })?,
    )
    .await?;
    eappend(
        &client,
        &format!("scene_shoot-{}", ss3.0),
        "SceneShootPlanned",
        "EMPTY",
        &encode(&SceneShootEvent::SceneShootPlanned {
            id: ss3,
            scene_id: scene_x,
            shooting_day_id: day2,
            planned_order: LexicalSortKey::new("003").unwrap(),
            status: SceneShootStatus::Planned,
            version: AggregateVersion(1),
        })?,
    )
    .await?;
    await_version(&ss_repo, ss3, 1).await?;

    // Shot on d1: start + finish ⇒ status 'Shot'.
    eappend(
        &client,
        &format!("scene_shoot-{}", ss1.0),
        "SceneShootStarted",
        "0",
        &encode(&SceneShootEvent::SceneShootStarted {
            id: ss1,
            start_dt: Utc::now(),
            version: AggregateVersion(2),
        })?,
    )
    .await?;
    eappend(
        &client,
        &format!("scene_shoot-{}", ss1.0),
        "SceneShootFinished",
        "1",
        &encode(&SceneShootEvent::SceneShootFinished {
            id: ss1,
            end_dt: Utc::now(),
            version: AggregateVersion(3),
        })?,
    )
    .await?;
    await_version(&ss_repo, ss1, 3).await?;

    // Archive d4 — must vanish from every aggregate scope.
    eappend(
        &client,
        &format!("shooting_day-{day4}"),
        "ShootingDayArchived",
        "0",
        &encode(&ShootingDayEvent::ShootingDayArchived {
            id: day4,
            version: AggregateVersion(1),
        })?,
    )
    .await?;
    let dl = Instant::now() + DEADLINE;
    loop {
        if sqlx::query_scalar::<_, bool>(
            "SELECT archived FROM projection_shooting_day WHERE id = $1",
        )
        .bind(day4.0)
        .fetch_one(&pool)
        .await?
        {
            break;
        }
        if Instant::now() > dl {
            bail!("d4 archive not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    // --- Episode aggregate (expected: d1+d2 = 2 days, 0 wrapped). ---
    let report = report_repo
        .episode_soll_ist_report(ep1)
        .await
        .unwrap_or_else(|e| panic!("episode report should succeed: {e}"));
    assert_eq!(report.total_shooting_days, 2);
    assert_eq!(report.wrapped_shooting_days, 0);
    assert!(!report.is_final);
    // Rows ordered by day order_key then planned order: (X,d1) Shot,
    // (Y,d1) missing, (X,d2) missing.
    assert_eq!(report.rows.len(), 3);
    // First row: (X,d1) — Shot, not missing, not reshot, not skipped.
    assert_eq!(report.rows[0].scene_id, scene_x);
    assert_eq!(report.rows[0].shooting_day_id, day1);
    assert!(!report.rows[0].missing && !report.rows[0].skipped);
    assert!(!report.rows[0].reshot_candidate);
    // (Y,d1): missing — planned without execution data.
    assert_eq!(report.rows[1].scene_id, scene_y);
    assert!(report.rows[1].missing);
    // (X,d2): missing AND reshot candidate (X has a Shot on d1 in scope).
    assert_eq!(report.rows[2].scene_id, scene_x);
    assert!(report.rows[2].missing);
    assert!(report.rows[2].reshot_candidate);
    // Rows carry the day label.
    assert_eq!(
        report.rows[0].shooting_day_label.as_deref(),
        Some("Tageins")
    );

    // --- Season aggregate spans episodes: adds nothing from d3 (no rows),
    // but counts all three non-archived days. ---
    let report = report_repo
        .season_soll_ist_report(season_id)
        .await
        .unwrap_or_else(|e| panic!("season report should succeed: {e}"));
    assert_eq!(report.total_shooting_days, 3);
    assert_eq!(report.wrapped_shooting_days, 0);
    assert!(!report.is_final);
    assert_eq!(report.rows.len(), 3);
    let scoped_episode = report_repo
        .episode_soll_ist_report(ep2)
        .await
        .unwrap_or_else(|e| panic!("ep2 report should succeed: {e}"));
    assert_eq!(scoped_episode.total_shooting_days, 1);
    assert!(scoped_episode.rows.is_empty());

    // Any unwrapped day keeps everything provisional: wrap d1.
    eappend(
        &client,
        &format!("shooting_day-{day1}"),
        "ShootingDayWrapped",
        "0",
        &encode(&ShootingDayEvent::ShootingDayWrapped {
            id: day1,
            wrapped_at: Utc::now(),
            version: AggregateVersion(1),
        })?,
    )
    .await?;
    let dl = Instant::now() + DEADLINE;
    loop {
        if let Ok(v) = sd_repo.find_by_id(day1).await
            && v.wrapped_at.is_some()
        {
            break;
        }
        if Instant::now() > dl {
            bail!("d1 wrap not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    let report = report_repo.episode_soll_ist_report(ep1).await?;
    assert_eq!(report.wrapped_shooting_days, 1);
    assert!(!report.is_final, "one unwrapped day keeps it provisional");

    // Wrap the rest of the episode's days → episode final …
    for (id, ver) in [(day2, 0u64)] {
        eappend(
            &client,
            &format!("shooting_day-{id}"),
            "ShootingDayWrapped",
            &ver.to_string(),
            &encode(&ShootingDayEvent::ShootingDayWrapped {
                id,
                wrapped_at: Utc::now(),
                version: AggregateVersion(1),
            })?,
        )
        .await?;
    }
    let dl = Instant::now() + DEADLINE;
    loop {
        let wrapped: u32 = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FILTER (WHERE wrapped_at IS NOT NULL) FROM projection_shooting_day \
             WHERE episode_id = $1 AND archived = false",
        )
        .bind(ep1.0)
        .fetch_one(&pool)
        .await? as u32;
        if wrapped == 2 {
            break;
        }
        if Instant::now() > dl {
            bail!("d2 wrap not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    let report = report_repo.episode_soll_ist_report(ep1).await?;
    assert!(report.is_final, "all episode days wrapped ⇒ final");
    assert_eq!(report.wrapped_shooting_days, report.total_shooting_days);

    // … while the season still has the unwrapped ep2 day d3.
    let report = report_repo.season_soll_ist_report(season_id).await?;
    assert!(!report.is_final, "season has an unwrapped day in ep2");

    // Wrap d3 → season final.
    eappend(
        &client,
        &format!("shooting_day-{day3}"),
        "ShootingDayWrapped",
        "0",
        &encode(&ShootingDayEvent::ShootingDayWrapped {
            id: day3,
            wrapped_at: Utc::now(),
            version: AggregateVersion(1),
        })?,
    )
    .await?;
    let dl = Instant::now() + DEADLINE;
    loop {
        let wrapped: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FILTER (WHERE wrapped_at IS NOT NULL) \
             FROM projection_shooting_day d \
             JOIN projection_episode e ON e.id = d.episode_id \
             JOIN projection_block b ON b.id = e.block_id \
             WHERE b.season_id = $1 AND d.archived = false",
        )
        .bind(season_id.0)
        .fetch_one(&pool)
        .await?;
        if wrapped == 3 {
            break;
        }
        if Instant::now() > dl {
            bail!("d3 wrap not projected");
        }
        tokio::time::sleep(POLL).await;
    }

    let report = report_repo.season_soll_ist_report(season_id).await?;
    assert!(report.is_final, "all season days wrapped ⇒ final");

    // Zero-day scope: an episode without days reports empty + never final.
    // NOTE: this episode id is never projected — the query must succeed with
    // zeroes (the 200-empty decision of #571): `404` on a missing scope is
    // the *handler's* job, not the read query's.
    let empty_ep = EpisodeId::new();
    let report = report_repo
        .episode_soll_ist_report(empty_ep)
        .await
        .unwrap_or_else(|e| panic!("empty episode report should succeed: {e}"));
    assert!(report.rows.is_empty());
    assert_eq!(report.total_shooting_days, 0);
    assert!(!report.is_final);

    Ok(())
}
