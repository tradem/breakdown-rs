// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

//! Cancellation-safety contract for the AI concurrency permit (issue #178).
//!
//! `AiWorkerRuntime::run_job` holds a PostgreSQL permit across
//! `operation().await`, which is a cancellation point. Rust cannot await
//! `release()` from `Drop`, so a cancelled worker used to leave the capacity
//! counter permanently raised and later jobs were refused admission.
//!
//! Two reclaim paths are asserted here against a real Postgres:
//!   * the **in-process reclaimer** — a dropped permit's capacity comes back
//!     without any lease wait, and the next job can acquire it;
//!   * the **lease** — a holder that died without even running its drop hook
//!     (process kill) is reclaimed by the next acquisition.
//!
//! The tests are timing-safe: lease expiry is produced by writing the
//! deadline into the past, never by sleeping, and the reclaimer race is
//! resolved by polling with a bounded deadline rather than by a fixed sleep.
//! The one raw `UPDATE` is deliberate — `expires_at` is operational
//! bookkeeping with no public setter, and the alternative would be sleeping
//! out a 30-second lease floor, which the deterministic-test rule forbids.

// Test-only lint suppressions: an unmet expectation must abort the test rather
// than be threaded through a Result.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use breakdown_core::error::DomainError;
use infra::ai::{AiWorkerRuntime, PgAiConcurrencyLimiter};
use sqlx::PgPool;
use tokio::sync::oneshot;

/// Bound for the reclaimer round-trip (channel hand-off + one DELETE). Two
/// seconds is orders of magnitude above the expected latency; the test still
/// fails fast because it polls.
const RECLAIM_DEADLINE: Duration = Duration::from_secs(5);
const POLL_INTERVAL: Duration = Duration::from_millis(25);

/// Count live permits directly. The permit table is operational bookkeeping,
/// not a projection, and `in_flight()` is the public accessor used elsewhere —
/// this helper exists so a test can distinguish "row gone" from "row expired".
async fn permit_rows(pool: &PgPool) -> i64 {
    sqlx::query_scalar("SELECT COUNT(*) FROM ai_import.concurrency_permit")
        .fetch_one(pool)
        .await
        .unwrap()
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

/// Force every live permit's lease into the past, simulating a process that
/// died without running any drop hook.
async fn expire_all_permits(pool: &PgPool) {
    sqlx::query("UPDATE ai_import.concurrency_permit SET expires_at = now() - interval '1 second'")
        .execute(pool)
        .await
        .unwrap();
}

/// A single-slot limiter: the next acquisition can only succeed if the
/// previous permit was genuinely reclaimed.
fn single_slot(pool: &PgPool) -> Result<PgAiConcurrencyLimiter> {
    Ok(PgAiConcurrencyLimiter::new(pool.clone(), 1, 1)?)
}

#[tokio::test]
async fn cancelled_job_releases_capacity_for_the_next_job() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let (limiter, _reclaimer) = single_slot(&pool)?.spawn_reclaimer();
    let limiter = Arc::new(limiter);
    let runtime = AiWorkerRuntime::new(Arc::clone(&limiter));

    // The operation parks forever, so the only way out is cancellation —
    // exactly the shutdown path that used to leak the permit.
    let (started_tx, started_rx) = oneshot::channel();
    let task_runtime = runtime.clone();
    let task = tokio::spawn(async move {
        task_runtime
            .run_job("cancel-user", || async move {
                started_tx.send(()).ok();
                std::future::pending::<Result<(), DomainError>>().await
            })
            .await
    });

    // Synchronise on the operation actually running, so the abort below lands
    // *after* acquisition rather than racing it.
    started_rx.await.expect("operation must start");
    assert_eq!(
        permit_rows(&pool).await,
        1,
        "the running job must hold its permit"
    );

    task.abort();
    assert!(task.await.unwrap_err().is_cancelled());

    await_capacity_released(&limiter, "after cancellation").await;
    assert_eq!(
        permit_rows(&pool).await,
        0,
        "a cancelled job must not leave its permit row behind"
    );

    // The actual availability guarantee: the next job gets in.
    let next = runtime
        .run_job("cancel-user", || async { Ok::<_, DomainError>(42) })
        .await?;
    assert_eq!(
        next,
        Some(42),
        "a subsequent job must be able to acquire the reclaimed capacity"
    );
    Ok(())
}

#[tokio::test]
async fn cancelled_job_leaves_no_in_flight_lifecycle_entry() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let (limiter, _reclaimer) = single_slot(&pool)?.spawn_reclaimer();
    let runtime = AiWorkerRuntime::new(Arc::new(limiter));

    let (started_tx, started_rx) = oneshot::channel();
    let task_runtime = runtime.clone();
    let task = tokio::spawn(async move {
        task_runtime
            .run_job("drain-user", || async move {
                started_tx.send(()).ok();
                std::future::pending::<Result<(), DomainError>>().await
            })
            .await
    });
    started_rx.await.expect("operation must start");
    assert_eq!(
        runtime.lifecycle.in_flight(),
        1,
        "a running job must be tracked for graceful shutdown"
    );

    task.abort();
    assert!(task.await.unwrap_err().is_cancelled());

    // The guard is dropped with the task, so shutdown must not wait for it.
    // `drain` is bounded by its own timeout, so a regression shows up as a
    // failed assertion here rather than as a hang.
    runtime.drain().await;
    assert_eq!(
        runtime.lifecycle.in_flight(),
        0,
        "cancellation must not leave a phantom in-flight job"
    );
    Ok(())
}

