// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Tier-4 proof for the acceptance criterion of issue #864: **an apply whose
//! caller disappears mid-run still leaves its applied-episode summary
//! resolvable**.
//!
//! The production `ApplyWorker` write chain is driven with a real SierraDB and
//! Postgres. Its mapping repository is wrapped in a **gate**: the first scene
//! mapping is written for real and the `insert` call then never returns, which
//! parks the worker inside `create_scene_reserved`'s confirm step. That is what
//! makes the cancellation provable instead of hopeful — the test waits for the
//! gate's own signal (the row IS committed, the run IS in flight), aborts the
//! future and asserts the join reports **cancelled**. A run that finished first
//! would be a test failure, never a vacuous pass.
//!
//! Two things are asserted:
//!
//! 1. at least one scene mapping survived the cancellation (otherwise the test
//!    would prove nothing about a partial run);
//! 2. the job read derives EXACTLY those committed rows — one entry for the
//!    target episode whose `applied_count` equals the number of confirmed scene
//!    mappings at read time.
//!
//! Why the risk is real and the test worth its cost: the summary used to be a
//! post-apply write in the handler, which this cancellation skips by
//! construction. A regression that moves the derivation back onto the write
//! path (or onto "the handler's own result") would make this test read an empty
//! list, while the seeded-fixture tests in `ai_import_job_identity` would still
//! pass.
//!
//! Determinism: no poll races the worker and no wall-clock budget is involved.
//! The gate blocks the worker until the test drops the future, so exactly ONE
//! scene mapping is committed when the run is cancelled, and the summary must
//! report exactly that.

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
    AiImportEnqueueRequest, AiImportJobId, AiImportMapping, AiImportMappingRepository,
    AiImportQueue, ApplyMapping, ApplyMappingDecision, DocumentKind, DraftScene, ScriptContext,
    SourceFormat, mapping_kind,
};
use breakdown_core::error::DomainError;
use breakdown_core::shared::{BlockId, EpisodeId, ProjectId, SeasonId, UserId};
use fixtures::{spawn_postgres_with_connections, spawn_sierradb};
use infra::ai::{ApplyScriptRequest, ApplyWorker, PgAiImportMappingRepository, PgAiImportQueue};
use infra::event_store::{
    CharacterCommandsImpl, EpisodeCommandsImpl, SceneCommandsImpl, SceneShootCommandsImpl,
    ShootingDayCommandsImpl, WardrobeCommandsImpl, WrapFinalityGate,
};
use infra::projectors::{ProjectorFlushConfig, spawn_scene_projector};
use infra::queries::SeasonRepositoryImpl;
use kameo_es::command_service::CommandService;

const DEADLINE: Duration = Duration::from_secs(60);
const POLL: Duration = Duration::from_millis(100);

