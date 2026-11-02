// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Handler tests for the apply-run progress stream (issue #762).
//!
//! The job stream closes on the terminal frame, and an apply runs against a
//! job that is *already* terminal — so the apply's progress travels on its own
//! endpoint. These tests pin: the snapshot frame, the live push per applied
//! row, the final `null` frame that closes the stream, the staleness rule for a
//! run whose process died, and that no run ever started (wait, then close).

// Test code: the workspace denies `clippy::expect_used`; assertions use
// `.expect()` with explicit messages.
#![allow(clippy::expect_used)]

use crate::common;

use api::problems::Path;
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use http_body_util::BodyExt;

use api::auth::CurrentUser;
use api::handlers::{
    ApplyStreamVerdict, SSE_APPLY_TICK_SECS, classify_apply_run, stream_ai_import_apply_events,
};
use api::state::AppState;
use breakdown_core::ai::{
    AiImportJob, AiImportJobId, AiImportQueue, ApplyProgress, ApplyStage, DocumentKind, JobStatus,
    SourceFormat,
};
use breakdown_core::shared::UserId;
use chrono::{Duration as ChronoDuration, Utc};
use common::FakePorts;
use uuid::Uuid;

const TEST_SUB: &str = "ai-apply-sse-test-user";

fn user() -> CurrentUser {
    CurrentUser::dummy(TEST_SUB)
}

fn state(ports: FakePorts) -> AppState<FakePorts> {
    AppState::with_ai_import(ports, true, 4096, Vec::new())
}

/// A `succeeded` job — the only state an apply can ever run against.
fn succeeded_job(id: AiImportJobId) -> AiImportJob {
    AiImportJob {
        id,
        user_id: UserId::from_sub(TEST_SUB),
        document_kind: DocumentKind::Script,
        source_format: SourceFormat::Pdf,
        block_id: None,
        dedup_key: format!("dedup-{}", Uuid::now_v7()),
        document_digest: "digest".to_owned(),
        source_handle: "source".to_owned(),
        status: JobStatus::Succeeded,
        preview_handle: Some("preview-handle".to_owned()),
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
        source_file_name: None,
        target: None,
        applied_episodes: Vec::new(),
        decision_telemetry: None,
        apply_progress: None,
    }
}

fn progress(applied: u32, total: u32) -> ApplyProgress {
    let now = Utc::now();
    ApplyProgress {
        stage: ApplyStage::Applying,
        applied,
        total,
        started_at: now,
        updated_at: now,
    }
}

async fn open_stream(
    state: AppState<FakePorts>,
    id: AiImportJobId,
) -> (StatusCode, axum::body::Body) {
    let response = stream_ai_import_apply_events(State(state), user(), Path(id), HeaderMap::new())
        .await
        .expect("authorized stream call must not error before the stream");
    let status = response.status();
    (status, response.into_body())
}

async fn next_frame(body: &mut axum::body::Body) -> Option<String> {
    let frame = body.frame().await?;
    let data = frame
        .expect("SSE body frame is readable")
        .into_data()
        .ok()?;
    Some(String::from_utf8_lossy(&data).into_owned())
}

fn frame_event(frame: &str) -> Option<&str> {
    frame.lines().find_map(|line| line.strip_prefix("event: "))
}

fn frame_data(frame: &str) -> Option<serde_json::Value> {
    frame
        .lines()
        .find_map(|line| line.strip_prefix("data: "))
        .map(|data| serde_json::from_str(data).expect("frame data is valid JSON"))
}

/// A fresh payload must classify as `Running`; reaching this means the
/// classifier regressed (kept panic-free for the `clippy::panic` lint, which
/// the workspace denies even in tests).
fn unreachable_not_running() -> ! {
    std::process::abort()
}

// ---------------------------------------------------------------------------
// The close/emit classification — pure, so the stream's conditions are testable
// without a stream, a timer or a database.
// ---------------------------------------------------------------------------

#[test]
fn classify_apply_run_reports_a_live_run() {
    let now = Utc::now();
    let live = progress(3, 9);
    let ApplyStreamVerdict::Running(seen) = classify_apply_run(Some(live.clone()), false, now)
    else {
        unreachable_not_running()
    };
    assert_eq!(seen, live);
    assert_eq!(seen.fraction(), 3.0 / 9.0);
}

#[test]
fn classify_apply_run_treats_a_stale_payload_as_finished() {
    // A process that died mid-apply leaves its last frame behind; holding a
    // stream open forever would be the only alternative.
    let mut stale = progress(3, 9);
    stale.updated_at = Utc::now() - ApplyProgress::STALE_AFTER - ChronoDuration::seconds(1);
    assert!(matches!(
        classify_apply_run(Some(stale), true, Utc::now()),
        ApplyStreamVerdict::Finished
    ));
}

#[test]
fn classify_apply_run_distinguishes_never_started_from_finished() {
    // Before anything started the stream must WAIT (a client subscribes a
    // moment before its POST lands) …
    assert!(matches!(
        classify_apply_run(None, false, Utc::now()),
        ApplyStreamVerdict::Idle
    ));
    // … but once a run was observed, an absent payload IS the end signal.
    assert!(matches!(
        classify_apply_run(None, true, Utc::now()),
        ApplyStreamVerdict::Finished
    ));
}

#[test]
fn apply_progress_fraction_is_clamped_and_empty_plans_are_indeterminate() {
    let mut over = progress(20, 10);
    assert_eq!(over.fraction(), 1.0);
    over.applied = 0;
    over.total = 0;
    assert_eq!(over.fraction(), 0.0, "an empty plan has no percentage");
}

// ---------------------------------------------------------------------------
// The stream itself.
// ---------------------------------------------------------------------------

