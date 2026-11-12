// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for workers.rs — kills mutations in acquire_for_claim,
//! release_permit_logging_errors, claim_lost_error, start_heartbeat.

use std::sync::Arc;
use std::time::Duration;

use breakdown_core::ai::{
    AiImportBounds, AiImportEnqueueResult, AiImportJob, AiImportJobId, AiImportProgress,
    AiImportQueue, AiImportStage, DocumentKind, DraftEpisode, DraftScene, JobStatus,
    LlmCallOutcome, LlmCallUsage, LlmChatRequest, LlmClient, LlmProvider, ScriptContext,
    SourceFormat, Telemetry, TelemetryApplyState,
};
use breakdown_core::error::DomainError;
use breakdown_core::shared::UserId;
use tokio::sync::Mutex;

use crate::ai::pdf::PdfTextExtractor;
use crate::ai::preview_store::{AiDocumentSource, AiPreviewStore};
use crate::ai::workers::{ScheduleImportWorker, ScriptImportWorker, claim_lost_error};

// ===========================================================================
// Mock queue for unit tests
// ===========================================================================

struct MockQueue {
    jobs: Mutex<Vec<AiImportJob>>,
    lease_window: Option<Duration>,
    /// Every accepted `mark_progress` frame, in call order (issue #664).
    progress_log: Mutex<Vec<AiImportProgress>>,
    /// The worker that currently holds the claim (owner fence).
    claimed_by: Mutex<Option<String>>,
    /// When set, `mark_progress` fails with this error (fault injection).
    progress_error: Mutex<Option<DomainError>>,
}

impl MockQueue {
    fn new() -> Self {
        Self {
            jobs: Mutex::new(Vec::new()),
            lease_window: None,
            progress_log: Mutex::new(Vec::new()),
            claimed_by: Mutex::new(None),
            progress_error: Mutex::new(None),
        }
    }

    fn with_lease(mut self, lease: Duration) -> Self {
        self.lease_window = Some(lease);
        self
    }

    async fn enqueue_job(&self, kind: DocumentKind) -> AiImportJobId {
        let id = AiImportJobId::new();
        let job = AiImportJob {
            // Issue #871: pre-#871 row — no provider snapshot, no hold.
            provider: None,
            model: None,
            provider_hold: None,
            id,
            user_id: UserId::from_sub("test-user"),
            document_kind: kind,
            source_format: SourceFormat::Csv,
            block_id: None,
            dedup_key: format!("dedup-{}", uuid::Uuid::now_v7()),
            document_digest: "digest".into(),
            source_handle: "handle".into(),
            status: JobStatus::Pending,
            preview_handle: None,
            last_error: None,
            retries: 0,
            progress: None,
            next_attempt_at: None,
            attempts: Vec::new(),
            max_retries: 5,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
            telemetry: None,
            cost: None,
            source_file_name: None,
            target: None,
            applied_episodes: Vec::new(),
            // No Decision Model outcome recorded by a test fixture (issue #767).
            decision_telemetry: None,
            apply_progress: None,
            applied: false,
            // Issue #899: no durable apply slot on a pre-change job literal.
            apply_state: breakdown_core::ai::ApplyState::Idle,
            apply_result: None,
        };
        self.jobs.lock().await.push(job);
        id
    }
}

