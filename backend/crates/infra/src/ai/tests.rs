// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::anyhow;
use async_trait::async_trait;
use breakdown_core::ai::{
    AiImportBounds, AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId,
    AiImportMapping, AiImportMappingRepository, AiImportQueue, ApplyMapping, DecisionAnswer,
    DecisionCallOutcome, DecisionClient, DecisionRequest, DocumentKind, DraftCharacter,
    DraftEpisode, DraftOutfit, DraftScene, DraftShootingDay, EpisodeGroupPlan, EpisodeTarget,
    JobStatus, LlmCallOutcome, LlmCallUsage, LlmChatRequest, LlmClient, LlmProvider,
    OutfitDecision, PRIMARY_ORDINAL, ScriptContext, ShootingDayPlan, ShootingSchedule,
    ShootingScheduleRow, SourceFormat, Telemetry, TelemetryApplyState, UnappliedOutfitReason,
    UncertaintyKind, character_identity, character_mapping_ref, mapping_kind,
    merge_schedule_to_scenes, question_keys,
};
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::error::DomainError;
use breakdown_core::scene::events::SceneSource;
use breakdown_core::season::ports::SeasonRepository;
use breakdown_core::season::views::SeasonView;
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
    let result = merge_loaded_schedule(&schedule, &[], &std::collections::HashMap::new());
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
                progress: None,
                next_attempt_at: None,
                attempts: Vec::new(),
                max_retries: 5,
                created_at: Utc::now(),
                updated_at: Utc::now(),
                telemetry: None,
                cost: None,
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
            _error_code: Option<&str>,
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
        episode_numbers: std::collections::HashMap::new(),
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
    use breakdown_core::scene::events::SceneSource;
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
            _error_code: Option<&str>,
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
            outfit_beats: Vec::new(),
            version: AggregateVersion::INITIAL,
            updated_at: Utc.timestamp_opt(0, 0).single().unwrap(),
            source: Some(SceneSource::Manual),
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
        episode_numbers: std::collections::HashMap::new(),
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
        progress: None,
        next_attempt_at: None,
        attempts: Vec::new(),
        max_retries: 3,
        created_at: Utc::now(),
        updated_at: Utc::now(),
        telemetry: None,
        cost: None,
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
        _error_code: Option<&str>,
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
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        // Issue #295: guarantee the latency window measured by the worker is
        // strictly > 0 ms so telemetry assertions can deterministically
        // distinguish a recorded `latency_total` from the `Default` (0).
        // tokio timers never fire early, so the lower bound is guaranteed —
        // this is not a wall-clock-jitter gate (AGENTS.md §4).
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        Ok(LlmCallOutcome::new(
            ScriptContext {
                title: Some("fixture".to_owned()),
                scenes: vec![DraftScene {
                    draft_ref: "fixture-scene".to_owned(),
                    scene_number: Some(1),
                    ..Default::default()
                }],
                uncertainties: Vec::new(),
            },
            LlmCallUsage::default(),
        ))
    }
}

#[derive(Clone, Default)]
struct FakeLlmClientWithoutSceneNumber;

#[async_trait]
impl LlmClient for FakeLlmClientWithoutSceneNumber {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        Ok(LlmCallOutcome::new(
            ScriptContext {
                title: Some("fixture".to_owned()),
                scenes: vec![DraftScene {
                    draft_ref: "fixture-scene".to_owned(),
                    ..Default::default()
                }],
                uncertainties: Vec::new(),
            },
            LlmCallUsage::default(),
        ))
    }
}

/// The model carries an episode WITH a title; the document's `Ep.:` marker
/// (titleless page header) is the deterministic number authority.
#[derive(Clone, Default)]
struct FakeLlmClientWithEpisodeTitle;

