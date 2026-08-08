// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::anyhow;
use async_trait::async_trait;
use breakdown_core::ai::{
    AiImportBounds, AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId,
    AiImportMapping, AiImportMappingRepository, AiImportQueue, ApplyMapping, DocumentKind,
    DraftScene, JobStatus, LlmChatRequest, LlmClient, LlmProvider, ScriptContext,
    ShootingScheduleRow, Telemetry, TelemetryApplyState, merge_schedule_to_scenes,
};
use breakdown_core::error::DomainError;
use breakdown_core::shared::UserId;
use chrono::Utc;
use reqwest::StatusCode;
use uuid::Uuid;

use super::{
    AiImportFeature, AiPreviewStore, ApplyScriptRequest, ApplyWorker, MemoryAiPreviewStore,
    ScheduleApplyRequest, ScheduleApplyWorker, ScriptImportWorker, classify_http_status,
    merge_loaded_schedule, validate_chunk_count,
};
use crate::photo::sagas::retry_transient_value_with_delay;

#[test]
fn transient_provider_statuses_are_service_unavailable() {
    assert!(matches!(
        classify_http_status(StatusCode::TOO_MANY_REQUESTS),
        DomainError::ServiceUnavailable(_)
    ));
    assert!(matches!(
        classify_http_status(StatusCode::INTERNAL_SERVER_ERROR),
        DomainError::ServiceUnavailable(_)
    ));
    assert!(matches!(
        classify_http_status(StatusCode::BAD_REQUEST),
        DomainError::ValidationError(_)
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
                        Err(anyhow!(DomainError::ServiceUnavailable(
                            "simulated 503".to_owned()
                        )))
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
    assert!(matches!(result, Err(DomainError::Conflict(_))));
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
) -> ScriptImportWorker<FakeQueue, FakeLlmClient, MemoryAiPreviewStore> {
    ScriptImportWorker {
        queue,
        client: Arc::new(FakeLlmClient),
        previews,
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
    assert!(matches!(result, Err(DomainError::ValidationError(_))));
    let state = queue.state.lock().unwrap();
    assert_eq!(state.failed, vec![job.id]);
    assert!(state.succeeded.is_empty());
    assert!(state.telemetry.is_empty());
}

#[derive(Clone, Default)]
struct FakeSceneCommands {
    created: Arc<Mutex<Vec<Uuid>>>,
    updated: Arc<Mutex<Vec<Uuid>>>,
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
        _command: breakdown_core::scene::commands::ScheduleSceneOnShootingDay,
    ) -> Result<breakdown_core::shared::AggregateVersion, DomainError> {
        Ok(breakdown_core::shared::AggregateVersion::INITIAL)
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

    async fn insert(&self, mapping: AiImportMapping) -> Result<(), DomainError> {
        self.values
            .lock()
            .unwrap()
            .insert((mapping.preview_id, mapping.draft_ref.clone()), mapping);
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
        self.created.lock().unwrap().push(command.id);
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
        self.planned.lock().unwrap().push(command.id);
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

#[tokio::test]
async fn schedule_apply_creates_and_reuses_day_and_scene_shoot_mapping() {
    let scene_commands = Arc::new(FakeSceneCommands::default());
    let shooting_days = Arc::new(FakeShootingDayCommands::default());
    let scene_shoots = Arc::new(FakeSceneShootCommands::default());
    let mappings = Arc::new(FakeMappings::default());
    let scene = breakdown_core::scene::views::SceneView {
        id: Uuid::now_v7(),
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
    let preview = merge_schedule_to_scenes(&schedule, &[scene]);
    let worker = ScheduleApplyWorker {
        scene_commands,
        shooting_day_commands: Arc::clone(&shooting_days),
        scene_shoot_commands: Arc::clone(&scene_shoots),
        mappings: Arc::clone(&mappings),
    };
    let preview_id = AiImportJobId::new();
    let actor = UserId::from_sub("schedule-test-user");
    worker
        .apply(ScheduleApplyRequest {
            actor: actor.clone(),
            preview_id,
            preview: &preview,
            series_id: None,
        })
        .await
        .unwrap();
    worker
        .apply(ScheduleApplyRequest {
            actor,
            preview_id,
            preview: &preview,
            series_id: None,
        })
        .await
        .unwrap();
    assert_eq!(shooting_days.created.lock().unwrap().len(), 1);
    assert_eq!(scene_shoots.planned.lock().unwrap().len(), 1);
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
