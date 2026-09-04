// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

//! Handler tests proving the AI import dependencies are reachable through the
//! generic `Ports` seam (issue #176).
//!
//! Before this change the AI import handlers were hard-wired to
//! `AppState<ProductionPorts>`, so every AI route was untestable without a
//! PostgreSQL-backed queue/mapping adapter. These tests drive the handlers
//! with `FakePorts` only — no container, no database.

// Test code: the workspace denies `clippy::expect_used`; assertions on
// handler `Result` returns use `.expect()`/`.expect_err()` with explicit
// messages. The allow list is kept minimal.
#![allow(clippy::expect_used)]
mod common;

use api::problems::Json; // test-only alias for the wrapper extractor (ADR-031)
use api::problems::{Path, Query};
use axum::extract::State;
use axum::http::{HeaderMap, HeaderValue, StatusCode};

use api::auth::CurrentUser;
use api::handlers::{
    ApplyAiImportRequest, CreateAiConfigRequest, ListParams, RevokeAiConfigRequest,
    UpdateAiConfigRequest, apply_ai_import, create_ai_config, get_ai_config, get_ai_import_job,
    get_ai_import_preview, list_ai_configs, list_ai_import_jobs, revoke_ai_config,
    update_ai_config, upload_ai_schedule, upload_ai_script,
};
use api::state::AppState;
use breakdown_core::ai::{
    AiConfigView, AiImportJob, AiImportJobId, AiImportMappingRepository, AiImportPreviewResponse,
    AiImportQueue, AiPreviewPayload, ApplyMapping, ApplyMappingDecision, DocumentKind, DraftScene,
    JobStatus, LlmProvider, MergedPreview, ScriptContext, ShootingSchedule, SourceFormat,
    TelemetryApplyState,
};
use breakdown_core::block::BlockView;
use breakdown_core::membership::Role;
use breakdown_core::shared::{AggregateVersion, BlockId, EpisodeId, SeasonId, SeriesId, UserId};
use chrono::Utc;
use common::FakePorts;
use infra::ai::AiPreviewStore;
use std::collections::HashMap;
use uuid::Uuid;

const TEST_SUB: &str = "ai-ports-test-user";

fn user() -> CurrentUser {
    CurrentUser::dummy(TEST_SUB)
}

fn state(ports: FakePorts) -> AppState<FakePorts> {
    AppState::with_ai_import(
        ports, /*ai_import_enabled=*/ true, /*max_document_bytes=*/ 4096,
    )
}