#[async_trait::async_trait]
impl AiImportQueue for MockQueue {
    async fn enqueue(
        &self,
        request: breakdown_core::ai::AiImportEnqueueRequest,
    ) -> Result<AiImportEnqueueResult, DomainError> {
        let job = AiImportJob {
            // Issue #871: pre-#871 row — no provider snapshot, no hold.
            provider: None,
            model: None,
            provider_hold: None,
            id: request.id,
            user_id: request.user_id,
            document_kind: request.document_kind,
            source_format: request.source_format,
            block_id: request.block_id,
            dedup_key: request.dedup_key,
            document_digest: request.document_digest,
            source_handle: request.source_handle,
            status: JobStatus::Pending,
            preview_handle: None,
            last_error: None,
            retries: 0,
            progress: None,
            next_attempt_at: None,
            attempts: Vec::new(),
            max_retries: 5,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
            telemetry: None,
            cost: None,
            source_file_name: None,
            target: None,
            applied_episodes: Vec::new(),
            // No Decision Model outcome recorded by a test fixture (issue #767).
            decision_telemetry: None,
            apply_progress: None,
            applied: false,
            // Issue #899: no durable apply slot on a pre-change job literal.
            apply_state: breakdown_core::ai::ApplyState::Idle,
            apply_result: None,
        };
        self.jobs.lock().await.push(job);
        Ok(AiImportEnqueueResult::Enqueued(request.id))
    }

    async fn claim_next(&self, worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
        let claimed = self.jobs.lock().await.pop();
        if let Some(job) = &claimed {
            *self.claimed_by.lock().await = Some(worker_id.to_owned());
            // Mirror the PG claim semantics: status flips to running and
            // stale progress from a prior attempt is reset (issue #664).
            let mut job = job.clone();
            job.status = JobStatus::Running;
            job.progress = None;
            return Ok(Some(job));
        }
        Ok(None)
    }