#[async_trait]
impl LlmClient for FakeLlmClientWithEpisodeTitle {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        Ok(LlmCallOutcome::new(
            ScriptContext {
                title: Some("fixture".to_owned()),
                scenes: vec![DraftScene {
                    draft_ref: "fixture-scene".to_owned(),
                    episode: Some(DraftEpisode {
                        number: Some(5),
                        title: Some("Der Unfall".to_owned()),
                    }),
                    ..Default::default()
                }],
                uncertainties: Vec::new(),
            },
            LlmCallUsage::default(),
        ))
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
        progress: None,
        next_attempt_at: None,
        attempts: Vec::new(),
        max_retries: 3,
        created_at: Utc::now(),
        updated_at: Utc::now(),
        telemetry: None,
        cost: None,
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
        pricing: None,
        decision: None,
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
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        Err(DomainError::validation(
            "RecordingScheduleClient only extracts schedules",
        ))
    }

    async fn extract_schedule(
        &self,
        request: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ShootingSchedule>, DomainError> {
        // Issue #295: guaranteed > 0 ms latency window (see FakeLlmClient).
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        self.seen.lock().unwrap().push(request.source_text);
        Ok(LlmCallOutcome::new(
            ShootingSchedule {
                block_id: None,
                rows: vec![ShootingScheduleRow {
                    row_ref: "llm-0".to_owned(),
                    scene_number: Some(1),
                    episode_number: None,
                    shooting_day_label: Some("T1".to_owned()),
                    date: None,
                    location: None,
                    order: None,
                    shooting_day_score: None,
                }],
            },
            LlmCallUsage::default(),
        ))
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
        progress: None,
        next_attempt_at: None,
        attempts: Vec::new(),
        max_retries: 3,
        created_at: Utc::now(),
        updated_at: Utc::now(),
        telemetry: None,
        cost: None,
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
        pricing: None,
        decision: None,
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

/// Issue #695: the model classifies per chunk, so a document-global conflict
/// (the same figure under two cast sections with differing non-default
/// categories) is only visible after the chunk rows are merged. The fake
/// returns two rows of one figure with conflicting categories; the stored
/// preview must carry the blocking conflict uncertainty.
#[derive(Clone, Default)]
struct FakeLlmClientWithConflictingCategories;

#[async_trait]
impl LlmClient for FakeLlmClientWithConflictingCategories {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        Ok(LlmCallOutcome::new(
            ScriptContext {
                title: Some("fixture".to_owned()),
                scenes: vec![
                    DraftScene {
                        draft_ref: "guest-row".to_owned(),
                        characters: vec![DraftCharacter {
                            name: "BEN".to_owned(),
                            category: CharacterCategory::Guest,
                        }],
                        ..Default::default()
                    },
                    DraftScene {
                        draft_ref: "extra-row".to_owned(),
                        characters: vec![DraftCharacter {
                            name: "Ben".to_owned(),
                            category: CharacterCategory::Extra,
                        }],
                        ..Default::default()
                    },
                ],
                uncertainties: Vec::new(),
            },
            LlmCallUsage::default(),
        ))
    }
}

#[tokio::test]
async fn script_worker_surfaces_document_global_category_conflicts() {
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let worker = ScriptImportWorker {
        queue: Arc::clone(&queue),
        client: Arc::new(FakeLlmClientWithConflictingCategories),
        previews: previews.clone() as Arc<dyn AiPreviewStore>,
        extractor: super::PdfTextExtractor::new(1024 * 1024, std::time::Duration::from_secs(30)),
        provider: LlmProvider::Neuralwatt,
        model: "deepseek-v4-flash".to_owned(),
        prompt: "fixture prompt".to_owned(),
        bounds: AiImportBounds {
            max_chunks_per_script: 4,
            ..AiImportBounds::default()
        },
        pricing: None,
        decision: None,
    };
    let job = script_job(AiImportJobId::new());
    let handle = worker
        .process_text(&job, "test-worker", "1. INT. KITCHEN - DAY\nA")
        .await
        .unwrap();
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ScriptContext = serde_json::from_slice(&payload).unwrap();
    let conflicts: Vec<_> = preview
        .uncertainties
        .iter()
        .filter(|uncertainty| uncertainty.field == "category")
        .collect();
    assert_eq!(conflicts.len(), 1, "one conflict per identity");
    assert_eq!(conflicts[0].kind, UncertaintyKind::FieldAmbiguity);
    assert_eq!(conflicts[0].scene_index, 0);
    assert_eq!(conflicts[0].suggested_value.as_deref(), Some("guest"));
}

#[tokio::test]
async fn script_worker_backfills_scene_number_from_chunk_heading() {
    // Issue #581: the model omitted `scene_number` although the document
    // heading carries one — the preview must not render "?" for a number
    // the server already read out of the heading. Server-side truth, same
    // doctrine as `stable_draft_ref` overwriting the model's `draft_ref`.
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let worker = ScriptImportWorker {
        queue: Arc::clone(&queue),
        client: Arc::new(FakeLlmClientWithoutSceneNumber),
        previews: previews.clone() as Arc<dyn AiPreviewStore>,
        extractor: super::PdfTextExtractor::new(1024 * 1024, std::time::Duration::from_secs(30)),
        provider: LlmProvider::Neuralwatt,
        model: "deepseek-v4-flash".to_owned(),
        prompt: "fixture prompt".to_owned(),
        bounds: AiImportBounds {
            max_chunks_per_script: 4,
            ..AiImportBounds::default()
        },
        pricing: None,
        decision: None,
    };
    let job = script_job(AiImportJobId::new());
    let handle = worker
        .process_text(
            &job,
            "test-worker",
            "12 I/T - WOHNUNG\nA\n14 I/T - KÜCHE\nB",
        )
        .await
        .unwrap();
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ScriptContext = serde_json::from_slice(&payload).unwrap();
    assert_eq!(preview.scenes.len(), 2);
    assert_eq!(
        preview.scenes[0].scene_number,
        Some(12),
        "first chunk's heading number must reach the preview row"
    );
    assert_eq!(preview.scenes[1].scene_number, Some(14));
    let state = queue.state.lock().unwrap();
    assert_eq!(state.succeeded, vec![job.id]);
}

#[tokio::test]
async fn script_worker_preserves_model_title_when_scan_has_none() {
    // CodeRabbit review: the scan's bare page-header marker (`Ep.: 5`, no
    // title) is authoritative for the NUMBER — but it must not erase the
    // model's extracted episode TITLE. The preview row keeps `{5,
    // "Der Unfall"}` when the title-page scan found no quoted title.
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let worker = ScriptImportWorker {
        queue: Arc::clone(&queue),
        client: Arc::new(FakeLlmClientWithEpisodeTitle),
        previews: previews.clone() as Arc<dyn AiPreviewStore>,
        extractor: super::PdfTextExtractor::new(1024 * 1024, std::time::Duration::from_secs(30)),
        provider: LlmProvider::Neuralwatt,
        model: "deepseek-v4-flash".to_owned(),
        prompt: "fixture prompt".to_owned(),
        bounds: AiImportBounds {
            max_chunks_per_script: 4,
            ..AiImportBounds::default()
        },
        pricing: None,
        decision: None,
    };
    let job = script_job(AiImportJobId::new());
    let handle = worker
        .process_text(&job, "test-worker", "Ep.: 5\n1 I/T - ORT\nA")
        .await
        .unwrap();
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ScriptContext = serde_json::from_slice(&payload).unwrap();
    let episode = preview.scenes[0]
        .episode
        .as_ref()
        .expect("episode metadata stamped");
    assert_eq!(episode.number, Some(5), "scan number stays authoritative");
    assert_eq!(
        episode.title.as_deref(),
        Some("Der Unfall"),
        "the model title survives when the scan carries none"
    );
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

/// Scene-command double faithful to the `SceneAggregate` + adapter contract
/// for the scene-relation chain (issue #546 §5.8): version fence per command,
/// `CharacterAlreadyAssigned` on a duplicate assign (409, the code the worker
/// folds into recovery), `CharacterNotInScene` for a beat of a figure that is
/// not assigned, and the identical-last guard as the only `scene.validation`
/// refusal of `AddCostumeBeat` (pinned in core).
#[derive(Clone, Default)]
struct FakeSceneCommands {
    created: Arc<Mutex<Vec<Uuid>>>,
    /// The full `CreateScene` commands, so tests can assert WHICH episode a
    /// scene landed in (issue #581).
    created_commands: Arc<Mutex<Vec<breakdown_core::scene::commands::CreateScene>>>,
    updated: Arc<Mutex<Vec<Uuid>>>,
    scheduled: Arc<Mutex<Vec<(Uuid, breakdown_core::shared::ShootingDayId)>>>,
    /// Shared dispatch journal ("scene:create", "scene:assign:{char}"…).
    journal: Arc<Mutex<Vec<String>>>,
    /// Scene-stream versions, i.e. how many events each scene has appended.
    versions: Arc<Mutex<HashMap<Uuid, Version>>>,
    /// `assigned_characters` per scene, as the aggregate state holds them.
    assigned: Arc<Mutex<HashMap<Uuid, Vec<Uuid>>>>,
    /// Beats per scene as `(character_id, costume_id)` in append order.
    beats: Arc<Mutex<Vec<(Uuid, Uuid, Uuid)>>>,
    /// One-shot refusal for the next `add_costume_beat` (simulating a
    /// concurrent manual edit between the assign and the beat).
    fail_beat_with: Arc<Mutex<Option<DomainError>>>,
}

impl FakeSceneCommands {
    fn version_of(&self, id: &Uuid) -> Version {
        self.versions
            .lock()
            .unwrap()
            .get(id)
            .copied()
            .unwrap_or(Version::INITIAL)
    }

    /// Mimic the aggregate's version fence: a stale expected version is a
    /// typed `VersionConflict` carrying the current one.
    fn check(&self, id: Uuid, expected: Version) -> Result<Version, DomainError> {
        let current = self.version_of(&id);
        if current == expected {
            Ok(current.next())
        } else {
            Err(DomainError::VersionConflict { expected, current })
        }
    }

    fn beats_of(&self, scene: Uuid) -> Vec<(Uuid, Uuid)> {
        self.beats
            .lock()
            .unwrap()
            .iter()
            .filter(|(id, _, _)| *id == scene)
            .map(|(_, character, costume)| (*character, *costume))
            .collect()
    }
}

impl breakdown_core::scene::ports::SceneCommands for FakeSceneCommands {
    async fn create(
        &self,
        _actor: UserId,
        command: breakdown_core::scene::commands::CreateScene,
    ) -> Result<(Uuid, breakdown_core::shared::AggregateVersion), DomainError> {
        let mut created = self.created.lock().unwrap();
        // Faithful to `SceneCommandsImpl`, which dispatches with
        // `ExpectedVersion::Empty`: a second create on the same (already
        // written) stream cannot append and reports the current version, so
        // concurrent script applies converging on one reserved id do not
        // duplicate the scene (issue #338).
        if created.contains(&command.id) {
            return Err(DomainError::VersionConflict {
                expected: version(0),
                current: self.version_of(&command.id),
            });
        }
        created.push(command.id);
        self.created_commands.lock().unwrap().push(command.clone());
        self.versions
            .lock()
            .unwrap()
            .insert(command.id, Version::INITIAL);
        self.journal.lock().unwrap().push("scene:create".to_owned());
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
        // The real stream advances to `next`; seed it so a later assign/beat
        // on an update-row scene has a version to fence against.
        self.versions
            .lock()
            .unwrap()
            .insert(command.id, command.version.next());
        Ok(command.version.next())
    }

    async fn assign_character(
        &self,
        _actor: UserId,
        command: breakdown_core::scene::commands::AssignCharacter,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        let next = self.check(command.id, command.version)?;
        let mut assigned = self.assigned.lock().unwrap();
        let members = assigned.entry(command.id).or_default();
        if members.contains(&command.character_id) {
            return Err(DomainError::Conflict {
                code: &breakdown_core::error_registry::SCENE_CHARACTER_ALREADY_ASSIGNED,
                reason: "character already assigned to this scene".to_owned(),
            });
        }
        members.push(command.character_id);
        drop(assigned);
        self.versions.lock().unwrap().insert(command.id, next);
        self.journal
            .lock()
            .unwrap()
            .push(format!("scene:assign:{}", command.character_id));
        Ok(next)
    }

    async fn remove_character(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene::commands::RemoveCharacter,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }
    async fn add_outfit_beat(
        &self,
        _actor: UserId,
        command: breakdown_core::scene::commands::AddOutfitBeat,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        if let Some(error) = self.fail_beat_with.lock().unwrap().take() {
            return Err(error);
        }
        let next = self.check(command.id, command.version)?;
        let assigned = self.assigned.lock().unwrap();
        let in_scene = assigned
            .get(&command.id)
            .is_some_and(|members| members.contains(&command.character_id));
        if !in_scene {
            return Err(DomainError::Validation {
                code: &breakdown_core::error_registry::SCENE_CHARACTER_NOT_IN_SCENE,
                reason: format!(
                    "character {} is not assigned to this scene",
                    command.character_id
                ),
            });
        }
        // Identical-last guard, faithful to the aggregate: appending the
        // (costume, note) the character already wears last is refused as the
        // ONLY `scene.validation` refusal of `AddOutfitBeat`.
        let last = self
            .beats_of(command.id)
            .into_iter()
            .rev()
            .find(|(character, _)| *character == command.character_id);
        if last.is_some_and(|(_, costume)| costume == command.outfit_id) {
            return Err(DomainError::Validation {
                code: &breakdown_core::error_registry::SCENE_VALIDATION,
                reason: "Outfit beat identical to the character's last beat".to_owned(),
            });
        }
        drop(assigned);
        self.versions.lock().unwrap().insert(command.id, next);
        self.beats
            .lock()
            .unwrap()
            .push((command.id, command.character_id, command.outfit_id));
        self.journal
            .lock()
            .unwrap()
            .push(format!("scene:beat:{}", command.outfit_id));
        Ok(next)
    }

    async fn update_outfit_beat(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene::commands::UpdateOutfitBeat,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
    }

    async fn remove_outfit_beat(
        &self,
        _actor: UserId,
        _command: breakdown_core::scene::commands::RemoveOutfitBeat,
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
    values: Arc<Mutex<HashMap<MappingKey, AiImportMapping>>>,
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

    /// Remove every mapping of `draft_ref` — simulating a lost reservation row
    /// (e.g. a rollback that dropped the reservation but the command had already
    /// appended). The core crash window of issue #182. All kinds and ordinals of
    /// the reference are dropped, which is what a rolled-back transaction does.
    fn remove(&self, preview_id: AiImportJobId, draft_ref: &str) {
        let mut values = self.values.lock().unwrap();
        values.retain(|key, _| !(key.0 == preview_id && key.1 == draft_ref));
    }
}

/// Full mapping row key, as the production table addresses it.
type MappingKey = (AiImportJobId, String, String, i32);

fn key_of(mapping: &AiImportMapping) -> MappingKey {
    (
        mapping.preview_id,
        mapping.draft_ref.clone(),
        mapping.aggregate_kind.clone(),
        mapping.ordinal,
    )
}

#[async_trait]
impl AiImportMappingRepository for FakeMappings {
    async fn find(
        &self,
        preview_id: AiImportJobId,
        draft_ref: &str,
        aggregate_kind: &str,
        ordinal: i32,
    ) -> Result<Option<AiImportMapping>, DomainError> {
        Ok(self
            .values
            .lock()
            .unwrap()
            .get(&(
                preview_id,
                draft_ref.to_owned(),
                aggregate_kind.to_owned(),
                ordinal,
            ))
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
            .entry(key_of(&mapping))
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
            .entry(key_of(&mapping))
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
                expected: version(0),
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
                expected: version(0),
                current: breakdown_core::shared::AggregateVersion(0),
            });
        }
        let mut planned = self.planned.lock().unwrap();
        // Faithful to `SceneShootCommandsImpl` (`ExpectedVersion::Empty`): a
        // re-plan onto an already-written stream reports the current version
        // rather than appending a duplicate `SceneShootPlanned`.
        if planned.contains(&command.id) {
            return Err(DomainError::VersionConflict {
                expected: version(0),
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
            outfit_beats: Vec::new(),
            version: breakdown_core::shared::AggregateVersion::INITIAL,
            updated_at: Utc::now(),
            source: Some(SceneSource::Manual),
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
            preview: merge_schedule_to_scenes(
                &schedule,
                &[scene],
                &std::collections::HashMap::new(),
            ),
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
                project_id: None,
            })
            .await
    }

    fn scene_shoot_pair_key(&self) -> String {
        let day = self.shooting_days.created.lock().unwrap()[0];
        format!("scene-shoot:{}:{}", self.scene_id, day.0)
    }

    async fn mapping(&self, draft_ref: &str, aggregate_kind: &str) -> Option<AiImportMapping> {
        self.mappings
            .find(self.preview_id, draft_ref, aggregate_kind, PRIMARY_ORDINAL)
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
        .mapping(&pair_key, mapping_kind::SCENE_SHOOT)
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
    let confirmed = fixture
        .mapping(&pair_key, mapping_kind::SCENE_SHOOT)
        .await
        .expect("mapping exists");
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
    let reserved = fixture
        .mapping(&day_key, mapping_kind::SHOOTING_DAY)
        .await
        .expect("reservation exists");
    assert!(reserved.is_reserved());
    assert_eq!(reserved.aggregate_id, created[0].0);

    fixture.apply().await.expect("the retry must converge");

    assert_eq!(
        fixture.shooting_days.created.lock().unwrap().len(),
        1,
        "the retry must not create a second shooting day"
    );
    assert_eq!(fixture.scene_shoots.planned.lock().unwrap().len(), 1);
    let confirmed = fixture
        .mapping(&day_key, mapping_kind::SHOOTING_DAY)
        .await
        .expect("mapping exists");
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
        .mapping(&pair_key, mapping_kind::SCENE_SHOOT)
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
        fixture
            .mapping(&day_key, mapping_kind::SHOOTING_DAY)
            .await
            .is_none(),
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
    let confirmed = fixture
        .mapping(&day_key, mapping_kind::SHOOTING_DAY)
        .await
        .expect("mapping exists");
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
    let reserved_id = fixture
        .mapping(&pair_key, mapping_kind::SCENE_SHOOT)
        .await
        .unwrap()
        .aggregate_id;

    // Lose the scene-shoot reservation row.
    fixture.mappings.remove(fixture.preview_id, &pair_key);
    assert!(
        fixture
            .mapping(&pair_key, mapping_kind::SCENE_SHOOT)
            .await
            .is_none()
    );

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
    let confirmed = fixture
        .mapping(&pair_key, mapping_kind::SCENE_SHOOT)
        .await
        .expect("mapping exists");
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

    let day_id_first = fixture
        .mapping(&day_key, mapping_kind::SHOOTING_DAY)
        .await
        .unwrap()
        .aggregate_id;
    let shoot_id_first = fixture
        .mapping(&pair_key, mapping_kind::SCENE_SHOOT)
        .await
        .unwrap()
        .aggregate_id;

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
        fixture
            .mapping(&day_key, mapping_kind::SHOOTING_DAY)
            .await
            .unwrap()
            .aggregate_id,
        day_id_first,
        "ShootingDayId must be stable across applies without the projection"
    );
    assert_eq!(
        fixture
            .mapping(&pair_key, mapping_kind::SCENE_SHOOT)
            .await
            .unwrap()
            .aggregate_id,
        shoot_id_first,
        "SceneShootId must be stable across applies without the projection"
    );
}

/// Issue #338: a repeated apply is a no-op for already-applied rows. The
/// retry returns the confirmed id/version without re-dispatching — a re-run
/// `Update` would fail in production (identical details are rejected as
/// unchanged) — and without creating a duplicate scene.
#[tokio::test]
async fn apply_retry_is_a_noop_for_confirmed_mappings() {
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
    let worker = script_apply_worker(
        Arc::clone(&commands),
        Arc::clone(&mappings),
        Arc::clone(&queue),
    );
    // Not the fake client's "fixture-scene": `process_text` overwrites every
    // row's reference with the server-owned `stable_draft_ref`, and the apply
    // resolves decisions by that reference.
    let row_ref = preview.scenes[0].draft_ref.clone();
    let decision = create_decision(&row_ref);
    let first = worker
        .apply_script(ApplyScriptRequest {
            continuity_selections: Vec::new(),
            acknowledged_uncertainties: Vec::new(),
            categories: Vec::new(),
            actor: UserId::from_sub("ai-test-user"),
            preview_id: job.id,
            preview: &preview,
            decisions: &[decision],
            episode_id: breakdown_core::shared::EpisodeId::new(),
            season_id: breakdown_core::shared::SeasonId::new(),
            project_id: None,
            // Single-episode flow fixtures: no group targets, no episode creation (issue #581).
            block_id: breakdown_core::shared::BlockId::new(),
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
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
    let second = worker
        .apply_script(ApplyScriptRequest {
            continuity_selections: Vec::new(),
            acknowledged_uncertainties: Vec::new(),
            categories: Vec::new(),
            actor: UserId::from_sub("ai-test-user"),
            preview_id: job.id,
            preview: &preview,
            decisions: &[],
            episode_id: breakdown_core::shared::EpisodeId::new(),
            season_id: breakdown_core::shared::SeasonId::new(),
            project_id: None,
            // Single-episode flow fixtures: no group targets, no episode creation (issue #581).
            block_id: breakdown_core::shared::BlockId::new(),
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
            telemetry: None,
        })
        .await
        .unwrap();
    assert_eq!(
        first.applied, second.applied,
        "the retry must return the stored id/version"
    );
    assert_eq!(
        second.created_characters, 0,
        "a retry must not report a second figure creation"
    );
    assert_eq!(commands.created.lock().unwrap().len(), 1);
    assert!(
        commands.updated.lock().unwrap().is_empty(),
        "the retry must not re-dispatch the confirmed row"
    );
    let state = queue.state.lock().unwrap();
    assert!(state.telemetry.iter().any(|telemetry| telemetry.apply_state
        == TelemetryApplyState::Applied {
            accept_as_is: true,
            edit_distance: 0,
        }));
}

/// Issue #338 AC #3: two applies in flight for the same job yield one scene
/// per draft and a stable `applied_count`. Both callers reserve-then-create
/// the same deterministic id; the `ExpectedVersion::Empty` guard rejects the
/// duplicate append and `recover_version` turns it into the same version, so
/// both callers observe identical results.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn apply_script_concurrent_applies_create_one_scene_per_draft() {
    use tokio::sync::Barrier;

    let queue = Arc::new(FakeQueue::default());
    let mappings = Arc::new(FakeMappings::default());
    let commands = Arc::new(FakeSceneCommands::default());
    let preview = ScriptContext {
        title: Some("fixture".to_owned()),
        scenes: vec![
            DraftScene {
                draft_ref: "concurrent-a".to_owned(),
                scene_number: Some(1),
                ..Default::default()
            },
            DraftScene {
                draft_ref: "concurrent-b".to_owned(),
                scene_number: Some(2),
                ..Default::default()
            },
        ],
        uncertainties: Vec::new(),
    };
    let preview_id = AiImportJobId::new();
    let decisions = vec![
        create_decision("concurrent-a"),
        create_decision("concurrent-b"),
    ];
    let episode_id = breakdown_core::shared::EpisodeId::new();
    let barrier = Arc::new(Barrier::new(2));
    let mut handles = Vec::new();
    for _ in 0..2 {
        let worker = script_apply_worker(
            Arc::clone(&commands),
            Arc::clone(&mappings),
            Arc::clone(&queue),
        );
        let barrier = Arc::clone(&barrier);
        let preview = preview.clone();
        let decisions = decisions.clone();
        handles.push(tokio::spawn(async move {
            barrier.wait().await;
            worker
                .apply_script(ApplyScriptRequest {
                    continuity_selections: Vec::new(),
                    acknowledged_uncertainties: Vec::new(),
                    categories: Vec::new(),
                    actor: UserId::from_sub("ai-test-user"),
                    preview_id,
                    preview: &preview,
                    decisions: &decisions,
                    episode_id,
                    season_id: breakdown_core::shared::SeasonId::new(),
                    project_id: None,
                    // Single-episode flow fixtures: no group targets, no episode creation (issue #581).
                    block_id: breakdown_core::shared::BlockId::new(),
                    episode_groups: Vec::new(),
                    shooting_days: Vec::new(),
                    telemetry: None,
                })
                .await
        }));
    }
    let mut results = Vec::new();
    for handle in handles {
        results.push(
            handle
                .await
                .expect("apply task panicked")
                .expect("apply failed"),
        );
    }
    assert_eq!(results[0], results[1], "both applies must converge");
    assert_eq!(
        results[0].applied.len(),
        2,
        "stable applied_count per draft"
    );
    let created = commands.created.lock().unwrap().clone();
    let mut unique: Vec<Uuid> = created.clone();
    unique.sort();
    unique.dedup();
    assert_eq!(unique.len(), 2, "one scene per draft, got {created:?}");
    assert_eq!(
        unique.len(),
        created.len(),
        "no duplicate scene streams were appended"
    );
    for draft_ref in ["concurrent-a", "concurrent-b"] {
        let mapping = mappings
            .find(preview_id, draft_ref, mapping_kind::SCENE, PRIMARY_ORDINAL)
            .await
            .expect("mappings readable")
            .expect("mapping exists");
        assert!(
            !mapping.is_reserved(),
            "every row must confirm, got {mapping:?}"
        );
    }
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
    let apply_worker = script_apply_worker(Arc::clone(&commands), Arc::clone(&mappings), queue);
    let decision = create_decision(&preview.scenes[0].draft_ref);
    apply_worker
        .apply_script(ApplyScriptRequest {
            continuity_selections: Vec::new(),
            acknowledged_uncertainties: Vec::new(),
            categories: Vec::new(),
            actor: UserId::from_sub("script-round-trip"),
            preview_id: job.id,
            preview: &preview,
            decisions: &[decision],
            episode_id: breakdown_core::shared::EpisodeId::new(),
            season_id: breakdown_core::shared::SeasonId::new(),
            project_id: None,
            // Single-episode flow fixtures: no group targets, no episode creation (issue #581).
            block_id: breakdown_core::shared::BlockId::new(),
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
            telemetry: None,
        })
        .await
        .unwrap();
    assert_eq!(commands.created.lock().unwrap().len(), 1);
}

// ===========================================================================
// Script apply: figures and costumes of a draft row
// (openspec: ai-import-character-costumes, groups 3 + 4)
// ===========================================================================

/// `ApplyMapping::decision` is not re-exported by name here; this keeps the
/// test literals below short.
fn create_decision(draft_ref: &str) -> ApplyMapping {
    ApplyMapping {
        draft_ref: draft_ref.to_owned(),
        decision: breakdown_core::ai::ApplyMappingDecision::Create,
        outfit_decisions: Vec::new(),
    }
}

/// Script-apply worker for the tests that do not inspect figures or costumes.
/// The previews those tests use carry none, so the two extra ports only have to
/// exist.
fn script_apply_worker(
    scene_commands: Arc<FakeSceneCommands>,
    mappings: Arc<FakeMappings>,
    queue: Arc<FakeQueue>,
) -> ApplyWorker<
    FakeSceneCommands,
    FakeCharacterCommands,
    FakeWardrobeCommands,
    FakeEpisodeCommands,
    FakeShootingDayCommands,
    FakeSceneShootCommands,
    FakeMappings,
    FakeQueue,
    FakeSeasonRepo,
> {
    ApplyWorker {
        scene_commands,
        character_commands: Arc::new(FakeCharacterCommands::default()),
        wardrobe_commands: Arc::new(FakeWardrobeCommands::default()),
        episode_commands: Arc::new(FakeEpisodeCommands::default()),
        shooting_day_commands: Arc::new(FakeShootingDayCommands::default()),
        scene_shoot_commands: Arc::new(FakeSceneShootCommands::default()),
        mappings,
        queue,
        season_repo: Arc::new(FakeSeasonRepo::default()),
    }
}

/// A port the AI apply must never call. Failing loudly beats returning a value
/// a dispatch bug could silently consume.
fn unexpected_command(name: &str) -> Result<Version, DomainError> {
    Err(unexpected_command_error(name))
}

fn unexpected_command_error(name: &str) -> DomainError {
    DomainError::validation(format!("unexpected AI apply command: {name}"))
}

/// Episode create port of the script apply (issue #581). Faithful to the real
/// aggregate's create contract: a second create on the same stream reports the
/// version instead of duplicating — exactly what `created_now` recovers on a
/// retry that re-drives its own reservation.
#[derive(Clone, Default)]
struct FakeEpisodeCommands {
    created: Arc<Mutex<Vec<breakdown_core::episode::commands::CreateEpisode>>>,
    /// Shared dispatch journal ("episode:create:{number}") so tests can
    /// assert the create order against the scene creates.
    journal: Arc<Mutex<Vec<String>>>,
}

impl breakdown_core::episode::ports::EpisodeCommands for FakeEpisodeCommands {
    async fn create(
        &self,
        _actor: UserId,
        command: breakdown_core::episode::commands::CreateEpisode,
    ) -> Result<(Uuid, Version), DomainError> {
        if self
            .created
            .lock()
            .unwrap()
            .iter()
            .any(|created| created.id == command.id)
        {
            return Err(DomainError::VersionConflict {
                expected: version(0),
                current: Version::INITIAL,
            });
        }
        let id = command.id;
        self.journal
            .lock()
            .unwrap()
            .push(format!("episode:create:{}", command.number));
        self.created.lock().unwrap().push(command);
        Ok((id, Version::INITIAL))
    }

    async fn rename(
        &self,
        _actor: UserId,
        _command: breakdown_core::episode::commands::RenameEpisode,
    ) -> Result<Version, DomainError> {
        unexpected_command("RenameEpisode")
    }
}

/// `CreateCharacter` faithful to the real aggregate's optimistic-locking
/// contract, plus an ordered journal of what the apply dispatched.
#[derive(Clone, Default)]
struct FakeCharacterCommands {
    created: Arc<Mutex<Vec<breakdown_core::character::commands::CreateCharacter>>>,
    /// `Some` refuses the next create with a domain error (task 3.6).
    fail_with: Arc<Mutex<Option<DomainError>>>,
    journal: Arc<Mutex<Vec<String>>>,
}

impl breakdown_core::character::ports::CharacterCommands for FakeCharacterCommands {
    async fn create(
        &self,
        _actor: UserId,
        command: breakdown_core::character::commands::CreateCharacter,
    ) -> Result<(Uuid, breakdown_core::shared::AggregateVersion), DomainError> {
        if let Some(error) = self.fail_with.lock().unwrap().take() {
            return Err(error);
        }
        let id = command.id;
        // `CharacterCommandsImpl` dispatches a create with
        // `ExpectedVersion::Empty`: re-driving onto a stream that already
        // appended reports the current version instead of duplicating.
        if self.created.lock().unwrap().iter().any(|c| c.id == id) {
            return Err(DomainError::VersionConflict {
                expected: version(0),
                current: breakdown_core::shared::AggregateVersion::INITIAL,
            });
        }
        let name = command.name.clone();
        self.created.lock().unwrap().push(command);
        self.journal
            .lock()
            .unwrap()
            .push(format!("character:{name}"));
        Ok((id, breakdown_core::shared::AggregateVersion::INITIAL))
    }

    async fn update_measurements(
        &self,
        _actor: UserId,
        _command: breakdown_core::character::commands::UpdateMeasurements,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        unexpected_command("update_measurements")
    }

    async fn update_contact_info(
        &self,
        _actor: UserId,
        _command: breakdown_core::character::commands::UpdateContactInfo,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        unexpected_command("update_contact_info")
    }

    async fn update_category(
        &self,
        _actor: UserId,
        _command: breakdown_core::character::commands::UpdateCharacterCategory,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        unexpected_command("update_category")
    }
}

/// Wardrobe write ports (`PieceCommands` + `OutfitCommands`) faithful to the
/// aggregates' version chains: every accepted command appends exactly one
/// event, so the version the apply stores is the phase record a retry re-drives
/// from. The journal keeps the historical `costume:*` keys so the apply-order
/// assertions stay readable.
#[derive(Clone, Default)]
struct FakeWardrobeCommands {
    created: Arc<Mutex<Vec<Uuid>>>,
    notes: Arc<Mutex<Vec<(Uuid, String)>>>,
    /// `(piece_id, category_id)` of every `SetPieceCategory` this apply sent.
    categories: CategoryDispatchLog,
    /// `(outfit_id, character_id)` of every created outfit.
    assigned: Arc<Mutex<Vec<(Uuid, Uuid)>>>,
    /// Version each piece carries, i.e. how many events it has appended.
    versions: Arc<Mutex<HashMap<Uuid, breakdown_core::shared::AggregateVersion>>>,
    /// Version each outfit carries.
    outfit_versions: Arc<Mutex<HashMap<Uuid, breakdown_core::shared::AggregateVersion>>>,
    fail_assign_with: Arc<Mutex<Option<DomainError>>>,
    /// Makes the next `CreateOutfit` behave like an earlier crashed attempt:
    /// the outfit stream exists but is still **empty**, so the worker takes its
    /// recovery path and has to add every piece itself (CodeRabbit, PR #744).
    lose_outfit_pieces_once: Arc<Mutex<bool>>,
    journal: Arc<Mutex<Vec<String>>>,
}

type Version = breakdown_core::shared::AggregateVersion;

/// `(piece_id, category_id)` pairs of the `SetPieceCategory` commands one
/// apply dispatched, in dispatch order.
type CategoryDispatchLog =
    Arc<Mutex<Vec<(Uuid, Option<breakdown_core::shared::CostumeCategoryId>)>>>;

/// Season read model of the apply worker (CR-002/D2).
///
/// Every season answers as **active** by default — that is what the apply tests
/// which are not about archiving need. `archived` makes the gate fire, and
/// `failure` injects a lookup error (outage vs. projection miss).
#[derive(Clone, Default)]
struct FakeSeasonRepo {
    archived: Arc<Mutex<Option<bool>>>,
    failure: Arc<Mutex<Option<DomainError>>>,
}

impl FakeSeasonRepo {
    /// Target season answers as archived (terminal lifecycle, issue #533).
    fn archived() -> Self {
        Self {
            archived: Arc::new(Mutex::new(Some(true))),
            failure: Arc::new(Mutex::new(None)),
        }
    }
}

impl SeasonRepository for FakeSeasonRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<SeasonView, DomainError> {
        if let Some(error) = self.failure.lock().unwrap().clone() {
            return Err(error);
        }
        Ok(SeasonView {
            id,
            project_id: breakdown_core::shared::ProjectId::new(),
            number: 1,
            title: None,
            archived: self.archived.lock().unwrap().unwrap_or(false),
            version: Version::INITIAL,
            updated_at: Utc::now(),
        })
    }

    async fn list_all(
        &self,
        _include_archived: bool,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<SeasonView>, DomainError> {
        Ok(Vec::new())
    }

    async fn list_by_project(
        &self,
        _project_id: breakdown_core::shared::ProjectId,
        _include_archived: bool,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<SeasonView>, DomainError> {
        Ok(Vec::new())
    }

    async fn find_by_project_and_number(
        &self,
        _project_id: breakdown_core::shared::ProjectId,
        _number: i32,
    ) -> Result<Option<SeasonView>, DomainError> {
        Ok(None)
    }
}

/// A pinned aggregate version (the alias above cannot construct the tuple).
fn version(n: u64) -> Version {
    breakdown_core::shared::AggregateVersion(n)
}

impl FakeWardrobeCommands {
    fn version_of(&self, id: &Uuid) -> Option<Version> {
        self.versions.lock().unwrap().get(id).copied()
    }

    fn outfit_version_of(&self, id: &Uuid) -> Option<Version> {
        self.outfit_versions.lock().unwrap().get(id).copied()
    }

    /// Mimic the aggregate's `check_version`: a stale expected version is a
    /// typed `VersionConflict` carrying the current one.
    fn check(&self, id: Uuid, expected: Version) -> Result<Version, DomainError> {
        match self.version_of(&id) {
            Some(current) if current == expected => Ok(current.next()),
            Some(current) => Err(DomainError::VersionConflict { expected, current }),
            None => Err(DomainError::validation("piece stream is missing")),
        }
    }

    fn check_outfit(&self, id: Uuid, expected: Version) -> Result<Version, DomainError> {
        match self.outfit_version_of(&id) {
            Some(current) if current == expected => Ok(current.next()),
            Some(current) => Err(DomainError::VersionConflict { expected, current }),
            None => Err(DomainError::validation("outfit stream is missing")),
        }
    }
}

impl breakdown_core::piece::ports::PieceCommands for FakeWardrobeCommands {
    async fn create(
        &self,
        _actor: UserId,
        command: breakdown_core::piece::commands::CreatePiece,
    ) -> Result<(Uuid, Version), DomainError> {
        let id = command.id;
        if self.created.lock().unwrap().contains(&id) {
            return Err(DomainError::VersionConflict {
                expected: version(0),
                current: self.version_of(&id).unwrap_or(Version::INITIAL),
            });
        }
        self.created.lock().unwrap().push(id);
        self.versions.lock().unwrap().insert(id, Version::INITIAL);
        self.journal
            .lock()
            .unwrap()
            .push(format!("piece:create:{id}"));
        Ok((id, Version::INITIAL))
    }

    async fn rename(
        &self,
        _actor: UserId,
        _command: breakdown_core::piece::commands::RenamePiece,
    ) -> Result<Version, DomainError> {
        unexpected_command("rename")
    }

    async fn update_notes(
        &self,
        _actor: UserId,
        command: breakdown_core::piece::commands::UpdatePieceNotes,
    ) -> Result<Version, DomainError> {
        let next = self.check(command.id, command.version)?;
        self.versions.lock().unwrap().insert(command.id, next);
        self.notes
            .lock()
            .unwrap()
            .push((command.id, command.notes.clone()));
        self.journal
            .lock()
            .unwrap()
            .push(format!("piece:notes:{}", command.id));
        Ok(next)
    }

    async fn add_to_season(
        &self,
        _actor: UserId,
        _command: breakdown_core::piece::commands::AddPieceToSeason,
    ) -> Result<Version, DomainError> {
        unexpected_command("add_to_season")
    }

    async fn remove_from_season(
        &self,
        _actor: UserId,
        _command: breakdown_core::piece::commands::RemovePieceFromSeason,
    ) -> Result<Version, DomainError> {
        unexpected_command("remove_from_season")
    }

    async fn add_detail(
        &self,
        _actor: UserId,
        _command: breakdown_core::piece::commands::AddPieceDetail,
    ) -> Result<Version, DomainError> {
        unexpected_command("add_detail")
    }

    async fn update_detail(
        &self,
        _actor: UserId,
        _command: breakdown_core::piece::commands::UpdatePieceDetail,
    ) -> Result<Version, DomainError> {
        unexpected_command("update_detail")
    }

    async fn remove_detail(
        &self,
        _actor: UserId,
        _command: breakdown_core::piece::commands::RemovePieceDetail,
    ) -> Result<Version, DomainError> {
        unexpected_command("remove_detail")
    }

    async fn set_category(
        &self,
        _actor: UserId,
        command: breakdown_core::piece::commands::SetPieceCategory,
    ) -> Result<Version, DomainError> {
        let next = self.check(command.id, command.version)?;
        self.versions.lock().unwrap().insert(command.id, next);
        self.categories
            .lock()
            .unwrap()
            .push((command.id, command.category_id));
        self.journal
            .lock()
            .unwrap()
            .push(format!("piece:category:{}", command.id));
        Ok(next)
    }

    async fn link_photo(
        &self,
        _actor: UserId,
        _command: breakdown_core::piece::commands::LinkPiecePhoto,
    ) -> Result<Version, DomainError> {
        unexpected_command("link_photo")
    }

    async fn unlink_photo(
        &self,
        _actor: UserId,
        _command: breakdown_core::piece::commands::UnlinkPiecePhoto,
    ) -> Result<Version, DomainError> {
        unexpected_command("unlink_photo")
    }
}

impl breakdown_core::outfit::ports::OutfitCommands for FakeWardrobeCommands {
    async fn create(
        &self,
        _actor: UserId,
        command: breakdown_core::outfit::commands::CreateOutfit,
    ) -> Result<(Uuid, Version), DomainError> {
        let id = command.id;
        if let Some(current) = self.outfit_version_of(&id) {
            return Err(DomainError::VersionConflict {
                expected: version(0),
                current,
            });
        }
        if let Some(error) = self.fail_assign_with.lock().unwrap().take() {
            return Err(error);
        }
        self.outfit_versions
            .lock()
            .unwrap()
            .insert(id, Version::INITIAL);
        // The simulated crash: the stream exists but carries no piece yet, so
        // the caller must recover by adding them one at a time.
        let lose_pieces = std::mem::take(&mut *self.lose_outfit_pieces_once.lock().unwrap());
        if lose_pieces {
            self.assigned
                .lock()
                .unwrap()
                .push((id, command.character_id));
            self.journal
                .lock()
                .unwrap()
                .push(format!("outfit:create:{id}"));
            return Err(DomainError::VersionConflict {
                expected: version(0),
                current: Version::INITIAL,
            });
        }
        self.assigned
            .lock()
            .unwrap()
            .push((id, command.character_id));
        self.journal
            .lock()
            .unwrap()
            .push(format!("outfit:create:{id}"));
        Ok((id, Version::INITIAL))
    }

    async fn create_variant(
        &self,
        _actor: UserId,
        _command: breakdown_core::outfit::commands::CreateOutfitVariant,
    ) -> Result<(Uuid, Version), DomainError> {
        Err(unexpected_command_error("create_variant"))
    }

    async fn rename(
        &self,
        _actor: UserId,
        _command: breakdown_core::outfit::commands::RenameOutfit,
    ) -> Result<Version, DomainError> {
        unexpected_command("outfit_rename")
    }

    async fn update_notes(
        &self,
        _actor: UserId,
        command: breakdown_core::outfit::commands::UpdateOutfitNotes,
    ) -> Result<Version, DomainError> {
        let next = self.check_outfit(command.id, command.version)?;
        self.outfit_versions
            .lock()
            .unwrap()
            .insert(command.id, next);
        // The extracted wording reaches the domain as the outfit's notes — the
        // same channel the piece notes use, so tests can assert one list.
        self.notes
            .lock()
            .unwrap()
            .push((command.id, command.notes.clone()));
        self.journal
            .lock()
            .unwrap()
            .push(format!("outfit:notes:{}", command.id));
        Ok(next)
    }

    async fn add_piece(
        &self,
        _actor: UserId,
        command: breakdown_core::outfit::commands::AddPieceToOutfit,
    ) -> Result<Version, DomainError> {
        let next = self.check_outfit(command.id, command.version)?;
        self.outfit_versions
            .lock()
            .unwrap()
            .insert(command.id, next);
        self.journal
            .lock()
            .unwrap()
            .push(format!("outfit:add_piece:{}", command.id));
        Ok(next)
    }

    async fn remove_piece(
        &self,
        _actor: UserId,
        _command: breakdown_core::outfit::commands::RemovePieceFromOutfit,
    ) -> Result<Version, DomainError> {
        unexpected_command("outfit_remove_piece")
    }

    async fn link_photo(
        &self,
        _actor: UserId,
        _command: breakdown_core::outfit::commands::LinkOutfitPhoto,
    ) -> Result<Version, DomainError> {
        unexpected_command("outfit_link_photo")
    }

    async fn unlink_photo(
        &self,
        _actor: UserId,
        _command: breakdown_core::outfit::commands::UnlinkOutfitPhoto,
    ) -> Result<Version, DomainError> {
        unexpected_command("outfit_unlink_photo")
    }
}

/// End-to-end script apply with all five ports and a shared dispatch journal.
struct ScriptApplyFixture {
    queue: Arc<FakeQueue>,
    mappings: Arc<FakeMappings>,
    scenes: Arc<FakeSceneCommands>,
    characters: Arc<FakeCharacterCommands>,
    wardrobe: Arc<FakeWardrobeCommands>,
    episodes: Arc<FakeEpisodeCommands>,
    shooting_days: Arc<FakeShootingDayCommands>,
    scene_shoots: Arc<FakeSceneShootCommands>,
    seasons: Arc<FakeSeasonRepo>,
    journal: Arc<Mutex<Vec<String>>>,
    preview_id: AiImportJobId,
    episode_id: breakdown_core::shared::EpisodeId,
    season_id: breakdown_core::shared::SeasonId,
    /// Series context the fixture apply carries (issue #581): a group mapped
    /// to a NEW episode needs it for `CreateEpisode`.
    project_id: breakdown_core::shared::ProjectId,
    block_id: breakdown_core::shared::BlockId,
}

impl ScriptApplyFixture {
    fn new() -> Self {
        let journal = Arc::new(Mutex::new(Vec::new()));
        Self {
            queue: Arc::new(FakeQueue::default()),
            mappings: Arc::new(FakeMappings::default()),
            scenes: Arc::new(FakeSceneCommands {
                journal: Arc::clone(&journal),
                ..Default::default()
            }),
            characters: Arc::new(FakeCharacterCommands {
                journal: Arc::clone(&journal),
                ..Default::default()
            }),
            wardrobe: Arc::new(FakeWardrobeCommands {
                journal: Arc::clone(&journal),
                ..Default::default()
            }),
            episodes: Arc::new(FakeEpisodeCommands {
                journal: Arc::clone(&journal),
                ..Default::default()
            }),
            shooting_days: Arc::new(FakeShootingDayCommands::default()),
            scene_shoots: Arc::new(FakeSceneShootCommands::default()),
            seasons: Arc::new(FakeSeasonRepo::default()),
            journal,
            preview_id: AiImportJobId::new(),
            episode_id: breakdown_core::shared::EpisodeId::new(),
            season_id: breakdown_core::shared::SeasonId::new(),
            project_id: breakdown_core::shared::ProjectId::new(),
            block_id: breakdown_core::shared::BlockId::new(),
        }
    }

    fn worker(
        &self,
    ) -> ApplyWorker<
        FakeSceneCommands,
        FakeCharacterCommands,
        FakeWardrobeCommands,
        FakeEpisodeCommands,
        FakeShootingDayCommands,
        FakeSceneShootCommands,
        FakeMappings,
        FakeQueue,
        FakeSeasonRepo,
    > {
        ApplyWorker {
            scene_commands: Arc::clone(&self.scenes),
            character_commands: Arc::clone(&self.characters),
            wardrobe_commands: Arc::clone(&self.wardrobe),
            episode_commands: Arc::clone(&self.episodes),
            shooting_day_commands: Arc::clone(&self.shooting_days),
            scene_shoot_commands: Arc::clone(&self.scene_shoots),
            mappings: Arc::clone(&self.mappings),
            queue: Arc::clone(&self.queue),
            season_repo: Arc::clone(&self.seasons),
        }
    }

    /// Apply with continuity selections (OpenSpec
    /// `ai-import-decision-outfit-continuity`).
    async fn apply_with_continuity(
        &self,
        preview: &ScriptContext,
        decisions: &[ApplyMapping],
        selections: &[breakdown_core::ai::OutfitContinuitySelection],
    ) -> Result<super::ScriptApplyResult, DomainError> {
        self.worker()
            .apply_script(ApplyScriptRequest {
                continuity_selections: selections.to_vec(),
                acknowledged_uncertainties: Vec::new(),
                categories: Vec::new(),
                actor: UserId::from_sub("apply-test-user"),
                preview_id: self.preview_id,
                preview,
                decisions,
                episode_id: self.episode_id,
                season_id: self.season_id,
                project_id: Some(self.project_id),
                block_id: self.block_id,
                episode_groups: Vec::new(),
                shooting_days: Vec::new(),
                telemetry: None,
            })
            .await
    }

    /// Apply with per-group episode targets (issue #581).
    async fn apply_with_groups(
        &self,
        preview: &ScriptContext,
        decisions: &[ApplyMapping],
        episode_groups: Vec<EpisodeGroupPlan>,
    ) -> Result<super::ScriptApplyResult, DomainError> {
        self.apply_with_day_plans(preview, decisions, episode_groups, Vec::new())
            .await
    }

    /// Apply with per-day decisions (issue #706).
    async fn apply_with_day_plans(
        &self,
        preview: &ScriptContext,
        decisions: &[ApplyMapping],
        episode_groups: Vec<EpisodeGroupPlan>,
        shooting_days: Vec<breakdown_core::ai::ShootingDayPlan>,
    ) -> Result<super::ScriptApplyResult, DomainError> {
        self.worker()
            .apply_script(ApplyScriptRequest {
                acknowledged_uncertainties: Vec::new(),
                categories: Vec::new(),
                continuity_selections: Vec::new(),
                actor: UserId::from_sub("apply-test-user"),
                preview_id: self.preview_id,
                preview,
                decisions,
                episode_id: self.episode_id,
                season_id: self.season_id,
                project_id: Some(self.project_id),
                block_id: self.block_id,
                episode_groups,
                shooting_days,
                telemetry: None,
            })
            .await
    }

    /// Apply with a season category vocabulary, so a piece's `category_hint`
    /// can resolve to an id exactly as it does in production.
    async fn apply_with_categories(
        &self,
        preview: &ScriptContext,
        decisions: &[ApplyMapping],
        categories: Vec<breakdown_core::ai::CategoryVocabularyEntry>,
    ) -> Result<super::ScriptApplyResult, DomainError> {
        self.worker()
            .apply_script(ApplyScriptRequest {
                acknowledged_uncertainties: Vec::new(),
                categories,
                continuity_selections: Vec::new(),
                actor: UserId::from_sub("apply-test-user"),
                preview_id: self.preview_id,
                preview,
                decisions,
                episode_id: self.episode_id,
                season_id: self.season_id,
                project_id: None,
                block_id: self.block_id,
                episode_groups: Vec::new(),
                shooting_days: Vec::new(),
                telemetry: None,
            })
            .await
    }

    async fn apply(
        &self,
        preview: &ScriptContext,
        decisions: &[ApplyMapping],
    ) -> Result<super::ScriptApplyResult, DomainError> {
        self.worker()
            .apply_script(ApplyScriptRequest {
                acknowledged_uncertainties: Vec::new(),
                categories: Vec::new(),
                continuity_selections: Vec::new(),
                actor: UserId::from_sub("apply-test-user"),
                preview_id: self.preview_id,
                preview,
                decisions,
                episode_id: self.episode_id,
                season_id: self.season_id,
                project_id: None,
                // Single-episode flow fixtures: no group targets, no episode
                // creation (issue #581).
                block_id: self.block_id,
                episode_groups: Vec::new(),
                shooting_days: Vec::new(),
                telemetry: None,
            })
            .await
    }

    fn steps(&self) -> Vec<String> {
        self.journal.lock().unwrap().clone()
    }

    /// Confirmed `scene_outfit_beat` mapping row of one figure lane, if any.
    async fn beat_mapping(
        &self,
        lane_identity: &str,
        per_figure_order: i32,
    ) -> Option<AiImportMapping> {
        self.mappings
            .find(
                self.preview_id,
                &breakdown_core::ai::character_mapping_ref(lane_identity),
                mapping_kind::SCENE_OUTFIT_BEAT,
                per_figure_order,
            )
            .await
            .unwrap()
    }

    /// The scene's beat list as `(character_id, costume_id)` in stream order.
    fn scene_beats(&self, scene: Uuid) -> Vec<(Uuid, Uuid)> {
        self.scenes.beats_of(scene)
    }

    /// The scene-stream version the fake has appended up to.
    fn scene_version_of(&self, scene: Uuid) -> Version {
        self.scenes.version_of(&scene)
    }
}

/// Test-side construction of a draft outfit with derived garments, so a test
/// can pin the pieces a shorthand decomposes into.
trait DraftOutfitPieces {
    fn with_pieces(self, pieces: &[(&str, Option<&str>)]) -> Self;
}

impl DraftOutfitPieces for breakdown_core::ai::DraftOutfit {
    fn with_pieces(mut self, pieces: &[(&str, Option<&str>)]) -> Self {
        self.pieces = pieces
            .iter()
            .map(|(name, hint)| breakdown_core::ai::DraftPiece {
                name: (*name).to_owned(),
                category_hint: hint.map(str::to_owned),
                description: None,
            })
            .collect();
        self
    }
}

/// A row with one figure and one outfit, as extraction would produce it.
fn row_with_outfit(draft_ref: &str, characters: &[&str], outfits: &[(&str, &str)]) -> DraftScene {
    DraftScene {
        draft_ref: draft_ref.to_owned(),
        scene_number: Some(1),
        characters: characters
            .iter()
            .map(|name| breakdown_core::ai::DraftCharacter {
                name: (*name).to_owned(),
                category: Default::default(),
            })
            .collect(),
        outfits: outfits
            .iter()
            .map(|(character, description)| breakdown_core::ai::DraftOutfit {
                character_name: (*character).to_owned(),
                name: (*description).to_owned(),
                notes: Some((*description).to_owned()),
                source_quote: (*description).to_owned(),
                // One derived garment: the fixture's rows describe a single
                // look, and the apply must create its pieces before the outfit.
                pieces: vec![breakdown_core::ai::DraftPiece {
                    name: (*description).to_owned(),
                    category_hint: None,
                    description: None,
                }],
                ..Default::default()
            })
            .collect(),
        ..Default::default()
    }
}

/// Issue #663: a draft row without a mapping decision answers its own
/// registered code so the client can point at the stale row instead of
/// rendering the generic `domain.conflict`.
#[tokio::test]
async fn script_apply_without_a_mapping_decision_answers_the_dedicated_code() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            &[("Ben", "ölverschmierter Mechaniker-Overall")],
        )],
        ..Default::default()
    };
    // No decisions at all: the planner must refuse the row.
    let error = fixture.apply(&preview, &[]).await.unwrap_err();
    match error {
        DomainError::Conflict { code, .. } => {
            assert_eq!(
                code.code, "ai-import.apply-missing-mapping",
                "the refusal must carry the dedicated code, got {}",
                code.code
            );
        }
        other => panic!("expected Conflict, got {other:?}"),
    }
}