#[tokio::test]
async fn first_frame_is_the_current_apply_run() {
    let ports = FakePorts::default();
    let mut job = succeeded_job(AiImportJobId::new());
    job.apply_progress = Some(progress(4, 57));
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports);

    let (status, mut body) = open_stream(app, job.id).await;
    assert_eq!(status, StatusCode::OK);

    let frame = next_frame(&mut body)
        .await
        .expect("snapshot frame arrives immediately");
    assert_eq!(frame_event(&frame), Some("apply"));
    let payload = frame_data(&frame).expect("snapshot carries JSON data");
    assert_eq!(payload["job_id"], job.id.as_uuid().to_string());
    assert_eq!(payload["apply_progress"]["stage"], "applying");
    assert_eq!(payload["apply_progress"]["applied"], 4);
    assert_eq!(payload["apply_progress"]["total"], 57);
    // The anchor an ETA needs travels with the frame (issue #762).
    assert!(payload["apply_progress"]["started_at"].is_string());
}

#[tokio::test(flavor = "current_thread", start_paused = true)]
async fn each_progress_write_is_pushed_without_polling() {
    let ports = FakePorts::default();
    let mut job = succeeded_job(AiImportJobId::new());
    job.apply_progress = Some(progress(4, 57));
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports.clone());

    let (_status, mut body) = open_stream(app, job.id).await;
    let _snapshot = next_frame(&mut body).await.expect("snapshot frame");

    // A worker-side write — the same port the apply worker calls. The clock is
    // PAUSED: virtual time never advances on its own, so the measurement below
    // is a bound, not a wall-clock gate (AGENTS.md §6: no timing-based tests).
    let pushed_at = tokio::time::Instant::now();
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, Some(&progress(7, 57)))
        .await
        .expect("apply progress write succeeds");

    let frame = next_frame(&mut body).await.expect("live apply frame");
    // The stream re-reads on the `SSE_APPLY_TICK_SECS` tick. A frame delivered
    // by the wake-up costs no virtual time; a tick-only delivery has to reach
    // the tick interval, so a bound equal to that interval separates the two
    // without measuring the runner's speed.
    assert!(
        pushed_at.elapsed() < std::time::Duration::from_secs(SSE_APPLY_TICK_SECS),
        "the frame must be PUSHED by the wake-up, not re-read on the stream \
         tick (virtual elapsed {:?})",
        pushed_at.elapsed()
    );
    let payload = frame_data(&frame).expect("live frame carries JSON data");
    assert_eq!(payload["apply_progress"]["applied"], 7);
    assert_eq!(payload["apply_progress"]["total"], 57);

    // End the run the way the worker does, so the stream completes cleanly.
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, None)
        .await
        .expect("clearing the run succeeds");
    let final_frame = next_frame(&mut body).await.expect("end-of-run frame");
    assert!(
        frame_data(&final_frame).expect("final frame data")["apply_progress"].is_null(),
        "the run ends with an explicit null"
    );
}

#[tokio::test]
async fn clearing_the_payload_emits_a_final_null_frame_and_closes() {
    let ports = FakePorts::default();
    let mut job = succeeded_job(AiImportJobId::new());
    job.apply_progress = Some(progress(57, 57));
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports.clone());

    let (_status, mut body) = open_stream(app, job.id).await;
    let _snapshot = next_frame(&mut body).await.expect("snapshot frame");

    // The run ended: the worker clears the column on every exit path.
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, None)
        .await
        .expect("clearing the run succeeds");

    let final_frame = next_frame(&mut body)
        .await
        .expect("end-of-run frame arrives");
    let payload = frame_data(&final_frame).expect("final frame carries JSON data");
    assert!(
        payload["apply_progress"].is_null(),
        "the end signal is an explicit null, never an absent field"
    );
    // And the stream closes by itself — no keep-alive frame follows.
    assert!(
        next_frame(&mut body).await.is_none(),
        "the stream must end after the end-of-run frame"
    );
}

#[tokio::test]
async fn a_job_that_is_not_succeeded_gets_no_apply_progress_written() {
    // The adapter's status predicate: an apply can only ever run against a
    // `succeeded` job, so a payload must never land on any other state.
    let ports = FakePorts::default();
    let mut job = succeeded_job(AiImportJobId::new());
    job.status = JobStatus::Running;
    ports.ai_import_queue.seed(job.clone()).await;

    ports
        .ai_import_queue
        .mark_apply_progress(job.id, Some(&progress(1, 2)))
        .await
        .expect("the write itself does not fail");
    let stored = ports
        .ai_import_queue
        .get(job.id)
        .await
        .expect("queue read succeeds")
        .expect("job exists");
    assert_eq!(stored.apply_progress, None);
}

#[tokio::test]
async fn an_apply_stream_is_rejected_for_a_foreign_job() {
    let ports = FakePorts::default();
    let mut job = succeeded_job(AiImportJobId::new());
    job.user_id = UserId::from_sub("somebody-else");
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports);

    // AUTHZ-GATE runs BEFORE the stream opens: a problem document, not a
    // text/event-stream.
    let error = stream_ai_import_apply_events(State(app), user(), Path(job.id), HeaderMap::new())
        .await
        .expect_err("a foreign job must be refused");
    drop(error);
}

#[tokio::test]
async fn an_unknown_job_is_a_404_before_the_stream_opens() {
    let app = state(FakePorts::default());
    let error = stream_ai_import_apply_events(
        State(app),
        user(),
        Path(AiImportJobId::new()),
        HeaderMap::new(),
    )
    .await
    .expect_err("an unknown job must be refused");
    drop(error);
}
