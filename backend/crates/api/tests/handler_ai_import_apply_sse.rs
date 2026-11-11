// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: glm-5.3 (neuralwatt)

//! Handler tests for the apply-run progress stream (issues #762, #800).
//!
//! The job stream closes on the terminal frame, and an apply runs against a
//! job that is *already* terminal — so the apply's progress travels on its own
//! endpoint. These tests pin: the snapshot frame, the live push per applied
//! row, the final `null` frame that closes the stream, the staleness rule for a
//! run whose process died, and that no run ever started (wait, then close).
//!
//! Since issue #800 the stream also classifies by the job's **run counter**, so
//! a run that starts and clears between two re-reads still owes its final `null`
//! frame, and a claimed-but-unpublished run keeps the stream waiting instead of
//! being reported as finished.

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
    AiImportJob, AiImportJobId, AiImportQueue, ApplyProgress, ApplyRunId, ApplyRunState,
    ApplyStage, DocumentKind, JobStatus, SourceFormat,
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
        // Issue #871: pre-#871 row — no provider snapshot, no hold.
        provider: None,
        model: None,
        provider_hold: None,
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
        applied: false,
    }
}

/// A payload of `run_id` (issue #800: progress always belongs to a run).
fn progress_of(run_id: ApplyRunId, applied: u32, total: u32) -> ApplyProgress {
    let now = Utc::now();
    ApplyProgress {
        stage: ApplyStage::Applying,
        applied,
        total,
        started_at: now,
        updated_at: now,
        run_id,
    }
}

