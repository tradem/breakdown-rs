// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! Handler tests for the SSE job-event stream (issue #664, ADR-038 D1):
//! snapshot-first delivery, `Last-Event-ID` reconnect, live frame push,
//! terminal auto-close, and the 403/404 rejections BEFORE the stream opens.

// Test code: the workspace denies `clippy::expect_used`; assertions use
// `.expect()` with explicit messages. No other lints are suppressed.
#![allow(clippy::expect_used)]

use crate::common;

use api::problems::Path; // ADR-031 wrapper extractor used by the handlers
use axum::extract::State;
use axum::http::{HeaderMap, HeaderValue, StatusCode};
use axum::response::IntoResponse;
use http_body_util::BodyExt;

use api::auth::CurrentUser;
use api::handlers::stream_ai_import_job_events;
use api::state::AppState;
use breakdown_core::ai::{
    AiImportJob, AiImportJobId, AiImportProgress, AiImportStage, DocumentKind, JobStatus,
    SourceFormat,
};
use breakdown_core::shared::UserId;
use chrono::Utc;
use common::FakePorts;
use uuid::Uuid;

const TEST_SUB: &str = "ai-sse-test-user";

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

fn running_job(id: AiImportJobId) -> AiImportJob {
    AiImportJob {
        id,
        user_id: UserId::from_sub(TEST_SUB),
        document_kind: DocumentKind::Script,
        source_format: SourceFormat::Pdf,
        block_id: None,
        dedup_key: format!("dedup-{}", Uuid::now_v7()),
        document_digest: "digest".to_owned(),
        source_handle: "source".to_owned(),
        status: JobStatus::Running,
        preview_handle: None,
        last_error: None,
        retries: 0,
        progress: Some(AiImportProgress {
            stage: AiImportStage::Extracting,
            chunk: Some(4),
            chunks_total: Some(12),
            episodes_seen: vec!["Ep. 3".to_owned(), "Ep. 4".to_owned()],
        }),
        next_attempt_at: None,
        attempts: Vec::new(),
        max_retries: 5,
        created_at: Utc::now(),
        updated_at: Utc::now(),
        telemetry: None,
        cost: None,
    }
}

fn no_headers() -> HeaderMap {
    HeaderMap::new()
}

fn last_event_id_header(value: &str) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(
        "last-event-id",
        HeaderValue::from_str(value).expect("numeric id is a valid header value"),
    );
    headers
}

/// Call the SSE handler and split the response into status + body stream.
async fn open_stream(
    state: AppState<FakePorts>,
    id: AiImportJobId,
    headers: HeaderMap,
) -> (StatusCode, axum::body::Body) {
    let response = stream_ai_import_job_events(State(state), user(), Path(id), headers)
        .await
        .expect("authorized stream call must not error before the stream");
    let status = response.status();
    (status, response.into_body())
}

/// Read the next raw SSE frame (bytes up to the blank line separator).
async fn next_frame(body: &mut axum::body::Body) -> Option<String> {
    let frame = body.frame().await?;
    let data = frame
        .expect("SSE body frame is readable")
        .into_data()
        .ok()?;
    Some(String::from_utf8_lossy(&data).into_owned())
}

/// Parse the `id:` field of an SSE frame.
fn frame_id(frame: &str) -> Option<&str> {
    frame.lines().find_map(|line| line.strip_prefix("id: "))
}

/// Parse the `event:` field of an SSE frame.
fn frame_event(frame: &str) -> Option<&str> {
    frame.lines().find_map(|line| line.strip_prefix("event: "))
}

/// Parse the JSON `data:` payload of an SSE frame.
fn frame_data(frame: &str) -> Option<serde_json::Value> {
    frame
        .lines()
        .find_map(|line| line.strip_prefix("data: "))
        .map(|data| serde_json::from_str(data).expect("frame data is valid JSON"))
}

#[tokio::test]
async fn first_frame_is_a_full_snapshot_with_id_and_progress() {
    let ports = FakePorts::default();
    let job = running_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports);

    let (status, mut body) = open_stream(app, job.id, no_headers()).await;
    assert_eq!(status, StatusCode::OK);

    let frame = next_frame(&mut body)
        .await
        .expect("snapshot frame arrives immediately");
    assert_eq!(frame_event(&frame), Some("job"));
    let expected_id = job.updated_at.timestamp_micros().to_string();
    assert_eq!(frame_id(&frame), Some(expected_id.as_str()));
    let payload = frame_data(&frame).expect("snapshot carries JSON data");
    assert_eq!(payload["job"]["status"], "running");
    assert_eq!(payload["job"]["progress"]["stage"], "extracting");
    assert_eq!(payload["job"]["progress"]["chunk"], 4);
    assert_eq!(payload["job"]["progress"]["chunks_total"], 12);
    assert_eq!(
        payload["job"]["progress"]["episodes_seen"],
        serde_json::json!(["Ep. 3", "Ep. 4"])
    );
}

