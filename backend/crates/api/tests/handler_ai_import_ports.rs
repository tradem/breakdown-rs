// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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
// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

#![allow(clippy::expect_used)]
use crate::common;

use api::problems::Json; // test-only alias for the wrapper extractor (ADR-031)
use api::problems::{Path, Query};
use axum::extract::State;
use axum::http::{HeaderMap, HeaderValue, StatusCode};

use api::auth::CurrentUser;
use api::handlers::{
    AiImportJobResponse, ApplyAiImportRequest, ApplyEpisodeGroupRequest, CreateAiConfigRequest,
    ListParams, RevokeAiConfigRequest, UpdateAiConfigRequest, apply_ai_import, create_ai_config,
    delete_ai_import_job, get_ai_config, get_ai_import_job, get_ai_import_preview, list_ai_configs,
    list_ai_import_jobs, revoke_ai_config, update_ai_config, upload_ai_schedule, upload_ai_script,
};
use api::state::AppState;
use breakdown_core::ai::{
    AiConfigView, AiImportJob, AiImportJobId, AiImportMappingRepository, AiImportPreviewResponse,
    AiImportQueue, AiPreviewPayload, ApplyMapping, ApplyMappingDecision, CostDisplayPreference,
    DocumentKind, DraftEpisode, DraftScene, EpisodeTarget, JobStatus, LlmProvider, MergedPreview,
    ScriptContext, ShootingSchedule, SourceFormat, TelemetryApplyState, Uncertainty,
    UncertaintyAcknowledgement, UncertaintyKind,
};
use breakdown_core::block::BlockView;
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::membership::Role;
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{AggregateVersion, BlockId, EpisodeId, ProjectId, SeasonId, UserId};
use chrono::Utc;
use common::FakePorts;
use infra::ai::{AiDocumentStore, AiPreviewStore};
use std::collections::HashMap;
use uuid::Uuid;

const TEST_SUB: &str = "ai-ports-test-user";

fn user() -> CurrentUser {
    CurrentUser::dummy(TEST_SUB)
}

fn state(ports: FakePorts) -> AppState<FakePorts> {
    AppState::with_ai_import(
        ports,
        /*ai_import_enabled=*/ true,
        /*max_document_bytes=*/ 4096,
        Vec::new(),
    )
}