/// Seed `block_id` into the block repo with a fresh season and grant the test
/// user an active costume-dept role in that season, so the AI block/job gates
/// (`authorize_ai_block`, `authorize_ai_job`) resolve allow from seeded rows
/// (issue #348).
async fn seed_ai_block_access(ports: &FakePorts, block_id: BlockId) {
    let season_id = SeasonId::new();
    let series_id = SeriesId::new();
    ports.block_repo.blocks.lock().await.insert(
        block_id.0,
        BlockView {
            id: block_id.0,
            season_id,
            series_id,
            number: 1,
            start_date: None,
            end_date: None,
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    ports
        .membership_repo
        .seed_active(
            block_id,
            UserId::from_sub(TEST_SUB),
            Role::CostumeDesigner,
            season_id,
            series_id,
        )
        .await;
}

/// A PDF upload request carrying the `X-Active-Block` header the AI gate
/// requires.
fn pdf_headers(block_id: BlockId) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert("content-type", HeaderValue::from_static("application/pdf"));
    headers.insert(
        "x-active-block",
        HeaderValue::from_str(&block_id.0.to_string()).expect("uuid is a valid header value"),
    );
    headers
}

/// A schedule upload request with the given Content-Type. The schedule
/// handler accepts `text/csv`, `application/pdf` and `text/plain`.
fn schedule_headers(content_type: &'static str, block_id: BlockId) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert("content-type", HeaderValue::from_static(content_type));
    headers.insert(
        "x-active-block",
        HeaderValue::from_str(&block_id.0.to_string()).expect("uuid is a valid header value"),
    );
    headers
}

fn succeeded_job(preview_handle: &str) -> AiImportJob {
    let now = Utc::now();
    AiImportJob {
        id: AiImportJobId::new(),
        user_id: UserId::from_sub(TEST_SUB),
        document_kind: DocumentKind::Script,
        source_format: breakdown_core::ai::SourceFormat::Pdf,
        block_id: None,
        dedup_key: "test|script|digest".to_owned(),
        document_digest: "digest".to_owned(),
        source_handle: "ai-source/test".to_owned(),
        status: JobStatus::Succeeded,
        preview_handle: Some(preview_handle.to_owned()),
        last_error: None,
        retries: 0,
        max_retries: 5,
        created_at: now,
        updated_at: now,
    }
}

#[tokio::test]
async fn upload_ai_script_enqueues_through_the_ports_seam() {
    let ports = FakePorts::default();
    let queue = ports.ai_import_queue.clone();
    let store = ports.ai_payload_store.clone();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    // Seed-backed allow (issue #348): the header block exists in a known
    // season and the caller holds a costume role there.
    seed_ai_block_access(&ports, block_id).await;

    let result = upload_ai_script::<FakePorts>(
        State(state(ports)),
        user(),
        pdf_headers(block_id),
        api::problems::Bytes(axum::body::Bytes::from_static(b"%PDF-1.7 fake")),
    )
    .await;

    let (status, Json(job_id)) = result.expect("authorized PDF upload should be accepted");
    assert_eq!(status, StatusCode::ACCEPTED);

    // The job landed in the fake queue with the block scope from the header.
    let job = queue
        .get(job_id)
        .await
        .expect("queue read should succeed")
        .expect("enqueued job should be retrievable");
    assert_eq!(job.block_id, Some(block_id));
    assert_eq!(job.document_kind, DocumentKind::Script);
    assert_eq!(job.source_format, SourceFormat::Pdf);
    assert_eq!(job.status, JobStatus::Pending);

    // The source bytes went to the document store, not the preview slot.
    let bytes = store
        .get(&job.source_handle)
        .await
        .expect("document store read should succeed");
    assert_eq!(bytes.as_deref(), Some(&b"%PDF-1.7 fake"[..]));
}

/// Issue #221: the schedule upload persists the declared source format so the
/// worker can route CSV natively and PDF/plain-text through the LLM path.
#[tokio::test]
async fn upload_ai_schedule_persists_the_declared_source_format() {
    for (content_type, expected) in [
        ("text/csv", SourceFormat::Csv),
        ("application/pdf", SourceFormat::Pdf),
        ("text/plain", SourceFormat::PlainText),
    ] {
        let ports = FakePorts::default();
        let queue = ports.ai_import_queue.clone();
        let block_id = BlockId::from_uuid(Uuid::now_v7());
        seed_ai_block_access(&ports, block_id).await;

        let result = upload_ai_schedule::<FakePorts>(
            State(state(ports)),
            user(),
            schedule_headers(content_type, block_id),
            api::problems::Bytes(axum::body::Bytes::from_static(b"fake schedule bytes")),
        )
        .await;

        let (status, Json(job_id)) = result.expect("authorized schedule upload should be accepted");
        assert_eq!(status, StatusCode::ACCEPTED, "{content_type}");
        let job = queue
            .get(job_id)
            .await
            .expect("queue read should succeed")
            .expect("enqueued job should be retrievable");
        assert_eq!(job.document_kind, DocumentKind::Schedule);
        assert_eq!(
            job.source_format, expected,
            "{content_type} must be persisted as {expected:?}"
        );
    }
}

/// Issue #221: the declared format match must tolerate real-world
/// `Content-Type` spelling — uppercase media types and parameters after `;`
/// are both valid HTTP and must not fall through to `415`.
#[tokio::test]
async fn upload_ai_schedule_accepts_normalized_content_types() {
    for (content_type, expected) in [
        ("TEXT/CSV", SourceFormat::Csv),
        ("text/csv ; charset=utf-8", SourceFormat::Csv),
        ("Application/PDF", SourceFormat::Pdf),
    ] {
        let ports = FakePorts::default();
        let queue = ports.ai_import_queue.clone();
        let block_id = BlockId::from_uuid(Uuid::now_v7());
        seed_ai_block_access(&ports, block_id).await;

        let result = upload_ai_schedule::<FakePorts>(
            State(state(ports)),
            user(),
            schedule_headers(content_type, block_id),
            api::problems::Bytes(axum::body::Bytes::from_static(b"fake schedule bytes")),
        )
        .await;

        let (status, Json(job_id)) = result.expect("a normalized content type must be accepted");
        assert_eq!(status, StatusCode::ACCEPTED, "{content_type}");
        let job = queue
            .get(job_id)
            .await
            .expect("queue read should succeed")
            .expect("enqueued job should be retrievable");
        assert_eq!(
            job.source_format, expected,
            "{content_type} must normalize to {expected:?}"
        );
    }
}

#[tokio::test]
async fn upload_ai_script_deduplicates_identical_reuploads() {
    let ports = FakePorts::default();
    let store = ports.ai_payload_store.clone();
    let queue = ports.ai_import_queue.clone();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;
    let state = state(ports);

    let (first_status, Json(first_id)) = upload_ai_script::<FakePorts>(
        State(state.clone()),
        user(),
        pdf_headers(block_id),
        api::problems::Bytes(axum::body::Bytes::from_static(b"%PDF same bytes")),
    )
    .await
    .expect("first upload should be accepted");
    assert_eq!(first_status, StatusCode::ACCEPTED);

    let (second_status, Json(second_id)) = upload_ai_script::<FakePorts>(
        State(state),
        user(),
        pdf_headers(block_id),
        api::problems::Bytes(axum::body::Bytes::from_static(b"%PDF same bytes")),
    )
    .await
    .expect("duplicate upload should resolve to the existing job");

    assert_eq!(second_status, StatusCode::OK);
    assert_eq!(second_id, first_id, "dedup must return the existing job id");

    // Dedup must not create a second queue row.
    assert_eq!(
        queue.jobs.lock().await.len(),
        1,
        "a deduplicated re-upload must not enqueue a second job"
    );

    // The second upload stores its bytes under a *fresh* job id before the
    // dedup lookup and then deletes that orphan. The surviving job's own
    // source blob must NOT be collateral damage of that cleanup.
    let surviving_handle = format!("ai-source/{}", first_id.as_uuid());
    let surviving = store
        .get(&surviving_handle)
        .await
        .expect("document store read should succeed");
    assert_eq!(
        surviving.as_deref(),
        Some(&b"%PDF same bytes"[..]),
        "the existing job's source document must survive orphan cleanup"
    );
}

#[tokio::test]
async fn upload_ai_script_rejects_oversize_documents() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    // Seed-backed allow so the size check (not the authz gate) rejects.
    seed_ai_block_access(&ports, block_id).await;
    // `with_ai_import` caps the document at 4096 bytes.
    let body = api::problems::Bytes(axum::body::Bytes::from(vec![b'x'; 4097]));

    let problem =
        upload_ai_script::<FakePorts>(State(state(ports)), user(), pdf_headers(block_id), body)
            .await
            .expect_err("oversize upload must be rejected")
            .into_problem();
    assert_eq!(problem.status, StatusCode::PAYLOAD_TOO_LARGE.as_u16());
    assert_eq!(problem.code, "http.payload-too-large");
    // Detail is localized (ADR-031 D5); the code is the contract.
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn get_ai_import_job_reads_through_the_queue_port() {
    let ports = FakePorts::default();
    let job = succeeded_job("ai-preview/handle");
    let job_id = job.id;
    ports.ai_import_queue.seed(job).await;

    let response = get_ai_import_job::<FakePorts>(State(state(ports)), user(), Path(job_id))
        .await
        .expect("owner should read their own job");
    assert_eq!(response.status(), StatusCode::OK);
    // AI job payloads are user-specific and must never be cached (CWE-525).
    assert_eq!(
        response
            .headers()
            .get(axum::http::header::CACHE_CONTROL)
            .and_then(|v| v.to_str().ok()),
        Some("no-store")
    );
}

#[tokio::test]
async fn get_ai_import_job_denies_a_foreign_owner() {
    let ports = FakePorts::default();
    let mut job = succeeded_job("ai-preview/handle");
    job.user_id = UserId::from_sub("someone-else");
    let job_id = job.id;
    ports.ai_import_queue.seed(job).await;

    let problem = get_ai_import_job::<FakePorts>(State(state(ports)), user(), Path(job_id))
        .await
        .expect_err("a foreign owner must be denied")
        .into_problem();
    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "domain.forbidden");
    // Detail is localized (ADR-031 D5); the code is the contract.
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn get_ai_import_preview_reads_through_the_preview_store_port() {
    let ports = FakePorts::default();
    // Store the payload through the port itself so the handle is exactly the
    // one the production store would mint for this job. A full
    // `ScriptContext` — the typed shape script jobs persist.
    let preview = ScriptContext {
        title: Some("test script".to_owned()),
        scenes: vec![DraftScene {
            draft_ref: "scene-0".to_owned(),
            scene_number: Some(1),
            ..DraftScene::default()
        }],
        uncertainties: vec![],
    };
    let mut job = succeeded_job("placeholder");
    let handle = ports
        .ai_payload_store
        .put(
            job.id,
            serde_json::to_vec(&preview).expect("preview serializes"),
        )
        .await
        .expect("preview store write should succeed");
    job.preview_handle = Some(handle);
    let job_id = job.id;
    ports.ai_import_queue.seed(job).await;

    let response = get_ai_import_preview::<FakePorts>(State(state(ports)), user(), Path(job_id))
        .await
        .expect("preview should be served from the fake store");
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), 1024 * 1024)
        .await
        .expect("preview body should read");
    let typed: AiImportPreviewResponse =
        serde_json::from_slice(&body).expect("preview body is the typed envelope");
    assert_eq!(typed.job_id, job_id.as_uuid());
    assert_eq!(typed.document_kind, DocumentKind::Script);
    assert_eq!(typed.status, JobStatus::Succeeded);
    assert!(
        matches!(typed.preview, AiPreviewPayload::Script(ref context)
            if context.scenes.len() == 1 && context.scenes[0].draft_ref == "scene-0"),
        "script payload must carry its draft rows structurally"
    );
}