#[tokio::test]
async fn normal_completion_releases_exactly_once() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let (limiter, _reclaimer) = single_slot(&pool)?.spawn_reclaimer();
    let limiter = Arc::new(limiter);
    let runtime = AiWorkerRuntime::new(Arc::clone(&limiter));

    for round in 0..3 {
        let value = runtime
            .run_job("happy-user", || async move { Ok::<_, DomainError>(round) })
            .await?;
        assert_eq!(value, Some(round), "the operation result must propagate");
        assert_eq!(
            permit_rows(&pool).await,
            0,
            "round {round}: completion must release the permit"
        );
    }
    assert_eq!(
        runtime.lifecycle.in_flight(),
        0,
        "no lifecycle guard may survive a completed job"
    );

    // A double release would have driven capacity negative; a missing release
    // would refuse this acquisition. Both show up as a failure here.
    assert!(
        limiter.try_acquire("happy-user").await?.is_some(),
        "capacity must be exactly restored after repeated completions"
    );
    Ok(())
}

#[tokio::test]
async fn operation_error_propagates_and_still_releases() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let (limiter, _reclaimer) = single_slot(&pool)?.spawn_reclaimer();
    let runtime = AiWorkerRuntime::new(Arc::new(limiter));

    let error = runtime
        .run_job("failing-user", || async {
            Err::<(), _>(DomainError::ValidationError("boom".to_owned()))
        })
        .await
        .expect_err("the operation error must not be swallowed");
    assert!(
        matches!(error, DomainError::ValidationError(ref reason) if reason == "boom"),
        "the original error must be preserved, got {error:?}"
    );
    assert_eq!(
        permit_rows(&pool).await,
        0,
        "a failed job must release its permit too"
    );
    Ok(())
}

#[tokio::test]
async fn expired_lease_is_reclaimed_by_the_next_acquisition() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    // Deliberately no reclaimer: this models the process-death case, where the
    // in-process fast path dies with the holder and only the lease is left.
    let limiter = single_slot(&pool)?;

    let permit = limiter
        .try_acquire("crashed-user")
        .await?
        .expect("capacity is free");
    assert!(
        limiter.try_acquire("crashed-user").await?.is_none(),
        "a live permit must keep the single slot occupied"
    );

    expire_all_permits(&pool).await;
    // Keep the permit alive across the assertion so the reclaim is provably
    // the lease's doing and not a drop hook's.
    let reclaimed = limiter.try_acquire("crashed-user").await?;
    assert!(
        reclaimed.is_some(),
        "an expired permit must be reclaimed by the next acquisition"
    );
    assert_eq!(
        permit_rows(&pool).await,
        1,
        "the expired row must be swept, leaving only the new permit"
    );

    drop(permit);
    Ok(())
}

#[tokio::test]
async fn renew_extends_the_lease_and_fails_once_reclaimed() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let permit = limiter
        .try_acquire("long-user")
        .await?
        .expect("capacity is free");
    expire_all_permits(&pool).await;
    permit
        .renew()
        .await
        .expect("a live holder must be able to push its deadline out");

    // Renewal pushed the deadline back into the future, so the sweep must not
    // touch it — the slot stays occupied.
    assert!(
        limiter.try_acquire("long-user").await?.is_none(),
        "a renewed permit must not be reclaimable"
    );

    permit.release().await?;
    let orphan = limiter
        .try_acquire("long-user")
        .await?
        .expect("released capacity is free again");
    drop(orphan);
    Ok(())
}

#[tokio::test]
async fn renew_reports_conflict_when_the_permit_is_gone() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 2, 2)?;

    let permit = limiter
        .try_acquire("gone-user")
        .await?
        .expect("capacity is free");
    expire_all_permits(&pool).await;
    // Any acquisition sweeps expired rows, including this holder's.
    let _other = limiter.try_acquire("other-user").await?;

    let error = permit
        .renew()
        .await
        .expect_err("renewing a swept permit must not silently succeed");
    assert!(
        matches!(error, DomainError::Conflict(_)),
        "a holder must learn its capacity is gone, got {error:?}"
    );
    Ok(())
}

#[tokio::test]
async fn ceilings_are_still_enforced_per_user_and_globally() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 2, 1)?;

    let first = limiter.try_acquire("user-a").await?.expect("slot 1 free");
    assert!(
        limiter.try_acquire("user-a").await?.is_none(),
        "the per-user ceiling must hold"
    );
    let second = limiter.try_acquire("user-b").await?.expect("slot 2 free");
    assert!(
        limiter.try_acquire("user-c").await?.is_none(),
        "the global ceiling must hold"
    );

    first.release().await?;
    let third = limiter
        .try_acquire("user-c")
        .await?
        .expect("released global capacity must be reusable");

    drop(second);
    drop(third);
    Ok(())
}

#[tokio::test]
async fn empty_user_id_is_rejected_before_touching_capacity() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let error = limiter
        .try_acquire("   ")
        .await
        .expect_err("a blank owner would make a permit unattributable");
    assert!(matches!(error, DomainError::ValidationError(_)));
    assert_eq!(
        permit_rows(&pool).await,
        0,
        "a rejected acquisition must not consume capacity"
    );
    Ok(())
}