/// Seed `block_id` into the block repo with a fresh season and grant the test
/// user an active piece-dept role in that season, so the AI block/job gates
/// (`authorize_ai_block`, `authorize_ai_job`) resolve allow from seeded rows
/// (issue #348).
async fn seed_ai_block_access(ports: &FakePorts, block_id: BlockId) {
    let season_id = SeasonId::new();
    let project_id = ProjectId::new();
    ports.block_repo.blocks.lock().await.insert(
        block_id.0,
        BlockView {
            id: block_id.0,
            season_id,
            project_id,
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
            project_id,
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

/// A PDF upload request carrying the document's display name (issue #763) —
/// percent-encoded UTF-8, exactly as the Flutter client sends it.
fn pdf_headers_with_name(block_id: BlockId, encoded_name: &str) -> HeaderMap {
    let mut headers = pdf_headers(block_id);
    headers.insert(
        "x-document-filename",
        HeaderValue::from_str(encoded_name).expect("a percent-encoded name is header-safe"),
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
        progress: None,
        next_attempt_at: None,
        attempts: Vec::new(),
        max_retries: 5,
        created_at: now,
        updated_at: now,
        telemetry: None,
        cost: None,
        source_file_name: None,
        applied_episodes: Vec::new(),
    }
}

/// Issue #763: the upload captures the picked document's own name from the
/// percent-encoded `X-Document-Filename` header, so the jobs list can show
/// which document a row belongs to. Nothing else about the raw-body contract
/// moves — same path, same declared media type, same bytes.
#[tokio::test]
async fn upload_ai_script_persists_the_percent_encoded_file_name() {
    let ports = FakePorts::default();
    let queue = ports.ai_import_queue.clone();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;

    let result = upload_ai_script::<FakePorts>(
        State(state(ports)),
        user(),
        // "Erlösung Skript.pdf" — the umlaut is percent-encoded UTF-8, because
        // an HTTP header value is ASCII.
        pdf_headers_with_name(block_id, "Erl%C3%B6sung%20Skript.pdf"),
        api::problems::Bytes(axum::body::Bytes::from_static(b"%PDF-1.7 fake")),
    )
    .await;

    let (status, Json(job_id)) = result.expect("authorized PDF upload should be accepted");
    assert_eq!(status, StatusCode::ACCEPTED);
    let job = queue
        .get(job_id)
        .await
        .expect("queue read should succeed")
        .expect("enqueued job should be retrievable");
    assert_eq!(
        job.source_file_name.as_deref(),
        Some("Erlösung Skript.pdf"),
        "the decoded name must survive verbatim"
    );
}

/// Issue #763 (CodeRabbit review): the schedule route reads the same header —
/// it hands its own `HeaderMap` to the shared enqueue helper, so a regression
/// that dropped the forwarding would otherwise pass the suite.
#[tokio::test]
async fn upload_ai_schedule_persists_the_percent_encoded_file_name() {
    let ports = FakePorts::default();
    let queue = ports.ai_import_queue.clone();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;

    let mut headers = schedule_headers("text/csv", block_id);
    headers.insert(
        "x-document-filename",
        HeaderValue::from_static("Drehplan%20299%20Erl%C3%B6sung.csv"),
    );

    let result = upload_ai_schedule::<FakePorts>(
        State(state(ports)),
        user(),
        headers,
        api::problems::Bytes(axum::body::Bytes::from_static(b"day,scene\n1,12")),
    )
    .await;

    let (status, Json(job_id)) = result.expect("authorized schedule upload should be accepted");
    assert_eq!(status, StatusCode::ACCEPTED);
    let job = queue
        .get(job_id)
        .await
        .expect("queue read should succeed")
        .expect("enqueued job should be retrievable");
    assert_eq!(
        job.source_file_name.as_deref(),
        Some("Drehplan 299 Erlösung.csv"),
    );
}

/// Issue #763: an upload without the header stores `NULL` — an honest absence,
/// never a fabricated name and never the opaque `source_handle`.
#[tokio::test]
async fn upload_ai_script_without_a_file_name_stays_absent() {
    let ports = FakePorts::default();
    let queue = ports.ai_import_queue.clone();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;

    let result = upload_ai_script::<FakePorts>(
        State(state(ports)),
        user(),
        pdf_headers(block_id),
        api::problems::Bytes(axum::body::Bytes::from_static(b"%PDF-1.7 fake")),
    )
    .await;

    let (_, Json(job_id)) = result.expect("authorized PDF upload should be accepted");
    let job = queue
        .get(job_id)
        .await
        .expect("queue read should succeed")
        .expect("enqueued job should be retrievable");
    assert_eq!(job.source_file_name, None);
}

/// Issue #763: a hostile or malformed name is sanitized at the edge — a path
/// never survives, control characters never round-trip, and a name that cannot
/// be decoded degrades to "no name" rather than an error. A display field must
/// never be able to block an upload.
#[tokio::test]
async fn upload_ai_script_sanitizes_a_hostile_file_name() {
    for (encoded, expected) in [
        // A path with a forged newline: only the basename survives.
        ("..%2F..%2Fetc%2Fpasswd%0A", Some("passwd")),
        // A CRLF header-injection attempt cannot produce a second line.
        ("a.pdf%0D%0AX-Injected%3A%201", Some("a.pdfX-Injected: 1")),
        // Invalid UTF-8 percent sequences: nothing decodable, so no name.
        ("%C3%28.pdf", None),
        // Percent-decodes to whitespace only: no name.
        ("%20%20%20", None),
        // A malformed escape is not a name either: `percent_decode_str` would
        // otherwise pass `%GG` through literally and the job would store it.
        ("script%GG.pdf", None),
        // A trailing bare `%` is equally malformed.
        ("script.pdf%", None),
    ] {
        let ports = FakePorts::default();
        let queue = ports.ai_import_queue.clone();
        let block_id = BlockId::from_uuid(Uuid::now_v7());
        seed_ai_block_access(&ports, block_id).await;

        let result = upload_ai_script::<FakePorts>(
            State(state(ports)),
            user(),
            pdf_headers_with_name(block_id, encoded),
            api::problems::Bytes(axum::body::Bytes::from_static(b"%PDF-1.7 fake")),
        )
        .await;

        let (status, Json(job_id)) = result.expect("a weird name must not fail the upload");
        assert_eq!(status, StatusCode::ACCEPTED, "{encoded}");
        let job = queue
            .get(job_id)
            .await
            .expect("queue read should succeed")
            .expect("enqueued job should be retrievable");
        assert_eq!(job.source_file_name.as_deref(), expected, "{encoded}");
    }
}

/// Issue #763: a duplicate re-upload returns the EXISTING job, whose name is
/// untouched — the row the user already knows keeps its identity (the Postgres
/// adapter's `ON CONFLICT` only echoes `dedup_key`). The 200 duplicate path and
/// its content-type contract are otherwise unchanged.
#[tokio::test]
async fn upload_ai_script_duplicate_keeps_the_first_file_name() {
    let ports = FakePorts::default();
    let queue = ports.ai_import_queue.clone();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;

    let first = upload_ai_script::<FakePorts>(
        State(state(ports.clone())),
        user(),
        pdf_headers_with_name(block_id, "Erstes%20Skript.pdf"),
        api::problems::Bytes(axum::body::Bytes::from_static(b"%PDF-1.7 fake")),
    )
    .await
    .expect("first upload should be accepted");
    let (_, Json(first_id)) = first;

    let second = upload_ai_script::<FakePorts>(
        State(state(ports)),
        user(),
        pdf_headers_with_name(block_id, "Zweites%20Skript.pdf"),
        api::problems::Bytes(axum::body::Bytes::from_static(b"%PDF-1.7 fake")),
    )
    .await
    .expect("the duplicate re-upload is a 200, not an error");
    let (status, Json(second_id)) = second;
    assert_eq!(status, StatusCode::OK, "one dedup hit is a 200");
    assert_eq!(second_id, first_id);

    let job = queue
        .get(first_id)
        .await
        .expect("queue read should succeed")
        .expect("enqueued job should be retrievable");
    assert_eq!(
        job.source_file_name.as_deref(),
        Some("Erstes Skript.pdf"),
        "the existing row keeps the name it was created with"
    );
}

#[tokio::test]
async fn upload_ai_script_enqueues_through_the_ports_seam() {
    let ports = FakePorts::default();
    let queue = ports.ai_import_queue.clone();
    let store = ports.ai_payload_store.clone();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    // Seed-backed allow (issue #348): the header block exists in a known
    // season and the caller holds a piece role there.
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
async fn upload_ai_script_rejects_wrong_content_type_with_scoped_code() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;
    // A text/plain body under the script route (declares application/pdf)
    // must be refused with the scoped AI code `ai-import.unsupported-media-type`
    // — not the generic `http.unsupported-media-type` (issue #481).
    let body = api::problems::Bytes(axum::body::Bytes::from_static(b"not a pdf"));
    let mut headers = pdf_headers(block_id);
    headers.insert("content-type", HeaderValue::from_static("text/plain"));

    let problem = upload_ai_script::<FakePorts>(State(state(ports)), user(), headers, body)
        .await
        .expect_err("wrong content type must be rejected")
        .into_problem();
    assert_eq!(problem.status, StatusCode::UNSUPPORTED_MEDIA_TYPE.as_u16());
    assert_eq!(problem.code, "ai-import.unsupported-media-type");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn upload_ai_schedule_rejects_wrong_content_type_with_scoped_code() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;
    // An image/heic body under the schedule route (declares text/csv,
    // application/pdf or text/plain) must be refused with the scoped AI code
    // `ai-import.unsupported-media-type` (issue #481).
    let body = api::problems::Bytes(axum::body::Bytes::from_static(b"nope"));
    let mut headers = pdf_headers(block_id);
    headers.insert("content-type", HeaderValue::from_static("image/heic"));

    let problem = upload_ai_schedule::<FakePorts>(State(state(ports)), user(), headers, body)
        .await
        .expect_err("wrong content type must be rejected")
        .into_problem();
    assert_eq!(problem.status, StatusCode::UNSUPPORTED_MEDIA_TYPE.as_u16());
    assert_eq!(problem.code, "ai-import.unsupported-media-type");
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
    assert_eq!(problem.code, "ai-import.forbidden");
    // Detail is localized (ADR-031 D5); the code is the contract.
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn get_ai_import_job_not_found_is_ai_import_not_found() {
    let ports = FakePorts::default();
    // No job seeded — the queue lookup returns None, so the handler emits the
    // scoped `ai-import.not-found` (issue #481), not the generic
    // `domain.not-found` the job-status watch would fall through on.
    let missing = AiImportJobId::new();

    let problem = get_ai_import_job::<FakePorts>(State(state(ports)), user(), Path(missing))
        .await
        .expect_err("a missing job must be reported as not-found")
        .into_problem();
    assert_eq!(problem.status, StatusCode::NOT_FOUND.as_u16());
    assert_eq!(problem.code, "ai-import.not-found");
    assert!(!problem.detail.is_empty());
}

/// Seed a terminal (deletable) job with both payload objects present in the
/// in-memory store — the pre-delete state the no-orphan assertion needs.
async fn seed_terminal_job_with_payloads(
    ports: &FakePorts,
    status: JobStatus,
) -> (AiImportJob, String) {
    let mut job = succeeded_job("placeholder");
    job.status = status;
    // The source payload is stored through the port itself so the handle is
    // exactly the one the production store would mint for this job.
    let source_handle = ports
        .ai_payload_store
        .put_source(job.id, b"source-bytes".to_vec())
        .await
        .expect("source store write should succeed");
    job.source_handle = source_handle.clone();
    let preview_handle = ports
        .ai_payload_store
        .put(job.id, b"preview-bytes".to_vec())
        .await
        .expect("preview store write should succeed");
    job.preview_handle = Some(preview_handle);
    ports.ai_import_queue.seed(job.clone()).await;
    (job, source_handle)
}

#[tokio::test]
async fn delete_ai_import_job_removes_a_terminal_job_and_its_payloads() {
    let ports = FakePorts::default();
    let (job, source_handle) = seed_terminal_job_with_payloads(&ports, JobStatus::DeadLetter).await;
    let job_id = job.id;
    let preview_handle = job.preview_handle.clone().expect("seeded preview handle");

    let (status, Json(())) =
        delete_ai_import_job::<FakePorts>(State(state(ports.clone())), user(), Path(job_id))
            .await
            .expect("the owner should delete their own terminal job");
    assert_eq!(status, StatusCode::NO_CONTENT);
    // The job row is gone …
    assert!(
        ports
            .ai_import_queue
            .get(job_id)
            .await
            .expect("queue read should succeed")
            .is_none()
    );
    // … and both payload objects are gone — no orphans for the GC to miss.
    assert!(
        ports
            .ai_payload_store
            .get_source(&source_handle)
            .await
            .expect("source read should succeed")
            .is_none()
    );
    assert!(
        ports
            .ai_payload_store
            .get(&preview_handle)
            .await
            .expect("preview read should succeed")
            .is_none()
    );
    // The dedup key is freed with the row: re-uploading the same document
    // enqueues a fresh job instead of bouncing off the old one.
    assert!(
        !ports
            .ai_import_queue
            .dedup
            .lock()
            .await
            .values()
            .any(|existing| *existing == job_id)
    );
}

#[tokio::test]
async fn delete_ai_import_job_refuses_a_non_terminal_job_with_the_registered_409() {
    let ports = FakePorts::default();
    let (job, source_handle) = seed_terminal_job_with_payloads(&ports, JobStatus::Failed).await;
    let job_id = job.id;
    // A `failed` job is the retryable backoff state: its source document is
    // still scheduled to run, so nothing may be deleted.
    let problem =
        delete_ai_import_job::<FakePorts>(State(state(ports.clone())), user(), Path(job_id))
            .await
            .expect_err("a non-terminal job must be refused")
            .into_problem();
    assert_eq!(problem.status, StatusCode::CONFLICT.as_u16());
    assert_eq!(problem.code, "ai-import.job-not-deletable");
    assert!(!problem.detail.is_empty());
    // The refusal is side-effect-free: row and payloads stay in place.
    assert!(
        ports
            .ai_import_queue
            .get(job_id)
            .await
            .expect("queue read should succeed")
            .is_some()
    );
    assert!(
        ports
            .ai_payload_store
            .get_source(&source_handle)
            .await
            .expect("source read should succeed")
            .is_some()
    );
}

#[tokio::test]
async fn delete_ai_import_job_denies_a_foreign_owner() {
    let ports = FakePorts::default();
    let mut job = succeeded_job("placeholder");
    job.status = JobStatus::DeadLetter;
    job.user_id = UserId::from_sub("someone-else");
    let job_id = job.id;
    ports.ai_import_queue.seed(job).await;

    let problem =
        delete_ai_import_job::<FakePorts>(State(state(ports.clone())), user(), Path(job_id))
            .await
            .expect_err("a foreign owner must be denied")
            .into_problem();
    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-import.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn delete_ai_import_job_missing_row_is_ai_import_not_found() {
    let ports = FakePorts::default();
    let missing = AiImportJobId::new();

    let problem =
        delete_ai_import_job::<FakePorts>(State(state(ports.clone())), user(), Path(missing))
            .await
            .expect_err("a missing job must be reported as not-found")
            .into_problem();
    assert_eq!(problem.status, StatusCode::NOT_FOUND.as_u16());
    assert_eq!(problem.code, "ai-import.not-found");
}

#[tokio::test]
async fn delete_frees_the_dedup_key_so_the_same_document_reuploads() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;
    let bytes = axum::body::Bytes::from_static(b"%PDF-1.7 round-trip");
    let (first_status, Json(first_id)) = upload_ai_script::<FakePorts>(
        State(state(ports.clone())),
        user(),
        pdf_headers(block_id),
        api::problems::Bytes(bytes.clone()),
    )
    .await
    .expect("first upload should enqueue");
    assert_eq!(first_status, StatusCode::ACCEPTED);
    // A second upload of the same bytes dedups onto the first job (200).
    let (second_status, Json(job_id)) = upload_ai_script::<FakePorts>(
        State(state(ports.clone())),
        user(),
        pdf_headers(block_id),
        api::problems::Bytes(bytes.clone()),
    )
    .await
    .expect("duplicate upload should dedup");
    assert_eq!(second_status, StatusCode::OK);
    assert_eq!(job_id, first_id);

    // Dead-letter the job (as a budget-exhausted worker would), then delete
    // it from the jobs list — the user's escape hatch for a stuck import.
    let mut job = ports
        .ai_import_queue
        .get(job_id)
        .await
        .expect("queue read should succeed")
        .expect("enqueued job should be retrievable");
    job.status = JobStatus::DeadLetter;
    ports.ai_import_queue.seed(job).await;
    let (status, Json(())) =
        delete_ai_import_job::<FakePorts>(State(state(ports.clone())), user(), Path(job_id))
            .await
            .expect("owner should delete their dead-letter job");
    assert_eq!(status, StatusCode::NO_CONTENT);

    // The dedup block is gone: the same document enqueues a fresh job (202).
    let (third_status, Json(fresh_id)) = upload_ai_script::<FakePorts>(
        State(state(ports.clone())),
        user(),
        pdf_headers(block_id),
        api::problems::Bytes(bytes),
    )
    .await
    .expect("re-upload after delete should enqueue");
    assert_eq!(third_status, StatusCode::ACCEPTED);
    assert_ne!(fresh_id, job_id, "the re-upload must be a fresh job");
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
    // The job's block lives in a season where the caller holds a piece
    // role, so the apply reaches the worker (issue #348).
    seed_ai_block_access(&ports, block_id).await;
    let job_id = seed_applyable_script_job(&ports, Some(block_id), 2).await;

    let (status, Json(response)) = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![
                ApplyMapping {
                    draft_ref: "scene-0".to_owned(),
                    decision: ApplyMappingDecision::Create,
                    outfit_decisions: Vec::new(),
                },
                ApplyMapping {
                    draft_ref: "scene-1".to_owned(),
                    decision: ApplyMappingDecision::Create,
                    outfit_decisions: Vec::new(),
                },
            ],
            accept_as_is: true,
            edit_distance: 0,
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
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

/// Seed a succeeded script job whose preview carries one draft row per
/// `(draft_ref, episode)` pair, so the apply can be driven across several
/// episode groups (issue #763).
async fn seed_multi_episode_script_job(
    ports: &FakePorts,
    block_id: Option<BlockId>,
) -> AiImportJobId {
    let preview = ScriptContext {
        title: Some("multi-episode script".to_owned()),
        scenes: vec![
            DraftScene {
                draft_ref: "scene-0".to_owned(),
                scene_number: Some(1),
                episode: Some(DraftEpisode {
                    number: Some(299),
                    title: Some("Erlösung".to_owned()),
                }),
                ..DraftScene::default()
            },
            DraftScene {
                draft_ref: "scene-1".to_owned(),
                scene_number: Some(2),
                episode: Some(DraftEpisode {
                    number: Some(300),
                    title: Some("Heimkehr".to_owned()),
                }),
                ..DraftScene::default()
            },
        ],
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

/// Issue #763 review (CodeRabbit): an `Update` row changes details only — the
/// scene keeps its episode — so a grouped `Update` must be attributed to the
/// primary episode, never to the group's target.
#[tokio::test]
async fn apply_ai_import_attributes_a_grouped_update_to_the_primary_episode() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    let queue = ports.ai_import_queue.clone();
    let job_id = seed_multi_episode_script_job(&ports, Some(block_id)).await;

    // The primary target episode A holds the scene the reviewer updates.
    let episode_a = EpisodeId::new();
    let episode_b = EpisodeId::new();
    {
        let mut episodes = ports.episode_repo.episodes.lock().await;
        for (id, number, name) in [(episode_a, 299, "Erlösung"), (episode_b, 300, "Heimkehr")] {
            episodes.insert(
                id.0,
                EpisodeView {
                    id: id.0,
                    block_id,
                    project_id: ProjectId::from_uuid(Uuid::now_v7()),
                    number,
                    name: Some(name.to_owned()),
                    version: AggregateVersion::INITIAL,
                    updated_at: Utc::now(),
                },
            );
        }
    }
    // The scene the Update targets lives in episode A (the handler rejects a
    // cross-episode Update target, so this is the only reachable shape).
    let scene_id = Uuid::now_v7();
    let second_scene_id = Uuid::now_v7();
    ports.scene_repo.scenes.lock().await.insert(
        second_scene_id,
        SceneView {
            id: second_scene_id,
            episode_id: episode_a,
            scene_number: Some(2),
            location: Some("Küche".to_owned()),
            mood: None,
            is_schedule_set: false,
            summary: None,
            script_day: None,
            shooting_day_ids: Vec::new(),
            assigned_characters: Vec::new(),
            outfit_beats: Vec::new(),
            source: None,
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    ports.scene_repo.scenes.lock().await.insert(
        scene_id,
        SceneView {
            id: scene_id,
            episode_id: episode_a,
            scene_number: Some(1),
            location: Some("OP".to_owned()),
            mood: None,
            is_schedule_set: false,
            summary: None,
            script_day: None,
            shooting_day_ids: Vec::new(),
            assigned_characters: Vec::new(),
            outfit_beats: Vec::new(),
            source: None,
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );

    let (status, Json(response)) = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: episode_a,
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![
                ApplyMapping {
                    draft_ref: "scene-0".to_owned(),
                    decision: ApplyMappingDecision::Update {
                        aggregate_id: scene_id,
                        version: AggregateVersion::INITIAL,
                    },
                    outfit_decisions: Vec::new(),
                },
                ApplyMapping {
                    draft_ref: "scene-1".to_owned(),
                    decision: ApplyMappingDecision::Update {
                        aggregate_id: second_scene_id,
                        version: AggregateVersion::INITIAL,
                    },
                    outfit_decisions: Vec::new(),
                },
            ],
            accept_as_is: true,
            edit_distance: 0,
            // The row carries `Ep.: 299` metadata, so the reviewer had to map a
            // group for it — here onto a DIFFERENT episode B.
            episode_groups: vec![ApplyEpisodeGroupRequest {
                episode_ref: "ep:299".to_owned(),
                target: EpisodeTarget::Existing {
                    episode_id: episode_b,
                },
            }],
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect("an in-block grouped update should apply");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        response.applied_episodes.len(),
        1,
        "only the scene's own episode may be named: {:?}",
        response.applied_episodes
    );
    assert_eq!(
        response.applied_episodes[0].id, episode_a.0,
        "an updated scene stays in its own — the primary — episode"
    );
    assert_eq!(response.applied_episodes[0].number, Some(299));
    assert_eq!(
        response.applied_episodes[0].applied_count, 2,
        "both updated rows live in the primary episode"
    );
    let stored = queue
        .applied_episodes
        .lock()
        .await
        .first()
        .cloned()
        .expect("the apply recorded the summary");
    assert_eq!(stored.1, response.applied_episodes);
}

/// Issue #763 (CodeRabbit review): the happy path of an **existing** group
/// target — the API edge resolves the episode's identity so the summary can name
/// it, and both the response and the persisted job carry it.
#[tokio::test]
async fn apply_ai_import_labels_an_existing_group_target() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    let queue = ports.ai_import_queue.clone();
    // The preview carries an `Ep.: 299` marker, so `ep:299` is a real group.
    let job_id = seed_multi_episode_script_job(&ports, Some(block_id)).await;
    // The reviewer maps both groups onto EXISTING episodes of the same block.
    let existing = EpisodeId::new();
    let existing_second = EpisodeId::new();
    {
        let mut episodes = ports.episode_repo.episodes.lock().await;
        episodes.insert(
            existing.0,
            EpisodeView {
                id: existing.0,
                block_id,
                project_id: ProjectId::from_uuid(Uuid::now_v7()),
                number: 299,
                name: Some("Erlösung".to_owned()),
                version: AggregateVersion::INITIAL,
                updated_at: Utc::now(),
            },
        );
        episodes.insert(
            existing_second.0,
            EpisodeView {
                id: existing_second.0,
                block_id,
                project_id: ProjectId::from_uuid(Uuid::now_v7()),
                number: 300,
                name: Some("Heimkehr".to_owned()),
                version: AggregateVersion::INITIAL,
                updated_at: Utc::now(),
            },
        );
    }

    let (status, Json(response)) = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![
                ApplyMapping {
                    draft_ref: "scene-0".to_owned(),
                    decision: ApplyMappingDecision::Create,
                    outfit_decisions: Vec::new(),
                },
                ApplyMapping {
                    draft_ref: "scene-1".to_owned(),
                    decision: ApplyMappingDecision::Create,
                    outfit_decisions: Vec::new(),
                },
            ],
            accept_as_is: true,
            edit_distance: 0,
            episode_groups: vec![
                ApplyEpisodeGroupRequest {
                    episode_ref: "ep:299".to_owned(),
                    target: EpisodeTarget::Existing {
                        episode_id: existing,
                    },
                },
                ApplyEpisodeGroupRequest {
                    episode_ref: "ep:300".to_owned(),
                    target: EpisodeTarget::Existing {
                        episode_id: existing_second,
                    },
                },
            ],
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect("an in-block existing target should apply");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(response.applied_episodes.len(), 2);
    let applied = &response.applied_episodes[0];
    assert_eq!(
        applied.id, existing.0,
        "the row landed in the existing episode"
    );
    assert_eq!(applied.number, Some(299));
    assert_eq!(applied.name.as_deref(), Some("Erlösung"));
    assert_eq!(applied.applied_count, 1);
    assert_eq!(response.applied_episodes[1].id, existing_second.0);
    assert_eq!(response.applied_episodes[1].number, Some(300));
    assert_eq!(
        response.applied_episodes[1].name.as_deref(),
        Some("Heimkehr")
    );
    // The persisted summary carries the same identity.
    let stored = queue
        .applied_episodes
        .lock()
        .await
        .first()
        .cloned()
        .expect("the apply recorded the summary");
    assert_eq!(stored.1, response.applied_episodes);
}

/// Issue #763 review (CWE-639): an **existing** group target is resolved at the
/// API edge purely to label the summary, so it must carry the same block guard
/// as the primary target. Otherwise a job scoped to block A could name — and
/// persist on its job row — an episode that belongs to block B.
#[tokio::test]
async fn apply_ai_import_rejects_an_existing_group_target_from_another_block() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    let mappings = ports.ai_import_mapping.clone();
    let queue = ports.ai_import_queue.clone();
    let job_id = seed_multi_episode_script_job(&ports, Some(block_id)).await;

    // The group target lives in a DIFFERENT block than the job.
    let foreign_block = BlockId::from_uuid(Uuid::now_v7());
    let foreign_episode = EpisodeId::new();
    ports.episode_repo.episodes.lock().await.insert(
        foreign_episode.0,
        EpisodeView {
            id: foreign_episode.0,
            block_id: foreign_block,
            project_id: ProjectId::from_uuid(Uuid::now_v7()),
            number: 4711,
            name: Some("Fremder Block".to_owned()),
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );

    let problem = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![ApplyMapping {
                draft_ref: "scene-0".to_owned(),
                decision: ApplyMappingDecision::Create,
                outfit_decisions: Vec::new(),
            }],
            accept_as_is: true,
            edit_distance: 0,
            episode_groups: vec![ApplyEpisodeGroupRequest {
                episode_ref: "ep:299".to_owned(),
                target: EpisodeTarget::Existing {
                    episode_id: foreign_episode,
                },
            }],
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect_err("a cross-block existing target must be rejected")
    .into_problem();

    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-import.forbidden");
    // The guard runs before the worker: nothing was written and the job's
    // summary was never touched.
    assert!(
        mappings
            .list_by_preview(job_id)
            .await
            .expect("mapping read should succeed")
            .is_empty(),
        "a rejected apply must not write any mapping"
    );
    assert!(
        queue.applied_episodes.lock().await.is_empty(),
        "a rejected apply must not persist an applied-episode summary"
    );
}

/// Issue #763: a successful apply records the episodes its rows landed in, both
/// on the job (so the jobs list can name the target) and in the response. The
/// label comes from data the request path already holds — the target episode the
/// handler resolved — never from a second projection lookup.
#[tokio::test]
async fn apply_ai_import_records_the_target_episode_on_the_job() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    let queue = ports.ai_import_queue.clone();
    let job_id = seed_applyable_script_job(&ports, Some(block_id), 2).await;
    // The target episode is the one the reviewer picked; seed its identity so
    // the summary carries a real number and title, not a stub.
    let episode_id = EpisodeId::new();
    ports.episode_repo.episodes.lock().await.insert(
        episode_id.0,
        EpisodeView {
            id: episode_id.0,
            block_id,
            project_id: ProjectId::from_uuid(Uuid::now_v7()),
            number: 299,
            name: Some("Erlösung".to_owned()),
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );

    let (status, Json(response)) = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id,
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![
                ApplyMapping {
                    draft_ref: "scene-0".to_owned(),
                    decision: ApplyMappingDecision::Create,
                    outfit_decisions: Vec::new(),
                },
                ApplyMapping {
                    draft_ref: "scene-1".to_owned(),
                    decision: ApplyMappingDecision::Create,
                    outfit_decisions: Vec::new(),
                },
            ],
            accept_as_is: true,
            edit_distance: 0,
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect("an in-block apply should succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(response.applied_episodes.len(), 1, "one target episode");
    let applied = &response.applied_episodes[0];
    assert_eq!(applied.id, episode_id.0);
    assert_eq!(applied.number, Some(299));
    assert_eq!(applied.name.as_deref(), Some("Erlösung"));
    assert_eq!(applied.applied_count, 2, "both rows landed in it");

    // The summary was persisted through the queue port (the jobs list reads it
    // back later), and it is identical to what the response carried.
    let sink = queue.applied_episodes.lock().await;
    assert_eq!(sink.len(), 1, "the apply must record the summary once");
    assert_eq!(sink[0].0, job_id);
    assert_eq!(sink[0].1, response.applied_episodes);
    drop(sink);
    let stored = queue
        .get(job_id)
        .await
        .expect("queue read should succeed")
        .expect("the job still exists");
    assert_eq!(stored.applied_episodes, response.applied_episodes);
}

/// Issue #763, multi-episode case: rows applied across episode groups are
/// reported per episode with their own counts — the list renders
/// `299 Erlösung (+2)` from exactly this list.
#[tokio::test]
async fn apply_ai_import_records_every_target_episode() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    let queue = ports.ai_import_queue.clone();
    let job_id = seed_multi_episode_script_job(&ports, Some(block_id)).await;
    let default_episode = EpisodeId::new();

    let (status, Json(response)) = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: default_episode,
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![
                ApplyMapping {
                    draft_ref: "scene-0".to_owned(),
                    decision: ApplyMappingDecision::Create,
                    outfit_decisions: Vec::new(),
                },
                ApplyMapping {
                    draft_ref: "scene-1".to_owned(),
                    decision: ApplyMappingDecision::Create,
                    outfit_decisions: Vec::new(),
                },
            ],
            accept_as_is: true,
            edit_distance: 0,
            // Both groups CREATE their episode, so the numbers/titles come from
            // the plan the apply builds — no projection read is involved.
            episode_groups: vec![
                ApplyEpisodeGroupRequest {
                    episode_ref: "ep:299".to_owned(),
                    target: EpisodeTarget::Create {
                        number: 299,
                        name: Some("Erlösung".to_owned()),
                    },
                },
                ApplyEpisodeGroupRequest {
                    episode_ref: "ep:300".to_owned(),
                    target: EpisodeTarget::Create {
                        number: 300,
                        name: Some("Heimkehr".to_owned()),
                    },
                },
            ],
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect("a multi-episode apply should succeed");

    assert_eq!(status, StatusCode::OK);
    let numbers: Vec<Option<i32>> = response
        .applied_episodes
        .iter()
        .map(|episode| episode.number)
        .collect();
    assert_eq!(
        numbers,
        vec![Some(299), Some(300)],
        "one entry per target episode, in applied order"
    );
    let names: Vec<Option<&str>> = response
        .applied_episodes
        .iter()
        .map(|episode| episode.name.as_deref())
        .collect();
    assert_eq!(names, vec![Some("Erlösung"), Some("Heimkehr")]);
    assert!(
        response
            .applied_episodes
            .iter()
            .all(|episode| episode.applied_count == 1),
        "each row landed in its own episode"
    );
    let sink = queue.applied_episodes.lock().await;
    assert_eq!(sink.len(), 1);
    assert_eq!(sink[0].1, response.applied_episodes);
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
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![ApplyMapping {
                draft_ref: "scene-0".to_owned(),
                decision: ApplyMappingDecision::Create,
                outfit_decisions: Vec::new(),
            }],
            accept_as_is: true,
            edit_distance: 0,
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect_err("a cross-block apply must be rejected")
    .into_problem();

    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-import.forbidden");
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
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![ApplyMapping {
                draft_ref: "scene-0".to_owned(),
                decision: ApplyMappingDecision::Create,
                outfit_decisions: Vec::new(),
            }],
            // Contradictory: "no edits" alongside a nonzero edit count.
            accept_as_is: true,
            edit_distance: 3,
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
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
    // The config's key is an active Neuralwatt credential owned by the caller
    // (issue #552) — the API-edge ownership pre-check resolves it before
    // dispatching the create.
    ports
        .settings_repo
        .bind_vault_key("vault-key", LlmProvider::Neuralwatt.as_str(), TEST_SUB)
        .await;
    // The replacement key is an active Ollama credential (issue #528) — the
    // API-edge pre-check resolves it before dispatching the update.
    ports
        .settings_repo
        .bind_vault_key(
            "replacement-vault-key",
            LlmProvider::Ollama.as_str(),
            TEST_SUB,
        )
        .await;
    let state = state(ports);

    let (status, Json(created)) = create_ai_config::<FakePorts>(
        State(state.clone()),
        user(),
        Json(CreateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            cost_display_preference: CostDisplayPreference::Token,
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
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            id: created.id,
            user_id: UserId::from_sub(TEST_SUB),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            // Stored prompt texts: issue #490 — the GET must expose them so
            // the configured/edit form can render what is persisted.
            prompts: HashMap::from([
                (DocumentKind::Script, "script-prompt".to_owned()),
                (DocumentKind::Schedule, "schedule-prompt".to_owned()),
            ]),
            prompt_kinds: vec![DocumentKind::Script, DocumentKind::Schedule],
            // Both stored texts are non-blank, so both are pinned to a snapshot
            // rather than following the deployment default (design D6). Seeded in
            // the order the production view emits (sorted by `kind.as_str()`).
            stored_prompt_kinds: vec![DocumentKind::Schedule, DocumentKind::Script],
            vault_key_id: "vault-key".to_owned(),
            version: created.version,
            revoked: false,
            cost_display_preference: CostDisplayPreference::Token,
        },
    );

    let (status, Json(view)) =
        get_ai_config::<FakePorts>(State(state.clone()), user(), Path(created.id))
            .await
            .expect("owner may read their config");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(view.id, created.id);
    // The stored prompt TEXTS round-trip through the read view (issue
    // #490) — not just the active kinds.
    assert_eq!(
        view.prompts.get(&DocumentKind::Script).map(String::as_str),
        Some("script-prompt")
    );
    assert_eq!(
        view.prompts
            .get(&DocumentKind::Schedule)
            .map(String::as_str),
        Some("schedule-prompt")
    );
    // Design D6: both texts are stored, so both are pinned to a snapshot rather
    // than following the deployment default — the surface has to say so, or an
    // operator hardening `default_ai_prompts.toml` believes their imports picked
    // it up. Observed live: a config kept the previous three-line prompt and
    // silently ignored a hardened one, costing a whole test round.
    assert!(
        view.stored_prompt_kinds.contains(&DocumentKind::Script)
            && view.stored_prompt_kinds.contains(&DocumentKind::Schedule),
        "a non-blank stored prompt must be reported as in effect: {:?}",
        view.stored_prompt_kinds
    );
    // Design D6: the read view must also say that these are *stored* snapshots,
    // i.e. that this configuration will not follow a later hardening of the
    // deployment default. Without the flag the override is invisible — the exact
    // live failure where a stale three-line prompt silently beat a hardened
    // default for a whole test round.
    let stored: Vec<&str> = view
        .stored_prompt_kinds
        .iter()
        .map(|kind| kind.as_str())
        .collect();
    assert_eq!(
        stored,
        vec![
            DocumentKind::Schedule.as_str(),
            DocumentKind::Script.as_str()
        ],
        "both kinds are pinned to a stored prompt and must be reported as such"
    );

    let (status, Json(_)) = update_ai_config::<FakePorts>(
        State(state.clone()),
        user(),
        Path(created.id),
        Json(UpdateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Ollama,
            assistant_model: "assistant-v2".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "replacement-vault-key".to_owned(),
            version: created.version,
            cost_display_preference: Some(CostDisplayPreference::Token),
        }),
    )
    .await
    .expect("owner may update their config");
    assert_eq!(status, StatusCode::OK);
    let updated = commands.updated.lock().await;
    assert_eq!(updated.len(), 1);
    assert_eq!(updated[0].provider, LlmProvider::Ollama);
    assert_eq!(updated[0].vault_key_id, "replacement-vault-key");
    drop(updated);

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
async fn ai_config_update_rejects_vault_key_from_another_provider() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let commands = ports.ai_config_commands.clone();
    // The key IS a real credential — it just belongs to OpenAI, not to the
    // Ollama provider the request pairs it with.
    ports
        .settings_repo
        .bind_vault_key("openai-vault-key", LlmProvider::OpenAI.as_str(), TEST_SUB)
        .await;
    let id = Uuid::now_v7();
    ports.ai_config_repo.views.lock().await.insert(
        id,
        AiConfigView {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            id,
            user_id: UserId::from_sub(TEST_SUB),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            prompt_kinds: vec![],
            stored_prompt_kinds: vec![],
            vault_key_id: "vault-key".to_owned(),
            version: AggregateVersion(2),
            revoked: false,
            cost_display_preference: CostDisplayPreference::Token,
        },
    );
    let state = state(ports);

    let problem = update_ai_config::<FakePorts>(
        State(state.clone()),
        user(),
        Path(id),
        Json(UpdateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Ollama,
            assistant_model: "assistant-v2".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "openai-vault-key".to_owned(),
            version: AggregateVersion(2),
            cost_display_preference: Some(CostDisplayPreference::Token),
        }),
    )
    .await
    .expect_err("a key bound to another provider must not be paired with it")
    .into_problem();

    assert_eq!(problem.status, StatusCode::CONFLICT.as_u16());
    assert_eq!(problem.code, "ai-config.provider-mismatch");
    // The command was never dispatched — no write-side event.
    assert!(commands.updated.lock().await.is_empty());
}

#[tokio::test]
async fn ai_config_update_rejects_unknown_vault_key() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let commands = ports.ai_config_commands.clone();
    // No credential is registered for this key (never created, purged, or a
    // projection miss) — the ownership pre-check fails closed into the same
    // 403 the create path emits, so the update route cannot be used as a
    // key-existence oracle (unknown vs. foreign must be indistinguishable,
    // issue #552 review).
    let id = Uuid::now_v7();
    ports.ai_config_repo.views.lock().await.insert(
        id,
        AiConfigView {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            id,
            user_id: UserId::from_sub(TEST_SUB),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            prompt_kinds: vec![],
            stored_prompt_kinds: vec![],
            vault_key_id: "vault-key".to_owned(),
            version: AggregateVersion(2),
            revoked: false,
            cost_display_preference: CostDisplayPreference::Token,
        },
    );
    let state = state(ports);

    let problem = update_ai_config::<FakePorts>(
        State(state.clone()),
        user(),
        Path(id),
        Json(UpdateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Ollama,
            assistant_model: "assistant-v2".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "never-vaulted-key".to_owned(),
            version: AggregateVersion(2),
            cost_display_preference: Some(CostDisplayPreference::Token),
        }),
    )
    .await
    .expect_err("an unknown vault key must not be persisted")
    .into_problem();

    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-config.vault-key-forbidden");
    assert!(commands.updated.lock().await.is_empty());
}

#[tokio::test]
async fn ai_config_update_keeps_unchanged_vault_key_without_binding_lookup() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let commands = ports.ai_config_commands.clone();
    // NO credential is registered for the currently bound key: an unchanged
    // key must not be re-validated, so a prompt/model-only edit cannot be
    // blocked by a projection miss (the aggregate remains the authority for
    // the provider/key pairing).
    let id = Uuid::now_v7();
    ports.ai_config_repo.views.lock().await.insert(
        id,
        AiConfigView {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            id,
            user_id: UserId::from_sub(TEST_SUB),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            prompt_kinds: vec![],
            stored_prompt_kinds: vec![],
            vault_key_id: "vault-key".to_owned(),
            version: AggregateVersion(2),
            revoked: false,
            cost_display_preference: CostDisplayPreference::Token,
        },
    );
    let state = state(ports);

    let (status, Json(_)) = update_ai_config::<FakePorts>(
        State(state.clone()),
        user(),
        Path(id),
        Json(UpdateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant-v2".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            version: AggregateVersion(2),
            cost_display_preference: Some(CostDisplayPreference::Token),
        }),
    )
    .await
    .expect("an unchanged key keeps the prompt/model edit working");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(commands.updated.lock().await.len(), 1);
}

#[tokio::test]
async fn ai_config_version_conflict_is_scoped_409() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let commands = ports.ai_config_commands.clone();
    *commands.version_conflict.lock().await = true;
    let id = Uuid::now_v7();
    // Seed the read-model row so the ownership check is satisfied.
    ports.ai_config_repo.views.lock().await.insert(
        id,
        AiConfigView {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            id,
            user_id: UserId::from_sub(TEST_SUB),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            prompt_kinds: vec![],
            stored_prompt_kinds: vec![],
            vault_key_id: "vault-key".to_owned(),
            version: AggregateVersion(2),
            revoked: false,
            cost_display_preference: CostDisplayPreference::Token,
        },
    );
    let state = state(ports);

    let problem = update_ai_config::<FakePorts>(
        State(state.clone()),
        user(),
        Path(id),
        Json(UpdateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant-v2".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            version: AggregateVersion(2),
            cost_display_preference: Some(CostDisplayPreference::Token),
        }),
    )
    .await
    .expect_err("a stale version must surface as a scoped version conflict")
    .into_problem();
    assert_eq!(problem.status, StatusCode::CONFLICT.as_u16());
    assert_eq!(problem.code, "ai-config.version-mismatch");
    // The typed S0 extensions are preserved alongside the scoped code.
    let extensions = problem
        .extensions
        .as_ref()
        .expect("version conflict carries typed extensions");
    assert_eq!(extensions["expected_version"], 2);
    assert_eq!(extensions["current_version"], 3);
    assert!(!problem.detail.is_empty());
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
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            id,
            user_id: UserId::from_sub("someone-else"),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            prompt_kinds: vec![],
            stored_prompt_kinds: vec![],
            vault_key_id: "vault-key".to_owned(),
            version: AggregateVersion::INITIAL,
            revoked: false,
            cost_display_preference: CostDisplayPreference::Token,
        },
    );

    let problem = get_ai_config::<FakePorts>(State(state(ports)), user(), Path(id))
        .await
        .expect_err("a foreign owner must be denied")
        .into_problem();
    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-config.forbidden");
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
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            cost_display_preference: CostDisplayPreference::Token,
        }),
    )
    .await
    .expect_err("a non-credential-role caller must be denied")
    .into_problem();
    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-config.forbidden");
    // Detail is localized (ADR-031 D5); the code is the contract.
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn ai_upload_is_feature_disabled_when_the_feature_is_disabled() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    let state = AppState::with_ai_import(
        ports,
        /*ai_import_enabled=*/ false,
        /*max_document_bytes=*/ 4096,
        Vec::new(),
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
    assert_eq!(problem.code, "ai-import.disabled");
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
        project_id: None,
    })
}