/// Seed a succeeded script job whose preview holds `scene_count` draft scenes
/// and no open uncertainties, so the apply gate is satisfied.
async fn seed_applyable_script_job(
    ports: &FakePorts,
    block_id: Option<BlockId>,
    scene_count: usize,
) -> AiImportJobId {
    let preview = ScriptContext {
        title: Some("test script".to_owned()),
        scenes: (0..scene_count)
            .map(|i| DraftScene {
                draft_ref: format!("scene-{i}"),
                scene_number: Some(i as u32 + 1),
                ..DraftScene::default()
            })
            .collect(),
        uncertainties: vec![],
    };
    let mut job = succeeded_job("placeholder");
    job.block_id = block_id;
    let handle = ports
        .ai_payload_store
        .put(
            job.id,
            serde_json::to_vec(&preview).expect("preview serializes"),
        )
        .await
        .expect("preview store write should succeed");
    job.preview_handle = Some(handle);
    let job_id = job.id;
    ports.ai_import_queue.seed(job).await;
    job_id
}

#[tokio::test]
async fn apply_ai_import_drives_the_script_worker_through_the_ports_seam() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    // Pin the stub episode into the job's block so the cross-block gate passes.
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    let mappings = ports.ai_import_mapping.clone();
    let queue = ports.ai_import_queue.clone();
    // The job's block lives in a season where the caller holds a costume
    // role, so the apply reaches the worker (issue #348).
    seed_ai_block_access(&ports, block_id).await;
    let job_id = seed_applyable_script_job(&ports, Some(block_id), 2).await;

    let (status, Json(response)) = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            episode_id: EpisodeId::new(),
            series_id: None,
            mappings: vec![
                ApplyMapping {
                    draft_ref: "scene-0".to_owned(),
                    decision: ApplyMappingDecision::Create,
                },
                ApplyMapping {
                    draft_ref: "scene-1".to_owned(),
                    decision: ApplyMappingDecision::Create,
                },
            ],
            accept_as_is: true,
            edit_distance: 0,
        }),
    )
    .await
    .expect("an in-block apply should succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(response.applied_count, 2);

    // `ApplyWorker` received owned clones of the command/mapping/queue ports
    // (the `+ Clone` bounds on `Ports`) and wrote through them: one idempotency
    // mapping per draft row, plus the apply telemetry.
    assert_eq!(
        mappings
            .list_by_preview(job_id)
            .await
            .expect("mapping read should succeed")
            .len(),
        2
    );
    let telemetry = queue.telemetry.lock().await;
    assert_eq!(telemetry.len(), 1, "apply must record telemetry once");
    assert_eq!(telemetry[0].0, job_id);
    // Issue #295: the apply handler must record the job's document kind and
    // the exact applied outcome (not a defaulted field).
    assert_eq!(
        telemetry[0].1.doc_kind,
        Some(DocumentKind::Script),
        "apply telemetry must carry the job's document kind"
    );
    assert_eq!(
        telemetry[0].1.apply_state,
        TelemetryApplyState::Applied {
            accept_as_is: true,
            edit_distance: 0,
        },
        "apply telemetry must carry the exact Applied outcome"
    );
}