/// Issue #677: the draft character's extracted category flows end-to-end
/// into the CreateCharacter dispatch (no hard-coded MainCast).
#[tokio::test]
async fn script_apply_carries_the_extracted_category_into_the_character() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".to_owned(),
            characters: vec![breakdown_core::ai::DraftCharacter {
                name: "BEN".to_owned(),
                category: breakdown_core::character::category::CharacterCategory::Guest,
            }],
            ..Default::default()
        }],
        ..Default::default()
    };
    fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();

    let created = fixture.characters.created.lock().unwrap();
    let ben = created
        .iter()
        .find(|command| command.name == "BEN")
        .unwrap_or_else(|| panic!("no CreateCharacter was dispatched"));
    assert!(
        matches!(
            ben.category,
            breakdown_core::character::category::CharacterCategory::Guest
        ),
        "the extracted Guest category must reach the dispatch, got {:?}",
        ben.category
    );
}

/// Task 3.4: the figure must exist before its outfit binds to it.
#[tokio::test]
async fn script_apply_dispatches_the_character_before_the_costume_binding() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            &[("Ben", "ölverschmierter Mechaniker-Overall")],
        )],
        ..Default::default()
    };
    fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();

    let steps = fixture.steps();
    let character = steps
        .iter()
        .position(|step| step == "character:BEN")
        .unwrap_or_else(|| panic!("no CreateCharacter was dispatched: {steps:?}"));
    let bind = steps
        .iter()
        .position(|step| step.starts_with("outfit:create:"))
        .unwrap_or_else(|| panic!("no CreateOutfit was dispatched: {steps:?}"));
    assert!(
        character < bind,
        "the figure must be created before its outfit binds to it: {steps:?}"
    );
    // The outfit that bound belongs to the figure this apply created. The
    // piece and the outfit are separate streams: the piece is the garment, the
    // outfit is the look that carries the character binding.
    let created_outfits = fixture.wardrobe.created.lock().unwrap().clone();
    let assigned = fixture.wardrobe.assigned.lock().unwrap().clone();
    assert_eq!(assigned.len(), 1, "one outfit for the figure");
    assert_ne!(
        assigned[0].0, created_outfits[0],
        "the outfit id must not be the piece id — they are different aggregates"
    );
    assert_eq!(
        assigned[0].1,
        fixture.characters.created.lock().unwrap()[0].id,
        "the outfit must bind to the figure created from the same row"
    );
}