/// Read a `no_store_json` list response: assert the anti-cache header, then
/// return the status and the deserialized JSON body.
async fn read_no_store_list<T: serde::de::DeserializeOwned>(
    response: axum::response::Response,
) -> (StatusCode, T) {
    assert_eq!(
        response
            .headers()
            .get(axum::http::header::CACHE_CONTROL)
            .and_then(|value| value.to_str().ok()),
        Some("no-store"),
        "authenticated AI lists must not be cacheable"
    );
    let status = response.status();
    let body = axum::body::to_bytes(response.into_body(), 1024 * 1024)
        .await
        .expect("list body should read");
    let value = serde_json::from_slice(&body).expect("list body is JSON");
    (status, value)
}

/// Seed a block in a fresh season *without* granting the caller a role there,
/// so the AI season gate denies jobs pointing at it (fail-closed fakes,
/// issue #348).
async fn seed_denied_block(ports: &FakePorts) -> BlockId {
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    ports.block_repo.blocks.lock().await.insert(
        block_id.0,
        BlockView {
            id: block_id.0,
            season_id: SeasonId::new(),
            project_id: ProjectId::new(),
            number: 1,
            start_date: None,
            end_date: None,
            version: AggregateVersion::INITIAL,
            updated_at: Utc::now(),
        },
    );
    block_id
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

    let response =
        list_ai_import_jobs::<FakePorts>(State(state(ports)), user(), jobs_query(None, None))
            .await
            .expect("owner should list their own jobs");
    let (status, jobs): (StatusCode, Vec<AiImportJobResponse>) = read_no_store_list(response).await;
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

    let response = list_ai_import_jobs::<FakePorts>(
        State(state(ports.clone())),
        user(),
        jobs_query(Some(1), Some(1)),
    )
    .await
    .expect("pagination should select the middle row");
    let (status, page): (StatusCode, Vec<AiImportJobResponse>) = read_no_store_list(response).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(page.len(), 1);
}