    async fn claim_next_kind(
        &self,
        worker_id: &str,
        kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError> {
        let mut jobs = self.jobs.lock().await;
        let pos = jobs.iter().position(|j| j.document_kind == kind);
        let claimed = pos.map(|p| {
            let mut job = jobs.remove(p);
            job.status = JobStatus::Running;
            // See `claim_next`: no stale progress across attempts.
            job.progress = None;
            job
        });
        drop(jobs);
        if claimed.is_some() {
            *self.claimed_by.lock().await = Some(worker_id.to_owned());
        }
        Ok(claimed)
    }

    async fn mark_progress(
        &self,
        _id: AiImportJobId,
        worker_id: &str,
        progress: &AiImportProgress,
    ) -> Result<(), DomainError> {
        if let Some(error) = self.progress_error.lock().await.take() {
            return Err(error);
        }
        // Owner fence: only the claiming worker may publish progress.
        let owner = self.claimed_by.lock().await.clone();
        if owner.as_deref() != Some(worker_id) {
            return Err(DomainError::conflict(format!(
                "worker {worker_id} no longer holds the claim on the AI import job"
            )));
        }
        self.progress_log.lock().await.push(progress.clone());
        Ok(())
    }

    async fn get(&self, _: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn mark_running(&self, _: AiImportJobId, _: &str) -> Result<(), DomainError> {
        Ok(())
    }

    async fn mark_succeeded(&self, _: AiImportJobId, _: &str, _: &str) -> Result<(), DomainError> {
        Ok(())
    }

    async fn mark_failed(
        &self,
        _: AiImportJobId,
        _: &str,
        _: &str,
        _error_code: Option<&str>,
        _: bool,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    async fn record_worker_telemetry(
        &self,
        _: AiImportJobId,
        _: &str,
        _: Telemetry,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    async fn record_telemetry(&self, _: AiImportJobId, _: Telemetry) -> Result<(), DomainError> {
        Ok(())
    }

    fn lease_window(&self) -> Option<Duration> {
        self.lease_window
    }
}

struct MockClient;

#[async_trait::async_trait]
impl LlmClient for MockClient {
    async fn chat_constrained(
        &self,
        _: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        Ok(LlmCallOutcome::new(
            ScriptContext::default(),
            LlmCallUsage::default(),
        ))
    }
}

struct MockSource {
    bytes: Vec<u8>,
}

#[async_trait::async_trait]
impl AiDocumentSource for MockSource {
    async fn load(&self, _: &str) -> Result<Vec<u8>, DomainError> {
        Ok(self.bytes.clone())
    }
}

struct MockPreviewStore;

#[async_trait::async_trait]
impl AiPreviewStore for MockPreviewStore {
    async fn put(&self, _: AiImportJobId, _: Vec<u8>) -> Result<String, DomainError> {
        Ok("preview-handle".into())
    }

    async fn get(&self, _: &str) -> Result<Option<Vec<u8>>, DomainError> {
        Ok(None)
    }

    async fn delete(&self, _: &str) -> Result<(), DomainError> {
        Ok(())
    }
}

/// Preview store that KEEPS the last stored payload (issue #827 review): the
/// progress frames say what the run knew live, this says what the preview
/// actually carries — the two must agree about the script's block.
#[derive(Default)]
struct CapturingPreviewStore {
    stored: Mutex<Option<Vec<u8>>>,
}

#[async_trait::async_trait]
impl AiPreviewStore for CapturingPreviewStore {
    async fn put(&self, _: AiImportJobId, payload: Vec<u8>) -> Result<String, DomainError> {
        *self.stored.lock().await = Some(payload);
        Ok("preview-handle".into())
    }

    async fn get(&self, _: &str) -> Result<Option<Vec<u8>>, DomainError> {
        Ok(None)
    }

    async fn delete(&self, _: &str) -> Result<(), DomainError> {
        Ok(())
    }
}

// ===========================================================================
// Tests
// ===========================================================================

#[tokio::test]
async fn script_worker_returns_false_when_no_jobs() {
    let queue = Arc::new(MockQueue::new());
    let client = Arc::new(MockClient);
    let previews = Arc::new(MockPreviewStore);

    let worker = ScriptImportWorker {
        // Issue #871: resume disabled — the pre-#871 path (chunk 0).
        chunks: None,
        queue,
        client,
        previews,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: None,
    };

    let result = worker
        .run_once(
            "worker-1",
            &MockSource {
                bytes: b"INT. ROOM - DAY\nHello.".to_vec(),
            },
        )
        .await;
    assert!(result.is_ok());
    assert!(!result.unwrap(), "should return false when no jobs");
}

#[tokio::test]
async fn schedule_worker_returns_false_when_no_jobs() {
    let queue = Arc::new(MockQueue::new());
    let client = Arc::new(MockClient);
    let previews = Arc::new(MockPreviewStore);

    let worker = ScheduleImportWorker {
        queue,
        client,
        previews,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: None,
    };

    let result = worker
        .run_once(
            "worker-1",
            &MockSource {
                bytes: b"INT. ROOM - DAY\nHello.".to_vec(),
            },
        )
        .await;
    assert!(result.is_ok());
    assert!(!result.unwrap(), "should return false when no jobs");
}

#[tokio::test]
async fn script_worker_skips_wrong_kind() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Schedule).await;
    let client = Arc::new(MockClient);
    let previews = Arc::new(MockPreviewStore);

    let worker = ScriptImportWorker {
        // Issue #871: resume disabled — the pre-#871 path (chunk 0).
        chunks: None,
        queue,
        client,
        previews,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: None,
    };

    let result = worker
        .run_once(
            "worker-1",
            &MockSource {
                bytes: b"INT. ROOM - DAY\nHello.".to_vec(),
            },
        )
        .await;
    assert!(result.is_ok());
    assert!(!result.unwrap(), "should return false for wrong kind");
}

// ===========================================================================
// claim_lost_error
// ===========================================================================

#[test]
fn claim_lost_error_returns_conflict() {
    let id = AiImportJobId::new();
    let err = claim_lost_error(id, "worker-1");
    assert!(matches!(err, DomainError::Conflict { .. }));
}

#[test]
fn claim_lost_error_contains_details() {
    let id = AiImportJobId::new();
    let err = claim_lost_error(id, "my-worker");
    let msg = err.to_string();
    assert!(msg.contains("my-worker"));
    assert!(msg.contains(&id.as_uuid().to_string()));
}

// ===========================================================================
// start_heartbeat
// ===========================================================================

#[tokio::test]
async fn start_heartbeat_returns_none_without_lease() {
    let queue = Arc::new(MockQueue::new());
    let client = Arc::new(MockClient);
    let previews = Arc::new(MockPreviewStore);

    let worker = ScriptImportWorker {
        // Issue #871: resume disabled — the pre-#871 path (chunk 0).
        chunks: None,
        queue,
        client,
        previews,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: None,
    };

    let heartbeat = worker.start_heartbeat(AiImportJobId::new(), "worker-1");
    assert!(
        heartbeat.is_none(),
        "should return None when no lease window"
    );
}

#[tokio::test]
async fn start_heartbeat_returns_some_with_lease() {
    let queue = Arc::new(MockQueue::new().with_lease(Duration::from_secs(30)));
    let client = Arc::new(MockClient);
    let previews = Arc::new(MockPreviewStore);

    let worker = ScriptImportWorker {
        // Issue #871: resume disabled — the pre-#871 path (chunk 0).
        chunks: None,
        queue,
        client,
        previews,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: None,
    };

    let heartbeat = worker.start_heartbeat(AiImportJobId::new(), "worker-1");
    assert!(
        heartbeat.is_some(),
        "should return Some when lease window set"
    );
    if let Some(h) = heartbeat {
        h.stop();
    }
}

// ===========================================================================
// Telemetry and ScriptContext
// ===========================================================================

#[test]
fn telemetry_default_is_not_applied() {
    let t = Telemetry::default();
    assert_eq!(t.apply_state, TelemetryApplyState::NotApplied);
}

#[test]
fn script_context_default_is_empty() {
    let ctx = ScriptContext::default();
    assert!(ctx.scenes.is_empty());
    assert!(ctx.uncertainties.is_empty());
}

#[test]
fn conflict_error_is_constructible() {
    let err = DomainError::conflict("test");
    assert!(matches!(err, DomainError::Conflict { .. }));
}

#[test]
fn validation_error_is_constructible() {
    let err = DomainError::validation("test");
    assert!(matches!(err, DomainError::Validation { .. }));
}

// ===========================================================================
// Throttled progress publication (issue #664)
// ===========================================================================

/// Client returning one scene whose episode metadata names `Ep. 3`.
struct EpisodeMockClient;

#[async_trait::async_trait]
impl LlmClient for EpisodeMockClient {
    async fn chat_constrained(
        &self,
        _: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        Ok(LlmCallOutcome::new(
            ScriptContext {
                block_number: None,
                scenes: vec![DraftScene {
                    episode: Some(DraftEpisode {
                        number: Some(3),
                        title: None,
                    }),
                    ..Default::default()
                }],
                ..Default::default()
            },
            LlmCallUsage::default(),
        ))
    }
}

/// Client reporting a block number the deterministic scan cannot read (issue
/// #827): a header in a shape the scan does not recognize.
struct BlockFallbackMockClient;

#[async_trait::async_trait]
impl LlmClient for BlockFallbackMockClient {
    async fn chat_constrained(
        &self,
        _: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        Ok(LlmCallOutcome::new(
            ScriptContext {
                block_number: Some(5),
                scenes: vec![DraftScene::default()],
                ..Default::default()
            },
            LlmCallUsage::default(),
        ))
    }
}

fn script_worker<C: LlmClient + 'static>(
    queue: Arc<MockQueue>,
    client: Arc<C>,
) -> ScriptImportWorker<MockQueue, C> {
    ScriptImportWorker {
        // Issue #871: resume disabled — the pre-#871 path (chunk 0).
        chunks: None,
        queue,
        client,
        previews: Arc::new(MockPreviewStore),
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: None,
    }
}

/// Two scene headings, the first carrying an `Ep.: 3` marker.
const TWO_CHUNK_SCRIPT: &str =
    "Ep.: 3 (Titel)\nINT. ROOM - DAY\nHello.\n\nINT. ROOM 2 - NIGHT\nMore.";

async fn claim_script_job(queue: &MockQueue) -> AiImportJob {
    queue
        .claim_next_kind("worker-progress", DocumentKind::Script)
        .await
        .expect("claim should succeed")
        .expect("fixture enqueued one script job")
}

#[tokio::test]
async fn script_worker_publishes_throttled_progress_frames() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Script).await;
    let worker = script_worker(Arc::clone(&queue), Arc::new(EpisodeMockClient));
    let job = claim_script_job(&queue).await;

    let result = worker
        .process_text(&job, "worker-progress", TWO_CHUNK_SCRIPT)
        .await;
    assert!(result.is_ok(), "script run should succeed: {result:?}");

    let log = queue.progress_log.lock().await;
    assert_eq!(
        log.len(),
        4,
        "frames: after chunking, per chunk (2), storing"
    );
    // First frame: chunking done, counter at 0, total known, first marker seeded.
    assert_eq!(log[0].stage, AiImportStage::Extracting);
    assert_eq!(log[0].chunk, Some(0));
    assert_eq!(log[0].chunks_total, Some(2));
    assert_eq!(log[0].episodes_seen, vec!["Ep. 3".to_owned()]);
    // Per-completed-chunk frames — never per token.
    assert_eq!(log[1].chunk, Some(1));
    assert_eq!(log[2].chunk, Some(2));
    // Storing boundary.
    assert_eq!(log[3].stage, AiImportStage::StoringPreview);
    assert_eq!(log[3].chunk, Some(2));
    // Issue #762: every frame of one attempt carries the SAME time anchor —
    // the claim stamp — so a client can recompute a rate per frame without
    // accumulating state, and a reconnecting client can still see it.
    assert_eq!(log[0].started_at, Some(job.updated_at));
    for frame in log.iter() {
        assert_eq!(
            frame.started_at,
            Some(job.updated_at),
            "the attempt's anchor never moves between frames"
        );
        // Issue #762: every published frame carries the server stamp of ITS
        // own write — the end of the interval an ETA measures. A client-side
        // "now" would count the time the screen was closed as extraction
        // time, and a heartbeat-refreshed `updated_at` would mask a stall.
        assert!(
            frame.written_at.is_some(),
            "every frame is stamped at publication"
        );
    }
}