/// Tasks 3.2 + 3.5: one figure per name across the whole preview, and a second
/// apply of the same preview creates neither a duplicate figure nor a duplicate
/// costume.
#[tokio::test]
async fn script_apply_creates_one_figure_per_name_and_re_applies_without_duplicates() {
    let fixture = ScriptApplyFixture::new();
    // The same figure named by two different draft rows, in three different
    // spellings — the case that made a per-row key useless (the live import
    // produced 268 character mentions over 131 scenes).
    let preview = ScriptContext {
        scenes: vec![
            row_with_outfit(
                "1. INT. OP",
                &["RENEE SANDERS"],
                &[("Renee Sanders", "Ölverschmierter Overall")],
            ),
            row_with_outfit(
                "2. A/T - VOR KLINIK",
                &[" renee sanders "],
                &[("RENEE SANDERS", "Kasack")],
            ),
        ],
        ..Default::default()
    };
    let decisions = [
        create_decision("1. INT. OP"),
        create_decision("2. A/T - VOR KLINIK"),
    ];

    let first = fixture.apply(&preview, &decisions).await.unwrap();
    assert_eq!(first.created_characters, 1, "one figure for two mentions");
    assert_eq!(first.created_outfits, 2, "both outfits applied");
    assert_eq!(first.created_pieces, 2, "both derived pieces applied");
    assert_eq!(fixture.characters.created.lock().unwrap().len(), 1);
    assert_eq!(fixture.wardrobe.created.lock().unwrap().len(), 2);
    // Two rows, two looks of the *same* figure: an outfit is per draft row
    // (keyed by `(draft_ref, 'outfit', ordinal)`), so the figure ends up with
    // two distinct outfits and still one aggregate.
    let bound: Vec<Uuid> = fixture
        .wardrobe
        .assigned
        .lock()
        .unwrap()
        .iter()
        .map(|(_, character)| *character)
        .collect();
    assert_eq!(bound.len(), 2, "one outfit per draft row");
    assert_eq!(
        bound[0],
        fixture.characters.created.lock().unwrap()[0].id,
        "the outfit belongs to the figure, not to one scene"
    );

    // Re-apply: every row is already mapped, so nothing dispatches again.
    let again = fixture.apply(&preview, &decisions).await.unwrap();
    assert_eq!(again.applied.len(), 2, "the rows are still reported");
    assert_eq!(again.created_characters, 0);
    assert_eq!(again.created_outfits, 0);
    assert!(again.unapplied_outfits.is_empty());
    assert_eq!(
        fixture.characters.created.lock().unwrap().len(),
        1,
        "no duplicate figure"
    );
    assert_eq!(
        fixture.wardrobe.created.lock().unwrap().len(),
        2,
        "no duplicate costume"
    );
    assert_eq!(
        fixture.scenes.created.lock().unwrap().len(),
        2,
        "no duplicate scene either"
    );
}

