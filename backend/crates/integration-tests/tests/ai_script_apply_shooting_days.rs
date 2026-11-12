// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Tier-4 round trip for the script-apply shooting-day path (issue #706).
//!
//! A reviewed script preview carrying two draft rows of the SAME day group is
//! applied through the production `ApplyWorker` write chain (`CommandService`
//! → `*CommandsImpl` → SierraDB, Postgres mapping projection). The test
//! asserts the projection catch-up (ADR-016 eventual consistency):
//!
//! 1. one episode-scoped `ShootingDay` (`AiExtracted` source) per accepted day
//!    group, created with the first-occurrence display label;
//! 2. both scenes linked to it (`projection_scene_shooting_day`), each with a
//!    planned `scene_shoot` pair;
//! 3. a re-apply of the same preview creates nothing (mapping-row idempotency).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr
)]

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportJobId, AiImportQueue as _, ApplyMapping, ApplyMappingDecision,
    DocumentKind, DraftScene, DraftShootingDay, ScriptContext, ShootingDayPlan,
};
use breakdown_core::error::DomainError;
use breakdown_core::scene_shoot::ports::SceneShootRepository as _;
use breakdown_core::shared::{EpisodeId, ProjectId, SeasonId, ShootingDayId};
use breakdown_core::shooting_day::ports::ShootingDayRepository;
use fixtures::{spawn_postgres_with_connections, spawn_sierradb};
use infra::ai::{ApplyScriptRequest, ApplyWorker, PgAiImportMappingRepository, PgAiImportQueue};
use infra::event_store::{
    CharacterCommandsImpl, EpisodeCommandsImpl, SceneCommandsImpl, SceneShootCommandsImpl,
    ShootingDayCommandsImpl, WardrobeCommandsImpl, WrapFinalityGate,
};
use infra::projectors::{
    ProjectorFlushConfig, spawn_scene_projector, spawn_scene_shoot_projector,
    spawn_shooting_day_projector,
};
use infra::queries::{SceneShootRepositoryImpl, SeasonRepositoryImpl, ShootingDayRepositoryImpl};
use kameo_es::command_service::CommandService;
use uuid::Uuid;

const DEADLINE: Duration = Duration::from_secs(30);
const POLL: Duration = Duration::from_millis(200);

fn preview() -> ScriptContext {
    let day = || DraftShootingDay {
        number: Some(1),
        label: Some("Tag 1".to_owned()),
        score: None,
    };
    ScriptContext {
        block_number: None,
        title: Some("Drehtag fixture".to_owned()),
        scenes: vec![
            DraftScene {
                draft_ref: "1. I/T - KLINIKUM".to_owned(),
                scene_number: Some(1),
                shooting_day: Some(day()),
                ..Default::default()
            },
            DraftScene {
                draft_ref: "2. I/T - FLUR".to_owned(),
                scene_number: Some(2),
                shooting_day: Some(day()),
                ..Default::default()
            },
        ],
        uncertainties: vec![],
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    }
}

fn decisions() -> Vec<ApplyMapping> {
    vec![
        ApplyMapping {
            draft_ref: "1. I/T - KLINIKUM".to_owned(),
            decision: ApplyMappingDecision::Create,
            outfit_decisions: Vec::new(),
        },
        ApplyMapping {
            draft_ref: "2. I/T - FLUR".to_owned(),
            decision: ApplyMappingDecision::Create,
            outfit_decisions: Vec::new(),
        },
    ]
}

struct Harness {
    /// The container guards MUST live as long as the pool: dropping either
    /// stops the container and every later pool acquire times out.
    _pg: testcontainers::ContainerAsync<testcontainers_modules::postgres::Postgres>,
    _sierra: testcontainers::ContainerAsync<fixtures::SierraDbImage>,
    worker: ApplyWorker<
        SceneCommandsImpl,
        CharacterCommandsImpl,
        WardrobeCommandsImpl,
        EpisodeCommandsImpl,
        ShootingDayCommandsImpl,
        SceneShootCommandsImpl,
        PgAiImportMappingRepository,
        infra::ai::PgAiImportQueue,
        SeasonRepositoryImpl,
    >,
    preview_id: AiImportJobId,
    episode_id: EpisodeId,
    pool: sqlx::PgPool,
}

