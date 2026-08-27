// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: glm-5.3-flash (opencode-go)

use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::anyhow;
use async_trait::async_trait;
use breakdown_core::ai::{
    AiImportBounds, AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId,
    AiImportMapping, AiImportMappingRepository, AiImportQueue, ApplyMapping, DocumentKind,
    DraftScene, JobStatus, LlmChatRequest, LlmClient, LlmProvider, ScriptContext, ShootingSchedule,
    ShootingScheduleRow, SourceFormat, Telemetry, TelemetryApplyState, merge_schedule_to_scenes,
};
use breakdown_core::error::DomainError;
use breakdown_core::shared::UserId;
use chrono::Utc;
use reqwest::StatusCode;
use uuid::Uuid;

use super::{
    AiImportFeature, AiPreviewStore, ApplyScriptRequest, ApplyWorker, MemoryAiPreviewStore,
    ScheduleApplyRequest, ScheduleApplyWorker, ScheduleImportWorker, ScriptImportWorker,
    classify_http_status, merge_loaded_schedule, validate_chunk_count,
};
use crate::photo::sagas::retry_transient_value_with_delay;

#[test]
fn transient_provider_statuses_are_service_unavailable() {
    assert!(matches!(
        classify_http_status(StatusCode::TOO_MANY_REQUESTS),
        DomainError::ServiceUnavailable { .. }
    ));
    assert!(matches!(
        classify_http_status(StatusCode::INTERNAL_SERVER_ERROR),
        DomainError::ServiceUnavailable { .. }
    ));
    assert!(matches!(
        classify_http_status(StatusCode::BAD_REQUEST),
        DomainError::Validation { .. }
    ));
}

#[tokio::test]
async fn transient_provider_failure_retries_without_wall_clock_sleep() {
    let attempts = Arc::new(AtomicUsize::new(0));
    let result = retry_transient_value_with_delay(
        {
            let attempts = Arc::clone(&attempts);
            move || {
                let attempts = Arc::clone(&attempts);
                async move {
                    if attempts.fetch_add(1, Ordering::SeqCst) == 0 {
                        Err(anyhow!(DomainError::service_unavailable("simulated 503")))
                    } else {
                        Ok::<_, anyhow::Error>("success")
                    }
                }
            }
        },
        |_| std::time::Duration::ZERO,
    )
    .await;
    assert_eq!(result.unwrap(), "success");
    assert_eq!(attempts.load(Ordering::SeqCst), 2);
}

#[test]
fn oversized_script_is_rejected_before_provider_calls() {
    assert!(validate_chunk_count(3, 2).is_err());
    assert!(validate_chunk_count(2, 2).is_ok());
}

#[test]
fn merge_blocks_when_no_applied_scenes_exist() {
    let schedule = breakdown_core::ai::ShootingSchedule::default();
    let result = merge_loaded_schedule(&schedule, &[]);
    assert!(matches!(result, Err(DomainError::Conflict { .. })));
}

/// Verify that an empty MergeInput (no applied scenes) is marked
/// non-retryable: the input is immutable and the worker cannot observe
/// later applied scenes, so retrying would exhaust retries against the
/// same blob. The caller must re-prepare a fresh MergeInput at the API
/// boundary after scenes are applied (CQRS boundary, AGENTS.md §1).
#[tokio::test]
async fn merge_worker_empty_input_is_non_retryable() {
    use super::QueueMergeWorker;
    use breakdown_core::ai::{AiImportJob, DocumentKind, MergeInput, ShootingSchedule};
    use breakdown_core::shared::UserId;

    #[derive(Clone, Default)]
    struct RetryTrackingQueue {
        state: Arc<Mutex<RetryTrackingState>>,
    }

    #[derive(Default)]
    struct RetryTrackingState {
        failed_retryable: Vec<bool>,
    }

    #[async_trait]
    impl AiImportQueue for RetryTrackingQueue {
        async fn enqueue(
            &self,
            _request: breakdown_core::ai::AiImportEnqueueRequest,
        ) -> Result<breakdown_core::ai::AiImportEnqueueResult, DomainError> {
            unimplemented!()
        }
        async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
            unimplemented!()
        }
        async fn claim_next_kind(
            &self,
            _worker_id: &str,
            _kind: DocumentKind,
        ) -> Result<Option<AiImportJob>, DomainError> {
            let job = AiImportJob {
                id: breakdown_core::ai::AiImportJobId(Uuid::now_v7()),
                user_id: UserId::from_sub("test-user"),
                document_kind: DocumentKind::Schedule,
                source_format: SourceFormat::Csv,
                block_id: None,
                dedup_key: "test-dedup".to_owned(),
                document_digest: "test-digest".to_owned(),
                source_handle: "test-source".to_owned(),
                status: breakdown_core::ai::JobStatus::Pending,
                preview_handle: Some("test-preview".to_owned()),
                last_error: None,
                retries: 0,
                max_retries: 5,
                created_at: Utc::now(),
                updated_at: Utc::now(),
            };
            Ok(Some(job))
        }
        async fn get(
            &self,
            _id: breakdown_core::ai::AiImportJobId,
        ) -> Result<Option<AiImportJob>, DomainError> {
            unimplemented!()
        }
        async fn mark_running(
            &self,
            _id: breakdown_core::ai::AiImportJobId,
            _worker_id: &str,
        ) -> Result<(), DomainError> {
            Ok(())
        }
        async fn mark_succeeded(
            &self,
            _id: breakdown_core::ai::AiImportJobId,
            _worker_id: &str,
            _preview_handle: &str,
        ) -> Result<(), DomainError> {
            unimplemented!()
        }
        async fn mark_failed(
            &self,
            _id: breakdown_core::ai::AiImportJobId,
            _worker_id: &str,
            _error_summary: &str,
            retryable: bool,
        ) -> Result<(), DomainError> {
            self.state.lock().unwrap().failed_retryable.push(retryable);
            Ok(())
        }
        async fn record_worker_telemetry(
            &self,
            _id: breakdown_core::ai::AiImportJobId,
            _worker_id: &str,
            _telemetry: breakdown_core::ai::Telemetry,
        ) -> Result<(), DomainError> {
            Ok(())
        }
        async fn record_telemetry(
            &self,
            _id: breakdown_core::ai::AiImportJobId,
            _telemetry: breakdown_core::ai::Telemetry,
        ) -> Result<(), DomainError> {
            Ok(())
        }
    }

    let queue = Arc::new(RetryTrackingQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());

    // Store an empty MergeInput (no scenes) as the preview payload.
    let input = MergeInput {
        schedule: ShootingSchedule::default(),
        scenes: Vec::new(),
    };
    let payload = serde_json::to_vec(&input).unwrap();
    // The queue returns a job with preview_handle="test-preview", so store
    // the payload under that exact handle.
    previews
        .put_raw_for_test("test-preview".to_owned(), payload)
        .await;

    let worker = QueueMergeWorker {
        queue: queue.clone(),
        previews: previews.clone(),
    };

    let result = worker.run_once("test-worker").await;
    // run_once propagates the Conflict error but also marks it failed
    // (non-retryable) before returning.
    assert!(result.is_err());

    // Verify mark_failed was called with retryable=false (non-retryable)
    let state = queue.state.lock().unwrap();
    assert_eq!(state.failed_retryable.len(), 1);
    assert!(
        !state.failed_retryable[0],
        "empty MergeInput Conflict must be non-retryable"
    );
}