/// Task 3.6: a figure that cannot be created must not leave an unbindable
/// costume behind — the costumes report why they are missing.
#[tokio::test]
async fn script_apply_reports_costumes_whose_figure_could_not_be_created() {
    let fixture = ScriptApplyFixture::new();
    fixture
        .characters
        .fail_with
        .lock()
        .unwrap()
        .replace(DomainError::validation("simulated character rejection"));
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            &[("Ben", "Marineblau"), ("Ben", "Silberkette")],
        )],
        ..Default::default()
    };
    let result = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();

    assert!(
        fixture.wardrobe.created.lock().unwrap().is_empty(),
        "a costume with no figure must never be created"
    );
    assert_eq!(result.unapplied_outfits.len(), 2);
    assert!(result.unapplied_outfits.iter().all(|costume| {
        costume.reason == UnappliedOutfitReason::CharacterUnavailable
            && costume.detail.as_deref() == Some("validation failed: simulated character rejection")
    }));
    // The scene of that row still applied — one bad figure is not a failed row.
    assert_eq!(result.applied.len(), 1);
    // And the refusal is not retried once per costume.
    assert_eq!(fixture.characters.created.lock().unwrap().len(), 0);
}

/// Spec `costume-character-binding`, "Binding fails after the costume was
/// created": the costume stays created and unassigned, the row is reported as
/// partially applied with the reason, and the retry **reuses the same costume
/// id** instead of appending a second one.
/// Design D8's crash window for the NOTES step: a crash between the successful
/// `UpdateCostumeNotes` append and its mapping confirm leaves the costume stream
/// at version 2 while the mapping still records version 1. The retry therefore
/// re-dispatches the notes command with a stale version, and the aggregate
/// refuses it with `VersionConflict`. Without folding that conflict through
/// `recover_version` (as the create and bind steps already do) the row ended as
/// `notes_rejected` on EVERY retry and the costume was never bound — a costume
/// created by the apply but permanently stuck one step short.
#[tokio::test]
async fn script_apply_recovers_when_only_the_notes_confirm_crashed() {
    let fixture = ScriptApplyFixture::new();
    // Insert order for one scene + one figure + one piece + one outfit:
    // #1 scene confirm, #2 figure confirm, #3 piece-create confirm, #4
    // outfit-create confirm, #5 OUTFIT-NOTES confirm. Failing #5 is precisely
    // the window: the notes command has already appended.
    fixture.mappings.fail_nth_insert(5);

    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            &[("Ben", "Marineblau")],
        )],
        ..Default::default()
    };
    let decisions = [create_decision("1. INT. OP")];
    let error = fixture
        .apply(&preview, &decisions)
        .await
        .expect_err("the notes confirm must fail");
    assert!(matches!(error, DomainError::ServiceUnavailable { .. }));

    // The notes DID reach the aggregate, but the mapping never recorded it.
    assert_eq!(fixture.wardrobe.notes.lock().unwrap().len(), 1);
    let outfit_mapping = fixture
        .mappings
        .find(fixture.preview_id, "1. INT. OP", mapping_kind::OUTFIT, 0)
        .await
        .unwrap()
        .expect("outfit mapping row");
    assert_eq!(
        outfit_mapping.aggregate_version,
        version(1),
        "the failed confirm must leave the phase record at create"
    );

    // Retry: the stale notes dispatch is refused, that refusal proves our own
    // earlier append, so the chain must continue to the binding instead of
    // reporting the row as unapplied.
    let second = fixture.apply(&preview, &decisions).await.unwrap();
    assert!(
        second.unapplied_outfits.is_empty(),
        "the retry must finish the chain, got {:?}",
        second.unapplied_outfits
    );
    assert_eq!(
        fixture.wardrobe.created.lock().unwrap().len(),
        1,
        "the retry must not create a second piece"
    );
    assert_eq!(
        fixture.wardrobe.assigned.lock().unwrap().len(),
        1,
        "the outfit must be created on the retry"
    );
    assert_eq!(
        fixture
            .mappings
            .find(fixture.preview_id, "1. INT. OP", mapping_kind::OUTFIT, 0)
            .await
            .unwrap()
            .expect("outfit mapping row")
            .aggregate_version,
        version(2),
        "create + notes, exactly one version per phase (the outfit lives on its own stream)"
    );
}

/// CR-002/D2: an archived target season refuses only the AI **outfit** step.
///
/// Steps 1 and 2 (create the piece, write the extracted description) run before
/// the gate and stay valid: the garment remains in the fundus, visible and
/// correctable, while the mapping row ends as `refused` (`BindingRejected`) and
/// no `OutfitCreated` is appended. The eight manual outfit routes answer 409
/// `season.archived` for the same invariant (issue #533: the archive is the
/// terminal lifecycle state).
#[tokio::test]
async fn script_apply_refuses_the_outfit_step_of_an_archived_season() {
    let mut fixture = ScriptApplyFixture::new();
    fixture.seasons = Arc::new(FakeSeasonRepo::archived());
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            &[("Ben", "Marineblau")],
        )],
        ..Default::default()
    };
    let decisions = [create_decision("1. INT. OP")];
    let applied = fixture.apply(&preview, &decisions).await.unwrap();

    // The piece step is NOT blocked by the archived season.
    assert_eq!(applied.created_pieces, 1, "the piece entered the fundus");
    assert_eq!(
        fixture.wardrobe.created.lock().unwrap().len(),
        1,
        "the piece must still be created in the fundus"
    );
    assert!(
        fixture.wardrobe.notes.lock().unwrap().is_empty(),
        "the outfit cannot carry notes: it was never created"
    );
    assert_eq!(
        applied.created_outfits, 0,
        "no outfit may be counted in an archived season"
    );
    assert!(
        fixture.wardrobe.assigned.lock().unwrap().is_empty(),
        "no outfit may be created in an archived season"
    );
    assert_eq!(applied.unapplied_outfits.len(), 1);
    assert_eq!(
        applied.unapplied_outfits[0].reason,
        UnappliedOutfitReason::BindingRejected
    );
    // The piece stream is complete: create + notes, exactly one event per phase.
    let mapping = fixture
        .mappings
        .find(fixture.preview_id, "1. INT. OP", mapping_kind::OUTFIT, 0)
        .await
        .unwrap()
        .expect("outfit mapping row");
    assert_eq!(
        mapping.aggregate_version,
        version(0),
        "the refused step never confirmed: the row stays reserved"
    );
}

/// CodeRabbit (PR #744): the outfit recovery loop dispatched every
/// `AddPieceToOutfit` at the SAME stale `current` version, so the second call
/// conflicted, was logged and swallowed — that piece never reached the look —
/// and the mapping then confirmed the stale version, which also lost the notes.
#[tokio::test]
async fn outfit_recovery_adds_every_missing_piece_at_the_advancing_version() {
    let fixture = ScriptApplyFixture::new();
    *fixture.wardrobe.lose_outfit_pieces_once.lock().unwrap() = true;
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".to_owned(),
            scene_number: Some(1),
            characters: vec![DraftCharacter::from("ANKE")],
            outfits: vec![
                breakdown_core::ai::DraftOutfit {
                    character_name: "ANKE".to_owned(),
                    name: "OP".to_owned(),
                    notes: Some("Kasack und Hose in OP-Grün".to_owned()),
                    source_quote: "in OP".to_owned(),
                    ..Default::default()
                }
                .with_pieces(&[("OP-Kasack", None), ("OP-Hose", None)]),
            ],
            ..Default::default()
        }],
        ..Default::default()
    };
    let result = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();

    assert!(
        result.unapplied_outfits.is_empty(),
        "{:?}",
        result.unapplied_outfits
    );
    let adds = fixture
        .steps()
        .into_iter()
        .filter(|step| step.starts_with("outfit:add_piece:"))
        .count();
    assert_eq!(
        adds, 2,
        "every missing piece must be re-added on the recovery path"
    );
    // The notes step must still run: the stale version would have dropped it.
    assert_eq!(
        fixture.wardrobe.notes.lock().unwrap().len(),
        1,
        "the recovered version must carry the notes step"
    );
}

/// CR-002/D2: a season lookup **outage** is not a refusal — it fails the apply
/// so the retry re-drives the unfinished rows instead of ending the mapping row
/// permanently.
#[tokio::test]
async fn script_apply_fails_the_apply_when_the_season_lookup_is_an_outage() {
    let fixture = ScriptApplyFixture::new();
    fixture
        .seasons
        .failure
        .lock()
        .unwrap()
        .replace(DomainError::service_unavailable(
            "season projection offline",
        ));
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            &[("Ben", "Marineblau")],
        )],
        ..Default::default()
    };
    let decisions = [create_decision("1. INT. OP")];
    let error = fixture.apply(&preview, &decisions).await;

    assert!(
        matches!(error, Err(DomainError::ServiceUnavailable { .. })),
        "an outage must fail the apply, got {error:?}"
    );
}

#[tokio::test]
async fn script_apply_reuses_the_piece_id_when_only_the_outfit_create_failed() {
    let fixture = ScriptApplyFixture::new();
    fixture
        .wardrobe
        .fail_assign_with
        .lock()
        .unwrap()
        .replace(DomainError::validation("simulated binding rejection"));
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            &[("Ben", "Marineblau")],
        )],
        ..Default::default()
    };
    let decisions = [create_decision("1. INT. OP")];
    let first = fixture.apply(&preview, &decisions).await.unwrap();

    assert_eq!(first.created_pieces, 1, "the piece exists");
    assert_eq!(first.created_outfits, 0, "the outfit was refused");
    assert!(fixture.wardrobe.assigned.lock().unwrap().is_empty());
    assert_eq!(first.unapplied_outfits.len(), 1);
    assert_eq!(
        first.unapplied_outfits[0].reason,
        UnappliedOutfitReason::CreateRejected
    );
    // The outfit's mapping row stayed a reservation: the refused step never
    // confirmed a version.
    let mapping = fixture
        .mappings
        .find(fixture.preview_id, "1. INT. OP", mapping_kind::OUTFIT, 0)
        .await
        .unwrap()
        .expect("outfit mapping row");
    assert_eq!(mapping.aggregate_version, version(0));

    // Retry with the binding allowed again: same id, now bound, no second
    // costume.
    let second = fixture.apply(&preview, &decisions).await.unwrap();
    assert!(
        second.unapplied_outfits.is_empty(),
        "{:?}",
        second.unapplied_outfits
    );
    assert_eq!(
        second.created_outfits, 1,
        "the retry creates the outfit the refusal blocked"
    );
    assert_eq!(
        fixture.wardrobe.created.lock().unwrap().len(),
        1,
        "the reserved piece id was reused"
    );
    let assigned = fixture.wardrobe.assigned.lock().unwrap().clone();
    assert_eq!(assigned.len(), 1, "the retry creates the outfit once");
    assert_eq!(
        fixture
            .mappings
            .find(fixture.preview_id, "1. INT. OP", mapping_kind::OUTFIT, 0)
            .await
            .unwrap()
            .unwrap()
            .aggregate_version,
        version(2),
        "create + notes (the outfit is a separate stream)"
    );
}

/// Design D7: the extracted garment description is what the import exists to
/// capture, so it must survive into the domain — and the binding must carry the
/// version the notes step left behind, not the one create returned.
#[tokio::test]
async fn script_apply_writes_the_description_as_notes_and_binds_at_that_version() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &[" BEN "],
            &[("ben", "  ölverschmierter Mechaniker-Overall  ")],
        )],
        ..Default::default()
    };
    let result = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();
    assert!(result.unapplied_outfits.is_empty());

    // Verbatim name form, untouched by the case-insensitive identity match.
    let created = fixture.characters.created.lock().unwrap().clone();
    assert_eq!(created.len(), 1);
    assert_eq!(created[0].name, " BEN ");
    assert_eq!(created[0].season_id, fixture.season_id);

    let notes = fixture.wardrobe.notes.lock().unwrap().clone();
    assert_eq!(notes.len(), 1);
    // The planner trims the plan fields; the wording itself is verbatim.
    assert_eq!(notes[0].1, "ölverschmierter Mechaniker-Overall");

    // The piece stream is one event (create): the extracted wording lives on
    // the outfit's notes, and the character binding is the outfit's too.
    let id = fixture.wardrobe.created.lock().unwrap()[0];
    assert_eq!(fixture.wardrobe.version_of(&id), Some(version(1)));
    assert_eq!(
        fixture
            .mappings
            .find(fixture.preview_id, "1. INT. OP", mapping_kind::OUTFIT, 0)
            .await
            .unwrap()
            .unwrap()
            .aggregate_version,
        version(2)
    );
    // Group 4: the figure's row is keyed by its identity, not by the scene row.
    let figure = fixture
        .mappings
        .find(
            fixture.preview_id,
            &character_mapping_ref(&character_identity(" BEN ")),
            mapping_kind::CHARACTER,
            PRIMARY_ORDINAL,
        )
        .await
        .unwrap()
        .expect("figure mapping row keyed by identity");
    assert_eq!(figure.aggregate_id, created[0].id);
}

/// A rejected costume row is not applied, and its scene and figures still are
/// (spec: the reviewer decides each costume row independently).
#[tokio::test]
async fn script_apply_skips_a_rejected_costume_row_without_failing_the_scene() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            &[("Ben", "Marineblau"), ("Ben", "Silberkette")],
        )],
        ..Default::default()
    };
    let mut decision = create_decision("1. INT. OP");
    decision.outfit_decisions = vec![OutfitDecision {
        ordinal: 0,
        accepted: false,
    }];
    let result = fixture.apply(&preview, &[decision]).await.unwrap();

    assert_eq!(result.applied.len(), 1, "the scene applied");
    assert_eq!(result.created_characters, 1, "the figure applied");
    assert_eq!(result.created_outfits, 1, "only the accepted costume");
    assert_eq!(fixture.wardrobe.notes.lock().unwrap().len(), 1);
    // The rejected row is not recorded as an unapplied failure — the reviewer
    // chose it.
    assert!(result.unapplied_outfits.is_empty());
    // The rejected costume's mapping row was never written, so a later apply that
    // accepts it can still create it.
    assert!(
        fixture
            .mappings
            .find(fixture.preview_id, "1. INT. OP", mapping_kind::OUTFIT, 0)
            .await
            .unwrap()
            .is_none()
    );
}

/// The outfit/piece split: a look extracted from a shorthand carries derived
/// garments, each created with the category its hint resolved to.
#[tokio::test]
async fn script_apply_creates_each_piece_with_its_resolved_category() {
    use breakdown_core::shared::CostumeCategoryId;

    let fixture = ScriptApplyFixture::new();
    let top = CostumeCategoryId::new();
    let bottom = CostumeCategoryId::new();
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".to_owned(),
            scene_number: Some(1),
            characters: vec![DraftCharacter::from("ANKE")],
            outfits: vec![
                breakdown_core::ai::DraftOutfit {
                    character_name: "ANKE".to_owned(),
                    name: "OP".to_owned(),
                    notes: None,
                    source_quote: "in OP".to_owned(),
                    ..Default::default()
                }
                .with_pieces(&[
                    ("OP-Kasack", Some("Oberteil")),
                    ("OP-Hose", Some("Unterteil")),
                ]),
            ],
            ..Default::default()
        }],
        ..Default::default()
    };
    let categories = vec![
        breakdown_core::ai::CategoryVocabularyEntry {
            name: "Oberteil".to_owned(),
            id: top,
        },
        breakdown_core::ai::CategoryVocabularyEntry {
            name: "Unterteil".to_owned(),
            id: bottom,
        },
    ];
    let result = fixture
        .apply_with_categories(&preview, &[create_decision("1. INT. OP")], categories)
        .await
        .unwrap();

    assert_eq!(result.created_pieces, 2, "both derived garments created");
    assert_eq!(result.created_outfits, 1, "one look");
    assert_eq!(result.unapplied_outfits.len(), 0);
    let resolved: Vec<_> = fixture.wardrobe.categories.lock().unwrap().clone();
    assert_eq!(
        resolved.iter().map(|(_, id)| *id).collect::<Vec<_>>(),
        vec![Some(top), Some(bottom)],
        "each hint set its own category on its own piece"
    );
    // Row-flat piece ordinals: the two garments of the row are rows 0 and 1.
    for ordinal in [0, 1] {
        assert!(
            fixture
                .mappings
                .find(
                    fixture.preview_id,
                    "1. INT. OP",
                    mapping_kind::PIECE,
                    ordinal
                )
                .await
                .unwrap()
                .is_some(),
            "piece mapping row {ordinal} must exist"
        );
    }
}

