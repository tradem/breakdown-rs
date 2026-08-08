// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

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

use axum::Json;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, HeaderValue, StatusCode};

use api::auth::CurrentUser;
use api::handlers::{
    CreateAiConfigRequest, RevokeAiConfigRequest, UpdateAiConfigRequest, create_ai_config,
    get_ai_config, get_ai_import_job, get_ai_import_preview, revoke_ai_config, update_ai_config,
    upload_ai_script,
};
use api::state::AppState;
use breakdown_core::ai::{
    AiConfigView, AiImportJob, AiImportJobId, AiImportQueue, DocumentKind, JobStatus, LlmProvider,
};
use breakdown_core::shared::{AggregateVersion, BlockId, UserId};
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

fn succeeded_job(preview_handle: &str) -> AiImportJob {
    let now = Utc::now();
    AiImportJob {
        id: AiImportJobId::new(),
        user_id: UserId::from_sub(TEST_SUB),
        document_kind: DocumentKind::Script,
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

    let result = upload_ai_script::<FakePorts>(
        State(state(ports)),
        user(),
        pdf_headers(block_id),
        axum::body::Bytes::from_static(b"%PDF-1.7 fake"),
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
    assert_eq!(job.status, JobStatus::Pending);

    // The source bytes went to the document store, not the preview slot.
    let bytes = store
        .get(&job.source_handle)
        .await
        .expect("document store read should succeed");
    assert_eq!(bytes.as_deref(), Some(&b"%PDF-1.7 fake"[..]));
}

#[tokio::test]
async fn upload_ai_script_deduplicates_identical_reuploads() {
    let ports = FakePorts::default();
    let store = ports.ai_payload_store.clone();
    let queue = ports.ai_import_queue.clone();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    let state = state(ports);

    let (first_status, Json(first_id)) = upload_ai_script::<FakePorts>(
        State(state.clone()),
        user(),
        pdf_headers(block_id),
        axum::body::Bytes::from_static(b"%PDF same bytes"),
    )
    .await
    .expect("first upload should be accepted");
    assert_eq!(first_status, StatusCode::ACCEPTED);

    let (second_status, Json(second_id)) = upload_ai_script::<FakePorts>(
        State(state),
        user(),
        pdf_headers(block_id),
        axum::body::Bytes::from_static(b"%PDF same bytes"),
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
    // `with_ai_import` caps the document at 4096 bytes.
    let body = axum::body::Bytes::from(vec![b'x'; 4097]);

    let (status, Json(body)) =
        upload_ai_script::<FakePorts>(State(state(ports)), user(), pdf_headers(block_id), body)
            .await
            .expect_err("oversize upload must be rejected");
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert!(body.message.contains("size limit"));
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

    let (status, Json(body)) =
        get_ai_import_job::<FakePorts>(State(state(ports)), user(), Path(job_id))
            .await
            .expect_err("a foreign owner must be denied");
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert!(body.message.contains("not authorized"));
}

#[tokio::test]
async fn get_ai_import_preview_reads_through_the_preview_store_port() {
    let ports = FakePorts::default();
    // Store the payload through the port itself so the handle is exactly the
    // one the production store would mint for this job.
    let mut job = succeeded_job("placeholder");
    let handle = ports
        .ai_payload_store
        .put(job.id, br#"{"scenes":[]}"#.to_vec())
        .await
        .expect("preview store write should succeed");
    job.preview_handle = Some(handle);
    let job_id = job.id;
    ports.ai_import_queue.seed(job).await;

    let response = get_ai_import_preview::<FakePorts>(State(state(ports)), user(), Path(job_id))
        .await
        .expect("preview should be served from the fake store");
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn ai_config_lifecycle_runs_through_the_config_ports() {
    let ports = FakePorts::default();
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

    let (status, Json(body)) = get_ai_config::<FakePorts>(State(state(ports)), user(), Path(id))
        .await
        .expect_err("a foreign owner must be denied");
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert!(body.message.contains("not authorized"));
}

#[tokio::test]
async fn ai_config_creation_is_denied_without_the_credential_role() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));

    let (status, Json(body)) = create_ai_config::<FakePorts>(
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
    .expect_err("a non-credential-role caller must be denied");
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert!(body.message.contains("not authorized"));
}

#[tokio::test]
async fn ai_upload_is_not_found_when_the_feature_is_disabled() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    let state = AppState::with_ai_import(
        ports, /*ai_import_enabled=*/ false, /*max_document_bytes=*/ 4096,
    );

    let (status, Json(body)) = upload_ai_script::<FakePorts>(
        State(state),
        user(),
        pdf_headers(block_id),
        axum::body::Bytes::from_static(b"%PDF"),
    )
    .await
    .expect_err("the disabled feature must hide the route");
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert!(body.message.contains("disabled"));
}