async fn harness() -> Result<Harness> {
    let (pool, pg_container) = spawn_postgres_with_connections(20).await?;
    let (redis_client, conn, sierra_container) = spawn_sierradb().await?;

    let cmd_service = CommandService::new(conn);
    let finality_gate = WrapFinalityGate::new(pool.clone());
    let _scene_proj = spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _sd_proj = spawn_shooting_day_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _ss_proj = spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let queue = PgAiImportQueue::new(pool.clone());
    // The apply path claims a terminal job's single-flight slot (issue #800), so
    // the fixture seeds the row the production import would have left behind:
    // enqueued, claimed by a worker, then succeeded.
    let preview_id = seed_succeeded_job(&queue, "day-round-trip-user").await?;
    let worker = ApplyWorker {
        scene_commands: Arc::new(SceneCommandsImpl::new(cmd_service.clone())),
        character_commands: Arc::new(CharacterCommandsImpl::new(cmd_service.clone())),
        wardrobe_commands: Arc::new(WardrobeCommandsImpl::new(cmd_service.clone())),
        // No group maps to a NEW episode, so the episode port stays idle —
        // but the production write chain must be wired (issue #581 shape).
        episode_commands: Arc::new(EpisodeCommandsImpl::new(cmd_service.clone())),
        shooting_day_commands: Arc::new(ShootingDayCommandsImpl::new(
            cmd_service.clone(),
            finality_gate.clone(),
        )),
        scene_shoot_commands: Arc::new(SceneShootCommandsImpl::new(
            cmd_service.clone(),
            finality_gate,
        )),
        mappings: Arc::new(PgAiImportMappingRepository::new(pool.clone())),
        queue: Arc::new(queue),
        // CR-002/D2: the worker refuses the outfit step of an archived season.
        season_repo: Arc::new(SeasonRepositoryImpl::new(pool.clone())),
    };
    Ok(Harness {
        _pg: pg_container,
        _sierra: sierra_container,
        worker,
        preview_id,
        episode_id: EpisodeId::new(),
        pool,
    })
}

/// An enqueue request for a script import (mirrors the fixture of the
/// job-progress tests): one fresh job, no payload storage configured.
fn make_enqueue_request(user_id: &str) -> AiImportEnqueueRequest {
    AiImportEnqueueRequest {
        // Issue #871: no breaker snapshot in this fixture — the job is
        // never breaker-filtered, which is the honest degradation.
        provider: None,
        model: None,
        id: AiImportJobId::new(),
        user_id: breakdown_core::shared::UserId::from_sub(user_id),
        document_kind: DocumentKind::Script,
        source_format: breakdown_core::ai::SourceFormat::Pdf,
        block_id: None,
        dedup_key: format!("dedup-{user_id}-{}", Uuid::now_v7()),
        document_digest: format!("digest-{}", Uuid::now_v7()),
        source_handle: format!("handle-{}", Uuid::now_v7()),
        source_file_name: None,
        target: None,
    }
}

/// Seed a `succeeded` import job whose id the apply can claim — the
/// single-flight slot (`claim_apply_run`, issue #800) only admits applies of
/// terminal jobs, mirroring the production flow (import ran, then apply).
async fn seed_succeeded_job(queue: &PgAiImportQueue, user: &str) -> Result<AiImportJobId> {
    let request = make_enqueue_request(user);
    let id = request.id;
    queue.enqueue(request).await?;
    let _claimed = queue.claim_next("worker-1").await?.expect("claimable");
    queue
        .mark_succeeded(id, "worker-1", "ai-preview/handle")
        .await?;
    Ok(id)
}