#[tokio::test]
async fn apply_ai_import_rejects_an_episode_from_another_block() {
    let ports = FakePorts::default();
    let job_block = BlockId::from_uuid(Uuid::now_v7());
    // Seed-backed allow in the *job's* season, so the apply reaches the
    // cross-block gate (CWE-639) instead of stopping at authz (issue #348).
    seed_ai_block_access(&ports, job_block).await;
    let other_block = BlockId::from_uuid(Uuid::now_v7());
    // The target episode lives in a DIFFERENT block than the job (CWE-639).
    *ports.episode_repo.block_id_override.lock().await = Some(other_block);
    let mappings = ports.ai_import_mapping.clone();
    let queue = ports.ai_import_queue.clone();
    let job_id = seed_applyable_script_job(&ports, Some(job_block), 1).await;

    let problem = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            episode_id: EpisodeId::new(),
            series_id: None,
            mappings: vec![ApplyMapping {
                draft_ref: "scene-0".to_owned(),
                decision: ApplyMappingDecision::Create,
            }],
            accept_as_is: true,
            edit_distance: 0,
        }),
    )
    .await
    .expect_err("a cross-block apply must be rejected")
    .into_problem();

    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "domain.forbidden");
    // Detail is localized (ADR-031 D5); the code is the contract.
    assert!(!problem.detail.is_empty());
    // The gate runs before the worker: nothing was written on *either* write
    // path — mappings and telemetry are separate sinks on the queue/mapping
    // ports, so both must stay empty.
    assert!(
        mappings
            .list_by_preview(job_id)
            .await
            .expect("mapping read should succeed")
            .is_empty(),
        "a rejected apply must not write any mapping"
    );
    assert!(
        queue.telemetry.lock().await.is_empty(),
        "a rejected apply must not record telemetry"
    );
}

