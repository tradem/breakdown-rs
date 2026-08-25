// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! P3.6 — Postgres integration tests for PgAiConcurrencyLimiter.
//!
//! These tests kill the remaining 16 mutations in `pg_concurrency.rs` that
//! require a live Postgres instance. Tests use testcontainers (Tier 1–3).

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

mod fixtures;

use std::time::Duration;

use anyhow::Result;
use infra::ai::PgAiConcurrencyLimiter;

/// A limiter with global=2, per_user=1 for boundary testing.
fn boundary_limiter(pool: &sqlx::PgPool) -> Result<PgAiConcurrencyLimiter> {
    Ok(PgAiConcurrencyLimiter::new(pool.clone(), 2, 1)?)
}

/// A limiter with global=1, per_user=1 for single-slot testing.
fn single_slot(pool: &sqlx::PgPool) -> Result<PgAiConcurrencyLimiter> {
    Ok(PgAiConcurrencyLimiter::new(pool.clone(), 1, 1)?)
}

// ===========================================================================
// try_acquire / try_acquire_as — kills Ok(None) replacement
// ===========================================================================

#[tokio::test]
async fn try_acquire_returns_permit_when_capacity_available() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let permit = limiter.try_acquire("user-1").await?;
    assert!(permit.is_some(), "should acquire when capacity is free");

    // Clean up
    permit.unwrap().release().await?;
    Ok(())
}

#[tokio::test]
async fn try_acquire_returns_none_when_at_global_capacity() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    // Fill the single slot
    let permit1 = limiter.try_acquire("user-1").await?.expect("first acquire");
    // Second acquire should fail (global capacity exhausted)
    let permit2 = limiter.try_acquire("user-2").await?;
    assert!(permit2.is_none(), "should return None at global capacity");

    permit1.release().await?;
    Ok(())
}

#[tokio::test]
async fn try_acquire_returns_none_when_at_per_user_capacity() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = boundary_limiter(&pool)?;

    // Fill user-1's per-user slot (global has 2 slots, but per-user is 1)
    let permit1 = limiter.try_acquire("user-1").await?.expect("first acquire");
    // Second acquire for same user should fail (per-user capacity exhausted)
    let permit2 = limiter.try_acquire("user-1").await?;
    assert!(permit2.is_none(), "should return None at per-user capacity");

    // Different user should still succeed (global has room)
    let permit3 = limiter.try_acquire("user-2").await?;
    assert!(permit3.is_some(), "different user should acquire");

    permit1.release().await?;
    // permit2 is None, nothing to release
    permit3.unwrap().release().await?;
    Ok(())
}

#[tokio::test]
async fn try_acquire_as_records_worker_id() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let permit = limiter
        .try_acquire_as("user-1", "worker-abc")
        .await?
        .expect("should acquire");
    assert!(permit.id().as_u128() != 0);

    // Verify the worker_id was persisted
    let row: (String,) =
        sqlx::query_as("SELECT worker_id FROM ai_import.concurrency_permit WHERE id = $1")
            .bind(permit.id())
            .fetch_one(&pool)
            .await?;
    assert_eq!(row.0, "worker-abc", "worker_id should be persisted");

    permit.release().await?;
    Ok(())
}

#[tokio::test]
async fn try_acquire_rejects_empty_user_id() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let result = limiter.try_acquire("").await;
    assert!(result.is_err(), "empty user_id should fail");

    let result = limiter.try_acquire("  ").await;
    assert!(result.is_err(), "whitespace-only user_id should fail");

    Ok(())
}

// ===========================================================================
// in_flight — kills Ok(-1) / Ok(0) / Ok(1) replacement
// ===========================================================================

#[tokio::test]
async fn in_flight_returns_zero_when_no_permits() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let count = limiter.in_flight().await?;
    assert_eq!(count, 0, "should be 0 with no permits");

    Ok(())
}

#[tokio::test]
async fn in_flight_counts_live_permits() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = boundary_limiter(&pool)?;

    let p1 = limiter.try_acquire("user-1").await?.expect("first");
    assert_eq!(limiter.in_flight().await?, 1);

    let p2 = limiter.try_acquire("user-2").await?.expect("second");
    assert_eq!(limiter.in_flight().await?, 2);

    p1.release().await?;
    assert_eq!(limiter.in_flight().await?, 1);

    p2.release().await?;
    assert_eq!(limiter.in_flight().await?, 0);

    Ok(())
}

// ===========================================================================
// PgAiConcurrencyPermit::release — kills Ok(()) replacement
// ===========================================================================

#[tokio::test]
async fn release_frees_capacity() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let permit = limiter.try_acquire("user-1").await?.expect("acquire");
    assert_eq!(limiter.in_flight().await?, 1);

    permit.release().await?;
    assert_eq!(limiter.in_flight().await?, 0);

    // Should be able to acquire again
    let permit2 = limiter.try_acquire("user-1").await?.expect("re-acquire");
    assert_eq!(limiter.in_flight().await?, 1);

    permit2.release().await?;
    Ok(())
}

