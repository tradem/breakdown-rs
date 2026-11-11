// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Tier-4 round trip for the Decision-Model score persistence (issue #834).
//!
//! A reviewed script preview whose draft row carries `scene_score` /
//! `synopsis_score` (issue #722's best-effort scoring pass) is applied through
//! the production `ApplyWorker` write chain. The test asserts the projection
//! catch-up: the `SceneCreated` event the apply dispatches carries the draft's
//! scores, the projector writes them into the `projection_scene` columns, and
//! the read adapter serves them on `SceneView`.

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
    DocumentKind, DraftScene, ScriptContext,
};
use breakdown_core::error::DomainError;
use breakdown_core::scene::ports::SceneRepository as _;
use breakdown_core::shared::{EpisodeId, ProjectId, SeasonId};
use fixtures::{spawn_postgres_with_connections, spawn_sierradb};
use infra::ai::{ApplyScriptRequest, ApplyWorker, PgAiImportMappingRepository, PgAiImportQueue};
use infra::event_store::{
    CharacterCommandsImpl, EpisodeCommandsImpl, SceneCommandsImpl, SceneShootCommandsImpl,
    ShootingDayCommandsImpl, WardrobeCommandsImpl, WrapFinalityGate,
};
use infra::projectors::{ProjectorFlushConfig, spawn_scene_projector, spawn_scene_shoot_projector};
use infra::queries::{SceneRepositoryImpl, SeasonRepositoryImpl};
use kameo_es::command_service::CommandService;
use uuid::Uuid;

const DEADLINE: Duration = Duration::from_secs(30);
const POLL: Duration = Duration::from_millis(200);

fn preview() -> ScriptContext {
    ScriptContext {
        block_number: None,
        title: Some("Score fixture".to_owned()),
        scenes: vec![DraftScene {
            draft_ref: "1. I/T - KLINIKUM".to_owned(),
            scene_number: Some(1),
            location: Some("Klinikum".to_owned()),
            mood: Some("Tag".to_owned()),
            summary: Some("Eröffnungsszene".to_owned()),
            scene_score: Some(0.82),
            synopsis_score: Some(0.41),
            ..Default::default()
        }],
        uncertainties: vec![],
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    }
}

fn decisions() -> Vec<ApplyMapping> {
    vec![ApplyMapping {
        draft_ref: "1. I/T - KLINIKUM".to_owned(),
        decision: ApplyMappingDecision::Create,
        outfit_decisions: Vec::new(),
    }]
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
    let _ss_proj = spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;

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
        queue: Arc::new(infra::ai::PgAiImportQueue::new(pool.clone())),
        // CR-002/D2: the worker refuses the outfit step of an archived season.
        season_repo: Arc::new(SeasonRepositoryImpl::new(pool.clone())),
    };
    Ok(Harness {
        _pg: pg_container,
        _sierra: sierra_container,
        worker,
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
    async fn apply(
        &self,
        user: &str,
    ) -> Result<(AiImportJobId, infra::ai::ScriptApplyResult), DomainError> {
        let preview = preview();
        let queue = PgAiImportQueue::new(self.pool.clone());
        let job_id = seed_succeeded_job(&queue, user)
            .await
            .map_err(|e| DomainError::conflict(e.to_string()))?;
        self.worker
            .apply_script(ApplyScriptRequest {
                continuity_selections: Vec::new(),
                actor: breakdown_core::shared::UserId::from_sub("score-round-trip-user"),
                preview_id: job_id,
                preview: &preview,
                decisions: &decisions(),
                episode_id: self.episode_id,
                season_id: SeasonId::new(),
                project_id: Some(ProjectId::new()),
                block_id: breakdown_core::shared::BlockId::new(),
                episode_groups: Vec::new(),
                shooting_days: Vec::new(),
                acknowledged_uncertainties: Vec::new(),
                // The fixture's row names no figure, so no piece/category row
                // is planned and the vocabulary is never consulted.
                categories: Vec::new(),
                telemetry: None,
                known_episodes: Vec::new(),
            })
            .await
            .map(|result| (job_id, result))
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn script_apply_persists_the_decision_model_scores() -> Result<()> {
    let harness = harness().await?;
    let (_job_id, result) = harness.apply("score-round-trip-user").await?;
    assert_eq!(result.applied.len(), 1);
    let scene_id = result.applied[0].aggregate_id;

    // The apply result acks the command; the projection catch-up is the
    // contract under test (ADR-016 eventual consistency).
    let repo = SceneRepositoryImpl::new(harness.pool.clone());
    let deadline = std::time::Instant::now() + DEADLINE;
    let scene = loop {
        match repo.find_by_id(scene_id).await {
            Ok(scene) => break scene,
            Err(_) if std::time::Instant::now() < deadline => {
                tokio::time::sleep(POLL).await;
            }
            Err(e) => anyhow::bail!("scene projection never caught up: {e}"),
        }
    };

    // The draft's Decision-Model scores survived the full apply chain
    // (DraftScene → SceneDetails → SceneCreated → projection → SceneView).
    assert_eq!(scene.scene_score, Some(0.82));
    assert_eq!(scene.synopsis_score, Some(0.41));

    Ok(())
}