/// Issue #295: the merge worker's success path must record telemetry with
/// the schedule document kind and an explicit `NotApplied` apply state —
/// not the `Default` of deleted struct fields.
#[tokio::test]
async fn merge_worker_success_records_telemetry() {
    use super::QueueMergeWorker;
    use breakdown_core::ai::MergeInput;
    use breakdown_core::scene::views::SceneView;
    use breakdown_core::shared::{AggregateVersion, EpisodeId};
    use chrono::TimeZone;

    /// Wraps the in-memory store and guarantees a ≥ 2 ms delay inside the
    /// worker's measured latency window (tokio timers never fire early, so
    /// the lower bound is deterministic — not a wall-clock-jitter gate).
    struct SlowPutStore {
        inner: Arc<MemoryAiPreviewStore>,
    }

    #[async_trait]
    impl AiPreviewStore for SlowPutStore {
        async fn put(&self, id: AiImportJobId, payload: Vec<u8>) -> Result<String, DomainError> {
            tokio::time::sleep(std::time::Duration::from_millis(2)).await;
            self.inner.put(id, payload).await
        }

        async fn get(&self, handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
            self.inner.get(handle).await
        }

        async fn delete(&self, handle: &str) -> Result<(), DomainError> {
            self.inner.delete(handle).await
        }
    }

    /// Capture queue: claims one fixed Schedule job and records telemetry.
    struct MergeCaptureQueue {
        job: AiImportJob,
        claimed: AtomicUsize,
        telemetry: Arc<Mutex<Vec<Telemetry>>>,
        succeeded: Arc<Mutex<Vec<AiImportJobId>>>,
    }

    #[async_trait]
    impl AiImportQueue for MergeCaptureQueue {
        async fn enqueue(
            &self,
            _request: AiImportEnqueueRequest,
        ) -> Result<AiImportEnqueueResult, DomainError> {
            unimplemented!("not used by this test")
        }
        async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
            unimplemented!("not used by this test")
        }
        async fn claim_next_kind(
            &self,
            _worker_id: &str,
            _kind: DocumentKind,
        ) -> Result<Option<AiImportJob>, DomainError> {
            if self.claimed.fetch_add(1, Ordering::SeqCst) == 0 {
                Ok(Some(self.job.clone()))
            } else {
                Ok(None)
            }
        }
        async fn get(&self, _id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
            unimplemented!("not used by this test")
        }
        async fn mark_running(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
        ) -> Result<(), DomainError> {
            Ok(())
        }
        async fn mark_succeeded(
            &self,
            id: AiImportJobId,
            _worker_id: &str,
            _preview_handle: &str,
        ) -> Result<(), DomainError> {
            self.succeeded.lock().unwrap().push(id);
            Ok(())
        }
        async fn mark_failed(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
            _error_summary: &str,
            _retryable: bool,
        ) -> Result<(), DomainError> {
            unimplemented!("the success path must not fail")
        }
        async fn record_worker_telemetry(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
            telemetry: Telemetry,
        ) -> Result<(), DomainError> {
            self.telemetry.lock().unwrap().push(telemetry);
            Ok(())
        }
        async fn record_telemetry(
            &self,
            _id: AiImportJobId,
            telemetry: Telemetry,
        ) -> Result<(), DomainError> {
            self.telemetry.lock().unwrap().push(telemetry);
            Ok(())
        }
    }

    fn scene(number: u32) -> SceneView {
        SceneView {
            id: Uuid::now_v7(),
            episode_id: EpisodeId::new(),
            scene_number: Some(number),
            location: None,
            mood: None,
            is_schedule_set: false,
            summary: None,
            script_day: None,
            shooting_day_ids: Vec::new(),
            assigned_characters: Vec::new(),
            version: AggregateVersion::INITIAL,
            updated_at: Utc.timestamp_opt(0, 0).single().unwrap(),
        }
    }

    let inner = Arc::new(MemoryAiPreviewStore::default());
    let input = MergeInput {
        schedule: ShootingSchedule {
            block_id: None,
            rows: vec![ShootingScheduleRow {
                row_ref: "row-1".to_owned(),
                scene_number: Some(1),
                ..Default::default()
            }],
        },
        scenes: vec![scene(1)],
    };
    inner
        .put_raw_for_test(
            "merge-success-preview".to_owned(),
            serde_json::to_vec(&input).unwrap(),
        )
        .await;

    let job = AiImportJob {
        id: AiImportJobId::new(),
        user_id: UserId::from_sub("merge-telemetry-user"),
        document_kind: DocumentKind::Schedule,
        source_format: SourceFormat::Csv,
        block_id: None,
        dedup_key: "merge-telemetry".to_owned(),
        document_digest: "digest".to_owned(),
        source_handle: "source".to_owned(),
        status: JobStatus::Running,
        preview_handle: Some("merge-success-preview".to_owned()),
        last_error: None,
        retries: 0,
        max_retries: 3,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };
    let queue = Arc::new(MergeCaptureQueue {
        job: job.clone(),
        claimed: AtomicUsize::new(0),
        telemetry: Arc::new(Mutex::new(Vec::new())),
        succeeded: Arc::new(Mutex::new(Vec::new())),
    });

    let worker = QueueMergeWorker {
        queue: queue.clone(),
        previews: Arc::new(SlowPutStore { inner }),
    };

    let result = worker.run_once("test-worker").await.unwrap();
    assert!(result, "the success path must report progress");
    assert_eq!(*queue.succeeded.lock().unwrap(), vec![job.id]);

    let telemetry = queue.telemetry.lock().unwrap();
    assert_eq!(telemetry.len(), 1, "merge must record telemetry once");
    assert_eq!(
        telemetry[0].doc_kind,
        Some(DocumentKind::Schedule),
        "merge telemetry must carry the schedule document kind"
    );
    assert_eq!(
        telemetry[0].apply_state,
        TelemetryApplyState::NotApplied,
        "a preview-only merge is explicitly NotApplied"
    );
    // A merge is a pure transform: no provider/model is recorded.
    assert_eq!(telemetry[0].provider, None);
    assert_eq!(telemetry[0].model, None);
    // The SlowPutStore sleeps ≥ 2 ms inside the measured window, so a
    // recorded latency is guaranteed ≥ 2 — a deleted field would be 0.
    assert!(
        telemetry[0].latency_total >= 2,
        "latency_total must be recorded, got {}",
        telemetry[0].latency_total
    );
}

#[test]
fn telemetry_serialization_is_content_free() {
    let telemetry = Telemetry {
        doc_kind: Some(DocumentKind::Script),
        chunk_count: 2,
        tokens_in: 10,
        tokens_out: 20,
        apply_state: TelemetryApplyState::Applied {
            accept_as_is: true,
            edit_distance: 0,
        },
        ..Telemetry::default()
    };
    let serialized = serde_json::to_string(&telemetry).expect("telemetry is serializable in test");
    assert!(!serialized.contains("script text"));
    assert!(!serialized.contains("costume description"));
    // Issue #171: the apply-state discriminator is explicit, not a bare 0.
    assert!(serialized.contains("\"applied\""));
}

