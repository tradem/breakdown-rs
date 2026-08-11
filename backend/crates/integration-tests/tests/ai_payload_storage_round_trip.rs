// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, bail};
use async_trait::async_trait;
use breakdown_core::ai::{
    AiImportBounds, AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId,
    AiImportQueue, ApplyMapping, ApplyMappingDecision, DocumentKind, DraftScene, JobStatus,
    LlmChatRequest, LlmClient, LlmProvider, ScriptContext, ShootingSchedule, SourceFormat,
    Telemetry, TelemetryApplyState,
};
use breakdown_core::error::DomainError;
use breakdown_core::scene::ports::SceneRepository as _;
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{EpisodeId, UserId};
use fixtures::{GarageCredentials, spawn_garage};
use infra::ai::{
    AiDocumentStore, AiPreviewStore, ApplyScriptRequest, ApplyWorker, OpenDalAiPayloadStorage,
    PgAiImportMappingRepository, PgAiImportQueue, ScheduleImportWorker,
};
use infra::event_store::SceneCommandsImpl;
use infra::queries::SceneRepositoryImpl;
use kameo_es::command_service::CommandService;
use uuid::Uuid;

/// Bounded-retry window for asynchronous state visibility (ADR-015 eventual
/// consistency): the worker's status flip and the scene projector's catch-up
/// are observed by polling, never by wall-clock sleeps.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// An LLM client that must never be called: the schedule worker runs in
/// `native_csv` mode, which parses the source document in-process.
struct UnusedLlmClient;

#[async_trait]
impl LlmClient for UnusedLlmClient {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<ScriptContext, DomainError> {
        Err(DomainError::ValidationError(
            "the LLM must not be reached in native_csv mode".to_owned(),
        ))
    }
}

/// A schedule worker in native-CSV mode: no subprocess (`pdftotext`) and no
/// LLM call, so the test stays hermetic and deterministic. The job is
/// enqueued with `SourceFormat::Csv`, which drives the in-process parser.
fn schedule_worker(
    queue: Arc<PgAiImportQueue>,
    previews: Arc<dyn AiPreviewStore>,
) -> ScheduleImportWorker<PgAiImportQueue, UnusedLlmClient> {
    ScheduleImportWorker {
        queue,
        client: Arc::new(UnusedLlmClient),
        previews,
        extractor: infra::ai::PdfTextExtractor::new(1024 * 1024, Duration::from_secs(30)),
        provider: LlmProvider::Neuralwatt,
        model: "unused".to_owned(),
        prompt: "unused".to_owned(),
        bounds: AiImportBounds::default(),
    }
}

/// Wait until the job reaches `expected`, retrying on transient reads for
/// [`PROJECTION_DEADLINE`]. Failures report the observed status explicitly.
async fn await_job_status(
    queue: &PgAiImportQueue,
    id: AiImportJobId,
    expected: JobStatus,
) -> Result<AiImportJob> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let job = queue
            .get(id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("AI import job {} vanished", id.as_uuid()))?;
        if job.status == expected {
            return Ok(job);
        }
        if std::time::Instant::now() >= deadline {
            bail!(
                "AI import job {} did not reach {expected:?} within {PROJECTION_DEADLINE:?}; \
                 last status was {:?}",
                id.as_uuid(),
                job.status
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Wait until the scene projector has materialized the scene, retrying on
/// `NotFound` for [`PROJECTION_DEADLINE`]. Other errors surface immediately.
async fn await_scene_projection(repo: &SceneRepositoryImpl, scene_id: Uuid) -> Result<SceneView> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(scene_id).await {
            Ok(view) => return Ok(view),
            Err(DomainError::NotFound(_)) if std::time::Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound(_)) => {
                bail!(
                    "projection lag: Scene({scene_id}) not projected within \
                     {PROJECTION_DEADLINE:?} — the PostgresProcessor did not catch up in time"
                );
            }
            Err(other) => return Err(anyhow::anyhow!(other.to_string())),
        }
    }
}

/// Build an `OpenDalAiPayloadStorage` from Garage test credentials.
fn build_ai_payload_storage(creds: &GarageCredentials) -> OpenDalAiPayloadStorage {
    OpenDalAiPayloadStorage::new(
        creds.endpoint.clone(),
        creds.access_key.clone(),
        creds.secret_key.clone(),
        creds.bucket.clone(),
        None,
    )
}