#[tokio::test]
async fn list_ai_import_jobs_paginates_visible_rows_after_the_season_gate() {
    let ports = FakePorts::default();
    let denied_block = seed_denied_block(&ports).await;
    let base = Utc::now();
    let mut denied_newest = succeeded_job("ai-preview/denied-newest");
    denied_newest.block_id = Some(denied_block);
    denied_newest.created_at = base + chrono::Duration::seconds(30);
    denied_newest.updated_at = denied_newest.created_at;
    let mut denied_older = succeeded_job("ai-preview/denied-older");
    denied_older.block_id = Some(denied_block);
    denied_older.created_at = base + chrono::Duration::seconds(20);
    denied_older.updated_at = denied_older.created_at;
    let mut allowed_newer = succeeded_job("ai-preview/allowed-newer");
    allowed_newer.created_at = base + chrono::Duration::seconds(10);
    allowed_newer.updated_at = allowed_newer.created_at;
    let mut allowed_older = succeeded_job("ai-preview/allowed-older");
    allowed_older.created_at = base;
    allowed_older.updated_at = base;
    let allowed_newer_id = allowed_newer.id;
    let allowed_older_id = allowed_older.id;
    for job in [denied_newest, denied_older, allowed_newer, allowed_older] {
        ports.ai_import_queue.seed(job).await;
    }

    // Two denied rows precede the allowed ones in stored order; the visible
    // page must still fill from the allowed rows (previously: empty page).
    let response = list_ai_import_jobs::<FakePorts>(
        State(state(ports.clone())),
        user(),
        jobs_query(Some(2), Some(0)),
    )
    .await
    .expect("denied rows must not punch holes in the page");
    let (status, jobs): (StatusCode, Vec<AiImportJobResponse>) = read_no_store_list(response).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        jobs.iter().map(|entry| entry.job.id).collect::<Vec<_>>(),
        vec![allowed_newer_id, allowed_older_id],
        "pagination must slice visible rows, not stored rows"
    );

    // The offset counts visible rows, not stored rows.
    let response =
        list_ai_import_jobs::<FakePorts>(State(state(ports)), user(), jobs_query(Some(1), Some(1)))
            .await
            .expect("offset must skip visible rows");
    let (status, jobs): (StatusCode, Vec<AiImportJobResponse>) = read_no_store_list(response).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        jobs.iter().map(|entry| entry.job.id).collect::<Vec<_>>(),
        vec![allowed_older_id],
        "offset must skip visible rows, not stored rows"
    );
}