/// Two outfits of one row keep distinct piece rows: the piece ordinal is
/// row-flat, so the same garment name on two figures never collapses.
#[tokio::test]
async fn script_apply_numbers_piece_rows_row_flat_across_one_rows_outfits() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".to_owned(),
            scene_number: Some(1),
            characters: vec![DraftCharacter::from("BEN"), DraftCharacter::from("ANKE")],
            outfits: vec![
                breakdown_core::ai::DraftOutfit {
                    character_name: "BEN".to_owned(),
                    name: "OP".to_owned(),
                    source_quote: "in OP".to_owned(),
                    ..Default::default()
                }
                .with_pieces(&[("OP-Schuhe", None)]),
                breakdown_core::ai::DraftOutfit {
                    character_name: "ANKE".to_owned(),
                    name: "OP".to_owned(),
                    source_quote: "in OP".to_owned(),
                    ..Default::default()
                }
                .with_pieces(&[("OP-Schuhe", None)]),
            ],
            ..Default::default()
        }],
        ..Default::default()
    };
    let result = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();

    assert_eq!(result.created_pieces, 2, "two figures, two fundus pieces");
    assert_eq!(result.created_outfits, 2);
    let mut ids = Vec::new();
    for ordinal in [0, 1] {
        let row = fixture
            .mappings
            .find(
                fixture.preview_id,
                "1. INT. OP",
                mapping_kind::PIECE,
                ordinal,
            )
            .await
            .unwrap()
            .unwrap_or_else(|| panic!("piece mapping row {ordinal} must exist"));
        ids.push(row.aggregate_id);
    }
    assert_ne!(
        ids[0], ids[1],
        "the same garment name on two figures stays two pieces"
    );
}

/// An outage is not a per-row outcome: it must fail the whole apply so the job
/// is retried instead of silently leaving rows unwritten.
#[tokio::test]
async fn script_apply_propagates_an_infra_outage_instead_of_reporting_a_row() {
    let fixture = ScriptApplyFixture::new();
    fixture
        .characters
        .fail_with
        .lock()
        .unwrap()
        .replace(DomainError::service_unavailable("event store down"));
    let preview = ScriptContext {
        scenes: vec![row_with_outfit("1. INT. OP", &["BEN"], &[])],
        ..Default::default()
    };
    let error = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .expect_err("an outage must fail the apply");
    assert!(
        matches!(error, DomainError::ServiceUnavailable { .. }),
        "got {error:?}"
    );
    // The reservation survives, so the retry drives the same figure id.
    let figure = fixture
        .mappings
        .find(
            fixture.preview_id,
            &character_mapping_ref("ben"),
            mapping_kind::CHARACTER,
            PRIMARY_ORDINAL,
        )
        .await
        .unwrap()
        .expect("reservation persisted");
    assert!(figure.is_reserved(), "the row must stay a reservation");
    let id = figure.aggregate_id;
    let result = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();
    assert_eq!(result.created_characters, 1);
    assert_eq!(
        fixture.characters.created.lock().unwrap()[0].id,
        id,
        "the retry must land on the reserved id"
    );
}

// ===========================================================================
// Provider contract: the grounding check runs in the extraction worker
// (openspec: ai-import-character-costumes, group 5)
// ===========================================================================

/// A client that answers with costumes of the reviewer's own choosing, so the
/// worker's server-side grounding check can be tested against a *returned*
/// entry rather than only against the pure helper.
#[derive(Clone)]
struct OutfitClient {
    outfits: Vec<breakdown_core::ai::DraftOutfit>,
}

#[async_trait]
impl LlmClient for OutfitClient {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        Ok(LlmCallOutcome::new(
            ScriptContext {
                title: Some("fixture".to_owned()),
                scenes: vec![DraftScene {
                    draft_ref: String::new(),
                    scene_number: Some(1),
                    characters: vec![breakdown_core::ai::DraftCharacter {
                        name: "RENEE".to_owned(),
                        category: Default::default(),
                    }],
                    outfits: self.outfits.clone(),
                    ..Default::default()
                }],
                uncertainties: Vec::new(),
            },
            LlmCallUsage::default(),
        ))
    }
}

/// Task 5.2/5.3: a costume the model was not told about never reaches the
/// reviewer, and the row it came from is recorded as an uncertainty.
#[tokio::test]
async fn extraction_drops_an_ungrounded_costume_and_records_an_uncertainty() {
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let worker: ScriptImportWorker<FakeQueue, OutfitClient> = ScriptImportWorker {
        queue: Arc::clone(&queue),
        client: Arc::new(OutfitClient {
            outfits: vec![
                // Quoted from the block: survives.
                breakdown_core::ai::DraftOutfit {
                    character_name: "renee".to_owned(),
                    name: "Mechaniker-Overall".to_owned(),
                    notes: Some("Ölverschmierter Overall".to_owned()),
                    source_quote: "ölverschmierten Mechaniker-Overall".to_owned(),
                    ..Default::default()
                },
                // Nowhere in the block: the prompt forbade it, the server checks.
                breakdown_core::ai::DraftOutfit {
                    character_name: "renee".to_owned(),
                    name: "Seidenkleid".to_owned(),
                    notes: Some("Seidenkleid".to_owned()),
                    source_quote: "in einem langen Seidenkleid aus Seide".to_owned(),
                    ..Default::default()
                },
            ],
        }),
        previews: Arc::clone(&previews) as Arc<dyn AiPreviewStore>,
        extractor: super::PdfTextExtractor::new(1024 * 1024, std::time::Duration::from_secs(5)),
        provider: LlmProvider::Ollama,
        model: "fixture".to_owned(),
        prompt: "fixture".to_owned(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: None,
    };
    let job = script_job(AiImportJobId::new());
    let handle = worker
        .process_text(&job, "test-worker", "I/T - OP RAUM 2\nRENEE (39) steigt aus dem Auto, trägt einen leicht ölverschmierten Mechaniker-Overall.")
        .await
        .unwrap();
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ScriptContext = serde_json::from_slice(&payload).unwrap();

    assert_eq!(preview.scenes.len(), 1);
    assert_eq!(
        preview.scenes[0].outfits.len(),
        1,
        "only the grounded costume may survive: {:?}",
        preview.scenes[0].outfits
    );
    assert_eq!(
        preview.scenes[0].outfits[0].notes.as_deref(),
        Some("Ölverschmierter Overall")
    );
    // The dropped one is visible as missing, and does NOT block the apply.
    assert_eq!(preview.uncertainties.len(), 1);
    let uncertainty = &preview.uncertainties[0];
    assert_eq!(uncertainty.field, "outfits");
    assert_eq!(uncertainty.kind, UncertaintyKind::DroppedRow);
    // The drop belongs to the ONLY scene in this preview, and `scene_index` is a
    // 0-based index into `scenes` — a 1-based value here would address a row that
    // does not exist and show the missing costume on the wrong scene.
    assert_eq!(uncertainty.scene_index, 0);
    assert_eq!(uncertainty.suggested_value.as_deref(), Some("Seidenkleid"));
    assert!(
        uncertainty.note.contains("ungrounded_quote"),
        "the note must carry the stable reason slug: {}",
        uncertainty.note
    );
    assert!(breakdown_core::ai::ensure_script_applyable(&preview, &[]).is_ok());
}

// ── Scene-relation persistence (issue #546 §5.8) ────────────────────────────

/// Pinned worker chain arithmetic: `CreateScene → AssignCharacter×n →
/// AddCostumeBeat×m` hangs exactly ONE event per step, and the mapping rows
/// record the scene-stream version after every confirmed beat — the phase
/// record a crashed apply re-drives from. (The aggregate-side arithmetic is
/// pinned in `test_ai_scene_chain_advances_exactly_one_version_per_step`.)
#[tokio::test]
async fn scene_apply_chain_appends_exactly_one_event_per_step() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN", "RENEE"],
            &[("Ben", "ölverschmierter Overall"), ("Renee", "Kasack")],
        )],
        ..Default::default()
    };
    let result = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();

    let scene_id = result.applied[0].aggregate_id;
    let steps = fixture.steps();
    let assigns: Vec<usize> = steps
        .iter()
        .enumerate()
        .filter(|(_, step)| step.starts_with("scene:assign:"))
        .map(|(index, _)| index)
        .collect();
    let beats: Vec<usize> = steps
        .iter()
        .enumerate()
        .filter(|(_, step)| step.starts_with("scene:beat:"))
        .map(|(index, _)| index)
        .collect();
    assert_eq!(assigns.len(), 2, "one assign per figure: {steps:?}");
    assert_eq!(beats.len(), 2, "one beat per outfit: {steps:?}");
    assert_eq!(steps[0], "scene:create");
    assert_eq!(
        steps.iter().filter(|s| s.starts_with("character:")).count(),
        2,
        "one created figure per row name"
    );
    // Assigns come strictly before any beat (invariant I1).
    assert!(
        assigns
            .iter()
            .all(|assign| beats.iter().all(|beat| assign < beat)),
        "every AssignCharacter must precede every AddOutfitBeat: {steps:?}"
    );
    assert_eq!(fixture.scene_beats(scene_id).len(), 2);

    // The mapping rows record the phase versions: create = INITIAL(1),
    // assign ben = 2, assign renee = 3, beat ben = 4, beat renee = 5.
    assert_eq!(result.applied[0].version, version(1));
    let ben_beat = fixture.beat_mapping("ben", 0).await.expect("ben beat row");
    assert!(!ben_beat.is_reserved());
    assert_eq!(ben_beat.aggregate_id, scene_id);
    assert_eq!(ben_beat.aggregate_version, version(4));
    let renee_beat = fixture
        .beat_mapping("renee", 0)
        .await
        .expect("renee beat row");
    assert_eq!(renee_beat.aggregate_version, version(5));
    assert_eq!(fixture.scene_version_of(scene_id), version(5));
    assert_eq!(result.created_outfit_beats, 2);
}

/// Re-applying a fully applied preview adds no second beat: the confirmed
/// `scene_costume_beat` rows skip the dispatch entirely.
#[tokio::test]
async fn scene_beat_re_apply_adds_no_second_beat() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            &[("Ben", "ölverschmierter Overall")],
        )],
        ..Default::default()
    };
    let first = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();
    let scene_id = first.applied[0].aggregate_id;
    assert_eq!(first.created_outfit_beats, 1);

    let second = fixture.apply(&preview, &[]).await.unwrap();
    assert_eq!(
        second.created_outfit_beats, 0,
        "a re-apply must not add a second beat"
    );
    assert_eq!(
        fixture.scene_beats(scene_id).len(),
        1,
        "the scene must not carry a duplicate beat"
    );
    assert_eq!(
        fixture
            .steps()
            .iter()
            .filter(|step| step.starts_with("scene:beat:"))
            .count(),
        1,
        "only the first apply may dispatch the beat"
    );
    let beat = fixture.beat_mapping("ben", 0).await.unwrap();
    assert!(!beat.is_reserved());
    assert_eq!(beat.aggregate_version, version(3));
}

/// Crash recovery: the confirm of ben's beat fails after the event appended.
/// The retry re-drives exactly the steps above the stored versions — renee's
/// figure lane — and settles ben's beat WITHOUT appending it a second time
/// (the identical-last guard is the aggregate's own fence against the
/// crash-window replay).
#[tokio::test]
async fn scene_beat_crash_between_steps_resumes_at_the_right_phase() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN", "RENEE"],
            &[("Ben", "Overall"), ("Renee", "Kasack")],
        )],
        ..Default::default()
    };
    // Inserts 1–6 are the scene/character/costume confirms of the first two
    // lanes; #7 is the confirm of ben's beat — crash right there.
    fixture.mappings.fail_nth_insert(7);
    let error = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .expect_err("the beat confirm must fail the apply");
    assert!(matches!(error, DomainError::ServiceUnavailable { .. }));

    let scene_id = fixture.scenes.created.lock().unwrap()[0];
    assert_eq!(
        fixture.scene_beats(scene_id).len(),
        1,
        "ben's beat DID append before the confirm crashed"
    );

    fixture
        .apply(&preview, &[])
        .await
        .expect("the retry must converge");

    // Exactly one beat per figure — ben's replayed dispatch was settled by
    // the identical-last guard, renee's lane was re-driven from its mapping.
    let scene_id = fixture.scenes.created.lock().unwrap()[0];
    assert_eq!(fixture.scene_beats(scene_id).len(), 2);
    assert_eq!(
        fixture
            .steps()
            .iter()
            .filter(|step| step.starts_with("scene:beat:"))
            .count(),
        2,
        "the retry must not append ben's beat twice"
    );
    let ben_beat = fixture.beat_mapping("ben", 0).await.unwrap();
    assert!(!ben_beat.is_reserved());
    assert_eq!(ben_beat.aggregate_version, version(4));
    let renee_beat = fixture.beat_mapping("renee", 0).await.unwrap();
    assert!(!renee_beat.is_reserved());
    assert_eq!(renee_beat.aggregate_version, version(5));
    assert_eq!(fixture.scene_version_of(scene_id), version(5));
}

/// The reviewer report distinguishes a costume dropped as ungrounded (never
/// created) from a costume whose scene beat was refused (created, bound, but
/// the scene relation is missing) — the two must never look identical.
#[tokio::test]
async fn a_refused_beat_is_reported_distinctly_from_the_ungrounded_drop() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_outfit(
            "1. INT. OP",
            &["BEN"],
            // "Ghost" names no figure of the row: dropped at plan time.
            &[("Ben", "Overall"), ("Ghost", "Nebelkulisse")],
        )],
        ..Default::default()
    };
    // Simulate a concurrent manual edit: the beat dispatch is refused.
    *fixture.scenes.fail_beat_with.lock().unwrap() = Some(DomainError::Validation {
        code: &breakdown_core::error_registry::SCENE_CHARACTER_NOT_IN_SCENE,
        reason: "character was removed from the scene".to_owned(),
    });

    let result = fixture
        .apply(&preview, &[create_decision("1. INT. OP")])
        .await
        .unwrap();

    let refused: Vec<_> = result
        .unapplied_outfits
        .iter()
        .filter(|entry| entry.reason == UnappliedOutfitReason::BeatRejected)
        .collect();
    let dropped: Vec<_> = result
        .unapplied_outfits
        .iter()
        .filter(|entry| entry.reason == UnappliedOutfitReason::CharacterNotPlanned)
        .collect();
    assert_eq!(
        refused.len(),
        1,
        "the grounded costume whose beat was refused must be reported as BeatRejected: {:?}",
        result.unapplied_outfits
    );
    assert_eq!(refused[0].name, "Overall");
    assert_eq!(
        dropped.len(),
        1,
        "the ungrounded costume must stay the plan-time drop"
    );
    assert_eq!(dropped[0].name, "Nebelkulisse");
    // The refused costume itself exists and is bound — only the scene
    // relation is missing, and no beat was appended.
    assert_eq!(fixture.wardrobe.assigned.lock().unwrap().len(), 1);
    assert!(
        fixture
            .scene_beats(fixture.scenes.created.lock().unwrap()[0])
            .is_empty()
    );
    assert_eq!(result.created_outfit_beats, 0);
}

