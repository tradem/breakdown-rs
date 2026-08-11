// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

//! Missing-payload semantics for the AI import workers (issue #181).
//!
//! A restart is survivable only because payloads live in durable storage. When
//! a payload is nonetheless *absent*, the job must be terminated as
//! non-resumable immediately instead of burning its retry budget rediscovering
//! the same absence — each retry costs a claim and a concurrency permit.
//!
//! The distinction under test is between two error shapes from the very same
//! call:
//!
//! * `NotFound` — the bytes are gone → `mark_payload_unavailable`;
//! * `ServiceUnavailable` — the backend is unreachable, the bytes may well
//!   still be there → ordinary retryable failure.
//!
//! The tests are deterministic: no clock, no sleep, no container. Every
//! transition is observed through the `AiImportQueue` port.

#![allow(
    // A violated contract must abort the test rather than be threaded
    // through a Result.
    clippy::unwrap_used,
    clippy::expect_used
)]

use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use breakdown_core::ai::{
    AiImportBounds, AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId,
    AiImportQueue, DocumentKind, JobStatus, LlmChatRequest, LlmClient, LlmProvider, ScriptContext,
    SourceFormat, Telemetry,
};
use breakdown_core::error::DomainError;
use breakdown_core::shared::UserId;
use chrono::Utc;

use super::preview_store::{
    AiDocumentSource, AiDocumentStore, AiPreviewStore, MemoryAiPreviewStore,
    UnconfiguredAiPayloadStore,
};
use super::workers::{ScheduleImportWorker, ScriptImportWorker};

/// Terminal transition observed on the queue.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Transition {
    /// `mark_failed` with its `retryable` flag.
    Failed { retryable: bool },
    /// `mark_payload_unavailable`.
    PayloadUnavailable,
}

/// Queue that hands out exactly one job and records every terminal write.
#[derive(Clone)]
struct RecordingQueue {
    job: AiImportJob,
    handed_out: Arc<Mutex<bool>>,
    transitions: Arc<Mutex<Vec<Transition>>>,
}

impl RecordingQueue {
    fn new(kind: DocumentKind, preview_handle: Option<&str>) -> Self {
        Self {
            job: AiImportJob {
                id: AiImportJobId::new(),
                user_id: UserId::from_sub("payload-recovery-user"),
                document_kind: kind,
                source_format: match kind {
                    DocumentKind::Script => SourceFormat::Pdf,
                    DocumentKind::Schedule => SourceFormat::Csv,
                },
                block_id: None,
                dedup_key: "payload-recovery".to_owned(),
                document_digest: "digest".to_owned(),
                source_handle: "ai-import/missing/source".to_owned(),
                status: JobStatus::Running,
                preview_handle: preview_handle.map(str::to_owned),
                last_error: None,
                retries: 0,
                max_retries: 5,
                created_at: Utc::now(),
                updated_at: Utc::now(),
            },
            handed_out: Arc::new(Mutex::new(false)),
            transitions: Arc::new(Mutex::new(Vec::new())),
        }
    }

    fn transitions(&self) -> Vec<Transition> {
        self.transitions.lock().unwrap().clone()
    }

    /// Hand the job out at most once, so a worker loop cannot spin on it.
    fn take_job(&self) -> Option<AiImportJob> {
        let mut handed_out = self.handed_out.lock().unwrap();
        if *handed_out {
            return None;
        }
        *handed_out = true;
        Some(self.job.clone())
    }
}

#[async_trait]
impl AiImportQueue for RecordingQueue {
    async fn enqueue(
        &self,
        request: AiImportEnqueueRequest,
    ) -> Result<AiImportEnqueueResult, DomainError> {
        Ok(AiImportEnqueueResult::Enqueued(request.id))
    }