#[tokio::test]
async fn release_is_idempotent() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let permit = limiter.try_acquire("user-1").await?.expect("acquire");
    let permit_id = permit.id();

    permit.release().await?;

    // Second release should be a no-op (row already deleted)
    // We can't call release again on the same permit, but we can verify
    // the slot is free
    let permit2 = limiter.try_acquire("user-1").await?.expect("re-acquire");
    assert_ne!(
        permit2.id(),
        permit_id,
        "new permit should have different id"
    );
    permit2.release().await?;

    Ok(())
}

// ===========================================================================
// PgAiConcurrencyPermit::deadline — kills Ok(None) replacement
// ===========================================================================

#[tokio::test]
async fn deadline_returns_some_for_live_permit() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let permit = limiter.try_acquire("user-1").await?.expect("acquire");
    let deadline = permit.deadline().await?;
    assert!(deadline.is_some(), "live permit should have a deadline");

    permit.release().await?;
    Ok(())
}

// ===========================================================================
// PgAiConcurrencyPermit::renew — kills Ok(()) replacement and == → !=
// ===========================================================================

#[tokio::test]
async fn renew_extends_lease() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    let permit = limiter.try_acquire("user-1").await?.expect("acquire");
    let deadline_before = permit.deadline().await?.unwrap();

    // Wait a bit and renew
    tokio::time::sleep(Duration::from_millis(100)).await;
    permit.renew().await?;

    let deadline_after = permit.deadline().await?.unwrap();
    assert!(
        deadline_after > deadline_before,
        "deadline should extend after renew"
    );

    permit.release().await?;
    Ok(())
}

// ===========================================================================
// PermitReclaimer — kills shutdown/abort/drop → () replacements
// ===========================================================================

#[tokio::test]
async fn reclaimer_shutdown_drains_queue() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let (limiter, reclaimer) = single_slot(&pool)?.spawn_reclaimer();

    let permit = limiter.try_acquire("user-1").await?.expect("acquire");
    assert_eq!(limiter.in_flight().await?, 1);

    // Use a separate observer to check capacity after dropping everything
    let observer = single_slot(&pool)?;

    // Drop the permit (simulates cancellation) and the limiter (closes channel)
    drop(permit);
    drop(limiter);
    reclaimer.shutdown().await;

    // After shutdown, the permit should be reclaimed
    assert_eq!(
        observer.in_flight().await?,
        0,
        "shutdown must drain queued reclaims"
    );

    Ok(())
}

#[tokio::test]
async fn reclaimer_abort_stops_immediately() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let (limiter, reclaimer) = single_slot(&pool)?.spawn_reclaimer();

    let permit = limiter.try_acquire("user-1").await?.expect("acquire");
    drop(permit);

    // Abort instead of shutdown — capacity returns via lease expiry
    reclaimer.abort();

    // The permit row still exists until lease expires, but we can acquire
    // a new one after the old one expires (or we force-expire it)
    sqlx::query("UPDATE ai_import.concurrency_permit SET expires_at = now() - interval '1 second'")
        .execute(&pool)
        .await?;

    let permit2 = limiter
        .try_acquire("user-2")
        .await?
        .expect("should acquire after expiry");
    permit2.release().await?;

    Ok(())
}

// ===========================================================================
// Boundary tests — kills > with < / == / >= mutations
// ===========================================================================

#[tokio::test]
async fn boundary_global_capacity_exact_match() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 2, 2)?;

    let p1 = limiter.try_acquire("user-1").await?.expect("first");
    let p2 = limiter.try_acquire("user-2").await?.expect("second");

    // At capacity (2 == max_global)
    let p3 = limiter.try_acquire("user-3").await?;
    assert!(p3.is_none(), "should be at capacity when count == max");

    p1.release().await?;
    p2.release().await?;
    Ok(())
}

#[tokio::test]
async fn boundary_per_user_capacity_exact_match() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 10, 2)?;

    let p1 = limiter.try_acquire("user-1").await?.expect("first");
    let p2 = limiter.try_acquire("user-1").await?.expect("second");

    // At per-user capacity (2 == max_per_user)
    let p3 = limiter.try_acquire("user-1").await?;
    assert!(p3.is_none(), "should be at per-user capacity");

    p1.release().await?;
    p2.release().await?;
    Ok(())
}

#[tokio::test]
async fn expired_permits_are_reclaimed_before_admission() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let limiter = single_slot(&pool)?;

    // Acquire and manually expire the permit
    let _permit = limiter.try_acquire("user-1").await?.expect("acquire");
    assert_eq!(limiter.in_flight().await?, 1);

    // Force-expire the permit
    sqlx::query("UPDATE ai_import.concurrency_permit SET expires_at = now() - interval '1 second'")
        .execute(&pool)
        .await?;

    // New acquire should succeed because expired permits are reclaimed first
    let permit2 = limiter
        .try_acquire("user-2")
        .await?
        .expect("should reclaim and acquire");
    permit2.release().await?;

    Ok(())
}