#[tokio::test]
async fn list_ai_import_jobs_scans_past_a_full_denied_page() {
    let ports = FakePorts::default();
    let denied_block = seed_denied_block(&ports).await;
    let base = Utc::now();
    // One full scan window of denied rows: the visible scan must advance to
    // the next stored page instead of stopping at the first page boundary.
    for index in 0..100 {
        let mut denied = succeeded_job(&format!("ai-preview/denied-{index}"));
        denied.block_id = Some(denied_block);
        denied.created_at = base + chrono::Duration::seconds(index + 1);
        denied.updated_at = denied.created_at;
        ports.ai_import_queue.seed(denied).await;
    }
    let mut allowed = succeeded_job("ai-preview/allowed");
    allowed.created_at = base;
    allowed.updated_at = base;
    let allowed_id = allowed.id;
    ports.ai_import_queue.seed(allowed).await;

    let response =
        list_ai_import_jobs::<FakePorts>(State(state(ports)), user(), jobs_query(None, None))
            .await
            .expect("the scan must reach past the denied page");
    let (status, jobs): (StatusCode, Vec<AiImportJobResponse>) = read_no_store_list(response).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        jobs.iter().map(|entry| entry.job.id).collect::<Vec<_>>(),
        vec![allowed_id],
        "the visible scan must advance past a full page of denied rows"
    );
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
    *ports.membership_repo.piece_role_override.lock().await = Some(Ok(false));

    let response =
        list_ai_import_jobs::<FakePorts>(State(state(ports)), user(), jobs_query(None, None))
            .await
            .expect("gate denials must skip rows, not fail the list");
    let (status, jobs): (StatusCode, Vec<AiImportJobResponse>) = read_no_store_list(response).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(jobs.len(), 1);
    assert_eq!(
        jobs[0].job.preview_handle.as_deref(),
        Some("ai-preview/plain")
    );
}

fn config_view(user_sub: &str) -> AiConfigView {
    AiConfigView {
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        id: Uuid::now_v7(),
        user_id: UserId::from_sub(user_sub),
        provider: LlmProvider::Neuralwatt,
        assistant_model: "assistant".to_owned(),
        image_model: None,
        prompts: HashMap::new(),
        prompt_kinds: vec![],
        stored_prompt_kinds: vec![],
        vault_key_id: "vault-key".to_owned(),
        version: AggregateVersion::INITIAL,
        revoked: false,
        cost_display_preference: CostDisplayPreference::Token,
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

    let response =
        list_ai_configs::<FakePorts>(State(state(ports)), user(), jobs_query(None, None))
            .await
            .expect("credential-role member should discover their configs");
    let (status, views): (StatusCode, Vec<AiConfigView>) = read_no_store_list(response).await;
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
    assert_eq!(problem.code, "ai-config.forbidden");
    assert!(!problem.detail.is_empty());
}

#[tokio::test]
async fn ai_config_create_rejects_a_foreign_vault_key() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let commands = ports.ai_config_commands.clone();
    // The key IS a real, active credential of the requested provider — but it
    // belongs to another user. Owning it, not provider pairing, is what the
    // create path checks (issue #552).
    ports
        .settings_repo
        .bind_vault_key(
            "foreign-vault-key",
            LlmProvider::Neuralwatt.as_str(),
            "someone-else",
        )
        .await;
    let state = state(ports);

    let problem = create_ai_config::<FakePorts>(
        State(state),
        user(),
        Json(CreateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "foreign-vault-key".to_owned(),
            cost_display_preference: CostDisplayPreference::Token,
        }),
    )
    .await
    .expect_err("a foreign credential binding must not be usable by another user")
    .into_problem();

    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-config.vault-key-forbidden");
    // The command was never dispatched — no write-side event.
    assert!(commands.created.lock().await.is_empty());
}

#[tokio::test]
async fn ai_config_create_rejects_an_unknown_vault_key_fail_closed() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let commands = ports.ai_config_commands.clone();
    // No binding exists for this key (unknown owner ⇒ unknown binding) — the
    // ownership pre-check fails closed; the worker never sees the config.
    let state = state(ports);

    let problem = create_ai_config::<FakePorts>(
        State(state),
        user(),
        Json(CreateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "never-vaulted-key".to_owned(),
            cost_display_preference: CostDisplayPreference::Token,
        }),
    )
    .await
    .expect_err("an unknown vault key must be rejected at the edge")
    .into_problem();

    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-config.vault-key-forbidden");
    assert!(commands.created.lock().await.is_empty());
}

#[tokio::test]
async fn ai_config_update_rejects_a_foreign_replacement_vault_key() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let commands = ports.ai_config_commands.clone();
    // Real, active, RIGHT-provider credential — owned by someone else. The
    // ownership check must fire before the provider check (issue #552).
    ports
        .settings_repo
        .bind_vault_key(
            "foreign-vault-key",
            LlmProvider::Ollama.as_str(),
            "someone-else",
        )
        .await;
    let id = Uuid::now_v7();
    ports.ai_config_repo.views.lock().await.insert(
        id,
        AiConfigView {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            id,
            user_id: UserId::from_sub(TEST_SUB),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            prompt_kinds: vec![],
            stored_prompt_kinds: vec![],
            vault_key_id: "vault-key".to_owned(),
            version: AggregateVersion(2),
            revoked: false,
            cost_display_preference: CostDisplayPreference::Token,
        },
    );
    let state = state(ports);

    let problem = update_ai_config::<FakePorts>(
        State(state),
        user(),
        Path(id),
        Json(UpdateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Ollama,
            assistant_model: "assistant-v2".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "foreign-vault-key".to_owned(),
            version: AggregateVersion(2),
            cost_display_preference: Some(CostDisplayPreference::Token),
        }),
    )
    .await
    .expect_err("a foreign credential binding must not become this config's key")
    .into_problem();

    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-config.vault-key-forbidden");
    assert!(commands.updated.lock().await.is_empty());
}

// ===========================================================================
// Episode groups on the apply endpoint (issue #581)
// ===========================================================================