/// Issue #827: the block the DOCUMENT states travels on every progress frame
/// — the reviewer can compare it with the import target before paying for an
/// apply that the cross-block guard would refuse.
#[tokio::test]
async fn script_worker_publishes_the_block_the_document_states() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Script).await;
    let worker = script_worker(Arc::clone(&queue), Arc::new(EpisodeMockClient));
    let job = claim_script_job(&queue).await;

    let script = "\
Block: 2   Ep.: 3 (Titel)
INT. ROOM - DAY
Hello.

INT. ROOM 2 - NIGHT
More.";

    let result = worker.process_text(&job, "worker-progress", script).await;
    assert!(result.is_ok(), "script run should succeed: {result:?}");

    let log = queue.progress_log.lock().await;
    assert!(!log.is_empty(), "the run publishes progress frames");
    for frame in log.iter() {
        assert_eq!(
            frame.block_number,
            Some(2),
            "every frame names the block the page header states"
        );
    }
}

/// Issue #827 (CodeRabbit review): the preview STORES the block the
/// deterministic scan read, not only what the model repeated. The seed used to
/// live only on the progress frames, so a model that said nothing about the
/// block left `ScriptContext.block_number` empty even though the document
/// states it.
#[tokio::test]
async fn script_preview_stores_the_block_the_document_states() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Script).await;
    // Kept concrete so the test can read what was stored; the worker takes the
    // trait object (coerced at the field assignment).
    let previews = Arc::new(CapturingPreviewStore::default());
    let worker = ScriptImportWorker {
        // Issue #871: resume disabled — the pre-#871 path (chunk 0).
        chunks: None,
        queue: Arc::clone(&queue),
        // The model reports NO block (only the episode) — the scan must carry
        // the stored value on its own.
        client: Arc::new(EpisodeMockClient),
        previews: Arc::clone(&previews) as Arc<dyn AiPreviewStore>,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: None,
    };
    let job = claim_script_job(&queue).await;

    let script = "\
Block: 2   Ep.: 3 (Titel)
INT. ROOM - DAY
Hello.";

    let result = worker.process_text(&job, "worker-progress", script).await;
    assert!(result.is_ok(), "script run should succeed: {result:?}");

    let raw = previews
        .stored
        .lock()
        .await
        .clone()
        .expect("the run stores a preview");
    let context: ScriptContext =
        serde_json::from_slice(&raw).expect("the stored payload is a ScriptContext");
    assert_eq!(
        context.block_number,
        Some(2),
        "the scan's block travels into the stored preview"
    );
}