/// Test that AI payloads survive a simulated restart (new storage instance, same bucket).
///
/// This verifies the core promise of Issue #174: durable storage for source documents
/// and preview payloads so that pending jobs can resume after an API restart.
#[tokio::test]
async fn ai_payload_storage_survives_simulated_restart() -> Result<()> {
    let (creds, _container) = spawn_garage().await?;

    // Create the AI payload bucket
    let storage = build_ai_payload_storage(&creds);
    // Note: In a real scenario, the bucket would be created by the provision script.
    // For this test, we use the same bucket as costume photos for simplicity.

    let job_id = AiImportJobId::new();
    let source_bytes = b"PDF content for script import".to_vec();
    let preview_bytes = b"{\"scenes\": [{\"heading\": \"INT. KITCHEN\"}]}".to_vec();

    // Phase 1: Store payloads with first storage instance
    {
        let source_handle = storage.put_source(job_id, source_bytes.clone()).await?;
        assert!(source_handle.contains(&job_id.as_uuid().to_string()));
        assert!(source_handle.ends_with("/source"));

        let preview_handle = storage.put(job_id, preview_bytes.clone()).await?;
        assert!(preview_handle.contains(&job_id.as_uuid().to_string()));
        assert!(preview_handle.ends_with("/preview"));

        // Verify both are readable
        let loaded_source = storage.get_source(&source_handle).await?.unwrap();
        assert_eq!(loaded_source, source_bytes);

        let loaded_preview = storage.get(&preview_handle).await?.unwrap();
        assert_eq!(loaded_preview, preview_bytes);
    }

    // Phase 2: Simulate restart - create new storage instance with same bucket
    {
        let storage = build_ai_payload_storage(&creds);

        // Reconstruct handles (as the queue would after restart)
        let source_handle = format!("ai-import/{}/source", job_id.as_uuid());
        let preview_handle = format!("ai-import/{}/preview", job_id.as_uuid());

        // Verify payloads are still accessible
        let loaded_source = storage.get_source(&source_handle).await?.unwrap();
        assert_eq!(
            loaded_source, source_bytes,
            "Source document should survive simulated restart"
        );

        let loaded_preview = storage.get(&preview_handle).await?.unwrap();
        assert_eq!(
            loaded_preview, preview_bytes,
            "Preview payload should survive simulated restart"
        );
    }

    Ok(())
}

/// Test that delete works correctly and missing handles are a no-op.
#[tokio::test]
async fn ai_payload_storage_delete_is_idempotent() -> Result<()> {
    let (creds, _container) = spawn_garage().await?;

    let storage = build_ai_payload_storage(&creds);
    let job_id = AiImportJobId::new();

    // Store and then delete source
    let source_handle = storage.put_source(job_id, b"test".to_vec()).await?;
    assert!(storage.get_source(&source_handle).await?.is_some());

    storage.delete_source(&source_handle).await?;
    assert!(storage.get_source(&source_handle).await?.is_none());

    // Deleting again should be a no-op (not an error)
    storage.delete_source(&source_handle).await?;

    // Store and then delete preview
    let preview_handle = storage.put(job_id, b"preview".to_vec()).await?;
    assert!(storage.get(&preview_handle).await?.is_some());

    storage.delete(&preview_handle).await?;
    assert!(storage.get(&preview_handle).await?.is_none());

    // Deleting again should be a no-op (not an error)
    storage.delete(&preview_handle).await?;

    Ok(())
}

/// Test that source and preview handles are independent.
#[tokio::test]
async fn ai_payload_storage_source_and_preview_are_independent() -> Result<()> {
    let (creds, _container) = spawn_garage().await?;

    let storage = build_ai_payload_storage(&creds);
    let job_id = AiImportJobId::new();

    let source_bytes = b"source document".to_vec();
    let preview_bytes = b"preview payload".to_vec();

    let source_handle = storage.put_source(job_id, source_bytes.clone()).await?;
    let preview_handle = storage.put(job_id, preview_bytes.clone()).await?;

    // Handles should be different
    assert_ne!(source_handle, preview_handle);

    // Deleting source should not affect preview
    storage.delete_source(&source_handle).await?;
    assert!(storage.get_source(&source_handle).await?.is_none());
    assert_eq!(storage.get(&preview_handle).await?, Some(preview_bytes));

    Ok(())
}

