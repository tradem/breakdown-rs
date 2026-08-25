// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for AiWorkerLifecycle — kills mutations in in_flight, drain,
//! and AiJobGuard::drop.

use std::time::Duration;

use super::{AiWorkerLifecycle, DRAIN_TIMEOUT};

// ===========================================================================
// in_flight — kills return 0 / 1 replacement
// ===========================================================================

#[test]
fn in_flight_starts_at_zero() {
    let lifecycle = AiWorkerLifecycle::default();
    assert_eq!(lifecycle.in_flight(), 0);
}

#[test]
fn in_flight_increments_on_start_job() {
    let lifecycle = AiWorkerLifecycle::default();
    let _guard = lifecycle.start_job();
    assert_eq!(lifecycle.in_flight(), 1);
}

#[test]
fn in_flight_decrements_on_guard_drop() {
    let lifecycle = AiWorkerLifecycle::default();
    {
        let _guard = lifecycle.start_job();
        assert_eq!(lifecycle.in_flight(), 1);
    }
    assert_eq!(lifecycle.in_flight(), 0);
}

#[test]
fn in_flight_counts_multiple_jobs() {
    let lifecycle = AiWorkerLifecycle::default();
    let _g1 = lifecycle.start_job();
    let _g2 = lifecycle.start_job();
    let _g3 = lifecycle.start_job();
    assert_eq!(lifecycle.in_flight(), 3);

    drop(_g2);
    assert_eq!(lifecycle.in_flight(), 2);
}

// ===========================================================================
// drain — kills () replacement and == → !=
// ===========================================================================

#[tokio::test]
async fn drain_returns_immediately_when_no_jobs() {
    let lifecycle = AiWorkerLifecycle::default();
    let start = tokio::time::Instant::now();
    lifecycle.drain().await;
    let elapsed = start.elapsed();
    assert!(
        elapsed < Duration::from_secs(1),
        "drain should return immediately when no jobs"
    );
}

#[tokio::test]
async fn drain_waits_for_jobs_to_complete() {
    let lifecycle = AiWorkerLifecycle::default();
    let guard = lifecycle.start_job();
    assert_eq!(lifecycle.in_flight(), 1);

    // Spawn a task that will complete after a short delay
    let lc = lifecycle.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(50)).await;
        drop(guard);
        // Signal that we're done
        lc.drained.notify_waiters();
    });

    // drain should wait until the job completes
    let start = tokio::time::Instant::now();
    lifecycle.drain().await;
    let elapsed = start.elapsed();
    assert!(
        elapsed >= Duration::from_millis(40),
        "drain should wait for job completion"
    );
    assert_eq!(lifecycle.in_flight(), 0);
}

#[tokio::test]
async fn drain_times_out_for_stuck_jobs() {
    let lifecycle = AiWorkerLifecycle::default();
    let _guard = lifecycle.start_job();

    // Start drain with a very short timeout by using a custom lifecycle
    // For this test, we verify that drain respects DRAIN_TIMEOUT
    let start = tokio::time::Instant::now();
    lifecycle.drain().await;
    let elapsed = start.elapsed();

    // Should have waited approximately DRAIN_TIMEOUT
    assert!(
        elapsed >= DRAIN_TIMEOUT - Duration::from_secs(1),
        "drain should wait for timeout: elapsed {elapsed:?}"
    );
}

// ===========================================================================
// AiJobGuard — kills drop → () replacement
// ===========================================================================

#[test]
fn guard_drop_decrements_in_flight() {
    let lifecycle = AiWorkerLifecycle::default();
    let guard = lifecycle.start_job();
    assert_eq!(lifecycle.in_flight(), 1);

    drop(guard);
    assert_eq!(lifecycle.in_flight(), 0);
}

#[tokio::test]
async fn guard_notifies_on_drop() {
    let lifecycle = AiWorkerLifecycle::default();
    let guard = lifecycle.start_job();

    // Spawn a waiter
    let lc = lifecycle.clone();
    let handle = tokio::spawn(async move {
        lc.drained.notified().await;
        lc.in_flight()
    });

    // Give the waiter time to register
    tokio::time::sleep(Duration::from_millis(10)).await;

    // Drop the guard — this should notify the waiter
    drop(guard);

    let result = handle.await.unwrap();
    assert_eq!(result, 0);
}

// ===========================================================================
// DRAIN_TIMEOUT constant
// ===========================================================================

#[test]
fn drain_timeout_is_reasonable() {
    assert!(DRAIN_TIMEOUT >= Duration::from_secs(10));
    assert!(DRAIN_TIMEOUT <= Duration::from_secs(60));
}

// ===========================================================================
// Multiple concurrent jobs
// ===========================================================================

#[tokio::test]
async fn drain_waits_for_all_concurrent_jobs() {
    let lifecycle = AiWorkerLifecycle::default();
    let g1 = lifecycle.start_job();
    let g2 = lifecycle.start_job();
    let g3 = lifecycle.start_job();
    assert_eq!(lifecycle.in_flight(), 3);

    // Complete jobs at different times
    let lc = lifecycle.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(30)).await;
        drop(g1);
        lc.drained.notify_waiters();
    });

    let lc = lifecycle.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(60)).await;
        drop(g2);
        lc.drained.notify_waiters();
    });

    let lc = lifecycle.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(90)).await;
        drop(g3);
        lc.drained.notify_waiters();
    });

    lifecycle.drain().await;
    assert_eq!(lifecycle.in_flight(), 0);
}

// ===========================================================================
// Clone behavior
// ===========================================================================

#[test]
fn lifecycle_clone_shares_state() {
    let lifecycle = AiWorkerLifecycle::default();
    let lifecycle2 = lifecycle.clone();

    let _guard = lifecycle.start_job();
    assert_eq!(lifecycle2.in_flight(), 1);
}
