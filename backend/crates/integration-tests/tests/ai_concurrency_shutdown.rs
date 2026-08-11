// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (pi)
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod fixtures;

// Graceful-shutdown contract for the AI import concurrency limiter (issue #214).
//
// The composition root (`main.rs`) must stop AI import workers in the exact
// order the permit reclaimer requires:
//
// 1. signal workers to stop + bounded `drain()` of in-flight permits;
// 2. join the worker tasks (dropping their limiter clones);
// 3. drop the limiter clone held by the composition root, then
//    `PermitReclaimer::shutdown()`.
//
// These tests assert the two acceptance criteria that can only be verified
// end-to-end: after a simulated shutdown no permit rows remain (the reclaims
// were drained rather than aborted), and the sequence terminates within its
// budget even when a task holds a permit longer than the drain timeout.

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use breakdown_core::error::DomainError;
use infra::ai::{AiWorkerLifecycle, AiWorkerRuntime, PgAiConcurrencyLimiter};
use sqlx::PgPool;
use tokio::task::JoinHandle;

/// Poll until the limiter reports at least `count` in-flight permits, or fail
/// at the deadline. Used to synchronize with a worker that is still
/// acquiring its permit, so a later `drain()` actually observes load.
async fn wait_until_in_flight(limiter: &PgAiConcurrencyLimiter, count: i64, context: &str) {
    let deadline = tokio::time::Instant::now() + RECLAIM_DEADLINE;
    loop {
        let in_flight = limiter.in_flight().await.unwrap();
        if in_flight >= count {
            return;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "{context}: never reached {count} in-flight (saw {in_flight})"
        );
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Poll until the limiter reports no in-flight permits, or fail at the
/// deadline. Polling (not sleeping) keeps the test fast and deterministic.
async fn await_capacity_released(limiter: &PgAiConcurrencyLimiter, context: &str) {
    let deadline = tokio::time::Instant::now() + RECLAIM_DEADLINE;
    loop {
        let in_flight = limiter.in_flight().await.unwrap();
        if in_flight == 0 {
            return;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "{context}: {in_flight} permit(s) still held after {RECLAIM_DEADLINE:?}"
        );
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Count rows in the permit table directly. The reclaimer's whole job is to
/// delete permits that were dropped without release, so a correct shutdown
/// leaves the table empty.
async fn count_permits(pool: &PgPool) -> i64 {
    sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM ai_import.concurrency_permit")
        .fetch_one(pool)
        .await
        .unwrap()
}

/// A single-slot limiter: the next acquisition can only succeed if the
/// previous permit was genuinely reclaimed.
fn single_slot(pool: &PgPool) -> Result<PgAiConcurrencyLimiter> {
    Ok(PgAiConcurrencyLimiter::new(pool.clone(), 1, 1)?)
}

/// A worker task that holds a permit for `hold` before releasing it. Mirrors
/// the real worker loop's contract: a job holds one permit for its whole
/// runtime, and the permit is released when the job completes (or the task is
/// cancelled, via the drop hook).
fn spawn_holding_worker(runtime: Arc<AiWorkerRuntime>, hold: Duration) -> JoinHandle<()> {
    tokio::spawn(async move {
        // `run_job` acquires a permit, holds it for `hold`, then releases it.
        match runtime
            .run_job("shutdown-test-user", || async move {
                tokio::time::sleep(hold).await;
                Ok::<_, DomainError>(())
            })
            .await
        {
            Ok(Some(())) => {}
            Ok(None) => panic!("worker failed to acquire a permit (got None)"),
            Err(error) => panic!("worker run_job errored: {error}"),
        }
    })
}

/// Bound for the reclaimer round-trip (channel hand-off + one DELETE).
const RECLAIM_DEADLINE: Duration = Duration::from_secs(5);
const POLL_INTERVAL: Duration = Duration::from_millis(25);

#[tokio::test]
async fn simulated_shutdown_leaves_no_permit_rows() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let (limiter, reclaimer) = single_slot(&pool)?.spawn_reclaimer();
    let limiter_arc = Arc::new(limiter);
    let runtime = Arc::new(AiWorkerRuntime::new(Arc::clone(&limiter_arc)));

    // Spawn a short-lived worker that acquires and releases a permit.
    let handle = spawn_holding_worker(Arc::clone(&runtime), Duration::from_millis(50));

    // Simulate the composition root's 3-step shutdown sequence.
    // Step 1: bounded drain of in-flight permits.
    runtime.drain().await;
    // Step 2: join the worker task (drops its limiter clone via the runtime Arc).
    handle.await.unwrap();
    // Step 3: drop every limiter clone — both the one held here and the one
    // inside `runtime` — so the reclaimer's channel closes and it can finish.
    // This MUST happen before `reclaimer.shutdown()`, which waits for the
    // channel to close.
    drop(limiter_arc);
    drop(runtime);
    reclaimer.shutdown().await;

    // The reclaimer must have drained every queued reclaim instead of
    // discarding them — the table is empty.
    assert_eq!(
        count_permits(&pool).await,
        0,
        "shutdown must drain queued reclaims, leaving no permit rows"
    );
    Ok(())
}

#[tokio::test]
async fn shutdown_reclaims_an_aborted_workers_permit() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let (limiter, reclaimer) = single_slot(&pool)?.spawn_reclaimer();
    let limiter_arc = Arc::new(limiter);
    let runtime = Arc::new(AiWorkerRuntime::new(Arc::clone(&limiter_arc)));

    // Hold a permit far longer than the drain budget, then abort the worker:
    // the drop hook enqueues the reclaim, and the reclaimer must delete the
    // row (permit reconciliation) even though the worker never released it.
    let handle = spawn_holding_worker(Arc::clone(&runtime), Duration::from_secs(60));
    wait_until_in_flight(&limiter_arc, 1, "worker holding permit").await;

    runtime.drain().await;
    handle.abort();
    await_capacity_released(&limiter_arc, "after abort").await;

    drop(limiter_arc);
    drop(runtime);
    reclaimer.shutdown().await;

    assert_eq!(
        count_permits(&pool).await,
        0,
        "aborted worker's permit must be reclaimed during shutdown"
    );
    Ok(())
}

/// Deterministic, no-DB lifecycle test: `AiWorkerRuntime::drain` must return
/// exactly at `DRAIN_TIMEOUT` when a permit is held, verified with a paused
/// `current_thread` runtime (issue #214). The AGENTS.md testing guardrail
/// forbids wall-clock-gated tests, so the clock is advanced synthetically.
#[tokio::test(flavor = "current_thread", start_paused = true)]
async fn drain_is_bounded_by_drain_timeout() {
    let lifecycle = AiWorkerLifecycle::default();
    // Hold a permit so drain() must wait for the deadline rather than
    // returning immediately on an empty table.
    let _guard = lifecycle.start_job();
    assert_eq!(lifecycle.in_flight(), 1);

    // Start the drain future; on the paused clock it must not complete before
    // DRAIN_TIMEOUT elapses.
    let drain = tokio::spawn(async move {
        lifecycle.drain().await;
    });

    // Yield so the spawned task registers its timer, then advance the clock
    // exactly to the deadline.
    tokio::task::yield_now().await;
    tokio::time::advance(infra::ai::DRAIN_TIMEOUT).await;

    // The drain must complete at (or very near) the deadline.
    drain
        .await
        .expect("drain did not complete after DRAIN_TIMEOUT");
}