#[tokio::test]
async fn apply_ai_import_rejects_accept_as_is_with_a_nonzero_edit_distance() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    let mappings = ports.ai_import_mapping.clone();
    let queue = ports.ai_import_queue.clone();
    seed_ai_block_access(&ports, block_id).await;
    let job_id = seed_applyable_script_job(&ports, Some(block_id), 1).await;

    let problem = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            episode_id: EpisodeId::new(),
            series_id: None,
            mappings: vec![ApplyMapping {
                draft_ref: "scene-0".to_owned(),
                decision: ApplyMappingDecision::Create,
            }],
            // Contradictory: "no edits" alongside a nonzero edit count.
            accept_as_is: true,
            edit_distance: 3,
        }),
    )
    .await
    .expect_err("contradictory telemetry must be rejected")
    .into_problem();

    // ADR-031 D6: domain validation is 422 (was 400 pre-change).
    assert_eq!(problem.status, StatusCode::UNPROCESSABLE_ENTITY.as_u16());
    assert_eq!(problem.code, "domain.validation");
    // Detail is localized (ADR-031 D5); the code is the contract.
    assert!(!problem.detail.is_empty());
    // The validation rejects before any write reaches either sink.
    assert!(
        mappings
            .list_by_preview(job_id)
            .await
            .expect("mapping read should succeed")
            .is_empty(),
        "a rejected apply must not write any mapping"
    );
    assert!(
        queue.telemetry.lock().await.is_empty(),
        "a rejected apply must not record telemetry"
    );
}