/// Full production lifecycle (Issue #202, PR #200 review comment
/// 3735128884): persist a source payload through the command interface,
/// recreate the API storage wiring to simulate a restart, and verify that a
/// worker reloads the source from durable storage, produces a preview, and
/// that the preview is retrievable — all through the production interfaces
/// (`AiDocumentStore`, `AiImportQueue`, `ScheduleImportWorker::run_once`,
/// `AiPreviewStore`).
///
/// Deterministic by construction: the schedule job uses `SourceFormat::Csv`
/// so the worker parses the source in-process — no `pdftotext` subprocess,
/// no LLM call — mirroring `ai_import_permit_reconciliation.rs`.
#[tokio::test]
async fn ai_payload_storage_lifecycle_survives_restart() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (creds, _garage) = crate::fixtures::spawn_garage().await?;

    // --- Upload through the command interface (API handler shape) ----------
    // `enqueue_ai_upload` stores the document via `AiDocumentStore::put_source`
    // and then enqueues a job carrying the returned handle. Reproduce both
    // steps against the production adapters.
    let storage_a = build_ai_payload_storage(&creds);
    let queue_a = PgAiImportQueue::new(pool.clone());
    let job_id = AiImportJobId::new();
    let user_id = UserId::from_sub("payload-lifecycle-user");
    let csv = b"scene_number,shooting_day_label,date,location,order\n\
                1,Tag 1,2026-01-02,Berlin,1\n\
                2,Tag 2,2026-01-03,Muenchen,2\n"
        .to_vec();
    let source_handle = storage_a.put_source(job_id, csv.clone()).await?;
    let enqueued = queue_a
        .enqueue(AiImportEnqueueRequest {
            id: job_id,
            user_id: user_id.clone(),
            document_kind: DocumentKind::Schedule,
            source_format: SourceFormat::Csv,
            block_id: None,
            dedup_key: format!("lifecycle-{}", job_id.as_uuid()),
            document_digest: "digest".to_owned(),
            source_handle: source_handle.clone(),
        })
        .await?;
    assert_eq!(enqueued, AiImportEnqueueResult::Enqueued(job_id));

    // --- Queue persistence -------------------------------------------------
    let persisted = queue_a
        .get(job_id)
        .await?
        .expect("the job row must be persisted by enqueue");
    assert_eq!(persisted.status, JobStatus::Pending);
    assert_eq!(persisted.source_handle, source_handle);
    assert_eq!(persisted.document_kind, DocumentKind::Schedule);
    assert_eq!(persisted.source_format, SourceFormat::Csv);

    // --- Simulated restart: recreate the API storage wiring ----------------
    // Fresh storage instance (same bucket) and fresh queue adapter (same
    // pool). The durable store — not the old instance — is what the source
    // must survive on.
    let storage_b = build_ai_payload_storage(&creds);
    let queue_b = PgAiImportQueue::new(pool.clone());
    let reloaded = storage_b
        .get_source(&source_handle)
        .await?
        .expect("the source document must survive the restart");
    assert_eq!(reloaded, csv);

    // --- Worker reloads the source from durable storage --------------------
    let worker = schedule_worker(Arc::new(queue_b.clone()), Arc::new(storage_b.clone()));
    let ran = worker.run_once("worker-a", &storage_b).await?;
    assert!(ran, "the pending job must be claimable after the restart");

    // Bounded eventual-consistency retries for the async status flip.
    let job = await_job_status(&queue_b, job_id, JobStatus::Succeeded).await?;
    let preview_handle = job
        .preview_handle
        .as_deref()
        .expect("a succeeded job must record its preview handle");

    // --- Preview retrieval through the production preview-store interface --
    // A third storage instance stands in for yet another process reading the
    // preview the restarted worker produced.
    let storage_c = build_ai_payload_storage(&creds);
    let payload = storage_c
        .get(preview_handle)
        .await?
        .expect("the preview payload must survive the restart");
    let schedule: ShootingSchedule = serde_json::from_slice(&payload)?;
    assert_eq!(schedule.rows.len(), 2);
    assert_eq!(schedule.rows[0].scene_number, Some(1));
    assert_eq!(
        schedule.rows[0].shooting_day_label.as_deref(),
        Some("Tag 1")
    );
    assert_eq!(
        schedule.rows[0].date,
        Some(chrono::NaiveDate::from_ymd_opt(2026, 1, 2).expect("static date"))
    );
    assert_eq!(schedule.rows[1].location.as_deref(), Some("Muenchen"));

    // --- Retry must not re-process a completed job -------------------------
    let again = worker.run_once("worker-a", &storage_b).await?;
    assert!(!again, "a succeeded job must not be claimed again");

    // The durable store is not a queue: the source survives the run.
    assert_eq!(
        storage_c.get_source(&source_handle).await?,
        Some(csv),
        "the source document must remain readable after processing"
    );

    Ok(())
}