/// Issue #827: the model's `block_number` is the FALLBACK for a document whose
/// header the deterministic scan cannot read — never an override. The first
/// frame is published before any paid call, so it still says "not known".
#[tokio::test]
async fn script_worker_falls_back_to_the_models_block_number() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Script).await;
    let worker = script_worker(Arc::clone(&queue), Arc::new(BlockFallbackMockClient));
    let job = claim_script_job(&queue).await;

    // No `Block:` marker at all: only the model can name one.
    let script = "Ep.: 3 (Titel)\nINT. ROOM - DAY\nHello.";

    let result = worker.process_text(&job, "worker-progress", script).await;
    assert!(result.is_ok(), "script run should succeed: {result:?}");

    let log = queue.progress_log.lock().await;
    assert_eq!(
        log[0].block_number, None,
        "the frame after chunking precedes every paid call"
    );
    for frame in log.iter().skip(1) {
        assert_eq!(
            frame.block_number,
            Some(5),
            "the model's block fills the gap the scan left"
        );
    }
}

#[tokio::test]
async fn script_worker_publishes_a_monotone_byte_budget() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Script).await;
    let worker = script_worker(Arc::clone(&queue), Arc::new(EpisodeMockClient));
    let job = claim_script_job(&queue).await;

    let result = worker
        .process_text(&job, "worker-progress", TWO_CHUNK_SCRIPT)
        .await;
    assert!(result.is_ok(), "script run should succeed: {result:?}");

    let log = queue.progress_log.lock().await;
    // Issue #762: the byte budget is known once the chunks are (first frame)
    // and the numerator never overtakes the denominator.
    let total = log[0].total_bytes.expect("byte budget on the first frame");
    assert!(total > 0, "two chunks of prose are more than zero bytes");
    assert_eq!(
        log[0].done_bytes,
        Some(0),
        "chunking finished, no chunk done"
    );
    assert!(
        log[1].done_bytes > log[0].done_bytes && log[2].done_bytes > log[1].done_bytes,
        "each completed chunk advances the numerator: {:?}",
        log.iter().map(|f| f.done_bytes).collect::<Vec<_>>()
    );
    for frame in log.iter() {
        assert_eq!(frame.total_bytes, Some(total), "budget is stable");
        assert!(
            frame.done_bytes.unwrap_or(0) <= total,
            "numerator never overtakes the denominator"
        );
    }
    // The last extraction frame accounts for the whole document.
    assert_eq!(log[2].done_bytes, Some(total));
    // `storing_preview` is a stage boundary, not a chunk: the numerator holds
    // at 100% instead of resetting or overshooting.
    assert_eq!(log[3].done_bytes, Some(total));
}