#[tokio::test]
async fn reconnect_with_last_event_id_receives_a_fresh_snapshot() {
    let ports = FakePorts::default();
    let job = running_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports);

    // The client reconnects with a STALE id (it missed intermediate chunk
    // updates); the first frame must be the current authoritative snapshot.
    let (status, mut body) = open_stream(app, job.id, last_event_id_header("42")).await;
    assert_eq!(status, StatusCode::OK);

    let frame = next_frame(&mut body).await.expect("snapshot frame");
    let expected_id = job.updated_at.timestamp_micros().to_string();
    assert_ne!(frame_id(&frame), Some("42"));
    assert_eq!(frame_id(&frame), Some(expected_id.as_str()));
    let payload = frame_data(&frame).expect("snapshot data");
    assert_eq!(payload["job"]["status"], "running");
}

#[tokio::test]
async fn live_progress_and_status_frames_are_pushed_and_terminal_closes() {
    let ports = FakePorts::default();
    let job = running_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports.clone());

    let (_status, mut body) = open_stream(app, job.id, no_headers()).await;
    let _snapshot = next_frame(&mut body).await.expect("snapshot frame");

    // A fenced progress write commits and publishes: the stream must push
    // the new frame without any polling.
    let mut updated = job.clone();
    updated.progress = Some(AiImportProgress {
        stage: AiImportStage::Extracting,
        chunk: Some(5),
        chunks_total: Some(12),
        episodes_seen: vec!["Ep. 3".to_owned()],
    });
    updated.updated_at = Utc::now();
    ports
        .ai_import_queue
        .update_and_notify(updated.clone())
        .await;
    let progress_frame = next_frame(&mut body).await.expect("live progress frame");
    let payload = frame_data(&progress_frame).expect("progress data");
    assert_eq!(payload["job"]["progress"]["chunk"], 5);
    assert_eq!(frame_event(&progress_frame), Some("job"));

    // Terminal write: the frame is pushed, then the stream closes by itself.
    let mut terminal = updated;
    terminal.status = JobStatus::Succeeded;
    terminal.preview_handle = Some("preview".to_owned());
    terminal.updated_at = Utc::now();
    ports.ai_import_queue.update_and_notify(terminal).await;
    let terminal_frame = next_frame(&mut body).await.expect("terminal frame");
    let payload = frame_data(&terminal_frame).expect("terminal data");
    assert_eq!(payload["job"]["status"], "succeeded");
    // After the terminal frame the stream ends (no further frames, no hang).
    assert!(
        next_frame(&mut body).await.is_none(),
        "stream must close immediately after the terminal frame"
    );
}

#[tokio::test]
async fn already_terminal_job_emits_one_snapshot_and_closes() {
    let ports = FakePorts::default();
    let mut job = running_job(AiImportJobId::new());
    job.status = JobStatus::DeadLetter;
    job.updated_at = Utc::now();
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports);

    let (status, mut body) = open_stream(app, job.id, no_headers()).await;
    assert_eq!(status, StatusCode::OK);
    let frame = next_frame(&mut body).await.expect("snapshot frame");
    let payload = frame_data(&frame).expect("data");
    assert_eq!(payload["job"]["status"], "dead_letter");
    assert!(
        next_frame(&mut body).await.is_none(),
        "terminal snapshot must close the stream"
    );
}