/// Apply after a simulated restart (Issue #202): the preview produced before
/// the restart is reloaded from durable storage and applied through the
/// production `ApplyWorker` interface, which drives the real
/// command → event → event-store → projector → projection chain (Tier 4,
/// ADR-016): `CreateScene` is dispatched through `SceneCommandsImpl` into
/// SierraDB, the scene projector materializes the projection row, and the
/// test observes it with bounded eventual-consistency retries.
#[tokio::test]
async fn ai_payload_apply_round_trips_through_projection() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, conn, _sierra) = crate::fixtures::spawn_sierradb().await?;
    let (creds, _garage) = crate::fixtures::spawn_garage().await?;

    // Production write chain: CommandService → SceneCommandsImpl → SierraDB.
    let cmd_service = CommandService::new(conn);
    let scene_commands = SceneCommandsImpl::new(cmd_service.clone());
    let scene_repo = SceneRepositoryImpl::new(pool.clone());
    let _scene_ref = infra::projectors::spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    // --- Upload + queue persistence (production interfaces) ----------------
    let storage_a = build_ai_payload_storage(&creds);
    let queue_a = PgAiImportQueue::new(pool.clone());
    let job_id = AiImportJobId::new();
    let user_id = UserId::from_sub("payload-apply-user");
    let source_handle = storage_a
        .put_source(job_id, b"dummy pdf bytes".to_vec())
        .await?;
    let enqueued = queue_a
        .enqueue(AiImportEnqueueRequest {
            id: job_id,
            user_id: user_id.clone(),
            document_kind: DocumentKind::Script,
            source_format: SourceFormat::Pdf,
            block_id: None,
            dedup_key: format!("apply-{}", job_id.as_uuid()),
            document_digest: "digest".to_owned(),
            source_handle: source_handle.clone(),
        })
        .await?;
    assert_eq!(enqueued, AiImportEnqueueResult::Enqueued(job_id));

    // --- Produce the preview through the production interfaces -------------
    // The worker's success path is `AiPreviewStore::put` followed by
    // `AiImportQueue::mark_succeeded`; reproduce both so the job is in the
    // exact `Succeeded` state the apply handler requires.
    let context = ScriptContext {
        title: Some("Lifecycle fixture script".to_owned()),
        scenes: vec![DraftScene {
            draft_ref: "scene-1".to_owned(),
            scene_number: Some(1),
            location: Some("Berlin".to_owned()),
            mood: Some("dark".to_owned()),
            summary: None,
            script_day: None,
            characters: vec![],
        }],
        uncertainties: vec![],
    };
    let preview_handle = storage_a.put(job_id, serde_json::to_vec(&context)?).await?;
    let claimed = queue_a
        .claim_next_kind("worker-a", DocumentKind::Script)
        .await?
        .expect("the enqueued script job must be claimable");
    assert_eq!(claimed.id, job_id);
    queue_a
        .mark_succeeded(job_id, "worker-a", &preview_handle)
        .await?;

    // --- Simulated restart: recreate the API storage wiring ----------------
    let storage_b = build_ai_payload_storage(&creds);
    let queue_b = PgAiImportQueue::new(pool.clone());
    let mappings_b = PgAiImportMappingRepository::new(pool.clone());

    // --- Preview retrieval after the restart -------------------------------
    let job = queue_b
        .get(job_id)
        .await?
        .expect("the job row must survive the restart");
    assert_eq!(job.status, JobStatus::Succeeded);
    let preview_handle = job
        .preview_handle
        .as_deref()
        .expect("the preview handle must survive the restart");
    let payload = storage_b
        .get(preview_handle)
        .await?
        .expect("the preview payload must survive the restart");
    let reloaded: ScriptContext = serde_json::from_slice(&payload)?;
    assert_eq!(reloaded, context);

    // --- Apply through the production ApplyWorker interface ----------------
    let worker = ApplyWorker {
        scene_commands: Arc::new(scene_commands),
        mappings: Arc::new(mappings_b),
        queue: Arc::new(queue_b),
    };
    let applied = worker
        .apply_script(ApplyScriptRequest {
            actor: user_id,
            preview_id: job_id,
            preview: &reloaded,
            decisions: &[ApplyMapping {
                draft_ref: "scene-1".to_owned(),
                decision: ApplyMappingDecision::Create,
            }],
            episode_id: EpisodeId::new(),
            series_id: None,
            telemetry: Some(Telemetry {
                doc_kind: Some(DocumentKind::Script),
                apply_state: TelemetryApplyState::NotApplied,
                ..Telemetry::default()
            }),
        })
        .await?;
    assert_eq!(applied.len(), 1, "one scene must be applied");

    // --- command → event → event-store → projector → projection ------------
    // Bounded eventual-consistency retries for the projector to catch up.
    let view = await_scene_projection(&scene_repo, applied[0].aggregate_id).await?;
    assert_eq!(view.scene_number, Some(1));
    assert_eq!(view.location.as_deref(), Some("Berlin"));
    assert_eq!(view.mood.as_deref(), Some("dark"));

    Ok(())
}