#[tokio::test]
async fn script_worker_accumulates_episode_labels_in_first_seen_order() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Script).await;
    let worker = script_worker(Arc::clone(&queue), Arc::new(EpisodeMockClient));

    // A repeated page-header marker must stay a single entry.
    let source_text = "Ep.: 3 (Titel)\nINT. A - DAY\nx\n\nEp.: 3 (Titel)\nINT. B - NIGHT\ny";
    let job = claim_script_job(&queue).await;
    let result = worker
        .process_text(&job, "worker-progress", source_text)
        .await;
    assert!(result.is_ok(), "script run should succeed: {result:?}");

    let log = queue.progress_log.lock().await;
    for frame in log.iter() {
        assert_eq!(
            frame.episodes_seen,
            vec!["Ep. 3".to_owned()],
            "deduplicated first-seen order in every frame"
        );
    }
}

#[tokio::test]
async fn schedule_worker_publishes_extraction_and_storing_progress() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Schedule).await;
    let client = Arc::new(MockClient);
    let worker = ScheduleImportWorker {
        queue: Arc::clone(&queue),
        client,
        previews: Arc::new(MockPreviewStore),
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: None,
    };
    // The mock source returns plain text; the job fixture is CSV, so the
    // worker parses it natively (see MockSource/MockQueue fixtures).
    let result = worker
        .run_once(
            "worker-progress",
            &MockSource {
                bytes: b"scene_number,order\n1,1\n".to_vec(),
            },
        )
        .await;
    assert!(result.is_ok(), "schedule run should succeed: {result:?}");

    let log = queue.progress_log.lock().await;
    assert_eq!(log.len(), 2, "extraction boundary + storing boundary");
    assert_eq!(log[0].stage, AiImportStage::Extracting);
    assert_eq!(log[0].chunks_total, Some(1));
    // Issue #762: a schedule is ONE extraction unit — the attempt anchor is
    // published, the byte pair is honestly absent instead of faked.
    assert!(log[0].started_at.is_some(), "claim stamp is the anchor");
    assert_eq!(log[0].done_bytes, None);
    assert_eq!(log[0].total_bytes, None);
    assert_eq!(log[1].stage, AiImportStage::StoringPreview);
    assert_eq!(log[1].chunk, Some(1));
}