#[tokio::test]
async fn ai_config_lifecycle_runs_through_the_config_ports() {
    let ports = FakePorts::default();
    // The config handlers gate on the credential role only (ADR-027).
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let commands = ports.ai_config_commands.clone();
    let repo = ports.ai_config_repo.clone();
    let state = state(ports);

    let (status, Json(created)) = create_ai_config::<FakePorts>(
        State(state.clone()),
        user(),
        Json(CreateAiConfigRequest {
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
        }),
    )
    .await
    .expect("credential-role member may create AI config");
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(commands.created.lock().await.len(), 1);

    // Seed the read model the way the projector would, so the ownership
    // checks on GET/PATCH/revoke have a row to resolve.
    repo.views.lock().await.insert(
        created.id,
        AiConfigView {
            id: created.id,
            user_id: UserId::from_sub(TEST_SUB),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompt_kinds: vec![],
            vault_key_id: "vault-key".to_owned(),
            version: created.version,
            revoked: false,
        },
    );

    let (status, Json(view)) =
        get_ai_config::<FakePorts>(State(state.clone()), user(), Path(created.id))
            .await
            .expect("owner may read their config");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(view.id, created.id);

    let (status, Json(_)) = update_ai_config::<FakePorts>(
        State(state.clone()),
        user(),
        Path(created.id),
        Json(UpdateAiConfigRequest {
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant-v2".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            version: created.version,
        }),
    )
    .await
    .expect("owner may update their config");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(commands.updated.lock().await.len(), 1);

    let (status, Json(_)) = revoke_ai_config::<FakePorts>(
        State(state),
        user(),
        Path(created.id),
        Json(RevokeAiConfigRequest {
            version: AggregateVersion(created.version.0 + 1),
        }),
    )
    .await
    .expect("owner may revoke their config");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(commands.revoked.lock().await.len(), 1);
}

#[tokio::test]
async fn get_ai_config_denies_a_foreign_owner() {
    let ports = FakePorts::default();
    // Seed the credential role so the denial exercises the ownership check,
    // not the credential gate (issue #348 fail-closed fakes).
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let id = Uuid::now_v7();
    ports.ai_config_repo.views.lock().await.insert(
        id,
        AiConfigView {
            id,
            user_id: UserId::from_sub("someone-else"),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompt_kinds: vec![],
            vault_key_id: "vault-key".to_owned(),
            version: AggregateVersion::INITIAL,
            revoked: false,
        },
    );

    let problem = get_ai_config::<FakePorts>(State(state(ports)), user(), Path(id))
        .await
        .expect_err("a foreign owner must be denied")
        .into_problem();
    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "domain.forbidden");
    // Detail is localized (ADR-031 D5); the code is the contract.
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn ai_config_creation_is_denied_without_the_credential_role() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));

    let problem = create_ai_config::<FakePorts>(
        State(state(ports)),
        user(),
        Json(CreateAiConfigRequest {
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
        }),
    )
    .await
    .expect_err("a non-credential-role caller must be denied")
    .into_problem();
    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "domain.forbidden");
    // Detail is localized (ADR-031 D5); the code is the contract.
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn ai_upload_is_not_found_when_the_feature_is_disabled() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    let state = AppState::with_ai_import(
        ports, /*ai_import_enabled=*/ false, /*max_document_bytes=*/ 4096,
    );

    let problem = upload_ai_script::<FakePorts>(
        State(state),
        user(),
        pdf_headers(block_id),
        api::problems::Bytes(axum::body::Bytes::from_static(b"%PDF")),
    )
    .await
    .expect_err("the disabled feature must hide the route")
    .into_problem();
    assert_eq!(problem.status, StatusCode::NOT_FOUND.as_u16());
    assert_eq!(problem.code, "domain.not-found");
    // Detail is localized (ADR-031 D5); the code is the contract.
    assert!(!problem.detail.is_empty());
}