fn preview() -> ScriptContext {
    ScriptContext {
        block_number: None,
        title: Some("Abbruch-Fixture".to_owned()),
        scenes: vec![
            DraftScene {
                draft_ref: "1. I/T - KLINIKUM".to_owned(),
                scene_number: Some(1),
                ..Default::default()
            },
            DraftScene {
                draft_ref: "2. I/T - FLUR".to_owned(),
                scene_number: Some(2),
                ..Default::default()
            },
            DraftScene {
                draft_ref: "3. I/T - HOF".to_owned(),
                scene_number: Some(3),
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
    ["1. I/T - KLINIKUM", "2. I/T - FLUR", "3. I/T - HOF"]
        .iter()
        .map(|draft_ref| ApplyMapping {
            draft_ref: (*draft_ref).to_owned(),
            decision: ApplyMappingDecision::Create,
            outfit_decisions: Vec::new(),
        })
        .collect()
}

/// How many CONFIRMED (non-reserved) `scene` mappings this job has.
///
/// A reservation carries `aggregate_version = 0` and means "id claimed, nothing
/// appended" — it is not a committed row and must not be counted.
async fn confirmed_scene_mappings(pool: &sqlx::PgPool, job: AiImportJobId) -> Result<i64> {
    let count: i64 = sqlx::query_scalar(
        r#"
        SELECT count(*)
        FROM ai_import.projection_ai_import_mapping
        WHERE preview_id = $1 AND aggregate_kind = 'scene' AND aggregate_version > 0
        "#,
    )
    .bind(job.as_uuid())
    .fetch_one(pool)
    .await?;
    Ok(count)
}

/// A mapping repository that holds the apply **in flight** at a chosen point.
///
/// The first confirmed `scene` mapping is written for real (so the row the
/// summary must derive is durable), then `insert` never returns, parking the
/// worker inside `create_scene_reserved`'s confirm step until the test drops the
/// apply future. Without such a gate "cancel an in-flight apply" is a race: a
/// three-row preview can finish between the test's observation and its `abort()`,
/// and the assertion would then pass without ever exercising cancellation.
struct GatedMappings<M> {
    inner: M,
    /// Signalled once the first scene mapping is durably confirmed.
    confirmed: tokio::sync::mpsc::Sender<()>,
    /// Held so exactly one call parks (the gate is a one-shot).
    gate_taken: std::sync::atomic::AtomicBool,
}

#[async_trait::async_trait]
impl<M: AiImportMappingRepository> AiImportMappingRepository for GatedMappings<M> {
    async fn find(
        &self,
        preview_id: AiImportJobId,
        draft_ref: &str,
        aggregate_kind: &str,
        ordinal: i32,
    ) -> Result<Option<AiImportMapping>, DomainError> {
        self.inner
            .find(preview_id, draft_ref, aggregate_kind, ordinal)
            .await
    }

    async fn reserve(&self, mapping: AiImportMapping) -> Result<AiImportMapping, DomainError> {
        self.inner.reserve(mapping).await
    }

    async fn insert(&self, mapping: AiImportMapping) -> Result<(), DomainError> {
        let is_scene = mapping.aggregate_kind == mapping_kind::SCENE;
        self.inner.insert(mapping).await?;
        if is_scene
            && !self
                .gate_taken
                .swap(true, std::sync::atomic::Ordering::SeqCst)
        {
            // The row above is committed and the run is provably mid-flight:
            // tell the test, then never resolve this future again.
            let _ = self.confirmed.send(()).await;
            std::future::pending::<()>().await;
        }
        Ok(())
    }

    async fn list_by_preview(
        &self,
        preview_id: AiImportJobId,
    ) -> Result<Vec<AiImportMapping>, DomainError> {
        self.inner.list_by_preview(preview_id).await
    }
}

/// Wait until the scene projector has projected every committed scene row.
async fn await_scene_projection(pool: &sqlx::PgPool, expected: i64) -> Result<()> {
    let deadline = std::time::Instant::now() + DEADLINE;
    loop {
        let projected: i64 = sqlx::query_scalar(r#"SELECT count(*) FROM projection_scene"#)
            .fetch_one(pool)
            .await?;
        if projected >= expected {
            return Ok(());
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("scene projection never caught up ({projected} of {expected})");
        }
        tokio::time::sleep(POLL).await;
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_cancelled_apply_still_leaves_its_summary_resolvable() -> Result<()> {
    let (pool, _pg) = spawn_postgres_with_connections(20).await?;
    let (redis_client, conn, _sierra) = spawn_sierradb().await?;

    // The real projector: the derivation joins the mapping to the PROJECTED
    // scene, so the summary is only complete once the projection caught up —
    // exactly the production ordering.
    let _scene_proj = spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let cmd_service = CommandService::new(conn);
    let finality_gate = WrapFinalityGate::new(pool.clone());
    let queue = Arc::new(PgAiImportQueue::new(pool.clone()));
    // The gate: the test learns the moment the first scene mapping is committed
    // and the worker stays parked there until the future is dropped.
    let (confirmed_tx, mut confirmed_rx) = tokio::sync::mpsc::channel(1);
    let worker = ApplyWorker {
        scene_commands: Arc::new(SceneCommandsImpl::new(cmd_service.clone())),
        character_commands: Arc::new(CharacterCommandsImpl::new(cmd_service.clone())),
        wardrobe_commands: Arc::new(WardrobeCommandsImpl::new(cmd_service.clone())),
        episode_commands: Arc::new(EpisodeCommandsImpl::new(cmd_service.clone())),
        shooting_day_commands: Arc::new(ShootingDayCommandsImpl::new(
            cmd_service.clone(),
            finality_gate.clone(),
        )),
        scene_shoot_commands: Arc::new(SceneShootCommandsImpl::new(
            cmd_service.clone(),
            finality_gate,
        )),
        mappings: Arc::new(GatedMappings {
            inner: PgAiImportMappingRepository::new(pool.clone()),
            confirmed: confirmed_tx,
            gate_taken: std::sync::atomic::AtomicBool::new(false),
        }),
        queue: Arc::clone(&queue),
        season_repo: Arc::new(SeasonRepositoryImpl::new(pool.clone())),
    };

    // A real job row: the summary is read off `GET /ai-import/jobs/{id}`'s own
    // adapter path, which needs the row to exist (a `succeeded` job is the only
    // state an apply can run against in production).
    let job = AiImportJobId::new();
    queue
        .seed_succeeded(
            AiImportEnqueueRequest {
                // Issue #871: no breaker snapshot in this fixture — the job is
                // never breaker-filtered, which is the honest degradation.
                provider: None,
                model: None,
                id: job,
                user_id: UserId::from_sub("cancelled-apply-user"),
                document_kind: DocumentKind::Script,
                source_format: SourceFormat::Pdf,
                block_id: Some(BlockId::new()),
                target: None,
                dedup_key: format!("dedup-{}", job.as_uuid()),
                document_digest: format!("digest-{}", job.as_uuid()),
                source_handle: format!("handle-{}", job.as_uuid()),
                source_file_name: None,
            },
            "preview-handle-cancelled",
        )
        .await?;

    let preview = preview();
    let decisions = decisions();
    let episode_id = EpisodeId::new();
    let season_id = SeasonId::new();
    let project_id = ProjectId::new();
    let block_id = BlockId::new();

    // The apply future IS the handler future: dropping it is what a client that
    // disconnects (or retries) does to the server side.
    let apply = tokio::spawn(async move {
        worker
            .apply_script(ApplyScriptRequest {
                continuity_selections: Vec::new(),
                actor: UserId::from_sub("cancelled-apply-user"),
                preview_id: job,
                preview: &preview,
                decisions: &decisions,
                episode_id,
                season_id,
                project_id: Some(project_id),
                block_id,
                episode_groups: Vec::new(),
                shooting_days: Vec::new(),
                acknowledged_uncertainties: Vec::new(),
                categories: Vec::new(),
                telemetry: None,
                known_episodes: Vec::new(),
            })
            .await
    });

    // Wait for the gate: the first scene mapping is committed AND the worker is
    // still inside the run. Nothing here races a clock.
    confirmed_rx
        .recv()
        .await
        .expect("the apply must reach its first scene confirm");

    apply.abort();
    // The join result is the proof that the run was CANCELLED rather than
    // finished: a completed apply would make the durability claim vacuous.
    match apply.await {
        Err(error) => assert!(
            error.is_cancelled(),
            "the apply future must be cancelled, not merely finished: {error}"
        ),
        Ok(Ok(_)) => panic!(
            "the apply ran to completion before the cancellation — the gate \
             failed to hold it in flight"
        ),
        Ok(Err(domain)) => panic!("the apply failed instead of being cancelled: {domain}"),
    }

    let committed = confirmed_scene_mappings(&pool, job).await?;
    assert_eq!(
        committed, 1,
        "the gate parks the run at its FIRST confirmed scene mapping, so exactly \
         one row is committed"
    );
    await_scene_projection(&pool, committed).await?;

    let read = queue.get(job).await?.expect("the seeded job exists");
    assert_eq!(
        read.applied_episodes.len(),
        1,
        "the interrupted run wrote ONE target episode: {:?}",
        read.applied_episodes
    );
    let entry = &read.applied_episodes[0];
    assert_eq!(
        entry.id, episode_id.0,
        "the entry names the episode the committed rows landed in"
    );
    assert_eq!(
        i64::from(entry.applied_count),
        committed,
        "the derived count is exactly the rows that committed before the cancel"
    );
    assert_eq!(
        entry.number, None,
        "the target episode has no projection row here — honest absence, never a guess"
    );
    Ok(())
}