impl Harness {
    /// Both applies drive the SAME terminal job: the mapping rows the first run
    /// writes are keyed by the preview id, which is what makes the second run
    /// converge instead of re-creating the day. The run slot itself is released
    /// when a run ends (`mark_apply_progress(.., None)` clears `apply_run_id`),
    /// so the re-apply claims the job again — no 409.
    async fn apply(&self) -> Result<infra::ai::ScriptApplyResult, DomainError> {
        let preview = preview();
        self.worker
            .apply_script(ApplyScriptRequest {
                continuity_selections: Vec::new(),
                actor: breakdown_core::shared::UserId::from_sub("day-round-trip-user"),
                preview_id: self.preview_id,
                preview: &preview,
                decisions: &decisions(),
                episode_id: self.episode_id,
                season_id: SeasonId::new(),
                project_id: Some(ProjectId::new()),
                // Single-episode flow; the day is created under the row's
                // resolved (default) episode.
                block_id: breakdown_core::shared::BlockId::new(),
                episode_groups: Vec::new(),
                shooting_days: vec![ShootingDayPlan {
                    day_ref: "day:1".to_owned(),
                    accepted: true,
                }],
                acknowledged_uncertainties: Vec::new(),
                // The fixture's rows name no figure, so no piece/category row
                // is planned and the vocabulary is never consulted.
                categories: Vec::new(),
                telemetry: None,
                known_episodes: Vec::new(),
            })
            .await
    }
}

/// Wait until the projection lists exactly one non-archived day in the
/// episode, and return it.
async fn await_day_projection(
    repo: &ShootingDayRepositoryImpl,
    episode_id: EpisodeId,
) -> Result<breakdown_core::shooting_day::views::ShootingDayView> {
    let deadline = std::time::Instant::now() + DEADLINE;
    loop {
        let days = repo.list_by_episode(episode_id).await.unwrap_or_default();
        if days.len() == 1 {
            return Ok(days[0].clone());
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!(
                "shooting-day projection never caught up (days: {:?})",
                days.len()
            );
        }
        tokio::time::sleep(POLL).await;
    }
}

/// Wait until the day's scene-link projection lists both applied scenes.
async fn await_scene_day_links(
    repo: &ShootingDayRepositoryImpl,
    day: ShootingDayId,
    expected: usize,
) -> Result<Vec<breakdown_core::scene::views::SceneView>> {
    let deadline = std::time::Instant::now() + DEADLINE;
    loop {
        let scenes = repo.scenes_by_shooting_day(day).await.unwrap_or_default();
        if scenes.len() >= expected {
            return Ok(scenes);
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!(
                "scene-day links never caught up ({} of {})",
                scenes.len(),
                expected
            );
        }
        tokio::time::sleep(POLL).await;
    }
}

/// Wait until the (scene, day) scene_shoot pair is projected.
async fn await_pair(
    repo: &SceneShootRepositoryImpl,
    scene_id: Uuid,
    day: ShootingDayId,
) -> Result<()> {
    let deadline = std::time::Instant::now() + DEADLINE;
    loop {
        if repo.find_by_scene_and_day(scene_id, day).await.is_ok() {
            return Ok(());
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("scene_shoot pair {scene_id}/{day:?} never projected");
        }
        tokio::time::sleep(POLL).await;
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn script_apply_creates_and_schedules_a_day_then_re_apply_converges() -> Result<()> {
    let harness = harness().await?;
    let day_repo = ShootingDayRepositoryImpl::new(harness.pool.clone());
    let ss_repo = SceneShootRepositoryImpl::new(harness.pool.clone());

    // --- First apply: one day, two links, two pairs -------------------------
    let first = harness.apply().await?;
    assert_eq!(first.created_days, 1, "exactly one day per group");
    assert_eq!(first.planned_scene_shoots, 2, "one pair per linked scene");
    assert_eq!(first.applied.len(), 2);

    let day = await_day_projection(&day_repo, harness.episode_id).await?;
    assert_eq!(
        day.label.as_deref(),
        Some("Tag 1"),
        "the first-occurrence display label is what the aggregate carries"
    );
    assert!(
        matches!(
            &day.source,
            breakdown_core::shooting_day::events::ShootingDaySource::AiExtracted { .. }
        ),
        "an apply-created day carries the AiExtracted provenance"
    );

    let scenes = await_scene_day_links(&day_repo, day.id, 2).await?;
    assert_eq!(scenes.len(), 2);
    for scene in &scenes {
        await_pair(&ss_repo, scene.id, day.id).await?;
    }

    // --- Re-apply: the mapping rows short-circuit everything ---------------
    let second = harness.apply().await?;
    assert_eq!(second.created_days, 0, "no second day");
    assert_eq!(second.planned_scene_shoots, 0, "no second pair");
    let days = day_repo.list_by_episode(harness.episode_id).await?;
    assert_eq!(days.len(), 1, "the re-apply created no duplicate day");
    Ok(())
}