#[tokio::test]
async fn unauthorized_caller_is_rejected_before_the_stream_opens() {
    let ports = FakePorts::default();
    let mut job = running_job(AiImportJobId::new());
    // A different user owns the job: the AUTHZ-GATE must deny.
    job.user_id = UserId::from_sub("someone-else");
    let job_id = job.id;
    job.block_id = None;
    ports.ai_import_queue.seed(job).await;
    let app = state(ports);

    let error = stream_ai_import_job_events(State(app), user(), Path(job_id), no_headers())
        .await
        .expect_err("foreign job must be rejected");
    let response = error.into_response();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn unknown_job_is_a_404_before_the_stream_opens() {
    let ports = FakePorts::default();
    let app = state(ports);

    let error =
        stream_ai_import_job_events(State(app), user(), Path(AiImportJobId::new()), no_headers())
            .await
            .expect_err("unknown job must 404");
    let response = error.into_response();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn disabled_ai_import_is_rejected_before_the_stream_opens() {
    let ports = FakePorts::default();
    let job = running_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job).await;
    let app = AppState::with_ai_import(
        ports,
        /*ai_import_enabled=*/ false,
        /*max_document_bytes=*/ 4096,
        Vec::new(),
    );

    let error =
        stream_ai_import_job_events(State(app), user(), Path(AiImportJobId::new()), no_headers())
            .await
            .expect_err("disabled feature must be rejected");
    let response = error.into_response();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn sse_headers_on_a_real_stream() {
    let ports = FakePorts::default();
    let job = running_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports);

    let response = stream_ai_import_job_events(State(app), user(), Path(job.id), no_headers())
        .await
        .expect("stream opens");
    let headers = response.headers();
    assert_eq!(
        headers.get("cache-control").expect("cache-control set"),
        "no-store, no-transform"
    );
    assert_eq!(
        headers
            .get("x-accel-buffering")
            .expect("buffering disabled"),
        "no"
    );
}

// ---------------------------------------------------------------------------
// Cost transparency (issue #675): the terminal `succeeded` SSE frame carries
// the job's immutable cost snapshot.
// ---------------------------------------------------------------------------

#[tokio::test]
async fn terminal_succeeded_frame_carries_the_job_cost_snapshot() {
    use breakdown_core::ai::CostBreakdown;

    let ports = FakePorts::default();
    let job = running_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports.clone());

    let (_status, mut body) = open_stream(app.clone(), job.id, no_headers()).await;
    let _snapshot = next_frame(&mut body).await.expect("snapshot frame");
    // The snapshot frame carries the running job's not-yet-computed cost.
    let (_status, mut body2) = open_stream(app, job.id, no_headers()).await;
    let frame2 = next_frame(&mut body2).await.expect("snapshot frame");
    assert_eq!(
        frame_data(&frame2).expect("snapshot data")["job"]["status"],
        "running"
    );

    // Terminal write with a `Known` token-cost snapshot (issue #675).
    let mut terminal = job.clone();
    terminal.status = JobStatus::Succeeded;
    terminal.preview_handle = Some("preview".to_owned());
    terminal.cost = Some(CostBreakdown {
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
            cached_input_rate_nano_per_million: None,
            total_nano: 3_700_000_000,
        }),
        energy_cost: None,
        image_cost: None,
    });
    terminal.updated_at = Utc::now();
    ports.ai_import_queue.update_and_notify(terminal).await;
    let terminal_frame = next_frame(&mut body).await.expect("terminal frame");
    let payload = frame_data(&terminal_frame).expect("terminal data");
    assert_eq!(payload["job"]["status"], "succeeded");
    let cost = &payload["job"]["cost"];
    assert_eq!(cost["status"], "known");
    assert_eq!(cost["currency"], "USD");
    assert_eq!(cost["token_cost"]["tokens_in"], 1_000u64);
    assert_eq!(
        cost["token_cost"]["total_nano"],
        serde_json::json!(3_700_000_000_i64)
    );
    assert!(next_frame(&mut body).await.is_none());
}

#[tokio::test]
async fn terminal_succeeded_frame_without_pricing_keeps_cost_unknown_not_null() {
    let ports = FakePorts::default();
    let job = running_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports.clone());

    let (_status, mut body) = open_stream(app, job.id, no_headers()).await;
    let _snapshot = next_frame(&mut body).await.expect("snapshot frame");

    // An unpriced model completes with the honest `unknown` snapshot —
    // never a fabricated zero.
    let mut terminal = job;
    terminal.status = JobStatus::Succeeded;
    terminal.cost = Some(breakdown_core::ai::CostBreakdown::unknown());
    terminal.updated_at = Utc::now();
    ports.ai_import_queue.update_and_notify(terminal).await;
    let terminal_frame = next_frame(&mut body).await.expect("terminal frame");
    let payload = frame_data(&terminal_frame).expect("terminal data");
    assert_eq!(payload["job"]["cost"]["status"], "unknown");
    assert!(payload["job"]["cost"].get("tokenCost").is_none());
}