/// Seed a succeeded schedule job holding `payload` bytes verbatim.
async fn seed_schedule_job_with_payload(ports: &FakePorts, payload: Vec<u8>) -> AiImportJobId {
    let now = Utc::now();
    let mut job = succeeded_job("placeholder");
    job.document_kind = DocumentKind::Schedule;
    job.source_format = SourceFormat::Csv;
    job.created_at = now;
    job.updated_at = now;
    let handle = ports
        .ai_payload_store
        .put(job.id, payload)
        .await
        .expect("preview store write should succeed");
    job.preview_handle = Some(handle);
    let job_id = job.id;
    ports.ai_import_queue.seed(job).await;
    job_id
}

async fn preview_body(ports: FakePorts, job_id: AiImportJobId) -> AiImportPreviewResponse {
    let response = get_ai_import_preview::<FakePorts>(State(state(ports)), user(), Path(job_id))
        .await
        .expect("preview should be served");
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), 1024 * 1024)
        .await
        .expect("preview body should read");
    serde_json::from_slice(&body).expect("preview body is the typed envelope")
}

#[tokio::test]
async fn get_ai_import_preview_serves_merged_schedule_payload() {
    let ports = FakePorts::default();
    let payload = serde_json::to_vec(&MergedPreview::default()).expect("preview serializes");
    let job_id = seed_schedule_job_with_payload(&ports, payload).await;

    let typed = preview_body(ports, job_id).await;
    assert_eq!(typed.document_kind, DocumentKind::Schedule);
    assert!(
        matches!(typed.preview, AiPreviewPayload::Merged(_)),
        "post-merge schedule payload must surface as the merged variant"
    );
}

#[tokio::test]
async fn get_ai_import_preview_serves_raw_schedule_payload() {
    let ports = FakePorts::default();
    let payload = serde_json::to_vec(&ShootingSchedule::default()).expect("preview serializes");
    let job_id = seed_schedule_job_with_payload(&ports, payload).await;

    let typed = preview_body(ports, job_id).await;
    assert!(
        matches!(typed.preview, AiPreviewPayload::Schedule(_)),
        "pre-merge schedule payload must surface as the schedule variant"
    );
}

#[tokio::test]
async fn get_ai_import_preview_rejects_an_unparseable_payload() {
    let ports = FakePorts::default();
    let job_id = seed_schedule_job_with_payload(&ports, b"not json at all".to_vec()).await;

    let problem = get_ai_import_preview::<FakePorts>(State(state(ports)), user(), Path(job_id))
        .await
        .expect_err("a corrupt preview must not be served untyped")
        .into_problem();
    assert_eq!(problem.status, StatusCode::UNPROCESSABLE_ENTITY.as_u16());
    assert_eq!(problem.code, "domain.validation");
    assert!(!problem.detail.is_empty());
}

fn jobs_query(limit: Option<i64>, offset: Option<i64>) -> Query<ListParams> {
    Query(ListParams {
        limit,
        offset,
        episode_id: None,
        season_id: None,
        series_id: None,
    })
}