    async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
        Ok(self.take_job())
    }

    async fn claim_next_kind(
        &self,
        _worker_id: &str,
        kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError> {
        if kind != self.job.document_kind {
            return Ok(None);
        }
        Ok(self.take_job())
    }

    async fn get(&self, _id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
        Ok(Some(self.job.clone()))
    }

    async fn mark_running(&self, _id: AiImportJobId, _worker_id: &str) -> Result<(), DomainError> {
        Ok(())
    }

    async fn mark_succeeded(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _preview_handle: &str,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    async fn mark_failed(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _error_summary: &str,
        retryable: bool,
    ) -> Result<(), DomainError> {
        self.transitions
            .lock()
            .unwrap()
            .push(Transition::Failed { retryable });
        Ok(())
    }

    async fn mark_payload_unavailable(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _error_summary: &str,
    ) -> Result<(), DomainError> {
        self.transitions
            .lock()
            .unwrap()
            .push(Transition::PayloadUnavailable);
        Ok(())
    }

    async fn record_worker_telemetry(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    async fn record_telemetry(
        &self,
        _id: AiImportJobId,
        _telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        Ok(())
    }
}

/// Document source that always fails with a caller-chosen error.
struct FailingSource(DomainError);

#[async_trait]
impl AiDocumentSource for FailingSource {
    async fn load(&self, _handle: &str) -> Result<Vec<u8>, DomainError> {
        Err(self.0.clone())
    }
}

#[derive(Clone, Default)]
struct UnusedLlmClient;

#[async_trait]
impl LlmClient for UnusedLlmClient {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<ScriptContext, DomainError> {
        // The worker must terminate on the payload load, before any paid call.
        Err(DomainError::ValidationError(
            "the LLM must not be called when the payload is missing".to_owned(),
        ))
    }
}

fn script_worker(
    queue: Arc<RecordingQueue>,
) -> ScriptImportWorker<RecordingQueue, UnusedLlmClient> {
    ScriptImportWorker {
        queue,
        client: Arc::new(UnusedLlmClient),
        previews: Arc::new(MemoryAiPreviewStore::default()) as Arc<dyn AiPreviewStore>,
        extractor: super::PdfTextExtractor::new(1024 * 1024, std::time::Duration::from_secs(30)),
        provider: LlmProvider::Neuralwatt,
        model: "deepseek-v4-flash".to_owned(),
        prompt: "fixture prompt".to_owned(),
        bounds: AiImportBounds::default(),
    }
}

fn schedule_worker(
    queue: Arc<RecordingQueue>,
) -> ScheduleImportWorker<RecordingQueue, UnusedLlmClient> {
    ScheduleImportWorker {
        queue,
        client: Arc::new(UnusedLlmClient),
        previews: Arc::new(MemoryAiPreviewStore::default()) as Arc<dyn AiPreviewStore>,
        extractor: super::PdfTextExtractor::new(1024 * 1024, std::time::Duration::from_secs(30)),
        provider: LlmProvider::Neuralwatt,
        model: "deepseek-v4-flash".to_owned(),
        prompt: "fixture prompt".to_owned(),
        bounds: AiImportBounds::default(),
    }
}

#[tokio::test]
async fn script_worker_marks_an_absent_source_document_non_resumable() {
    let queue = Arc::new(RecordingQueue::new(DocumentKind::Script, None));
    let worker = script_worker(Arc::clone(&queue));
    let source = FailingSource(DomainError::NotFound(
        "AI document source ai-import/missing/source".to_owned(),
    ));

    let result = worker.run_once("worker-1", &source).await;

    assert!(matches!(result, Err(DomainError::NotFound(_))));
    assert_eq!(
        queue.transitions(),
        vec![Transition::PayloadUnavailable],
        "an absent source document must terminate the job as non-resumable, \
         not consume a retry"
    );
}

#[tokio::test]
async fn script_worker_keeps_unreachable_storage_retryable() {
    let queue = Arc::new(RecordingQueue::new(DocumentKind::Script, None));
    let worker = script_worker(Arc::clone(&queue));
    // Storage being down says nothing about whether the bytes exist.
    let source = FailingSource(DomainError::ServiceUnavailable(
        "S3 endpoint unreachable".to_owned(),
    ));

    let result = worker.run_once("worker-1", &source).await;

    assert!(matches!(result, Err(DomainError::ServiceUnavailable(_))));
    assert_eq!(
        queue.transitions(),
        vec![Transition::Failed { retryable: true }],
        "a transient storage outage must stay retryable"
    );
}

#[tokio::test]
async fn schedule_worker_marks_an_absent_source_document_non_resumable() {
    let queue = Arc::new(RecordingQueue::new(DocumentKind::Schedule, None));
    let worker = schedule_worker(Arc::clone(&queue));
    let source = FailingSource(DomainError::NotFound(
        "AI document source ai-import/missing/source".to_owned(),
    ));

    let result = worker.run_once("worker-1", &source).await;

    assert!(matches!(result, Err(DomainError::NotFound(_))));
    assert_eq!(queue.transitions(), vec![Transition::PayloadUnavailable]);
}

#[tokio::test]
async fn schedule_worker_keeps_unreachable_storage_retryable() {
    let queue = Arc::new(RecordingQueue::new(DocumentKind::Schedule, None));
    let worker = schedule_worker(Arc::clone(&queue));
    let source = FailingSource(DomainError::ServiceUnavailable(
        "S3 endpoint unreachable".to_owned(),
    ));

    let result = worker.run_once("worker-1", &source).await;

    assert!(matches!(result, Err(DomainError::ServiceUnavailable(_))));
    assert_eq!(
        queue.transitions(),
        vec![Transition::Failed { retryable: true }]
    );
}

#[tokio::test]
async fn merge_worker_marks_an_absent_preview_non_resumable() {
    // Regression: the merge worker used to mark a missing preview blob
    // `retryable = true`, so a permanently lost payload burned the whole
    // retry budget before dead-lettering.
    let queue = Arc::new(RecordingQueue::new(
        DocumentKind::Schedule,
        Some("ai-import/missing/preview"),
    ));
    let worker = super::merge_worker::QueueMergeWorker {
        queue: Arc::clone(&queue),
        // Empty store: `get` resolves to `None` — absence, not an outage.
        previews: Arc::new(MemoryAiPreviewStore::default()),
    };

    let result = worker.run_once("worker-1").await;

    assert!(matches!(result, Err(DomainError::NotFound(_))));
    assert_eq!(queue.transitions(), vec![Transition::PayloadUnavailable]);
}

/// Preview store whose `get` fails outright, rather than reporting absence.
#[derive(Clone)]
struct FailingPreviewStore(DomainError);

#[async_trait]
impl AiPreviewStore for FailingPreviewStore {
    async fn put(&self, _job_id: AiImportJobId, _payload: Vec<u8>) -> Result<String, DomainError> {
        Err(self.0.clone())
    }

    async fn get(&self, _handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
        Err(self.0.clone())
    }

    async fn delete(&self, _handle: &str) -> Result<(), DomainError> {
        Err(self.0.clone())
    }
}

#[tokio::test]
async fn merge_worker_persists_a_retryable_failure_when_the_store_is_unreachable() {
    // Regression: this path propagated the store error with `?`, skipping the
    // terminal write entirely. The job then sat in `running` until its lease
    // lapsed — recovery delayed by a full lease window, with no backoff
    // recorded and no retry charged.
    let queue = Arc::new(RecordingQueue::new(
        DocumentKind::Schedule,
        Some("ai-import/unreachable/preview"),
    ));
    let worker = super::merge_worker::QueueMergeWorker {
        queue: Arc::clone(&queue),
        previews: Arc::new(FailingPreviewStore(DomainError::ServiceUnavailable(
            "S3 endpoint unreachable".to_owned(),
        ))),
    };

    let result = worker.run_once("worker-1").await;

    assert!(matches!(result, Err(DomainError::ServiceUnavailable(_))));
    assert_eq!(
        queue.transitions(),
        vec![Transition::Failed { retryable: true }],
        "an unreachable store says nothing about whether the blob exists, so \
         the job must stay retryable — and the failure must be persisted"
    );
}

#[tokio::test]
async fn merge_worker_does_not_dead_end_on_a_permanent_store_error() {
    // A non-transient store error is this attempt's failure, not proof the
    // payload is gone: it must go through the retry budget, never straight to
    // the non-resumable terminal state.
    let queue = Arc::new(RecordingQueue::new(
        DocumentKind::Schedule,
        Some("ai-import/broken/preview"),
    ));
    let worker = super::merge_worker::QueueMergeWorker {
        queue: Arc::clone(&queue),
        previews: Arc::new(FailingPreviewStore(DomainError::ValidationError(
            "malformed storage key".to_owned(),
        ))),
    };

    let result = worker.run_once("worker-1").await;

    assert!(matches!(result, Err(DomainError::ValidationError(_))));
    assert_eq!(
        queue.transitions(),
        vec![Transition::Failed { retryable: false }],
        "a permanent store error dead-letters through the budget; only proven \
         absence may mark the job non-resumable"
    );
}

#[tokio::test]
async fn unconfigured_store_refuses_every_operation_as_unavailable() {
    // The refusal must be `ServiceUnavailable`, never `NotFound`: a
    // `NotFound` is the signal that permanently dead-ends a job, and a
    // deployment with AI import merely switched off must not produce it.
    let store = UnconfiguredAiPayloadStore;
    let job_id = AiImportJobId::new();

    let errors: Vec<DomainError> = vec![
        AiPreviewStore::put(&store, job_id, vec![1, 2, 3])
            .await
            .unwrap_err(),
        AiPreviewStore::get(&store, "handle").await.unwrap_err(),
        AiPreviewStore::delete(&store, "handle").await.unwrap_err(),
        store.put_source(job_id, vec![1, 2, 3]).await.unwrap_err(),
        store.get_source("handle").await.unwrap_err(),
        store.delete_source("handle").await.unwrap_err(),
        store.load("handle").await.unwrap_err(),
    ];

    for error in errors {
        assert!(
            matches!(error, DomainError::ServiceUnavailable(_)),
            "expected ServiceUnavailable, got {error:?}"
        );
    }
}