/// Seed a succeeded script job whose preview carries `scene_count` rows, the
/// first of which belongs to episode group `ep:7`.
async fn seed_episode_grouped_script_job(
    ports: &FakePorts,
    block_id: Option<BlockId>,
    scene_count: usize,
) -> AiImportJobId {
    let preview = ScriptContext {
        title: Some("grouped script".to_owned()),
        scenes: (0..scene_count)
            .map(|i| DraftScene {
                draft_ref: format!("scene-{i}"),
                scene_number: Some(i as u32 + 1),
                episode: Some(breakdown_core::ai::DraftEpisode {
                    number: Some(7),
                    title: None,
                }),
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

fn create_group_request(number: i32) -> ApplyEpisodeGroupRequest {
    ApplyEpisodeGroupRequest {
        episode_ref: "ep:7".to_owned(),
        target: EpisodeTarget::Create {
            number,
            name: Some("Episode 7".to_owned()),
        },
    }
}

#[tokio::test]
async fn apply_ai_import_rejects_an_episode_group_the_preview_does_not_carry() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    // The preview carries NO episode metadata at all.
    let job_id = seed_applyable_script_job(&ports, Some(block_id), 1).await;

    let problem = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![ApplyMapping {
                draft_ref: "scene-0".to_owned(),
                decision: ApplyMappingDecision::Create,
                outfit_decisions: Vec::new(),
            }],
            accept_as_is: true,
            edit_distance: 0,
            episode_groups: vec![create_group_request(7)],
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect_err("unknown group must be rejected")
    .into_problem();
    assert_eq!(problem.status, StatusCode::UNPROCESSABLE_ENTITY.as_u16());
    assert_eq!(problem.code, "domain.validation");
}

#[tokio::test]
async fn apply_ai_import_prechecks_a_taken_episode_number_with_409() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;
    let job_id = seed_episode_grouped_script_job(&ports, Some(block_id), 1).await;
    // Seed the apply's target episode (pinned into the job's block) and a
    // sibling of the SAME series already using number 7 — the number the
    // create group wants. The sibling lives in a DIFFERENT block (issue
    // #705's shape: project-global numbering collides across blocks), so the
    // 409's `existing_block_id` must carry that foreign home block.
    let project_id = ProjectId::from_uuid(Uuid::now_v7());
    let other_block = BlockId::from_uuid(Uuid::now_v7());
    let target = EpisodeView {
        id: Uuid::now_v7(),
        block_id,
        project_id,
        number: 1,
        name: None,
        version: AggregateVersion::INITIAL,
        updated_at: chrono::Utc::now(),
    };
    let taken = EpisodeView {
        id: Uuid::now_v7(),
        block_id: other_block,
        project_id,
        number: 7,
        name: None,
        version: AggregateVersion::INITIAL,
        updated_at: chrono::Utc::now(),
    };
    let taken_id = taken.id;
    ports
        .episode_repo
        .episodes
        .lock()
        .await
        .insert(target.id, target.clone());
    ports
        .episode_repo
        .episodes
        .lock()
        .await
        .insert(taken.id, taken);

    let problem = apply_ai_import::<FakePorts>(
        State(state(ports.clone())),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::from_uuid(target.id),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![ApplyMapping {
                draft_ref: "scene-0".to_owned(),
                decision: ApplyMappingDecision::Create,
                outfit_decisions: Vec::new(),
            }],
            accept_as_is: true,
            edit_distance: 0,
            episode_groups: vec![create_group_request(7)],
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect_err("taken episode number must be a clean 409")
    .into_problem();
    // #404 doctrine: the API-edge pre-check is advisory; the projection
    // unique index stays authoritative.
    assert_eq!(problem.status, StatusCode::CONFLICT.as_u16());
    assert_eq!(problem.code, "episode.number-already-exists");
    // Issue #665: the S1 `existing_episode_id` extension carries the existing
    // episode's id, so the client can offer assign-existing in one tap.
    assert_eq!(
        problem
            .extensions
            .as_ref()
            .and_then(|ext| ext.get("existing_episode_id"))
            .and_then(|value| value.as_str()),
        Some(taken_id.to_string().as_str())
    );
    assert_eq!(
        problem
            .extensions
            .as_ref()
            .and_then(|ext| ext.get("number"))
            .and_then(|value| value.as_i64()),
        Some(7)
    );
    // Issue #705: the S1 `existing_block_id` extension carries the
    // conflicting episode's home block — a DIFFERENT one than the job's, so
    // the client can offer the scope-switch recovery instead of the
    // assign-existing tap that would 403 at the cross-block IDOR gate.
    assert_eq!(
        problem
            .extensions
            .as_ref()
            .and_then(|ext| ext.get("existing_block_id"))
            .and_then(|value| value.as_str()),
        Some(other_block.0.to_string().as_str())
    );
    // The pre-check fires BEFORE any dispatch: nothing was created.
    assert!(
        ports.episode_commands.created.lock().await.is_empty(),
        "a 409 pre-check must not create an episode"
    );
}

#[tokio::test]
async fn apply_ai_import_creates_an_episode_for_a_free_group_number() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    seed_ai_block_access(&ports, block_id).await;
    let job_id = seed_episode_grouped_script_job(&ports, Some(block_id), 1).await;
    let project_id = ProjectId::from_uuid(Uuid::now_v7());
    let target = EpisodeView {
        id: Uuid::now_v7(),
        block_id,
        project_id,
        number: 1,
        name: None,
        version: AggregateVersion::INITIAL,
        updated_at: chrono::Utc::now(),
    };
    ports
        .episode_repo
        .episodes
        .lock()
        .await
        .insert(target.id, target.clone());

    let (status, Json(response)) = apply_ai_import::<FakePorts>(
        State(state(ports.clone())),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::from_uuid(target.id),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![ApplyMapping {
                draft_ref: "scene-0".to_owned(),
                decision: ApplyMappingDecision::Create,
                outfit_decisions: Vec::new(),
            }],
            accept_as_is: true,
            edit_distance: 0,
            episode_groups: vec![create_group_request(7)],
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect("free episode number applies");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(response.created_episodes, 1);
    let created = ports.episode_commands.created.lock().await;
    assert_eq!(created.len(), 1);
    assert_eq!(created[0].number, 7);
    assert_eq!(created[0].block_id, block_id);
    assert_eq!(created[0].project_id, project_id);
}

#[tokio::test]
async fn apply_ai_import_rejects_more_episode_groups_than_the_preview_carries() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    // The preview carries ONE group (ep:7); the request tries two. The bound
    // mirrors the mappings/piece-decisions bounds: reject before the
    // per-group validation reads (CodeRabbit review, issue #581).
    let job_id = seed_episode_grouped_script_job(&ports, Some(block_id), 1).await;

    let mut second = create_group_request(9);
    second.episode_ref = "ep:9".to_owned();
    let problem = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: vec![ApplyMapping {
                draft_ref: "scene-0".to_owned(),
                decision: ApplyMappingDecision::Create,
                outfit_decisions: Vec::new(),
            }],
            accept_as_is: true,
            edit_distance: 0,
            episode_groups: vec![create_group_request(7), second],
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect_err("an oversized group list must be rejected before any read")
    .into_problem();
    assert_eq!(problem.status, StatusCode::UNPROCESSABLE_ENTITY.as_u16());
    assert_eq!(problem.code, "domain.validation");
}

// ===========================================================================
// Issue #663: uncertainty acknowledgements + dedicated apply-gate codes
// ===========================================================================

/// Seeds a succeeded script job whose preview carries ONE blocking
/// `field_ambiguity` uncertainty on scene 0 (plus a non-blocking
/// `dropped_row` that must never gate) and returns the job id.
async fn seed_blocking_uncertainty_job(
    ports: &FakePorts,
    block_id: Option<BlockId>,
) -> AiImportJobId {
    let preview = ScriptContext {
        title: Some("blocked script".to_owned()),
        scenes: (0..2)
            .map(|i| DraftScene {
                draft_ref: format!("scene-{i}"),
                scene_number: Some(i as u32 + 1),
                ..DraftScene::default()
            })
            .collect(),
        uncertainties: vec![
            Uncertainty {
                scene_index: 0,
                field: "location".to_owned(),
                note: "ambiguous heading".to_owned(),
                suggested_value: Some("Keller".to_owned()),
                kind: UncertaintyKind::FieldAmbiguity,
                candidates: Vec::new(),
            },
            Uncertainty {
                scene_index: 0,
                field: "piece".to_owned(),
                note: "dropped row".to_owned(),
                suggested_value: None,
                kind: UncertaintyKind::DroppedRow,
                candidates: Vec::new(),
            },
        ],
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

fn create_mappings() -> Vec<ApplyMapping> {
    (0..2)
        .map(|i| ApplyMapping {
            draft_ref: format!("scene-{i}"),
            decision: ApplyMappingDecision::Create,
            outfit_decisions: Vec::new(),
        })
        .collect()
}

#[tokio::test]
async fn apply_with_blocking_uncertainty_answers_apply_blocked_with_the_items() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    let job_id = seed_blocking_uncertainty_job(&ports, Some(block_id)).await;

    let problem = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: Vec::new(),
            mappings: create_mappings(),
            accept_as_is: false,
            edit_distance: 0,
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect_err("an unacknowledged blocking uncertainty must refuse the apply")
    .into_problem();

    assert_eq!(problem.status, StatusCode::CONFLICT.as_u16());
    assert_eq!(problem.code, "ai-import.apply-blocked");
    assert!(!problem.detail.is_empty());
    // The S1 extension names exactly the remaining blocking items — the
    // advisory `dropped_row` is not among them (it never gates).
    let items = problem
        .extensions
        .as_ref()
        .and_then(|ext| ext.get("blocking_uncertainties"))
        .cloned()
        .unwrap_or_default();
    let items = items.as_array().cloned().unwrap_or_default();
    assert_eq!(items.len(), 1, "only the field_ambiguity blocks: {items:?}");
    assert_eq!(items[0]["field"], "location");
    assert_eq!(items[0]["kind"], "field_ambiguity");
    assert_eq!(items[0]["scene_index"], 0);
}

#[tokio::test]
async fn apply_with_acknowledged_uncertainties_reaches_the_worker() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    let mappings = ports.ai_import_mapping.clone();
    seed_ai_block_access(&ports, block_id).await;
    let job_id = seed_blocking_uncertainty_job(&ports, Some(block_id)).await;

    let (status, _) = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            // Acknowledging the single blocker lets the apply through; the
            // advisory `dropped_row` needs no acknowledgement.
            uncertainty_acknowledgements: vec![UncertaintyAcknowledgement {
                scene_index: 0,
                field: "location".to_owned(),
            }],
            mappings: create_mappings(),
            accept_as_is: false,
            edit_distance: 0,
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect("the acknowledged apply must pass the gate");
    assert_eq!(status, StatusCode::OK);
    assert!(
        !mappings
            .list_by_preview(job_id)
            .await
            .expect("mapping read should succeed")
            .is_empty(),
        "the worker must have recorded the apply mappings"
    );
}

#[tokio::test]
async fn apply_rejects_an_acknowledgement_for_an_uncertainty_the_preview_does_not_carry() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    let job_id = seed_blocking_uncertainty_job(&ports, Some(block_id)).await;

    let problem = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: vec![UncertaintyAcknowledgement {
                scene_index: 99,
                field: "location".to_owned(),
            }],
            mappings: create_mappings(),
            accept_as_is: false,
            edit_distance: 0,
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect_err("a foreign acknowledgement is a client bug")
    .into_problem();

    assert_eq!(problem.status, StatusCode::UNPROCESSABLE_ENTITY.as_u16());
    assert_eq!(problem.code, "domain.validation");
}

#[tokio::test]
async fn apply_rejects_a_duplicate_acknowledgement() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    *ports.episode_repo.block_id_override.lock().await = Some(block_id);
    seed_ai_block_access(&ports, block_id).await;
    let job_id = seed_blocking_uncertainty_job(&ports, Some(block_id)).await;

    let ack = UncertaintyAcknowledgement {
        scene_index: 0,
        field: "location".to_owned(),
    };
    let problem = apply_ai_import::<FakePorts>(
        State(state(ports)),
        user(),
        Path(job_id),
        Json(ApplyAiImportRequest {
            continuity_selections: Vec::new(),
            episode_id: EpisodeId::new(),
            project_id: None,
            uncertainty_acknowledgements: vec![ack.clone(), ack],
            mappings: create_mappings(),
            accept_as_is: false,
            edit_distance: 0,
            episode_groups: Vec::new(),
            shooting_days: Vec::new(),
        }),
    )
    .await
    .expect_err("a duplicate acknowledgement would over-acknowledge")
    .into_problem();

    assert_eq!(problem.status, StatusCode::UNPROCESSABLE_ENTITY.as_u16());
    assert_eq!(problem.code, "domain.validation");
}