// ===========================================================================
// Script apply — episode groups (issue #581)
// ===========================================================================

/// A draft row carrying episode metadata, as the `Ep.:` scan produces it.
fn row_with_episode(draft_ref: &str, episode: DraftEpisode) -> DraftScene {
    DraftScene {
        draft_ref: draft_ref.to_owned(),
        scene_number: Some(1),
        episode: Some(episode),
        ..Default::default()
    }
}

fn create_group(ref_name: &str, number: i32) -> EpisodeGroupPlan {
    EpisodeGroupPlan {
        episode_ref: ref_name.to_owned(),
        target: EpisodeTarget::Create {
            number,
            name: Some(format!("Episode {number}")),
        },
    }
}

#[tokio::test]
async fn script_apply_scene_lands_in_the_created_episode() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_episode(
            "1. INT. OP",
            DraftEpisode {
                number: Some(3),
                title: None,
            },
        )],
        ..Default::default()
    };
    fixture
        .apply_with_groups(
            &preview,
            &[create_decision("1. INT. OP")],
            vec![create_group("ep:3", 3)],
        )
        .await
        .expect("apply");
    let episode_id = fixture.episodes.created.lock().unwrap()[0].id;
    // The row's scene was created in the episode the apply created. The
    // guards are scoped so no std Mutex lock is held across the mapping
    // `await` below (`await_holding_lock`).
    let (scene_count, scene_episode_id) = {
        let created_scenes = fixture.scenes.created_commands.lock().unwrap();
        (created_scenes.len(), created_scenes[0].episode_id)
    };
    assert_eq!(scene_count, 1);
    assert_eq!(
        scene_episode_id,
        breakdown_core::shared::EpisodeId::from_uuid(episode_id)
    );
    // The episode create happened BEFORE the scene create.
    let steps = fixture.steps();
    let episode_step = steps
        .iter()
        .position(|step| step.starts_with("episode:create"))
        .unwrap_or_else(|| panic!("journal: {steps:?}"));
    let scene_step = steps
        .iter()
        .position(|step| step.contains("scene:create"))
        .unwrap_or_else(|| panic!("journal: {steps:?}"));
    assert!(episode_step < scene_step, "journal: {steps:?}");
    // The episode mapping row is confirmed (version > 0), not a reservation.
    let mapping = fixture
        .mappings
        .find(
            fixture.preview_id,
            "ep:3",
            mapping_kind::EPISODE,
            PRIMARY_ORDINAL,
        )
        .await
        .unwrap()
        .expect("episode mapping row");
    assert_eq!(mapping.aggregate_id, episode_id);
    assert!(!mapping.is_reserved());
}

#[tokio::test]
async fn script_apply_two_rows_of_one_group_create_one_episode() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![
            row_with_episode(
                "1. INT. OP",
                DraftEpisode {
                    number: Some(3),
                    title: None,
                },
            ),
            row_with_episode(
                "2. INT. OP",
                DraftEpisode {
                    number: Some(3),
                    title: None,
                },
            ),
        ],
        ..Default::default()
    };
    let result = fixture
        .apply_with_groups(
            &preview,
            &[create_decision("1. INT. OP"), create_decision("2. INT. OP")],
            vec![create_group("ep:3", 3)],
        )
        .await
        .expect("apply");
    assert_eq!(result.applied.len(), 2);
    assert_eq!(result.created_episodes, 1);
    assert_eq!(fixture.episodes.created.lock().unwrap().len(), 1);
    // Both scenes were created (in distinct streams).
    assert_eq!(fixture.scenes.created.lock().unwrap().len(), 2);
}

#[tokio::test]
async fn script_apply_retry_does_not_recreate_the_episode() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_episode(
            "1. INT. OP",
            DraftEpisode {
                number: Some(3),
                title: None,
            },
        )],
        ..Default::default()
    };
    let decisions = vec![create_decision("1. INT. OP")];
    let groups = vec![create_group("ep:3", 3)];
    let first = fixture
        .apply_with_groups(&preview, &decisions, groups.clone())
        .await
        .expect("first apply");
    assert_eq!(first.created_episodes, 1);
    // Retry: the confirmed episode mapping short-circuits, the scene mapping
    // too — nothing is re-created.
    let second = fixture
        .apply_with_groups(&preview, &[], groups)
        .await
        .expect("retry");
    assert_eq!(second.created_episodes, 0);
    assert_eq!(fixture.episodes.created.lock().unwrap().len(), 1);
    assert_eq!(fixture.scenes.created.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn script_apply_rows_without_metadata_stay_in_the_picked_episode() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".to_owned(),
            scene_number: Some(1),
            ..Default::default()
        }],
        ..Default::default()
    };
    let result = fixture
        .apply_with_groups(&preview, &[create_decision("1. INT. OP")], Vec::new())
        .await
        .expect("apply");
    assert_eq!(result.created_episodes, 0);
    assert!(fixture.episodes.created.lock().unwrap().is_empty());
    assert_eq!(fixture.scenes.created.lock().unwrap().len(), 1);
}

// ===========================================================================
// Script apply — shooting days (issue #706)
// ===========================================================================

/// A draft row carrying shooting-day metadata, as the deterministic day scan
/// produces it.
fn row_with_day(draft_ref: &str, day: DraftShootingDay) -> DraftScene {
    DraftScene {
        draft_ref: draft_ref.to_owned(),
        scene_number: Some(1),
        shooting_day: Some(day),
        ..Default::default()
    }
}

fn accept_day(day_ref: &str) -> ShootingDayPlan {
    ShootingDayPlan {
        day_ref: day_ref.to_owned(),
        accepted: true,
    }
}

#[tokio::test]
async fn script_apply_creates_the_accepted_day_and_schedules_the_row() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_day(
            "1. INT. OP",
            DraftShootingDay {
                number: Some(1),
                label: Some("Tag 1".into()),
                score: None,
            },
        )],
        ..Default::default()
    };
    let result = fixture
        .apply_with_day_plans(
            &preview,
            &[create_decision("1. INT. OP")],
            Vec::new(),
            vec![accept_day("day:1")],
        )
        .await
        .expect("apply");
    assert_eq!(result.created_days, 1);
    assert_eq!(result.planned_scene_shoots, 1);
    // Exactly one day was created, with the verbatim first-occurrence label.
    let created_days = fixture.shooting_days.created.lock().unwrap().clone();
    assert_eq!(created_days.len(), 1);
    // The scene was linked onto the created day…
    let scheduled = fixture.scenes.scheduled.lock().unwrap().clone();
    assert_eq!(scheduled.len(), 1);
    assert_eq!(scheduled[0].1, created_days[0]);
    // …and the scene_shoot pair was planned.
    let planned = fixture.scene_shoots.planned.lock().unwrap().clone();
    assert_eq!(planned.len(), 1);
}

#[tokio::test]
async fn script_apply_shares_one_day_across_rows_of_the_same_group() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![
            row_with_day(
                "1. INT. OP",
                DraftShootingDay {
                    number: Some(1),
                    label: Some("Tag 1".into()),
                    score: None,
                },
            ),
            row_with_day(
                "2. INT. OP",
                DraftShootingDay {
                    number: Some(1),
                    label: Some("Tag 1".into()),
                    score: None,
                },
            ),
        ],
        ..Default::default()
    };
    let result = fixture
        .apply_with_day_plans(
            &preview,
            &[create_decision("1. INT. OP"), create_decision("2. INT. OP")],
            Vec::new(),
            vec![accept_day("day:1")],
        )
        .await
        .expect("apply");
    // One day per group — the second row reuses the resolved day.
    assert_eq!(result.created_days, 1);
    assert_eq!(result.planned_scene_shoots, 2);
    assert_eq!(fixture.shooting_days.created.lock().unwrap().len(), 1);
    assert_eq!(fixture.scenes.scheduled.lock().unwrap().len(), 2);
}

#[tokio::test]
async fn script_apply_leaves_a_rejected_day_group_unscheduled() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_day(
            "1. INT. OP",
            DraftShootingDay {
                number: Some(1),
                label: Some("Tag 1".into()),
                score: None,
            },
        )],
        ..Default::default()
    };
    let result = fixture
        .apply_with_day_plans(
            &preview,
            &[create_decision("1. INT. OP")],
            Vec::new(),
            vec![ShootingDayPlan {
                day_ref: "day:1".into(),
                accepted: false,
            }],
        )
        .await
        .expect("apply");
    assert_eq!(result.created_days, 0);
    assert_eq!(result.planned_scene_shoots, 0);
    assert!(fixture.shooting_days.created.lock().unwrap().is_empty());
    assert!(fixture.scenes.scheduled.lock().unwrap().is_empty());
    // The scene itself still applied.
    assert_eq!(fixture.scenes.created.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn script_apply_day_group_without_a_decision_is_a_registered_conflict() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_day(
            "1. INT. OP",
            DraftShootingDay {
                number: Some(1),
                label: Some("Tag 1".into()),
                score: None,
            },
        )],
        ..Default::default()
    };
    let error = fixture
        .apply_with_day_plans(
            &preview,
            &[create_decision("1. INT. OP")],
            Vec::new(),
            Vec::new(),
        )
        .await
        .expect_err("a referenced day group must not silently apply unscheduled");
    match error {
        DomainError::Conflict { code, .. } => {
            assert_eq!(
                code.code, "ai-import.apply-missing-shooting-day-group",
                "the gate answers its own registered code"
            );
        }
        other => panic!("expected Conflict, got {other:?}"),
    }
}

#[tokio::test]
async fn script_apply_day_is_idempotent_on_re_apply() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![row_with_day(
            "1. INT. OP",
            DraftShootingDay {
                number: Some(1),
                label: Some("Tag 1".into()),
                score: None,
            },
        )],
        ..Default::default()
    };
    let decisions = vec![create_decision("1. INT. OP")];
    let day_plans = vec![accept_day("day:1")];
    let first = fixture
        .apply_with_day_plans(&preview, &decisions, Vec::new(), day_plans.clone())
        .await
        .expect("first apply");
    let second = fixture
        .apply_with_day_plans(&preview, &decisions, Vec::new(), day_plans)
        .await
        .expect("re-apply");
    // Nothing is created or planned twice.
    assert_eq!(second.created_days, 0);
    assert_eq!(second.planned_scene_shoots, 0);
    assert_eq!(first.created_days, 1);
    assert_eq!(fixture.shooting_days.created.lock().unwrap().len(), 1);
    assert_eq!(fixture.scene_shoots.planned.lock().unwrap().len(), 1);
}

// ---------------------------------------------------------------------------
// Decision Model scoring pass (issue #722): chunk-signal alignment, the
// summary-less synopsis contract, and usage accumulation — driven through
// the real ScriptImportWorker with a scripted LLM and a recording client.
// ---------------------------------------------------------------------------

/// Records every decision request's `state` payload and answers the full
/// rubric with calibrated "yes"/top-score distributions.
#[derive(Clone, Default)]
struct RecordingDecisionClient {
    states: Arc<std::sync::Mutex<Vec<serde_json::Value>>>,
}

#[async_trait::async_trait]
impl DecisionClient for RecordingDecisionClient {
    async fn decide(&self, req: DecisionRequest) -> Result<DecisionCallOutcome, DomainError> {
        self.states.lock().unwrap().push(req.state.clone());
        let mut answers = std::collections::BTreeMap::new();
        for name in req.questions.keys() {
            answers.insert(
                name.clone(),
                DecisionAnswer {
                    noul: Some(0.9),
                    choice: None,
                    score: Some(vec![0.0, 0.0, 0.0, 0.0, 1.0]),
                },
            );
        }
        Ok(DecisionCallOutcome {
            answers,
            usage: LlmCallUsage {
                tokens_in: 11,
                tokens_out: 0,
                cached_tokens_in: 0,
                energy_millijoules: 5,
            },
        })
    }
}

/// Two scripted calls: the FIRST chunk's scene carries a meta summary
/// (the #668 guard rewrites it to `null`) and an ungrounded costume (the
/// grounding check drops it); the SECOND chunk's scene is clean.
#[derive(Clone, Default)]
struct TwoChunkScoringLlmClient;

#[async_trait::async_trait]
impl LlmClient for TwoChunkScoringLlmClient {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        // Call order is the chunk order: extract_scenes yields exactly two
        // chunks for the two-heading fixture below. This client is only used
        // by the two-chunk test.
        thread_local! {
            static CALL: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
        }
        let call = CALL.with(|c| c.get());
        CALL.with(|c| c.set(call + 1));
        let scene = if call == 0 {
            DraftScene {
                draft_ref: "chunk-1".to_owned(),
                scene_number: Some(1),
                mood: Some("I/T".into()),
                // Meta summary: `sanitize_meta_summary` rewrites it to null
                // and the synopsis score must degrade to the honest 0.0.
                summary: Some("Outline-style block with heading and day marker only.".to_owned()),
                characters: vec![DraftCharacter::from("BEN")],
                outfits: vec![DraftOutfit {
                    character_name: "BEN".to_owned(),
                    name: "Schutzhelm".to_owned(),
                    notes: Some("Schutzhelm".to_owned()),
                    // Never in the chunk text → dropped as ungrounded.
                    source_quote: "NICHT IM TEXT".to_owned(),
                    ..Default::default()
                }],
                ..Default::default()
            }
        } else {
            DraftScene {
                draft_ref: "chunk-2".to_owned(),
                scene_number: Some(2),
                mood: Some("I/T".into()),
                summary: Some("Ben repariert das Auto.".to_owned()),
                characters: vec![DraftCharacter::from("BEN")],
                outfits: Vec::new(),
                ..Default::default()
            }
        };
        Ok(LlmCallOutcome::new(
            ScriptContext {
                title: Some("fixture".to_owned()),
                scenes: vec![scene],
                uncertainties: Vec::new(),
            },
            LlmCallUsage::default(),
        ))
    }

    async fn extract_schedule(
        &self,
        _request: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ShootingSchedule>, DomainError> {
        Err(DomainError::validation(
            "TwoChunkScoringLlmClient only extracts scripts",
        ))
    }
}

fn scoring_worker(
    queue: Arc<FakeQueue>,
    previews: Arc<MemoryAiPreviewStore>,
    decision: Arc<super::DecisionPass>,
) -> ScriptImportWorker<FakeQueue, TwoChunkScoringLlmClient> {
    ScriptImportWorker {
        queue,
        client: Arc::new(TwoChunkScoringLlmClient),
        previews: previews as Arc<dyn AiPreviewStore>,
        extractor: super::PdfTextExtractor::new(1024 * 1024, std::time::Duration::from_secs(30)),
        provider: LlmProvider::Neuralwatt,
        model: "deepseek-v4-flash".to_owned(),
        prompt: "fixture prompt".to_owned(),
        bounds: AiImportBounds::default(),
        pricing: None,
        decision: Some(decision),
    }
}