#[tokio::test]
async fn list_ai_import_jobs_returns_only_the_caller_jobs_newest_first() {
    let ports = FakePorts::default();
    let base = Utc::now();
    let mut first = succeeded_job("ai-preview/first");
    first.created_at = base;
    first.updated_at = base;
    let mut second = succeeded_job("ai-preview/second");
    second.created_at = base + chrono::Duration::seconds(10);
    second.updated_at = second.created_at;
    let mut foreign = succeeded_job("ai-preview/foreign");
    foreign.user_id = UserId::from_sub("someone-else");
    let second_id = second.id;
    let first_id = first.id;
    ports.ai_import_queue.seed(first).await;
    ports.ai_import_queue.seed(second).await;
    ports.ai_import_queue.seed(foreign).await;

    let (status, Json(jobs)) =
        list_ai_import_jobs::<FakePorts>(State(state(ports)), user(), jobs_query(None, None))
            .await
            .expect("owner should list their own jobs");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        jobs.iter().map(|entry| entry.job.id).collect::<Vec<_>>(),
        vec![second_id, first_id],
        "jobs must be newest-first and scoped to the caller"
    );
}

#[tokio::test]
async fn list_ai_import_jobs_honors_pagination() {
    let ports = FakePorts::default();
    let base = Utc::now();
    for index in 0..3 {
        let mut job = succeeded_job(&format!("ai-preview/{index}"));
        job.created_at = base + chrono::Duration::seconds(index);
        job.updated_at = job.created_at;
        ports.ai_import_queue.seed(job).await;
    }

    let (status, Json(page)) = list_ai_import_jobs::<FakePorts>(
        State(state(ports.clone())),
        user(),
        jobs_query(Some(1), Some(1)),
    )
    .await
    .expect("pagination should select the middle row");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(page.len(), 1);
}

#[tokio::test]
async fn list_ai_import_jobs_hides_jobs_losing_the_season_gate() {
    let ports = FakePorts::default();
    let mut gated = succeeded_job("ai-preview/gated");
    gated.block_id = Some(BlockId::from_uuid(Uuid::now_v7()));
    ports.ai_import_queue.seed(gated).await;
    let plain = succeeded_job("ai-preview/plain");
    ports.ai_import_queue.seed(plain).await;
    // Revoke the season role: the block-scoped job must drop out of the
    // list while the block-less job stays visible.
    *ports.membership_repo.costume_role_override.lock().await = Some(Ok(false));

    let (status, Json(jobs)) =
        list_ai_import_jobs::<FakePorts>(State(state(ports)), user(), jobs_query(None, None))
            .await
            .expect("gate denials must skip rows, not fail the list");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(jobs.len(), 1);
    assert_eq!(
        jobs[0].job.preview_handle.as_deref(),
        Some("ai-preview/plain")
    );
}

fn config_view(user_sub: &str) -> AiConfigView {
    AiConfigView {
        id: Uuid::now_v7(),
        user_id: UserId::from_sub(user_sub),
        provider: LlmProvider::Neuralwatt,
        assistant_model: "assistant".to_owned(),
        image_model: None,
        prompt_kinds: vec![],
        vault_key_id: "vault-key".to_owned(),
        version: AggregateVersion::INITIAL,
        revoked: false,
    }
}

#[tokio::test]
async fn list_ai_configs_returns_only_the_caller_configs() {
    let ports = FakePorts::default();
    // Seed-backed allow (issue #348): without a credential-role row the
    // fail-closed fake denies with 403 before reaching the list.
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let mine = config_view(TEST_SUB);
    let mine_id = mine.id;
    let foreign = config_view("someone-else");
    ports
        .ai_config_repo
        .views
        .lock()
        .await
        .insert(mine_id, mine);
    ports
        .ai_config_repo
        .views
        .lock()
        .await
        .insert(foreign.id, foreign);

    let (status, Json(views)) =
        list_ai_configs::<FakePorts>(State(state(ports)), user(), jobs_query(None, None))
            .await
            .expect("credential-role member should discover their configs");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        views.iter().map(|view| view.id).collect::<Vec<_>>(),
        vec![mine_id],
        "config discovery must be scoped to the caller"
    );
}

#[tokio::test]
async fn list_ai_configs_is_denied_without_the_credential_role() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));

    let problem = list_ai_configs::<FakePorts>(State(state(ports)), user(), jobs_query(None, None))
        .await
        .expect_err("a non-credential-role caller must be denied")
        .into_problem();
    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "domain.forbidden");
    assert!(!problem.detail.is_empty());
}