#[tokio::test]
async fn displaced_worker_cannot_publish_progress() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Script).await;
    let worker = script_worker(Arc::clone(&queue), Arc::new(EpisodeMockClient));

    // First worker claims, then its lease lapses and another worker reclaims.
    let source = MockSource {
        bytes: TWO_CHUNK_SCRIPT.as_bytes().to_vec(),
    };
    let _ = worker.run_once("worker-a", &source).await;
    // Reclaim with a different worker id (owner fence moves).
    *queue.claimed_by.lock().await = Some("worker-b".to_owned());

    let progress = AiImportProgress::default();
    let outcome =
        AiImportQueue::mark_progress(&*queue, AiImportJobId::new(), "worker-a", &progress).await;
    assert!(
        matches!(outcome, Err(DomainError::Conflict { .. })),
        "displaced worker must get Conflict, got {outcome:?}"
    );
    // The new owner may still publish.
    let outcome =
        AiImportQueue::mark_progress(&*queue, AiImportJobId::new(), "worker-b", &progress).await;
    assert!(outcome.is_ok(), "the new owner may publish: {outcome:?}");
}

// ===========================================================================
// Merge worker progress stages (issue #701 mutation gap)
// ===========================================================================

#[tokio::test]
async fn merge_worker_publishes_merging_and_storing_progress() {
    use crate::ai::QueueMergeWorker;
    use crate::ai::preview_store::MemoryAiPreviewStore;
    use breakdown_core::ai::{MergeInput, ShootingSchedule, ShootingScheduleRow};
    use breakdown_core::scene::events::SceneSource;
    use breakdown_core::scene::views::SceneView;
    use breakdown_core::shared::{AggregateVersion, EpisodeId};
    use chrono::TimeZone;

    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Schedule).await;
    // The merge worker claims Schedule jobs and loads the prepared
    // MergeInput blob from the preview store via `preview_handle`.
    {
        let mut jobs = queue.jobs.lock().await;
        if let Some(job) = jobs.last_mut() {
            job.preview_handle = Some("merge-progress-preview".to_owned());
        }
    }

    let previews = Arc::new(MemoryAiPreviewStore::default());
    let scene = SceneView {
        scene_score: None,
        synopsis_score: None,
        id: uuid::Uuid::now_v7(),
        episode_id: EpisodeId::new(),
        scene_number: Some(1),
        location: None,
        mood: None,
        is_schedule_set: false,
        summary: None,
        script_day: None,
        shooting_day_ids: Vec::new(),
        assigned_characters: Vec::new(),
        outfit_beats: Vec::new(),
        version: AggregateVersion::INITIAL,
        updated_at: chrono::Utc.timestamp_opt(0, 0).single().unwrap(),
        source: Some(SceneSource::Manual),
    };
    let input = MergeInput {
        schedule: ShootingSchedule {
            block_id: None,
            rows: vec![ShootingScheduleRow {
                row_ref: "row-1".to_owned(),
                scene_number: Some(1),
                ..Default::default()
            }],
        },
        scenes: vec![scene],
        episode_numbers: std::collections::HashMap::new(),
    };
    previews
        .put_raw_for_test(
            "merge-progress-preview".to_owned(),
            serde_json::to_vec(&input).unwrap(),
        )
        .await;

    let worker = QueueMergeWorker {
        queue: Arc::clone(&queue),
        previews: Arc::clone(&previews),
    };
    let result = worker.run_once("worker-progress").await;
    assert!(result.is_ok(), "merge run should succeed: {result:?}");
    assert!(result.unwrap(), "the claimed schedule job must be merged");

    let log = queue.progress_log.lock().await;
    assert_eq!(log.len(), 2, "merging boundary + storing boundary");
    // Issue #701: the first frame must carry `Merging` — with the field
    // deleted from the struct init, the enum default (`ExtractingText`)
    // would be published instead and clients would see a wrong stage.
    assert_eq!(log[0].stage, AiImportStage::Merging);
    assert_eq!(log[1].stage, AiImportStage::StoringPreview);
}