/// A run slot as the stream re-reads it.
fn run_state(
    owner: Option<ApplyRunId>,
    seq: i64,
    progress: Option<ApplyProgress>,
) -> ApplyRunState {
    ApplyRunState {
        owner,
        seq,
        progress,
        // These stream tests are about frames, not about the refusal's age
        // (issue #863); the slot reports no claim instant, which the core read
        // treats as "nothing to age" rather than inventing one.
        owner_claimed_at: None,
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

/// A `succeeded` job seeded into a fake queue, plus the run that owns its slot.
///
/// Two steps on purpose: the claim is what gives the run its identity and bumps
/// the counter (issue #800), exactly like a real apply.
async fn claimed_job(ports: &FakePorts, applied: u32, total: u32) -> (AiImportJob, ApplyRunId) {
    let job = succeeded_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    let run_id = ApplyRunId::new();
    assert!(
        ports
            .ai_import_queue
            .claim_apply_run(job.id, run_id)
            .await
            .expect("claim succeeds"),
        "the slot starts free"
    );
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, run_id, Some(&progress_of(run_id, applied, total)))
        .await
        .expect("apply progress write succeeds");
    (job, run_id)
}

// ---------------------------------------------------------------------------
// The close/emit classification — pure, so the stream's conditions are testable
// without a stream, a timer or a database.
// ---------------------------------------------------------------------------

#[test]
fn classify_apply_run_reports_a_live_run() {
    let now = Utc::now();
    let run_id = ApplyRunId::new();
    let live = progress_of(run_id, 3, 9);
    let ApplyStreamVerdict::Running(seen) = classify_apply_run(
        &run_state(Some(run_id), 1, Some(live.clone())),
        0,
        false,
        now,
    ) else {
        unreachable_not_running()
    };
    assert_eq!(seen, live);
    assert_eq!(seen.fraction(), 3.0 / 9.0);
}

#[test]
fn classify_apply_run_treats_a_stale_payload_as_finished() {
    // A process that died mid-apply leaves its last frame behind; holding a
    // stream open forever would be the only alternative. The heartbeat keeps a
    // LIVE run's payload fresh, so a stale one really means the process is gone.
    let run_id = ApplyRunId::new();
    let mut stale = progress_of(run_id, 3, 9);
    stale.updated_at = Utc::now() - ApplyProgress::STALE_AFTER - ChronoDuration::seconds(1);
    assert!(matches!(
        classify_apply_run(
            &run_state(Some(run_id), 1, Some(stale)),
            0,
            true,
            Utc::now()
        ),
        ApplyStreamVerdict::Finished
    ));
}

#[test]
fn classify_apply_run_distinguishes_never_started_from_finished() {
    // Before anything started the stream must WAIT (a client subscribes a
    // moment before its POST lands) …
    assert!(matches!(
        classify_apply_run(&run_state(None, 0, None), 0, false, Utc::now()),
        ApplyStreamVerdict::Idle
    ));
    // … but once a run was observed, an absent payload IS the end signal.
    assert!(matches!(
        classify_apply_run(&run_state(None, 1, None), 0, true, Utc::now()),
        ApplyStreamVerdict::Finished
    ));
}

/// Issue #800 #2: a run that started AND cleared between two re-reads owes the
/// documented final `null` frame. Before the run counter existed, the stream
/// inferred "a run happened" from the frames it emitted — and this run emitted
/// none, so the stream waited out its idle ticks and closed silently, which the
/// client read as a dropped connection.
#[test]
fn classify_apply_run_reports_a_run_that_started_and_ended_unseen() {
    assert!(matches!(
        classify_apply_run(&run_state(None, 1, None), 0, false, Utc::now()),
        ApplyStreamVerdict::Finished
    ));
    // The same counter as the subscriber's baseline means nothing happened yet.
    assert!(matches!(
        classify_apply_run(&run_state(None, 3, None), 3, false, Utc::now()),
        ApplyStreamVerdict::Idle
    ));
}

/// Issue #800: a claim lands before the worker's first frame, so a claimed slot
/// without a payload is a run that has just started — never a finished one.
#[test]
fn classify_apply_run_waits_for_a_claimed_run_without_a_payload() {
    let run_id = ApplyRunId::new();
    assert!(matches!(
        classify_apply_run(&run_state(Some(run_id), 1, None), 0, false, Utc::now()),
        ApplyStreamVerdict::Idle
    ));
}

#[test]
fn apply_progress_fraction_is_clamped_and_empty_plans_are_indeterminate() {
    let mut over = progress_of(ApplyRunId::new(), 20, 10);
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
    let (job, run_id) = claimed_job(&ports, 4, 57).await;
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
    // The anchor an ETA needs travels with the frame (issue #762) …
    assert!(payload["apply_progress"]["started_at"].is_string());
    // … and so does the run it belongs to (issue #800): two runs of one job must
    // be distinguishable by the client.
    assert_eq!(
        payload["apply_progress"]["run_id"],
        run_id.as_uuid().to_string()
    );
}

#[tokio::test(flavor = "current_thread", start_paused = true)]
async fn each_progress_write_is_pushed_without_polling() {
    let ports = FakePorts::default();
    let (job, run_id) = claimed_job(&ports, 4, 57).await;
    let app = state(ports.clone());

    let (_status, mut body) = open_stream(app, job.id).await;
    let _snapshot = next_frame(&mut body).await.expect("snapshot frame");

    // A worker-side write — the same port the apply worker calls. The clock is
    // PAUSED: virtual time never advances on its own, so the measurement below
    // is a bound, not a wall-clock gate (AGENTS.md §6: no timing-based tests).
    let pushed_at = tokio::time::Instant::now();
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, run_id, Some(&progress_of(run_id, 7, 57)))
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
        .mark_apply_progress(job.id, run_id, None)
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
    let (job, run_id) = claimed_job(&ports, 57, 57).await;
    let app = state(ports.clone());

    let (_status, mut body) = open_stream(app, job.id).await;
    let _snapshot = next_frame(&mut body).await.expect("snapshot frame");

    // The run ended: the worker clears the column on every exit path.
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, run_id, None)
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

/// Issue #800 #2 end-to-end: a run that starts and finishes inside one stream
/// tick still gets its final `null` frame. The stream subscribed while no run
/// existed, so it never saw a `Running` frame — the run counter is the only
/// evidence that a run happened at all.
#[tokio::test(start_paused = true)]
async fn a_run_that_starts_and_ends_between_two_reads_still_emits_the_end_frame() {
    let ports = FakePorts::default();
    let job = succeeded_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports.clone());

    // Subscribed BEFORE any apply: baseline seq 0, no payload.
    let (_status, mut body) = open_stream(app, job.id).await;

    // The whole run: claim, publish, clear — all inside this tick. Each write
    // wakes the stream, and the stream's re-read must conclude "that run is
    // over" instead of "nothing started yet".
    let run_id = ApplyRunId::new();
    assert!(
        ports
            .ai_import_queue
            .claim_apply_run(job.id, run_id)
            .await
            .expect("claim succeeds")
    );
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, run_id, Some(&progress_of(run_id, 1, 1)))
        .await
        .expect("apply progress write succeeds");
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, run_id, None)
        .await
        .expect("clearing the run succeeds");

    // The stream may still deliver the run's own `Running` frame if it wins the
    // race with the clear — what matters is that the END arrives instead of a
    // silent close. Collect data frames until the documented null shows up.
    let mut saw_null = false;
    for _ in 0..4 {
        let Some(frame) = next_frame(&mut body).await else {
            break;
        };
        let Some(payload) = frame_data(&frame) else {
            continue; // keep-alive
        };
        if payload["apply_progress"].is_null() {
            saw_null = true;
            break;
        }
    }
    assert!(
        saw_null,
        "the run's end must reach the client instead of the stream closing \
         silently (the #800 #2 symptom)"
    );
    assert!(
        next_frame(&mut body).await.is_none(),
        "and the stream ends after the end-of-run frame"
    );
}