// ---------------------------------------------------------------------------
// Cost transparency (issue #675, OpenSpec ai-import-cost-transparency):
// model-pricing enrichment, the `google`/`gemini` provider alias, and the
// `cost_display_preference` round-trip.
// ---------------------------------------------------------------------------

use api::handlers::list_ai_models;

fn seeded_pricing(provider: LlmProvider, model: &str) -> breakdown_core::ai::ModelPricingRow {
    breakdown_core::ai::ModelPricingRow {
        provider,
        model: model.to_owned(),
        pricing: breakdown_core::ai::ModelPricing {
            currency: breakdown_core::ai::Currency::Usd,
            input_nano_per_million: 1_450_000_000,
            output_nano_per_million: 4_500_000_000,
            cached_input_nano_per_million: Some(145_000_000),
            energy_nano_per_kwh: Some(10_000_000_000),
            energy_capped_by_token: true,
            image_output_nano_per_million: None,
            image_nano_per_unit: None,
            pricing_source: breakdown_core::ai::PricingSource::ProviderLive,
            price_as_of: Utc::now(),
        },
    }
}

#[tokio::test]
async fn list_ai_models_enriches_pricing_and_keeps_unpriced_models_null() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    // Seed live pricing for exactly one curated Neuralwatt model.
    let priced_model = infra::ai::curated_model_ids(LlmProvider::Neuralwatt)[0].to_owned();
    ports
        .ai_model_pricing
        .seed(vec![seeded_pricing(LlmProvider::Neuralwatt, &priced_model)]);

    let (status, Json(models)) =
        list_ai_models::<FakePorts>(State(state(ports)), user(), Path("neuralwatt".to_owned()))
            .await
            .expect("credential-role member may list models");
    assert_eq!(status, StatusCode::OK);
    assert!(!models.is_empty());
    let priced = models
        .iter()
        .find(|m| m.id == priced_model)
        .expect("priced model in catalog");
    let pricing = priced.pricing.as_ref().expect("pricing attached");
    assert_eq!(pricing.input_nano_per_million, 1_450_000_000);
    assert_eq!(pricing.cached_input_nano_per_million, Some(145_000_000));
    assert_eq!(pricing.energy_nano_per_kwh, Some(10_000_000_000));
    // Honest degradation: every other curated model keeps `pricing: null`
    // — never a fabricated zero-price object.
    let unpriced = models
        .iter()
        .find(|m| m.id != priced_model)
        .expect("a second curated model exists");
    assert!(unpriced.pricing.is_none());
}

#[tokio::test]
async fn list_ai_models_accepts_the_google_alias_for_gemini() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let state = state(ports);

    let (status_a, Json(canonical)) =
        list_ai_models::<FakePorts>(State(state.clone()), user(), Path("gemini".to_owned()))
            .await
            .expect("canonical key resolves");
    assert_eq!(status_a, StatusCode::OK);
    assert!(!canonical.is_empty(), "gemini has curated models");

    let (status_b, Json(alias)) =
        list_ai_models::<FakePorts>(State(state), user(), Path("google".to_owned()))
            .await
            .expect("google alias resolves to gemini");
    assert_eq!(status_b, StatusCode::OK);
    let ids_a: Vec<&str> = canonical.iter().map(|m| m.id.as_str()).collect();
    let ids_b: Vec<&str> = alias.iter().map(|m| m.id.as_str()).collect();
    assert_eq!(ids_a, ids_b, "the alias serves the same catalog");
    assert!(alias.iter().all(|m| m.provider == LlmProvider::Gemini));
}

#[tokio::test]
async fn ai_config_cost_display_preference_round_trips_to_the_commands() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    ports
        .settings_repo
        .bind_vault_key("vault-key", LlmProvider::Neuralwatt.as_str(), TEST_SUB)
        .await;
    ports
        .settings_repo
        .bind_vault_key(
            "replacement-vault-key",
            LlmProvider::Ollama.as_str(),
            TEST_SUB,
        )
        .await;
    let commands = ports.ai_config_commands.clone();
    let repo = ports.ai_config_repo.clone();
    let state = state(ports);

    let (status, Json(created)) = create_ai_config::<FakePorts>(
        State(state.clone()),
        user(),
        Json(CreateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            // User opts into energy-based display (issue #675).
            cost_display_preference: CostDisplayPreference::Energy,
        }),
    )
    .await
    .expect("credential-role member may create AI config");
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(
        commands.created.lock().await[0].cost_display_preference,
        CostDisplayPreference::Energy,
        "the create command carries the caller's display preference"
    );

    // Seed the read model the way the projector would, so the update's
    // ownership pre-check has a row to resolve.
    repo.views.lock().await.insert(
        created.id,
        AiConfigView {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            id: created.id,
            user_id: UserId::from_sub(TEST_SUB),
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            prompt_kinds: Vec::new(),
            stored_prompt_kinds: Vec::new(),
            vault_key_id: "vault-key".to_owned(),
            version: created.version,
            revoked: false,
            cost_display_preference: CostDisplayPreference::Energy,
        },
    );

    let (status, _) = update_ai_config::<FakePorts>(
        State(state),
        user(),
        Path(created.id),
        Json(UpdateAiConfigRequest {
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            provider: LlmProvider::Ollama,
            assistant_model: "assistant-v2".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "replacement-vault-key".to_owned(),
            version: created.version,
            cost_display_preference: Some(CostDisplayPreference::Token),
        }),
    )
    .await
    .expect("owner may update their config");
    assert_eq!(status, StatusCode::OK);
    let updated = commands.updated.lock().await;
    assert_eq!(updated.len(), 1);
    assert_eq!(
        updated[0].cost_display_preference,
        Some(CostDisplayPreference::Token),
        "the update command carries the switched display preference"
    );
}

#[tokio::test]
async fn get_ai_import_job_serves_the_persisted_cost_snapshot() {
    let ports = FakePorts::default();
    let mut job = succeeded_job("ai-preview/handle");
    // The worker persisted a `Known` token-cost snapshot before
    // `mark_succeeded` (issue #675).
    job.telemetry = Some(breakdown_core::ai::JobTelemetrySummary {
        provider: Some(LlmProvider::Neuralwatt),
        model: Some("glm-5.3".to_owned()),
        doc_kind: Some(DocumentKind::Script),
        chunk_count: 3,
        tokens_in: 1_000,
        tokens_out: 500,
        cached_tokens_in: 0,
        energy_millijoules: 4_200_000,
        latency_total_ms: 9_000,
    });
    job.cost = Some(breakdown_core::ai::CostBreakdown {
        status: breakdown_core::ai::CostStatus::Known,
        currency: Some(breakdown_core::ai::Currency::Usd),
        price_as_of: Some(Utc::now()),
        pricing_source: Some(breakdown_core::ai::PricingSource::ProviderLive),
        token_cost: Some(breakdown_core::ai::TokenCostBreakdown {
            tokens_in: 1_000,
            tokens_out: 500,
            cached_tokens_in: 0,
            input_rate_nano_per_million: 1_450_000_000,
            output_rate_nano_per_million: 4_500_000_000,
            cached_input_rate_nano_per_million: Some(145_000_000),
            total_nano: 3_700_000_000,
        }),
        energy_cost: None,
        image_cost: None,
    });
    let job_id = job.id;
    ports.ai_import_queue.seed(job).await;

    let response = get_ai_import_job::<FakePorts>(State(state(ports)), user(), Path(job_id))
        .await
        .expect("owner should read their own job");
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    let payload: serde_json::Value = serde_json::from_slice(&body).expect("json");
    assert_eq!(payload["job"]["cost"]["status"], "known");
    assert_eq!(payload["job"]["cost"]["currency"], "USD");
    assert_eq!(
        payload["job"]["cost"]["token_cost"]["total_nano"],
        serde_json::json!(3_700_000_000_i64)
    );
    assert_eq!(payload["job"]["telemetry"]["tokens_in"], 1_000u64);
    assert_eq!(
        payload["job"]["telemetry"]["energy_millijoules"],
        4_200_000u64
    );
}

// ---------------------------------------------------------------------------
// Decision Model scoring (issue #722): the curated decision-models endpoint
// and the API-edge decision credential pre-check (same-key reuse vs. split
// billing vs. provider mismatch).
// ---------------------------------------------------------------------------

use api::handlers::list_ai_decision_models;

#[tokio::test]
async fn list_ai_decision_models_serves_the_curated_catalog_with_pricing() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    // Seed pricing for exactly one curated Neuralwatt decision model.
    let priced_model = infra::ai::curated_decision_model_ids(LlmProvider::Neuralwatt)[0].to_owned();
    ports
        .ai_model_pricing
        .seed(vec![seeded_pricing(LlmProvider::Neuralwatt, &priced_model)]);

    let (status, Json(models)) = list_ai_decision_models::<FakePorts>(
        State(state(ports)),
        user(),
        Path("neuralwatt".to_owned()),
    )
    .await
    .expect("credential-role member may list decision models");
    assert_eq!(status, StatusCode::OK);
    let ids: Vec<&str> = models.iter().map(|m| m.id.as_str()).collect();
    assert_eq!(ids, vec!["clef-flash", "clef"]);
    let priced = models
        .iter()
        .find(|m| m.id == priced_model)
        .expect("priced decision model in catalog");
    assert!(priced.pricing.is_some(), "pricing enrichment applies");
    let unpriced = models
        .iter()
        .find(|m| m.id != priced_model)
        .expect("a second curated decision model exists");
    assert!(unpriced.pricing.is_none(), "unpriced stays null, never 0");
    // A decision model is never the recommended default (optional slot).
    assert!(models.iter().all(|m| !m.recommended));
}

#[tokio::test]
async fn list_ai_decision_models_serves_an_empty_catalog_for_non_decision_providers() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let (status, Json(models)) = list_ai_decision_models::<FakePorts>(
        State(state(ports)),
        user(),
        Path("openai".to_owned()),
    )
    .await
    .expect("credential-role member may query the (empty) catalog");
    assert_eq!(status, StatusCode::OK);
    assert!(models.is_empty(), "OpenAI hosts no decision models");
}

// Image-generation model catalog (issue #732): the curated image-models
// endpoint mirrors the decision-models route with the `curated_image_models`
// catalog (#675 prep for #673) — Gemini/OpenAI only, empty for text-only
// providers, with the same pricing enrichment.

use api::handlers::list_ai_image_models;