#[test]
fn feature_flag_parser_is_off_for_unrecognised_values() {
    assert!(!AiImportFeature::from_enabled_value("maybe").enabled);
    assert!(AiImportFeature::from_enabled_value("true").enabled);
    assert_eq!(AiImportBounds::default().max_chunks_per_script, 128);
}

#[derive(Clone, Default)]
struct FakeQueue {
    state: Arc<Mutex<FakeQueueState>>,
}

#[derive(Default)]
struct FakeQueueState {
    succeeded: Vec<AiImportJobId>,
    failed: Vec<AiImportJobId>,
    telemetry: Vec<Telemetry>,
}

#[async_trait]
impl AiImportQueue for FakeQueue {
    async fn enqueue(
        &self,
        request: AiImportEnqueueRequest,
    ) -> Result<AiImportEnqueueResult, DomainError> {
        Ok(AiImportEnqueueResult::Enqueued(request.id))
    }

    async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn claim_next_kind(
        &self,
        _worker_id: &str,
        _kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn get(&self, _id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn mark_running(&self, _id: AiImportJobId, _worker_id: &str) -> Result<(), DomainError> {
        Ok(())
    }

    async fn mark_succeeded(
        &self,
        id: AiImportJobId,
        _worker_id: &str,
        _preview_handle: &str,
    ) -> Result<(), DomainError> {
        self.state.lock().unwrap().succeeded.push(id);
        Ok(())
    }

    async fn mark_failed(
        &self,
        id: AiImportJobId,
        _worker_id: &str,
        _error_summary: &str,
        _retryable: bool,
    ) -> Result<(), DomainError> {
        self.state.lock().unwrap().failed.push(id);
        Ok(())
    }

    async fn record_worker_telemetry(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        // Same sink as the unfenced write: the existing telemetry assertions
        // are about the recorded values, not about which port carried them.
        self.state.lock().unwrap().telemetry.push(telemetry);
        Ok(())
    }

    async fn record_telemetry(
        &self,
        _id: AiImportJobId,
        telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        self.state.lock().unwrap().telemetry.push(telemetry);
        Ok(())
    }
}

#[derive(Clone, Default)]
struct FakeLlmClient;

#[async_trait]
impl LlmClient for FakeLlmClient {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<ScriptContext, DomainError> {
        // Issue #295: guarantee the latency window measured by the worker is
        // strictly > 0 ms so telemetry assertions can deterministically
        // distinguish a recorded `latency_total` from the `Default` (0).
        // tokio timers never fire early, so the lower bound is guaranteed —
        // this is not a wall-clock-jitter gate (AGENTS.md §4).
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        Ok(ScriptContext {
            title: Some("fixture".to_owned()),
            scenes: vec![DraftScene {
                draft_ref: "fixture-scene".to_owned(),
                scene_number: Some(1),
                ..Default::default()
            }],
            uncertainties: Vec::new(),
        })
    }
}

fn script_job(id: AiImportJobId) -> AiImportJob {
    AiImportJob {
        id,
        user_id: UserId::from_sub("ai-test-user"),
        document_kind: DocumentKind::Script,
        source_format: SourceFormat::Pdf,
        block_id: None,
        dedup_key: "fixture".to_owned(),
        document_digest: "digest".to_owned(),
        source_handle: "source".to_owned(),
        status: JobStatus::Running,
        preview_handle: None,
        last_error: None,
        retries: 0,
        max_retries: 3,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    }
}

fn script_worker(
    queue: Arc<FakeQueue>,
    previews: Arc<MemoryAiPreviewStore>,
    max_chunks: u32,
) -> ScriptImportWorker<FakeQueue, FakeLlmClient> {
    ScriptImportWorker {
        queue,
        client: Arc::new(FakeLlmClient),
        previews: previews as Arc<dyn AiPreviewStore>,
        extractor: super::PdfTextExtractor::new(1024 * 1024, std::time::Duration::from_secs(30)),
        provider: LlmProvider::Neuralwatt,
        model: "deepseek-v4-flash".to_owned(),
        prompt: "fixture prompt".to_owned(),
        bounds: AiImportBounds {
            max_chunks_per_script: max_chunks,
            ..AiImportBounds::default()
        },
    }
}

/// LLM client that records the `source_text` of every schedule extraction
/// request and returns a fixed schedule, so worker tests can prove the LLM
/// path was taken — and with which text — without a network call.
#[derive(Clone, Default)]
struct RecordingScheduleClient {
    seen: Arc<std::sync::Mutex<Vec<String>>>,
}

#[async_trait]
impl LlmClient for RecordingScheduleClient {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<ScriptContext, DomainError> {
        Err(DomainError::validation(
            "RecordingScheduleClient only extracts schedules",
        ))
    }

    async fn extract_schedule(
        &self,
        request: LlmChatRequest,
    ) -> Result<ShootingSchedule, DomainError> {
        // Issue #295: guaranteed > 0 ms latency window (see FakeLlmClient).
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        self.seen.lock().unwrap().push(request.source_text);
        Ok(ShootingSchedule {
            block_id: None,
            rows: vec![ShootingScheduleRow {
                row_ref: "llm-0".to_owned(),
                scene_number: Some(1),
                shooting_day_label: Some("T1".to_owned()),
                date: None,
                location: None,
                order: None,
            }],
        })
    }
}

/// A schedule job carrying the given declared source format.
fn schedule_job(format: SourceFormat) -> AiImportJob {
    AiImportJob {
        id: AiImportJobId::new(),
        user_id: UserId::from_sub("ai-schedule-test-user"),
        document_kind: DocumentKind::Schedule,
        source_format: format,
        block_id: None,
        dedup_key: "schedule-fixture".to_owned(),
        document_digest: "digest".to_owned(),
        source_handle: "source".to_owned(),
        status: JobStatus::Running,
        preview_handle: None,
        last_error: None,
        retries: 0,
        max_retries: 3,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    }
}

fn schedule_worker(
    queue: Arc<FakeQueue>,
    previews: Arc<MemoryAiPreviewStore>,
    client: Arc<RecordingScheduleClient>,
) -> ScheduleImportWorker<FakeQueue, RecordingScheduleClient> {
    ScheduleImportWorker {
        queue,
        client,
        previews: previews as Arc<dyn AiPreviewStore>,
        extractor: super::PdfTextExtractor::new(1024 * 1024, std::time::Duration::from_secs(30)),
        provider: LlmProvider::Neuralwatt,
        model: "deepseek-v4-flash".to_owned(),
        prompt: "fixture prompt".to_owned(),
        bounds: AiImportBounds::default(),
    }
}

/// Issue #221: a CSV job must stay on the native parser — the LLM must never
/// be reached, and the preview must be produced from the CSV rows.
#[tokio::test]
async fn schedule_worker_parses_csv_natively_without_the_llm() {
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let client = Arc::new(RecordingScheduleClient::default());
    let worker = schedule_worker(Arc::clone(&queue), Arc::clone(&previews), client.clone());
    let job = schedule_job(SourceFormat::Csv);

    let handle = worker
        .process(
            &job,
            "test-worker",
            b"scene_number,shooting_day_label\n1,T1\n".as_slice(),
        )
        .await
        .expect("CSV must parse natively");

    assert!(
        client.seen.lock().unwrap().is_empty(),
        "the LLM must not be reached for a CSV job"
    );
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ShootingSchedule = serde_json::from_slice(&payload).unwrap();
    assert_eq!(preview.rows.len(), 1);
    assert_eq!(
        queue.state.lock().unwrap().succeeded,
        vec![job.id],
        "the job must be marked succeeded"
    );
    let telemetry = &queue.state.lock().unwrap().telemetry[0];
    assert!(
        telemetry.provider.is_none(),
        "native CSV runs record no provider"
    );
}

/// Issue #221: a plain-text job is routed through the LLM extraction path
/// with the raw document text.
#[tokio::test]
async fn schedule_worker_routes_plain_text_through_the_llm() {
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let client = Arc::new(RecordingScheduleClient::default());
    let worker = schedule_worker(Arc::clone(&queue), Arc::clone(&previews), client.clone());
    let job = schedule_job(SourceFormat::PlainText);

    let handle = worker
        .process(
            &job,
            "test-worker",
            b"T1 - scene 1: kitchen\nT2 - scene 2: park\n".as_slice(),
        )
        .await
        .expect("plain text must be routed through the LLM");

    let seen = client.seen.lock().unwrap().clone();
    assert_eq!(seen.len(), 1, "the LLM must be called exactly once");
    assert!(
        seen[0].contains("kitchen"),
        "the LLM must receive the document text, got: {}",
        seen[0]
    );
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ShootingSchedule = serde_json::from_slice(&payload).unwrap();
    assert_eq!(preview.rows.len(), 1);
    let telemetry = &queue.state.lock().unwrap().telemetry[0];
    assert_eq!(
        telemetry.provider,
        Some(LlmProvider::Neuralwatt),
        "an LLM extraction records the provider"
    );
    // Issue #295: model/kind/latency/apply-state must be recorded, not the
    // `Default` of a deleted struct field.
    assert_eq!(telemetry.model.as_deref(), Some("deepseek-v4-flash"));
    assert_eq!(telemetry.doc_kind, Some(DocumentKind::Schedule));
    // RecordingScheduleClient sleeps ≥ 2 ms inside the measured window, so a
    // recorded latency is guaranteed ≥ 2 — a deleted field would be 0.
    assert!(
        telemetry.latency_total >= 2,
        "latency_total must be recorded, got {}",
        telemetry.latency_total
    );
    assert_eq!(
        telemetry.apply_state,
        TelemetryApplyState::NotApplied,
        "a preview-only schedule run is explicitly NotApplied"
    );
}

/// Issue #221: a PDF job is extracted to text first (same bounded
/// `pdftotext` adapter as the script worker) and then routed through the LLM.
#[tokio::test]
async fn schedule_worker_routes_pdf_through_the_llm() {
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let client = Arc::new(RecordingScheduleClient::default());
    let worker = schedule_worker(Arc::clone(&queue), Arc::clone(&previews), client.clone());
    let job = schedule_job(SourceFormat::Pdf);

    let handle = worker
        .process(&job, "test-worker", &tiny_script_pdf())
        .await
        .expect("a PDF schedule must be extracted and routed through the LLM");

    let seen = client.seen.lock().unwrap().clone();
    assert_eq!(seen.len(), 1, "the LLM must be called exactly once");
    assert!(
        !seen[0].trim().is_empty(),
        "the extracted PDF text must reach the LLM, got: {:?}",
        seen[0]
    );
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ShootingSchedule = serde_json::from_slice(&payload).unwrap();
    assert_eq!(preview.rows.len(), 1);
}

#[tokio::test]
async fn script_worker_assembles_preview_and_telemetry() {
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let worker = script_worker(Arc::clone(&queue), Arc::clone(&previews), 4);
    let job = script_job(AiImportJobId::new());
    let handle = worker
        .process_text(
            &job,
            "test-worker",
            "1. INT. KITCHEN - DAY\nA\n2. EXT. PARK - NIGHT\nB",
        )
        .await
        .unwrap();
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ScriptContext = serde_json::from_slice(&payload).unwrap();
    assert_eq!(preview.scenes.len(), 2);
    assert_eq!(preview.title.as_deref(), Some("fixture"));
    let state = queue.state.lock().unwrap();
    assert_eq!(state.succeeded, vec![job.id]);
    assert_eq!(state.telemetry.len(), 1);
    assert_eq!(state.telemetry[0].chunk_count, 2);
    // Issue #295: the worker must record its provider/model/kind — not the
    // `Default` of a deleted struct field.
    assert_eq!(state.telemetry[0].provider, Some(LlmProvider::Neuralwatt));
    assert_eq!(
        state.telemetry[0].model.as_deref(),
        Some("deepseek-v4-flash")
    );
    assert_eq!(state.telemetry[0].doc_kind, Some(DocumentKind::Script));
    // The FakeLlmClient sleeps ≥ 2 ms per chunk inside the measured window,
    // so a recorded latency is guaranteed ≥ 2 — a deleted field would be 0.
    assert!(
        state.telemetry[0].latency_total >= 2,
        "latency_total must be recorded, got {}",
        state.telemetry[0].latency_total
    );
    // Issue #171: a job that only reached preview is explicitly NotApplied
    // (edit_distance NULL), never a misleading zero.
    assert_eq!(
        state.telemetry[0].apply_state,
        TelemetryApplyState::NotApplied
    );
    assert_eq!(state.telemetry[0].apply_state.edit_distance(), None);
    assert_eq!(state.telemetry[0].apply_state.accept_as_is(), None);
}

#[tokio::test]
async fn oversized_script_transitions_to_failed_without_llm_calls() {
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let worker = script_worker(Arc::clone(&queue), Arc::clone(&previews), 1);
    let job = script_job(AiImportJobId::new());
    let result = worker
        .process_text(
            &job,
            "test-worker",
            "1. INT. KITCHEN - DAY\nA\n2. EXT. PARK - NIGHT\nB",
        )
        .await;
    assert!(matches!(result, Err(DomainError::Validation { .. })));
    let state = queue.state.lock().unwrap();
    assert_eq!(state.failed, vec![job.id]);
    assert!(state.succeeded.is_empty());
    assert!(state.telemetry.is_empty());
}

#[derive(Clone, Default)]
struct FakeSceneCommands {
    created: Arc<Mutex<Vec<Uuid>>>,
    updated: Arc<Mutex<Vec<Uuid>>>,
    scheduled: Arc<Mutex<Vec<(Uuid, breakdown_core::shared::ShootingDayId)>>>,
}

impl breakdown_core::scene::ports::SceneCommands for FakeSceneCommands {
    async fn create(
        &self,
        _actor: UserId,
        command: breakdown_core::scene::commands::CreateScene,
    ) -> Result<(Uuid, breakdown_core::shared::AggregateVersion), DomainError> {
        self.created.lock().unwrap().push(command.id);
        Ok((
            command.id,
            breakdown_core::shared::AggregateVersion::INITIAL,
        ))
    }

    async fn update_details(
        &self,
        _actor: UserId,
        command: breakdown_core::scene::commands::UpdateSceneDetails,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        self.updated.lock().unwrap().push(command.id);
        Ok(command.version.next())
    }

    async fn assign_character(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene::commands::AssignCharacter,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }

    async fn remove_character(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene::commands::RemoveCharacter,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }

    async fn schedule_on_shooting_day(
        &self,
        _actor: UserId,
        command: breakdown_core::scene::commands::ScheduleSceneOnShootingDay,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        let mut scheduled = self.scheduled.lock().unwrap();
        let pair = (command.id, command.shooting_day_id);
        // Faithful to `SceneAggregate::is_state_idempotent`: re-scheduling an
        // already-linked day yields `ExecuteResult::Idempotent`, which the
        // adapter maps to the *unchanged* current version.
        if scheduled.contains(&pair) {
            return Ok(command.version);
        }
        scheduled.push(pair);
        Ok(command.version.next())
    }

    async fn unschedule_from_shooting_day(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene::commands::UnscheduleSceneFromShootingDay,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
}

#[derive(Clone, Default)]
struct FakeMappings {
    values: Arc<Mutex<HashMap<(AiImportJobId, String), AiImportMapping>>>,
    /// 1-based ordinal of an `insert` call that must fail once — simulating a
    /// crash between a successful command and the mapping write (issue #179).
    fail_insert_at: Arc<Mutex<Option<usize>>>,
    insert_calls: Arc<AtomicUsize>,
    reserved: Arc<Mutex<Vec<AiImportMapping>>>,
}

impl FakeMappings {
    /// Arm a one-shot failure on the `nth` (1-based) `insert` call.
    fn fail_nth_insert(&self, nth: usize) {
        *self.fail_insert_at.lock().unwrap() = Some(nth);
    }

    /// Reservations in call order (the confirm path uses `insert`).
    fn reservations(&self) -> Vec<AiImportMapping> {
        self.reserved.lock().unwrap().clone()
    }

    /// Remove the mapping for `(preview_id, draft_ref)` — simulating a lost
    /// reservation row (e.g. a rollback that dropped the reservation but the
    /// command had already appended). The core crash window of issue #182.
    fn remove(&self, preview_id: AiImportJobId, draft_ref: &str) {
        self.values
            .lock()
            .unwrap()
            .remove(&(preview_id, draft_ref.to_owned()));
    }
}

#[async_trait]
impl AiImportMappingRepository for FakeMappings {
    async fn find(
        &self,
        preview_id: AiImportJobId,
        draft_ref: &str,
    ) -> Result<Option<AiImportMapping>, DomainError> {
        Ok(self
            .values
            .lock()
            .unwrap()
            .get(&(preview_id, draft_ref.to_owned()))
            .cloned())
    }

    async fn reserve(&self, mapping: AiImportMapping) -> Result<AiImportMapping, DomainError> {
        self.reserved.lock().unwrap().push(mapping.clone());
        // Mirrors the production insert-if-absent: an existing row (reserved or
        // confirmed) wins, so retries converge on one aggregate id.
        Ok(self
            .values
            .lock()
            .unwrap()
            .entry((mapping.preview_id, mapping.draft_ref.clone()))
            .or_insert(mapping)
            .clone())
    }

    async fn insert(&self, mapping: AiImportMapping) -> Result<(), DomainError> {
        let call = self.insert_calls.fetch_add(1, Ordering::SeqCst) + 1;
        {
            let mut fail = self.fail_insert_at.lock().unwrap();
            if *fail == Some(call) {
                *fail = None;
                return Err(DomainError::service_unavailable(
                    "simulated mapping write failure",
                ));
            }
        }
        let mut values = self.values.lock().unwrap();
        let entry = values
            .entry((mapping.preview_id, mapping.draft_ref.clone()))
            .or_insert_with(|| mapping.clone());
        // Mirrors the production upsert's monotonic version guard.
        if entry.aggregate_version < mapping.aggregate_version {
            *entry = mapping;
        }
        Ok(())
    }

    async fn list_by_preview(
        &self,
        preview_id: AiImportJobId,
    ) -> Result<Vec<AiImportMapping>, DomainError> {
        Ok(self
            .values
            .lock()
            .unwrap()
            .values()
            .filter(|mapping| mapping.preview_id == preview_id)
            .cloned()
            .collect())
    }
}

#[derive(Clone, Default)]
struct FakeShootingDayCommands {
    created: Arc<Mutex<Vec<breakdown_core::shared::ShootingDayId>>>,
}

impl breakdown_core::shooting_day::ports::ShootingDayCommands for FakeShootingDayCommands {
    async fn create(
        &self,
        _actor: UserId,
        command: breakdown_core::shooting_day::commands::CreateShootingDay,
    ) -> Result<
        (
            breakdown_core::shared::ShootingDayId,
            breakdown_core::shared::AggregateVersion,
        ),
        DomainError,
    > {
        let mut created = self.created.lock().unwrap();
        // Faithful to `ShootingDayCommandsImpl`, which dispatches with
        // `ExpectedVersion::Empty`: a second create on the same (already
        // written) stream cannot append and reports the current version.
        if created.contains(&command.id) {
            return Err(DomainError::VersionConflict {
                expected: breakdown_core::shared::AggregateVersion(0),
                current: breakdown_core::shared::AggregateVersion::INITIAL,
            });
        }
        created.push(command.id);
        Ok((
            command.id,
            breakdown_core::shared::AggregateVersion::INITIAL,
        ))
    }

    async fn rename(
        &self,
        _actor: UserId,
        _command: breakdown_core::shooting_day::commands::RenameShootingDay,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }

    async fn reschedule(
        &self,
        _actor: UserId,
        _command: breakdown_core::shooting_day::commands::RescheduleShootingDay,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }

    async fn reorder(
        &self,
        _actor: UserId,
        _command: breakdown_core::shooting_day::commands::ReorderShootingDay,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }

    async fn archive(
        &self,
        _actor: UserId,
        _command: breakdown_core::shooting_day::commands::ArchiveShootingDay,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }

    async fn wrap(
        &self,
        _actor: UserId,
        _command: breakdown_core::shooting_day::commands::WrapShootingDay,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
}

#[derive(Clone, Default)]
struct FakeSceneShootCommands {
    planned: Arc<Mutex<Vec<breakdown_core::shared::SceneShootId>>>,
    /// Reject `plan` with a `VersionConflict` whose `current` is 0 — an empty
    /// stream, i.e. *not* a recoverable "we already appended" signal.
    zero_version_conflict: Arc<Mutex<bool>>,
}

impl FakeSceneShootCommands {
    fn fail_plan_with_zero_version_conflict(&self) {
        *self.zero_version_conflict.lock().unwrap() = true;
    }
}

impl breakdown_core::scene_shoot::ports::SceneShootCommands for FakeSceneShootCommands {
    async fn plan(
        &self,
        _actor: UserId,
        command: breakdown_core::scene_shoot::commands::PlanSceneShoot,
    ) -> Result<
        (
            breakdown_core::shared::SceneShootId,
            breakdown_core::shared::AggregateVersion,
        ),
        DomainError,
    > {
        if *self.zero_version_conflict.lock().unwrap() {
            return Err(DomainError::VersionConflict {
                expected: breakdown_core::shared::AggregateVersion(0),
                current: breakdown_core::shared::AggregateVersion(0),
            });
        }
        let mut planned = self.planned.lock().unwrap();
        // Faithful to `SceneShootCommandsImpl` (`ExpectedVersion::Empty`): a
        // re-plan onto an already-written stream reports the current version
        // rather than appending a duplicate `SceneShootPlanned`.
        if planned.contains(&command.id) {
            return Err(DomainError::VersionConflict {
                expected: breakdown_core::shared::AggregateVersion(0),
                current: breakdown_core::shared::AggregateVersion::INITIAL,
            });
        }
        planned.push(command.id);
        Ok((
            command.id,
            breakdown_core::shared::AggregateVersion::INITIAL,
        ))
    }

    async fn replan(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::ReplanSceneShoot,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn start(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::StartSceneShoot,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn set_actual_order(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::SetActualOrder,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn finish(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::FinishSceneShoot,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn skip(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::SkipSceneShoot,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn add_note(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::AddSceneShootNote,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn update_note(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::UpdateSceneShootNote,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn remove_note(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::RemoveSceneShootNote,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn link_continuity_photo(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::LinkContinuityPhoto,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn unlink_continuity_photo(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene_shoot::commands::UnlinkContinuityPhoto,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
}

/// Shared one-scene / one-schedule-row fixture for the schedule-apply tests.
struct ScheduleApplyFixture {
    scene_commands: Arc<FakeSceneCommands>,
    shooting_days: Arc<FakeShootingDayCommands>,
    scene_shoots: Arc<FakeSceneShootCommands>,
    mappings: Arc<FakeMappings>,
    preview: breakdown_core::ai::MergedPreview,
    preview_id: AiImportJobId,
    scene_id: Uuid,
}

impl ScheduleApplyFixture {
    fn new() -> Self {
        let scene_id = Uuid::now_v7();
        let scene = breakdown_core::scene::views::SceneView {
            id: scene_id,
            episode_id: breakdown_core::shared::EpisodeId::new(),
            scene_number: Some(1),
            location: None,
            mood: None,
            is_schedule_set: false,
            summary: None,
            script_day: None,
            shooting_day_ids: Vec::new(),
            assigned_characters: Vec::new(),
            version: breakdown_core::shared::AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        };
        let schedule = breakdown_core::ai::ShootingSchedule {
            block_id: None,
            rows: vec![ShootingScheduleRow {
                row_ref: "row-1".to_owned(),
                scene_number: Some(1),
                shooting_day_label: Some("Day 1".to_owned()),
                ..ShootingScheduleRow::default()
            }],
        };
        Self {
            scene_commands: Arc::new(FakeSceneCommands::default()),
            shooting_days: Arc::new(FakeShootingDayCommands::default()),
            scene_shoots: Arc::new(FakeSceneShootCommands::default()),
            mappings: Arc::new(FakeMappings::default()),
            preview: merge_schedule_to_scenes(&schedule, &[scene]),
            preview_id: AiImportJobId::new(),
            scene_id,
        }
    }

    fn worker(
        &self,
    ) -> ScheduleApplyWorker<
        FakeSceneCommands,
        FakeShootingDayCommands,
        FakeSceneShootCommands,
        FakeMappings,
    > {
        ScheduleApplyWorker {
            scene_commands: Arc::clone(&self.scene_commands),
            shooting_day_commands: Arc::clone(&self.shooting_days),
            scene_shoot_commands: Arc::clone(&self.scene_shoots),
            mappings: Arc::clone(&self.mappings),
        }
    }

    async fn apply(&self) -> Result<super::ScheduleApplyResult, DomainError> {
        self.worker()
            .apply(ScheduleApplyRequest {
                actor: UserId::from_sub("schedule-test-user"),
                preview_id: self.preview_id,
                preview: &self.preview,
                series_id: None,
            })
            .await
    }

    fn scene_shoot_pair_key(&self) -> String {
        let day = self.shooting_days.created.lock().unwrap()[0];
        format!("scene-shoot:{}:{}", self.scene_id, day.0)
    }

    async fn mapping(&self, draft_ref: &str) -> Option<AiImportMapping> {
        self.mappings
            .find(self.preview_id, draft_ref)
            .await
            .unwrap()
    }
}

#[tokio::test]
async fn schedule_apply_creates_and_reuses_day_and_scene_shoot_mapping() {
    let fixture = ScheduleApplyFixture::new();
    fixture.apply().await.unwrap();
    fixture.apply().await.unwrap();
    assert_eq!(fixture.shooting_days.created.lock().unwrap().len(), 1);
    assert_eq!(fixture.scene_shoots.planned.lock().unwrap().len(), 1);
}

/// Issue #179 AC #1 + #2: a crash between a successful `PlanSceneShoot` and
/// the mapping write must not let the retry plan a *second* scene shoot.
#[tokio::test]
async fn schedule_apply_retry_after_a_scene_shoot_mapping_failure_plans_once() {
    let fixture = ScheduleApplyFixture::new();
    // Insert #1 is the shooting-day confirm, #2 the scene-shoot confirm. Fail
    // the latter: the `PlanSceneShoot` command has already appended by then —
    // exactly the crash window this issue is about.
    fixture.mappings.fail_nth_insert(2);

    let error = fixture
        .apply()
        .await
        .expect_err("the confirming mapping write must fail");
    assert!(matches!(error, DomainError::ServiceUnavailable { .. }));

    // The command DID append: exactly one scene shoot is planned, and the
    // mapping is left as a bare reservation.
    assert_eq!(fixture.scene_shoots.planned.lock().unwrap().len(), 1);
    let pair_key = fixture.scene_shoot_pair_key();
    let reserved = fixture
        .mapping(&pair_key)
        .await
        .expect("the reservation must survive the failed confirm");
    assert!(
        reserved.is_reserved(),
        "a failed confirm must leave the mapping reserved, got {reserved:?}"
    );
    let reserved_id = reserved.aggregate_id;

    // Retry: re-drives the reserved id, recovers the version, confirms.
    fixture.apply().await.expect("the retry must converge");

    assert_eq!(
        fixture.scene_shoots.planned.lock().unwrap().len(),
        1,
        "the retry must not plan a second scene shoot for the same pair"
    );
    assert_eq!(
        fixture.shooting_days.created.lock().unwrap().len(),
        1,
        "the retry must not create a second shooting day"
    );
    let confirmed = fixture.mapping(&pair_key).await.expect("mapping exists");
    assert!(
        !confirmed.is_reserved(),
        "the retry must confirm the mapping"
    );
    assert_eq!(
        confirmed.aggregate_id, reserved_id,
        "the retry must reuse the reserved SceneShootId"
    );
    assert_eq!(
        confirmed.aggregate_version,
        breakdown_core::shared::AggregateVersion::INITIAL,
        "the version must be recovered from the existing stream (AC #4)"
    );
}

/// Issue #179: the same crash window on the `CreateShootingDay` side.
#[tokio::test]
async fn schedule_apply_retry_after_a_day_mapping_failure_creates_one_day() {
    let fixture = ScheduleApplyFixture::new();
    // The shooting-day confirm is the first mapping insert of an apply run.
    fixture.mappings.fail_nth_insert(1);

    let error = fixture
        .apply()
        .await
        .expect_err("the day confirm must fail");
    assert!(matches!(error, DomainError::ServiceUnavailable { .. }));

    let created = fixture.shooting_days.created.lock().unwrap().clone();
    assert_eq!(created.len(), 1, "the day command DID append");
    let day_key = fixture.mappings.reservations()[0].draft_ref.clone();
    let reserved = fixture.mapping(&day_key).await.expect("reservation exists");
    assert!(reserved.is_reserved());
    assert_eq!(reserved.aggregate_id, created[0].0);

    fixture.apply().await.expect("the retry must converge");

    assert_eq!(
        fixture.shooting_days.created.lock().unwrap().len(),
        1,
        "the retry must not create a second shooting day"
    );
    assert_eq!(fixture.scene_shoots.planned.lock().unwrap().len(), 1);
    let confirmed = fixture.mapping(&day_key).await.expect("mapping exists");
    assert!(!confirmed.is_reserved());
    assert_eq!(confirmed.aggregate_id, created[0].0);
}

/// The reservation must be durable *before* the command runs — otherwise a
/// crash inside the command dispatch still loses the id.
#[tokio::test]
async fn schedule_apply_reserves_the_scene_shoot_id_before_planning() {
    let fixture = ScheduleApplyFixture::new();
    fixture.apply().await.unwrap();

    let reservations = fixture.mappings.reservations();
    let kinds: Vec<&str> = reservations
        .iter()
        .map(|mapping| mapping.aggregate_kind.as_str())
        .collect();
    assert_eq!(
        kinds,
        vec!["shooting_day", "scene_shoot"],
        "both aggregates are reserved, day first"
    );
    assert!(
        reservations.iter().all(AiImportMapping::is_reserved),
        "reservations carry the version-0 sentinel"
    );
    let planned = fixture.scene_shoots.planned.lock().unwrap();
    assert_eq!(
        reservations[1].aggregate_id, planned[0].0,
        "the planned SceneShootId is the reserved one, not a fresh uuid"
    );
}

/// A `VersionConflict` on an *empty* stream is not a recovery signal — it must
/// stay an error rather than confirming a mapping to a nonexistent aggregate.
#[tokio::test]
async fn schedule_apply_does_not_recover_a_zero_version_conflict() {
    let fixture = ScheduleApplyFixture::new();
    fixture.scene_shoots.fail_plan_with_zero_version_conflict();

    let error = fixture.apply().await.expect_err("must not be recovered");
    assert!(matches!(error, DomainError::VersionConflict { .. }));
    let pair_key = fixture.scene_shoot_pair_key();
    let mapping = fixture
        .mapping(&pair_key)
        .await
        .expect("reservation exists");
    assert!(
        mapping.is_reserved(),
        "an unrecoverable failure must leave the mapping unconfirmed"
    );
}

/// Issue #182 AC #1 + #3: a retry after the `CreateShootingDay` command
/// succeeds but its mapping write fails must not create a second shooting day.
/// With a *deterministic* id, the retry re-derives the same `ShootingDayId`
/// and the aggregate rejects the duplicate — even if the reservation row was
/// lost (the mapping projection alone cannot close this window).
#[tokio::test]
async fn schedule_apply_retry_after_day_command_success_creates_one_day() {
    let fixture = ScheduleApplyFixture::new();
    // The shooting-day confirm is the first mapping insert of an apply run.
    fixture.mappings.fail_nth_insert(1);

    let error = fixture
        .apply()
        .await
        .expect_err("the day confirm must fail");
    assert!(matches!(error, DomainError::ServiceUnavailable { .. }));

    let created = fixture.shooting_days.created.lock().unwrap().clone();
    assert_eq!(created.len(), 1, "the day command DID append");
    let day_id = created[0];
    let day_key = fixture.mappings.reservations()[0].draft_ref.clone();

    // Lose the reservation row — the mapping projection no longer knows about
    // the day. A random-id retry would create a duplicate here.
    fixture.mappings.remove(fixture.preview_id, &day_key);
    assert!(
        fixture.mapping(&day_key).await.is_none(),
        "reservation must be gone"
    );

    // Retry: deterministic id → aggregate rejects duplicate → one day.
    fixture.apply().await.expect("the retry must converge");

    assert_eq!(
        fixture.shooting_days.created.lock().unwrap().len(),
        1,
        "the retry must not create a second shooting day (AC #1)"
    );
    assert_eq!(
        fixture.shooting_days.created.lock().unwrap()[0],
        day_id,
        "the retry must converge on the SAME ShootingDayId (AC #3)"
    );
    let confirmed = fixture.mapping(&day_key).await.expect("mapping exists");
    assert!(
        !confirmed.is_reserved(),
        "the retry must confirm the mapping"
    );
    assert_eq!(confirmed.aggregate_id, day_id.0);
}

/// Issue #182 AC #2 + #3: a retry after the `PlanSceneShoot` command succeeds
/// but its mapping write fails must not create a second scene shoot. The
/// deterministic `SceneShootId` makes the aggregate itself reject the
/// duplicate — closing the window even without the reservation row.
#[tokio::test]
async fn schedule_apply_retry_after_scene_shoot_command_success_plans_once() {
    let fixture = ScheduleApplyFixture::new();
    // Insert #1 is the shooting-day confirm, #2 the scene-shoot confirm.
    fixture.mappings.fail_nth_insert(2);

    let error = fixture
        .apply()
        .await
        .expect_err("the scene-shoot confirm must fail");
    assert!(matches!(error, DomainError::ServiceUnavailable { .. }));

    assert_eq!(fixture.scene_shoots.planned.lock().unwrap().len(), 1);
    let pair_key = fixture.scene_shoot_pair_key();
    let reserved_id = fixture.mapping(&pair_key).await.unwrap().aggregate_id;

    // Lose the scene-shoot reservation row.
    fixture.mappings.remove(fixture.preview_id, &pair_key);
    assert!(fixture.mapping(&pair_key).await.is_none());

    // Retry: deterministic id → aggregate rejects duplicate → one scene shoot.
    fixture.apply().await.expect("the retry must converge");

    assert_eq!(
        fixture.scene_shoots.planned.lock().unwrap().len(),
        1,
        "the retry must not plan a second scene shoot (AC #2)"
    );
    assert_eq!(
        fixture.scene_shoots.planned.lock().unwrap()[0].0,
        reserved_id,
        "the retry must converge on the SAME SceneShootId (AC #3)"
    );
    let confirmed = fixture.mapping(&pair_key).await.expect("mapping exists");
    assert!(
        !confirmed.is_reserved(),
        "the retry must confirm the mapping"
    );
    assert_eq!(confirmed.aggregate_id, reserved_id);
}

/// Issue #182 AC #5: the deterministic id derivation MUST be stable — the
/// same `(preview_id, draft_ref)` always yields the same id, and distinct
/// inputs yield distinct ids. Without stability, retries could diverge.
///
/// This test removes ALL mapping rows after the first apply, so the second
/// apply cannot rely on the mapping projection — it must re-derive the SAME
/// ids purely from `(preview_id, draft_ref)`. A random-id implementation
/// fails this: the second apply derives fresh random ids that differ from
/// the first.
#[tokio::test]
async fn schedule_apply_ids_are_deterministic_and_distinct() {
    let fixture = ScheduleApplyFixture::new();
    fixture.apply().await.unwrap();

    let day_key = fixture.mappings.reservations()[0].draft_ref.clone();
    let pair_key = fixture.scene_shoot_pair_key();

    let day_id_first = fixture.mapping(&day_key).await.unwrap().aggregate_id;
    let shoot_id_first = fixture.mapping(&pair_key).await.unwrap().aggregate_id;

    // The two ids (different draft_refs) must differ.
    assert_ne!(
        day_id_first, shoot_id_first,
        "day and scene-shoot ids must not collide"
    );

    // Lose ALL mapping rows — the projection no longer knows the ids.
    fixture.mappings.remove(fixture.preview_id, &day_key);
    fixture.mappings.remove(fixture.preview_id, &pair_key);

    // Second apply must re-derive the SAME ids without the projection.
    fixture.apply().await.unwrap();
    assert_eq!(
        fixture.mapping(&day_key).await.unwrap().aggregate_id,
        day_id_first,
        "ShootingDayId must be stable across applies without the projection"
    );
    assert_eq!(
        fixture.mapping(&pair_key).await.unwrap().aggregate_id,
        shoot_id_first,
        "SceneShootId must be stable across applies without the projection"
    );
}

#[tokio::test]
async fn apply_retry_updates_mapping_without_creating_duplicate_scenes() {
    let queue = Arc::new(FakeQueue::default());
    let mappings = Arc::new(FakeMappings::default());
    let commands = Arc::new(FakeSceneCommands::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let import_worker = script_worker(Arc::clone(&queue), Arc::clone(&previews), 4);
    let job = script_job(AiImportJobId::new());
    let handle = import_worker
        .process_text(&job, "test-worker", "1. INT. KITCHEN - DAY\nA")
        .await
        .unwrap();
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ScriptContext = serde_json::from_slice(&payload).unwrap();
    let worker = ApplyWorker {
        scene_commands: Arc::clone(&commands),
        mappings: Arc::clone(&mappings),
        queue: Arc::clone(&queue),
    };
    let decision = ApplyMapping {
        draft_ref: "fixture-scene".to_owned(),
        decision: breakdown_core::ai::ApplyMappingDecision::Create,
    };
    worker
        .apply_script(ApplyScriptRequest {
            actor: UserId::from_sub("ai-test-user"),
            preview_id: job.id,
            preview: &preview,
            decisions: &[decision],
            episode_id: breakdown_core::shared::EpisodeId::new(),
            series_id: None,
            telemetry: Some(Telemetry {
                doc_kind: Some(DocumentKind::Script),
                // Zero-edit applied outcome is a valid edit_distance of 0 —
                // distinct from the NotApplied (NULL) contract.
                apply_state: TelemetryApplyState::Applied {
                    accept_as_is: true,
                    edit_distance: 0,
                },
                ..Telemetry::default()
            }),
        })
        .await
        .unwrap();
    worker
        .apply_script(ApplyScriptRequest {
            actor: UserId::from_sub("ai-test-user"),
            preview_id: job.id,
            preview: &preview,
            decisions: &[],
            episode_id: breakdown_core::shared::EpisodeId::new(),
            series_id: None,
            telemetry: None,
        })
        .await
        .unwrap();
    assert_eq!(commands.created.lock().unwrap().len(), 1);
    assert_eq!(commands.updated.lock().unwrap().len(), 1);
    let state = queue.state.lock().unwrap();
    assert!(state.telemetry.iter().any(|telemetry| telemetry.apply_state
        == TelemetryApplyState::Applied {
            accept_as_is: true,
            edit_distance: 0,
        }));
}

fn tiny_script_pdf() -> Vec<u8> {
    let mut pdf = b"%PDF-1.4\n".to_vec();
    let mut offsets = Vec::new();
    let mut add_object = |object: String| {
        offsets.push(pdf.len());
        pdf.extend_from_slice(object.as_bytes());
    };
    add_object("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n".to_owned());
    add_object("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n".to_owned());
    add_object("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n".to_owned());
    add_object(
        "4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n".to_owned(),
    );
    let stream = "BT /F1 12 Tf 72 720 Td (1. INT. KITCHEN - DAY) Tj ET";
    add_object(format!(
        "5 0 obj\n<< /Length {} >>\nstream\n{}\nendstream\nendobj\n",
        stream.len(),
        stream
    ));
    let xref_offset = pdf.len();
    pdf.extend_from_slice(b"xref\n0 6\n0000000000 65535 f \n");
    for offset in offsets {
        pdf.extend_from_slice(format!("{offset:010} 00000 n \n").as_bytes());
    }
    pdf.extend_from_slice(
        format!("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n").as_bytes(),
    );
    pdf
}

/// Prove the extractor is safe under concurrent use: each call spawns its own
/// pdftotext subprocess and drains stdin/stdout concurrently, so parallel
/// extractions must all complete without deadlock or shared-state corruption.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn pdf_extractor_handles_concurrent_use_without_deadlock() {
    let extractor = Arc::new(super::PdfTextExtractor::new(
        1024 * 1024,
        std::time::Duration::from_secs(30),
    ));
    let pdf = tiny_script_pdf();
    let mut handles = Vec::new();
    for _ in 0..8 {
        let extractor = Arc::clone(&extractor);
        let pdf = pdf.clone();
        handles.push(tokio::spawn(async move { extractor.extract(&pdf).await }));
    }
    for handle in handles {
        let text = handle
            .await
            .expect("extraction task panicked")
            .expect("extraction failed");
        assert!(
            !text.is_empty(),
            "concurrent extraction returned empty text"
        );
    }
}

/// The oversized-output path must kill the child and report the bound error
/// promptly instead of letting the outer timeout fire with a misleading message.
#[tokio::test]
async fn pdf_extractor_rejects_oversized_output_with_bound_error() {
    let extractor = super::PdfTextExtractor::new(1, std::time::Duration::from_secs(30));
    let error = extractor
        .extract(&tiny_script_pdf())
        .await
        .expect_err("oversized output must be rejected");
    assert!(
        error.to_string().contains("exceeds the configured bound"),
        "unexpected error: {error}"
    );
}

#[tokio::test]
async fn script_pdf_round_trip_reaches_scene_apply() {
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let import_worker = script_worker(Arc::clone(&queue), Arc::clone(&previews), 4);
    let job = script_job(AiImportJobId::new());
    let handle = import_worker
        .process(&job, "test-worker", &tiny_script_pdf())
        .await
        .unwrap();
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ScriptContext = serde_json::from_slice(&payload).unwrap();
    assert!(!preview.scenes.is_empty());

    let commands = Arc::new(FakeSceneCommands::default());
    let mappings = Arc::new(FakeMappings::default());
    let apply_worker = ApplyWorker {
        scene_commands: Arc::clone(&commands),
        mappings,
        queue,
    };
    let decision = ApplyMapping {
        draft_ref: preview.scenes[0].draft_ref.clone(),
        decision: breakdown_core::ai::ApplyMappingDecision::Create,
    };
    apply_worker
        .apply_script(ApplyScriptRequest {
            actor: UserId::from_sub("script-round-trip"),
            preview_id: job.id,
            preview: &preview,
            decisions: &[decision],
            episode_id: breakdown_core::shared::EpisodeId::new(),
            series_id: None,
            telemetry: None,
        })
        .await
        .unwrap();
    assert_eq!(commands.created.lock().unwrap().len(), 1);
}