/// Issue #800: a claimed run that has not published yet must not be reported as
/// finished — the claim lands before the worker's first frame.
#[tokio::test(start_paused = true)]
async fn a_claimed_run_without_a_payload_keeps_the_stream_open() {
    let ports = FakePorts::default();
    let job = succeeded_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    let app = state(ports.clone());

    let run_id = ApplyRunId::new();
    assert!(
        ports
            .ai_import_queue
            .claim_apply_run(job.id, run_id)
            .await
            .expect("claim succeeds")
    );
    let (_status, mut body) = open_stream(app, job.id).await;

    // The worker's first payload is the first frame — not a null.
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, run_id, Some(&progress_of(run_id, 2, 9)))
        .await
        .expect("apply progress write succeeds");
    let frame = next_frame(&mut body).await.expect("first run frame");
    let payload = frame_data(&frame).expect("frame carries JSON data");
    assert_eq!(payload["apply_progress"]["applied"], 2);
    assert_eq!(
        payload["apply_progress"]["run_id"],
        run_id.as_uuid().to_string()
    );
}

/// Issue #800 review: the run baseline is read **before** the subscription, and
/// the snapshot after it. A run that claims and clears inside that window must
/// still produce the documented final `null` frame — with the baseline read
/// afterwards, its counter bump would be absorbed and the stream would go
/// `Idle` and close silently.
#[tokio::test(start_paused = true)]
async fn a_run_inside_the_subscribe_window_still_emits_the_end_frame() {
    let ports = FakePorts::default();
    let job = succeeded_job(AiImportJobId::new());
    ports.ai_import_queue.seed(job.clone()).await;
    // The scripted run fires right after the FIRST `apply_run_state` read — i.e.
    // between the baseline read and the subscription.
    let scripted_run = ApplyRunId::new();
    *ports
        .ai_import_queue
        .run_inside_window
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(scripted_run);

    let app = state(ports.clone());
    let (_status, mut body) = open_stream(app, job.id).await;

    // The baseline was read before the subscription (the fix under test) …
    let order: Vec<&'static str> = ports
        .ai_import_queue
        .call_log
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone();
    let first_baseline = order
        .iter()
        .position(|call| *call == "apply_run_state")
        .expect("the stream reads the run slot");
    let first_subscribe = order
        .iter()
        .position(|call| *call == "subscribe")
        .expect("the stream subscribes");
    assert!(
        first_baseline < first_subscribe,
        "the run counter must be read BEFORE subscribing, got {order:?}"
    );

    // … and the run that landed in the window is reported, not swallowed.
    let frame = next_frame(&mut body)
        .await
        .expect("the window run's end is reported instead of a silent close");
    let payload = frame_data(&frame).expect("frame carries JSON data");
    assert!(
        payload["apply_progress"].is_null(),
        "the unseen run's end signal is the documented null frame, got {payload}"
    );
    assert!(
        next_frame(&mut body).await.is_none(),
        "and the stream ends after it"
    );
    let slot = ports
        .ai_import_queue
        .apply_run_state(job.id)
        .await
        .expect("run slot read")
        .expect("the fake tracks the slot");
    assert_eq!(slot.seq, 1, "the scripted run bumped the counter once");
    assert_eq!(slot.owner, None, "and it is over");
}

#[tokio::test]
async fn a_job_that_is_not_succeeded_gets_no_apply_progress_written() {
    // The adapter's status predicate: an apply can only ever run against a
    // `succeeded` job, so neither a claim nor a payload may land on any other
    // state (issue #800: the claim is the gate that keeps a run unique).
    let ports = FakePorts::default();
    let mut job = succeeded_job(AiImportJobId::new());
    job.status = JobStatus::Running;
    ports.ai_import_queue.seed(job.clone()).await;

    let run_id = ApplyRunId::new();
    assert!(
        !ports
            .ai_import_queue
            .claim_apply_run(job.id, run_id)
            .await
            .expect("the claim itself does not fail"),
        "a running job has no apply slot"
    );
    ports
        .ai_import_queue
        .mark_apply_progress(job.id, run_id, Some(&progress_of(run_id, 1, 2)))
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