#[tokio::test]
async fn list_ai_image_models_serves_the_curated_catalog_with_pricing() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    // Seed pricing for exactly one curated Gemini image model.
    let priced_model = infra::ai::curated_image_model_ids(LlmProvider::Gemini)[0].to_owned();
    ports
        .ai_model_pricing
        .seed(vec![seeded_pricing(LlmProvider::Gemini, &priced_model)]);

    let (status, Json(models)) =
        list_ai_image_models::<FakePorts>(State(state(ports)), user(), Path("gemini".to_owned()))
            .await
            .expect("credential-role member may list image models");
    assert_eq!(status, StatusCode::OK);
    let ids: Vec<&str> = models.iter().map(|m| m.id.as_str()).collect();
    assert_eq!(
        ids,
        vec![
            "gemini-3.1-flash-image",
            "gemini-3.1-flash-lite-image",
            "gemini-3-pro-image",
            "gemini-2.5-flash-image",
        ]
    );
    let priced = models
        .iter()
        .find(|m| m.id == priced_model)
        .expect("priced image model in catalog");
    assert!(priced.pricing.is_some(), "pricing enrichment applies");
    let unpriced = models
        .iter()
        .find(|m| m.id != priced_model)
        .expect("a second curated image model exists");
    assert!(unpriced.pricing.is_none(), "unpriced stays null, never 0");
    // An image model is never the recommended default (optional slot).
    assert!(models.iter().all(|m| !m.recommended));
}

#[tokio::test]
async fn list_ai_image_models_serves_an_empty_catalog_for_text_only_providers() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    let (status, Json(models)) = list_ai_image_models::<FakePorts>(
        State(state(ports)),
        user(),
        Path("neuralwatt".to_owned()),
    )
    .await
    .expect("credential-role member may query the (empty) catalog");
    assert_eq!(status, StatusCode::OK);
    assert!(models.is_empty(), "neuralwatt hosts no image models");
}

#[tokio::test]
async fn create_ai_config_accepts_same_key_decision_reuse_within_one_provider() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    ports
        .settings_repo
        .bind_vault_key("vault-key", LlmProvider::Neuralwatt.as_str(), TEST_SUB)
        .await;
    let commands = ports.ai_config_commands.clone();

    let (status, _) = create_ai_config::<FakePorts>(
        State(state(ports)),
        user(),
        Json(CreateAiConfigRequest {
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            cost_display_preference: CostDisplayPreference::Token,
            // Same-key reuse within the SAME provider is legitimate (D1).
            decision_provider: Some(LlmProvider::Neuralwatt),
            decision_model: Some("clef-flash".to_owned()),
            decision_vault_key_id: Some("vault-key".to_owned()),
        }),
    )
    .await
    .expect("same-provider decision key reuse is accepted");
    assert_eq!(status, StatusCode::CREATED);
    let created = commands.created.lock().await;
    let command = created.first().expect("create dispatched");
    assert_eq!(command.decision_provider, Some(LlmProvider::Neuralwatt));
    assert_eq!(command.decision_model.as_deref(), Some("clef-flash"));
}

#[tokio::test]
async fn create_ai_config_rejects_a_decision_key_shared_across_providers() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    ports
        .settings_repo
        .bind_vault_key("vault-key", LlmProvider::Neuralwatt.as_str(), TEST_SUB)
        .await;
    let state = state(ports);

    let problem = create_ai_config::<FakePorts>(
        State(state),
        user(),
        Json(CreateAiConfigRequest {
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            cost_display_preference: CostDisplayPreference::Token,
            // Same KEY as the extraction config but a DIFFERENT decision
            // provider: sharing is only legitimate within one provider.
            decision_provider: Some(LlmProvider::OpenRouter),
            decision_model: Some("cloudflare/clef-flash".to_owned()),
            decision_vault_key_id: Some("vault-key".to_owned()),
        }),
    )
    .await
    .expect_err("cross-provider same-key reuse is rejected")
    .into_problem();
    assert_eq!(problem.status, StatusCode::CONFLICT.as_u16());
    assert_eq!(problem.code, "ai-config.provider-mismatch");
}

#[tokio::test]
async fn create_ai_config_rejects_a_foreign_distinct_decision_key() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    ports
        .settings_repo
        .bind_vault_key("vault-key", LlmProvider::Neuralwatt.as_str(), TEST_SUB)
        .await;
    // The distinct decision key exists but is owned by ANOTHER caller —
    // the confused-deputy invariant (#552) applies to the decision slot too.
    ports
        .settings_repo
        .bind_vault_key(
            "foreign-decision-key",
            LlmProvider::Neuralwatt.as_str(),
            "someone-else",
        )
        .await;
    let state = state(ports);

    let problem = create_ai_config::<FakePorts>(
        State(state),
        user(),
        Json(CreateAiConfigRequest {
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            cost_display_preference: CostDisplayPreference::Token,
            decision_provider: Some(LlmProvider::Neuralwatt),
            decision_model: Some("clef".to_owned()),
            decision_vault_key_id: Some("foreign-decision-key".to_owned()),
        }),
    )
    .await
    .expect_err("a foreign decision credential must be rejected")
    .into_problem();
    assert_eq!(problem.status, StatusCode::FORBIDDEN.as_u16());
    assert_eq!(problem.code, "ai-config.vault-key-forbidden");
}

#[tokio::test]
async fn create_ai_config_accepts_a_distinct_owned_decision_key_for_split_billing() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    ports
        .settings_repo
        .bind_vault_key("vault-key", LlmProvider::Neuralwatt.as_str(), TEST_SUB)
        .await;
    // A distinct, ACTIVE, owned credential of the SAME provider — the split
    // billing path (issue #722 D1).
    ports
        .settings_repo
        .bind_vault_key(
            "split-billing-key",
            LlmProvider::Neuralwatt.as_str(),
            TEST_SUB,
        )
        .await;
    let commands = ports.ai_config_commands.clone();

    let (status, _) = create_ai_config::<FakePorts>(
        State(state(ports)),
        user(),
        Json(CreateAiConfigRequest {
            provider: LlmProvider::Neuralwatt,
            assistant_model: "assistant".to_owned(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: "vault-key".to_owned(),
            cost_display_preference: CostDisplayPreference::Token,
            decision_provider: Some(LlmProvider::Neuralwatt),
            decision_model: Some("clef".to_owned()),
            decision_vault_key_id: Some("split-billing-key".to_owned()),
        }),
    )
    .await
    .expect("a distinct owned active credential is accepted");
    assert_eq!(status, StatusCode::CREATED);
    let created = commands.created.lock().await;
    let command = created.first().expect("create dispatched");
    assert_eq!(
        command.decision_vault_key_id.as_deref(),
        Some("split-billing-key")
    );
}

#[tokio::test]
async fn update_ai_config_raw_json_null_clears_the_decision_slot() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    ports
        .settings_repo
        .bind_vault_key("vault-key", LlmProvider::Neuralwatt.as_str(), TEST_SUB)
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
            cost_display_preference: CostDisplayPreference::Token,
            decision_provider: Some(LlmProvider::Neuralwatt),
            decision_model: Some("clef-flash".to_owned()),
            decision_vault_key_id: Some("vault-key".to_owned()),
        }),
    )
    .await
    .expect("owner may create the config");
    assert_eq!(status, StatusCode::CREATED);
    // Seed the read model the way the projector would (the update handler
    // resolves the stored binding through it).
    let mut view = config_view(TEST_SUB);
    view.id = created.id;
    view.provider = LlmProvider::Neuralwatt;
    view.vault_key_id = "vault-key".to_owned();
    view.decision_provider = Some(LlmProvider::Neuralwatt);
    view.decision_model = Some("clef-flash".to_owned());
    view.decision_vault_key_id = Some("vault-key".to_owned());
    repo.views.lock().await.insert(created.id, view);

    // Raw JSON with EXPLICIT `null` on the decision fields: the tri-state
    // contract says `null` CLEARS, and `deserialize_optional_nullable` is
    // what makes the outer `Some(None)` reachable (a plain
    // `#[serde(default)]` folds `null` into "absent" and the clear path
    // would be dead code).
    let raw = serde_json::json!({
        "provider": "neuralwatt",
        "assistant_model": "assistant-v2",
        "image_model": null,
        "prompts": {},
        "vault_key_id": "vault-key",
        "cost_display_preference": "token",
        "decision_provider": null,
        "decision_model": null,
        "decision_vault_key_id": null,
        "version": 1
    });
    let request: UpdateAiConfigRequest =
        serde_json::from_value(raw).expect("explicit nulls deserialize to the clearing Some(None)");
    assert_eq!(request.decision_provider, Some(None));
    assert_eq!(request.decision_model, Some(None));
    assert_eq!(request.decision_vault_key_id, Some(None));

    let (status, _) =
        update_ai_config::<FakePorts>(State(state), user(), Path(created.id), Json(request))
            .await
            .expect("owner may update their config");
    assert_eq!(status, StatusCode::OK);
    let updated = commands.updated.lock().await;
    let command = updated.first().expect("update dispatched");
    assert_eq!(command.decision_provider, Some(None));
    assert_eq!(command.decision_model, Some(None));
    assert_eq!(command.decision_vault_key_id, Some(None));
}

#[tokio::test]
async fn update_ai_config_omitted_decision_fields_resolve_from_the_stored_binding() {
    let ports = FakePorts::default();
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(TEST_SUB))
        .await;
    ports
        .settings_repo
        .bind_vault_key("vault-key", LlmProvider::Neuralwatt.as_str(), TEST_SUB)
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
            cost_display_preference: CostDisplayPreference::Token,
            decision_provider: Some(LlmProvider::Neuralwatt),
            decision_model: Some("clef-flash".to_owned()),
            decision_vault_key_id: Some("vault-key".to_owned()),
        }),
    )
    .await
    .expect("owner may create the config");
    assert_eq!(status, StatusCode::CREATED);
    let mut view = config_view(TEST_SUB);
    view.id = created.id;
    view.provider = LlmProvider::Neuralwatt;
    view.vault_key_id = "vault-key".to_owned();
    view.decision_provider = Some(LlmProvider::Neuralwatt);
    view.decision_model = Some("clef-flash".to_owned());
    view.decision_vault_key_id = Some("vault-key".to_owned());
    repo.views.lock().await.insert(created.id, view);

    // A partial update (decision fields ABSENT — the raw JSON omits them)
    // keeps the stored binding; the edge must NOT re-validate an unchanged
    // binding and the aggregate must resolve the stored values.
    let raw = serde_json::json!({
        "provider": "neuralwatt",
        "assistant_model": "assistant-v2",
        "image_model": null,
        "prompts": {},
        "vault_key_id": "vault-key",
        "version": 1
    });
    let request: UpdateAiConfigRequest =
        serde_json::from_value(raw).expect("omitted fields deserialize to the keeping outer None");
    assert_eq!(request.decision_provider, None);
    assert_eq!(request.decision_model, None);
    assert_eq!(request.decision_vault_key_id, None);

    let (status, _) =
        update_ai_config::<FakePorts>(State(state), user(), Path(created.id), Json(request))
            .await
            .expect("an unchanged stored decision binding must not block the update");
    assert_eq!(status, StatusCode::OK);
    let updated = commands.updated.lock().await;
    let command = updated.first().expect("update dispatched");
    // Omitted → the aggregate resolves the stored slot (None in the
    // dispatched command only means "the edge did not re-resolve it"; the
    // aggregate fills from its own state).
    assert_eq!(command.decision_provider, None);
    assert_eq!(command.decision_model, None);
    assert_eq!(command.decision_vault_key_id, None);
}