#[tokio::test]
async fn claim_resets_progress_from_a_prior_attempt() {
    let queue = Arc::new(MockQueue::new());
    queue.enqueue_job(DocumentKind::Script).await;

    // Attempt 1: claim + publish progress, then fail (retryable).
    let worker = script_worker(Arc::clone(&queue), Arc::new(EpisodeMockClient));
    let job = claim_script_job(&queue).await;
    let _ = worker
        .process_text(&job, "worker-progress", TWO_CHUNK_SCRIPT)
        .await;
    assert!(!queue.progress_log.lock().await.is_empty());

    // Simulate the retryable `failed` state the PG queue would leave, with
    // the stale progress of attempt 1 still attached: the claimed job goes
    // back into the runnable pool as `failed`.
    {
        let mut job = job;
        job.status = JobStatus::Failed;
        job.progress = Some(AiImportProgress {
            // Issue #871: additive field; this fixture is not resumed.
            resumed_from: None,
            block_number: None,
            stage: AiImportStage::StoringPreview,
            chunk: Some(2),
            chunks_total: Some(2),
            episodes_seen: vec!["Ep. 3".to_owned()],
            started_at: None,
            done_bytes: None,
            total_bytes: None,
            written_at: None,
        });
        queue.jobs.lock().await.push(job);
    }
    *queue.claimed_by.lock().await = None;

    // Attempt 2: claim resets progress — mirroring the PG claim SQL — so
    // stale progress never flashes before the new attempt's first frame.
    let claimed = queue
        .claim_next_kind("worker-b", DocumentKind::Script)
        .await
        .expect("claim should succeed")
        .expect("retryable failed job is claimable");
    assert_eq!(claimed.status, JobStatus::Running);
    assert_eq!(
        claimed.progress, None,
        "stale progress from attempt 1 must not survive the reclaim"
    );
}
