// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for workers.rs — kills mutations in acquire_for_claim,
//! release_permit_logging_errors, claim_lost_error, start_heartbeat.

use std::sync::Arc;
use std::time::Duration;

use breakdown_core::ai::{
    AiImportBounds, AiImportEnqueueResult, AiImportJob, AiImportJobId, AiImportQueue, DocumentKind,
    JobStatus, LlmChatRequest, LlmClient, LlmProvider, ScriptContext, SourceFormat, Telemetry,
    TelemetryApplyState,
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
}

impl MockQueue {
    fn new() -> Self {
        Self {
            jobs: Mutex::new(Vec::new()),
            lease_window: None,
        }
    }

    fn with_lease(mut self, lease: Duration) -> Self {
        self.lease_window = Some(lease);
        self
    }

    async fn enqueue_job(&self, kind: DocumentKind) -> AiImportJobId {
        let id = AiImportJobId::new();
        let job = AiImportJob {
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
            max_retries: 5,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
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
            max_retries: 5,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        };
        self.jobs.lock().await.push(job);
        Ok(AiImportEnqueueResult::Enqueued(request.id))
    }

    async fn claim_next(&self, _: &str) -> Result<Option<AiImportJob>, DomainError> {
        Ok(self.jobs.lock().await.pop())
    }

    async fn claim_next_kind(
        &self,
        _: &str,
        kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError> {
        let mut jobs = self.jobs.lock().await;
        let pos = jobs.iter().position(|j| j.document_kind == kind);
        Ok(pos.map(|p| jobs.remove(p)))
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
    async fn chat_constrained(&self, _: LlmChatRequest) -> Result<ScriptContext, DomainError> {
        Ok(ScriptContext::default())
    }
}

struct MockSource;

#[async_trait::async_trait]
impl AiDocumentSource for MockSource {
    async fn load(&self, _: &str) -> Result<Vec<u8>, DomainError> {
        Ok(b"INT. ROOM - DAY\nHello.".to_vec())
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

// ===========================================================================
// Tests
// ===========================================================================

#[tokio::test]
async fn script_worker_returns_false_when_no_jobs() {
    let queue = Arc::new(MockQueue::new());
    let client = Arc::new(MockClient);
    let previews = Arc::new(MockPreviewStore);

    let worker = ScriptImportWorker {
        queue,
        client,
        previews,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
    };

    let result = worker.run_once("worker-1", &MockSource).await;
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
    };

    let result = worker.run_once("worker-1", &MockSource).await;
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
        queue,
        client,
        previews,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
    };

    let result = worker.run_once("worker-1", &MockSource).await;
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
        queue,
        client,
        previews,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
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
        queue,
        client,
        previews,
        extractor: PdfTextExtractor::new(1024, Duration::from_secs(30)),
        provider: LlmProvider::OpenAI,
        model: "gpt-4o".into(),
        prompt: "test".into(),
        bounds: AiImportBounds::default(),
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