#[tokio::test]
async fn scoring_receives_chunk_local_grounding_signals_and_honors_the_summary_contract() {
    let queue = Arc::new(FakeQueue::default());
    let previews = Arc::new(MemoryAiPreviewStore::default());
    let recorder = RecordingDecisionClient::default();
    let decision = Arc::new(super::DecisionPass {
        client: Arc::new(recorder.clone()),
        provider: LlmProvider::Neuralwatt,
        model: "clef-flash".to_owned(),
    });
    let worker = scoring_worker(Arc::clone(&queue), Arc::clone(&previews), decision);
    let job = script_job(AiImportJobId::new());
    // Two INT./EXT. headings → exactly two chunks, one scene each.
    let handle = worker
        .process_text(
            &job,
            "test-worker",
            "1. INT. WERKSTATT - TAG\nBen trägt einen Schutzhelm.\n\n2. INT. GARAGE - TAG\nBen repariert das Auto.",
        )
        .await
        .unwrap();

    let states: Vec<serde_json::Value> = recorder
        .states
        .lock()
        .unwrap()
        .clone()
        .into_iter()
        .filter(|state| state["kind"] == "script_chunk")
        .collect();
    assert_eq!(
        states.len(),
        2,
        "one single-pass decision request per chunk"
    );
    // Chunk 1's scene was scored with ITS OWN signals: the ungrounded
    // costume drop is visible and the summary is the REWRITTEN (null) one.
    let chunk1_scene = &states[0]["scenes"][0];
    assert_eq!(chunk1_scene["grounding"]["dropped_outfits"], 1);
    assert_eq!(chunk1_scene["grounding"]["scene_number_match"], true);
    assert!(chunk1_scene["summary"].is_null());
    // Chunk 2's scene must NOT inherit chunk 1's signals (the job-wide
    // vectors would have leaked dropped=1 and the sanitized flag here).
    let chunk2_scene = &states[1]["scenes"][0];
    assert_eq!(chunk2_scene["grounding"]["dropped_outfits"], 0);
    assert_eq!(chunk2_scene["summary"], "Ben repariert das Auto.");

    // Preview contract: the sanitized chunk-1 scene carries the honest 0.0;
    // the clean chunk-2 scene carries a computed score (NOT the None that a
    // summary-less row would get).
    let payload = previews.get(&handle).await.unwrap().unwrap();
    let preview: ScriptContext = serde_json::from_slice(&payload).unwrap();
    assert_eq!(preview.scenes.len(), 2);
    assert_eq!(preview.scenes[0].summary, None, "#668 guard rewrote it");
    assert_eq!(preview.scenes[0].synopsis_score, Some(0.0));
    assert!(preview.scenes[0].scene_score.is_some());
    assert_eq!(
        preview.scenes[1].summary.as_deref(),
        Some("Ben repariert das Auto.")
    );
    let synopsis = preview.scenes[1].synopsis_score.unwrap();
    assert!((synopsis - (0.9_f32 * 0.9 * (0.5 + 0.5))).abs() < 1e-5);
    assert!(
        preview.scenes[1]
            .scoring
            .as_ref()
            .unwrap()
            .sub_scores
            .contains_key(question_keys::CHARACTERS_COMPLETE)
    );

    // Decision usage accumulates into the job telemetry: two chunk requests
    // (11 input tokens / 5 mJ each) plus one Pass-2 continuity request per
    // wardrobe gap the merged preview still carries.
    let continuity_calls = {
        let all = recorder.states.lock().unwrap();
        all.iter()
            .filter(|state| state["kind"] == "outfit_continuity")
            .count()
    };
    let state = queue.state.lock().unwrap();
    let telemetry = state.telemetry.first().expect("telemetry recorded");
    assert_eq!(telemetry.tokens_in, 22 + (continuity_calls as u64) * 11);
    assert_eq!(
        telemetry.energy_millijoules,
        10 + (continuity_calls as u64) * 5
    );
}

// ── Pass 2 apply: a continued outfit reuses the source scene's Outfit
// (OpenSpec `ai-import-decision-outfit-continuity`, design D3) ──

/// A continued look in `target`, continuing `source`'s explicit outfit.
fn continued_row(source_ref: &str, draft_ref: &str) -> DraftScene {
    DraftScene {
        draft_ref: draft_ref.to_owned(),
        scene_number: Some(2),
        characters: vec![DraftCharacter::from("BEN")],
        outfits: vec![breakdown_core::ai::DraftOutfit {
            character_name: "BEN".to_owned(),
            name: "Zivil-Look".to_owned(),
            notes: None,
            source_quote: String::new(),
            origin: breakdown_core::ai::DraftOutfitOrigin::ContinuedFromScene,
            provenance: Some(breakdown_core::ai::DraftOutfitProvenance {
                source_draft_ref: Some(source_ref.to_owned()),
                source_scene_number: Some(1),
                confidence: 0.9,
            }),
            pieces: Vec::new(),
        }],
        ..Default::default()
    }
}

#[tokio::test]
async fn script_apply_binds_a_continuation_to_the_source_outfit() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![
            row_with_outfit("1. INT. WOHNUNG", &["BEN"], &[("BEN", "Zivil-Look")]),
            continued_row("1. INT. WOHNUNG", "2. INT. OP"),
        ],
        ..Default::default()
    };
    let decisions = [
        create_decision("1. INT. WOHNUNG"),
        create_decision("2. INT. OP"),
    ];
    let result = fixture.apply(&preview, &decisions).await.unwrap();

    assert!(
        result.unapplied_outfits.is_empty(),
        "{:?}",
        result.unapplied_outfits
    );
    // Exactly ONE look for the figure ...
    let outfits = fixture.wardrobe.assigned.lock().unwrap().clone();
    assert_eq!(outfits.len(), 1, "a continuation creates no second Outfit");
    assert_eq!(result.created_outfits, 1);
    // ... referenced by BOTH scenes' beats.
    let scene_ids = fixture.scenes.created.lock().unwrap().clone();
    assert_eq!(scene_ids.len(), 2);
    let mut beat_outfits: Vec<Uuid> = Vec::new();
    for scene_id in scene_ids {
        for (_, outfit_id) in fixture.scenes.beats_of(scene_id) {
            beat_outfits.push(outfit_id);
        }
    }
    assert_eq!(beat_outfits.len(), 2, "one beat per scene");
    assert_eq!(
        beat_outfits[0], beat_outfits[1],
        "both scenes cast the same Outfit aggregate"
    );
    assert_eq!(beat_outfits[0], outfits[0].0);
}

#[tokio::test]
async fn re_applying_a_continuation_adds_no_second_outfit_or_beat() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![
            row_with_outfit("1. INT. WOHNUNG", &["BEN"], &[("BEN", "Zivil-Look")]),
            continued_row("1. INT. WOHNUNG", "2. INT. OP"),
        ],
        ..Default::default()
    };
    let decisions = [
        create_decision("1. INT. WOHNUNG"),
        create_decision("2. INT. OP"),
    ];
    fixture.apply(&preview, &decisions).await.unwrap();
    let after_first = fixture.scenes.beats.lock().unwrap().len();
    // The retry re-drives the same plan; every mapping row is confirmed.
    let retried = fixture.apply(&preview, &decisions).await.unwrap();
    assert!(
        retried.unapplied_outfits.is_empty(),
        "{:?}",
        retried.unapplied_outfits
    );
    assert_eq!(
        fixture.wardrobe.assigned.lock().unwrap().len(),
        1,
        "no second Outfit"
    );
    assert_eq!(
        fixture.scenes.beats.lock().unwrap().len(),
        after_first,
        "no second beat"
    );
}

#[tokio::test]
async fn a_continuation_whose_source_was_rejected_is_reported() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![
            row_with_outfit("1. INT. WOHNUNG", &["BEN"], &[("BEN", "Zivil-Look")]),
            continued_row("1. INT. WOHNUNG", "2. INT. OP"),
        ],
        ..Default::default()
    };
    let mut source_decision = create_decision("1. INT. WOHNUNG");
    source_decision.outfit_decisions = vec![breakdown_core::ai::OutfitDecision {
        ordinal: 0,
        accepted: false,
    }];
    let decisions = [source_decision, create_decision("2. INT. OP")];
    let result = fixture.apply(&preview, &decisions).await.unwrap();

    assert_eq!(
        result.created_outfits, 0,
        "the rejected source creates nothing"
    );
    assert_eq!(
        result.unapplied_outfits.len(),
        1,
        "{:?}",
        result.unapplied_outfits
    );
    assert_eq!(
        result.unapplied_outfits[0].reason,
        breakdown_core::ai::UnappliedOutfitReason::ContinuityUnresolved
    );
}

#[tokio::test]
async fn script_apply_honours_a_continuity_selection() {
    // OpenSpec `ai-import-decision-outfit-continuity`: the reviewer resolves a
    // wardrobe gap by picking the continuation candidate; the apply plans the
    // row and binds the beat to the source scene's look.
    let fixture = ScriptApplyFixture::new();
    // A gap needs plausible action (design D1), or no candidate is offered.
    let mut source = row_with_outfit("1. INT. WOHNUNG", &["BEN"], &[("BEN", "Zivil-Look")]);
    source.summary = Some("Ben wartet auf den Anruf.".to_owned());
    let mut gap = row_with_outfit("2. INT. OP", &["BEN"], &[]);
    gap.summary = Some("Ben betritt den OP.".to_owned());
    let preview = ScriptContext {
        scenes: vec![source, gap],
        ..Default::default()
    };
    let decisions = [
        create_decision("1. INT. WOHNUNG"),
        create_decision("2. INT. OP"),
    ];
    let selections = vec![breakdown_core::ai::OutfitContinuitySelection {
        scene_index: 1,
        character_identity: "ben".to_owned(),
        candidate: breakdown_core::ai::OutfitContinuityCandidate::Continued,
    }];
    let result = fixture
        .apply_with_continuity(&preview, &decisions, &selections)
        .await
        .unwrap();
    assert!(
        result.unapplied_outfits.is_empty(),
        "{:?}",
        result.unapplied_outfits
    );
    assert_eq!(result.created_outfits, 1, "the selection creates no look");
    let scene_ids = fixture.scenes.created.lock().unwrap().clone();
    let second = *scene_ids.last().expect("two scenes created");
    assert_eq!(
        fixture.scenes.beats_of(second).len(),
        1,
        "the gap scene got its beat"
    );
}

#[tokio::test]
async fn script_apply_refuses_a_selection_the_preview_does_not_offer() {
    let fixture = ScriptApplyFixture::new();
    let mut source = row_with_outfit("1. INT. WOHNUNG", &["BEN"], &[("BEN", "Zivil-Look")]);
    source.summary = Some("Ben wartet auf den Anruf.".to_owned());
    let mut gap = row_with_outfit("2. INT. OP", &["BEN"], &[]);
    gap.summary = Some("Ben betritt den OP.".to_owned());
    let preview = ScriptContext {
        scenes: vec![source, gap],
        ..Default::default()
    };
    let decisions = [
        create_decision("1. INT. WOHNUNG"),
        create_decision("2. INT. OP"),
    ];
    // The location never changed, so the preview offers no context candidate.
    let selections = vec![breakdown_core::ai::OutfitContinuitySelection {
        scene_index: 1,
        character_identity: "ben".to_owned(),
        candidate: breakdown_core::ai::OutfitContinuityCandidate::Inferred,
    }];
    let error = fixture
        .apply_with_continuity(&preview, &decisions, &selections)
        .await
        .expect_err("an unoffered candidate is a client bug");
    match error {
        DomainError::Conflict { code, .. } => {
            assert_eq!(code.code, "ai-import.apply-unknown-continuity-candidate");
        }
        other => panic!("expected the registered conflict, got {other:?}"),
    }
    assert!(
        fixture.scenes.created.lock().unwrap().is_empty(),
        "nothing may be dispatched"
    );
}

/// CodeRabbit review (PR #746): a beat's mapping address must come from the
/// immutable preview, not from the plan. Re-applying after the reviewer accepts
/// a previously rejected outfit must give THAT scene its beat and leave the later
/// row's address untouched.
#[tokio::test]
async fn accepting_a_previously_rejected_outfit_keeps_every_beat_address() {
    let fixture = ScriptApplyFixture::new();
    let preview = ScriptContext {
        scenes: vec![
            row_with_outfit("1. INT. WOHNUNG", &["BEN"], &[("BEN", "Zivil-Look")]),
            row_with_outfit("2. INT. OP", &["BEN"], &[("BEN", "OP-Kleidung")]),
        ],
        ..Default::default()
    };
    let accepted = [
        create_decision("1. INT. WOHNUNG"),
        create_decision("2. INT. OP"),
    ];
    let reject_first = [
        ApplyMapping {
            draft_ref: "1. INT. WOHNUNG".to_owned(),
            decision: breakdown_core::ai::ApplyMappingDecision::Create,
            outfit_decisions: vec![breakdown_core::ai::OutfitDecision {
                ordinal: 0,
                accepted: false,
            }],
        },
        create_decision("2. INT. OP"),
    ];

    // Apply 1: scene 1 contradictorily rejected — only scene 2 gets a beat.
    fixture.apply(&preview, &reject_first).await.unwrap();
    let scene_ids = fixture.scenes.created.lock().unwrap().clone();
    assert_eq!(scene_ids.len(), 2);
    assert!(fixture.scenes.beats_of(scene_ids[0]).is_empty());
    assert_eq!(fixture.scenes.beats_of(scene_ids[1]).len(), 1);

    // Apply 2: the reviewer accepts scene 1's outfit. Before the fix, scene 1's
    // beat took position 0 — already confirmed for scene 2 — and was dropped
    // silently as "Settled".
    let result = fixture.apply(&preview, &accepted).await.unwrap();
    assert!(
        result.unapplied_outfits.is_empty(),
        "{:?}",
        result.unapplied_outfits
    );
    assert_eq!(
        fixture.scenes.beats_of(scene_ids[0]).len(),
        1,
        "the newly accepted scene must get its beat"
    );
    assert_eq!(
        fixture.scenes.beats_of(scene_ids[1]).len(),
        1,
        "and the later scene must not gain a second one"
    );
    // The later row's address did not move: its beat still points at its own look.
    assert_eq!(result.created_outfit_beats, 1, "only the new beat appended");
}

/// CodeRabbit review (PR #746): a reviewer-selected gap row is addressed from the
/// immutable draft, so adding another selection later must not shift it.
#[tokio::test]
async fn a_continuity_selection_keeps_its_address_when_others_are_added() {
    let fixture = ScriptApplyFixture::new();
    let mut source = row_with_outfit("1. INT. WOHNUNG", &["BEN"], &[("BEN", "Zivil-Look")]);
    source.summary = Some("Ben wartet.".to_owned());
    let mut gap_a = row_with_outfit("2. INT. OP", &["BEN"], &[]);
    gap_a.summary = Some("Ben betritt den OP.".to_owned());
    let mut gap_b = row_with_outfit("3. INT. ITS", &["BEN"], &[]);
    gap_b.summary = Some("Ben wacht auf.".to_owned());
    let preview = ScriptContext {
        scenes: vec![source, gap_a, gap_b],
        ..Default::default()
    };
    let decisions = [
        create_decision("1. INT. WOHNUNG"),
        create_decision("2. INT. OP"),
        create_decision("3. INT. ITS"),
    ];
    let selection = |scene_index: usize| breakdown_core::ai::OutfitContinuitySelection {
        scene_index,
        character_identity: "ben".to_owned(),
        candidate: breakdown_core::ai::OutfitContinuityCandidate::Continued,
    };

    // Apply 1 selects the LATER gap only.
    let later_only = [selection(2)];
    let first = fixture
        .apply_with_continuity(&preview, &decisions, &later_only)
        .await
        .unwrap();
    assert_eq!(first.created_outfit_beats, 2, "source beat + selected beat");

    // Apply 2 adds the earlier gap. Its address is its own row, so the later
    // selection keeps the mapping row it already confirmed.
    let both = [selection(1), selection(2)];
    let second = fixture
        .apply_with_continuity(&preview, &decisions, &both)
        .await
        .unwrap();
    assert!(
        second.unapplied_outfits.is_empty(),
        "{:?}",
        second.unapplied_outfits
    );
    assert_eq!(
        second.created_outfit_beats, 1,
        "only the newly selected scene appended a beat"
    );
    let scene_ids = fixture.scenes.created.lock().unwrap().clone();
    let beats: usize = scene_ids
        .iter()
        .map(|scene| fixture.scenes.beats_of(*scene).len())
        .sum();
    assert_eq!(beats, 3, "one beat per scene: source, gap A, gap B");
}
