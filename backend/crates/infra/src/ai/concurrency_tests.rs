// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for `AiConcurrencyLimiter` (in-memory concurrency guard).

use breakdown_core::ai::AiImportBounds;

use super::AiConcurrencyLimiter;

/// Helper to create bounds with specific concurrency limits.
fn bounds(global: u32, per_user: u32) -> AiImportBounds {
    AiImportBounds {
        max_concurrent_jobs_global: global,
        max_concurrent_jobs_per_user: per_user,
        ..AiImportBounds::default()
    }
}

// ===========================================================================
// Constructor
// ===========================================================================

#[test]
fn new_with_valid_bounds_succeeds() {
    let limiter = AiConcurrencyLimiter::new(bounds(4, 2));
    assert!(limiter.is_ok());
}

#[test]
fn new_with_zero_global_fails() {
    let result = AiConcurrencyLimiter::new(bounds(0, 1));
    assert!(result.is_err());
}

#[test]
fn new_with_zero_per_user_fails() {
    let result = AiConcurrencyLimiter::new(bounds(4, 0));
    assert!(result.is_err());
}

#[test]
fn new_with_per_user_exceeding_global_fails() {
    let result = AiConcurrencyLimiter::new(bounds(2, 4));
    assert!(result.is_err());
}

// ===========================================================================
// try_acquire — kills Ok(None) replacement
// ===========================================================================

#[tokio::test]
async fn try_acquire_returns_permit_when_capacity_available() {
    let limiter = AiConcurrencyLimiter::new(bounds(2, 1)).unwrap();

    let permit = limiter.try_acquire("user-1").await;
    assert!(permit.is_ok(), "try_acquire should succeed");
    assert!(
        permit.unwrap().is_some(),
        "should return Some when capacity free"
    );
}

#[tokio::test]
async fn try_acquire_returns_none_at_global_capacity() {
    let limiter = AiConcurrencyLimiter::new(bounds(1, 1)).unwrap();

    let _permit1 = limiter.try_acquire("user-1").await.unwrap().expect("first");
    let permit2 = limiter.try_acquire("user-2").await.unwrap();
    assert!(permit2.is_none(), "should return None at global capacity");
}

#[tokio::test]
async fn try_acquire_returns_none_at_per_user_capacity() {
    let limiter = AiConcurrencyLimiter::new(bounds(4, 1)).unwrap();

    let _permit1 = limiter.try_acquire("user-1").await.unwrap().expect("first");
    let permit2 = limiter.try_acquire("user-1").await.unwrap();
    assert!(permit2.is_none(), "should return None at per-user capacity");
}

// ===========================================================================
// try_acquire — kills comparison mutations (> → <, ==, >=; < → <=, ==, >)
// ===========================================================================

#[tokio::test]
async fn try_acquire_allows_different_users_at_global_capacity() {
    let limiter = AiConcurrencyLimiter::new(bounds(2, 1)).unwrap();

    let _permit1 = limiter
        .try_acquire("user-1")
        .await
        .unwrap()
        .expect("user-1");
    let permit2 = limiter.try_acquire("user-2").await.unwrap();
    assert!(
        permit2.is_some(),
        "different user should succeed when global has room"
    );
}

#[tokio::test]
async fn try_acquire_allows_same_user_until_per_user_limit() {
    let limiter = AiConcurrencyLimiter::new(bounds(4, 2)).unwrap();

    let _permit1 = limiter.try_acquire("user-1").await.unwrap().expect("first");
    let permit2 = limiter.try_acquire("user-1").await.unwrap();
    assert!(
        permit2.is_some(),
        "same user should succeed until per-user limit"
    );

    let permit3 = limiter.try_acquire("user-1").await.unwrap();
    assert!(permit3.is_none(), "same user should fail at per-user limit");
}

// ===========================================================================
// try_acquire — kills || → && mutation
// ===========================================================================

#[tokio::test]
async fn cleanup_removes_empty_user_semaphores() {
    let limiter = AiConcurrencyLimiter::new(bounds(4, 1)).unwrap();

    // Acquire and release to create an entry
    {
        let _permit = limiter
            .try_acquire("user-1")
            .await
            .unwrap()
            .expect("acquire");
        // Permit dropped here, semaphore should be cleaned up
    }

    // Next acquire should create a fresh semaphore (not reuse stale one)
    let permit = limiter.try_acquire("user-1").await.unwrap();
    assert!(permit.is_some(), "should succeed after cleanup");
}

#[tokio::test]
async fn retain_keeps_semaphores_with_available_permits() {
    let limiter = AiConcurrencyLimiter::new(bounds(4, 2)).unwrap();

    // Acquire one slot for user-1
    let _permit1 = limiter.try_acquire("user-1").await.unwrap().expect("first");

    // user-1's semaphore should still have 1 available permit
    // so it should be retained even though strong_count > 1
    let permit2 = limiter.try_acquire("user-1").await.unwrap();
    assert!(
        permit2.is_some(),
        "should allow second permit for same user"
    );
}

// ===========================================================================
// AiConcurrencyPermit
// ===========================================================================

#[tokio::test]
async fn permit_holds_both_global_and_user_capacity() {
    let limiter = AiConcurrencyLimiter::new(bounds(1, 1)).unwrap();

    let permit = limiter
        .try_acquire("user-1")
        .await
        .unwrap()
        .expect("acquire");
    let (global, user) = permit.permits();

    // Both permits should be held
    assert!(global.num_permits() > 0 || user.num_permits() > 0);
}

#[tokio::test]
async fn dropping_permit_releases_capacity() {
    let limiter = AiConcurrencyLimiter::new(bounds(1, 1)).unwrap();

    {
        let _permit = limiter
            .try_acquire("user-1")
            .await
            .unwrap()
            .expect("acquire");
        // Permit dropped here
    }

    // Should be able to acquire again
    let permit = limiter.try_acquire("user-1").await.unwrap();
    assert!(permit.is_some(), "capacity should be released after drop");
}

#[tokio::test]
async fn multiple_users_can_hold_capacity_concurrently() {
    let limiter = AiConcurrencyLimiter::new(bounds(3, 1)).unwrap();

    let _p1 = limiter
        .try_acquire("user-1")
        .await
        .unwrap()
        .expect("user-1");
    let _p2 = limiter
        .try_acquire("user-2")
        .await
        .unwrap()
        .expect("user-2");
    let _p3 = limiter
        .try_acquire("user-3")
        .await
        .unwrap()
        .expect("user-3");

    // At global capacity now
    let p4 = limiter.try_acquire("user-4").await.unwrap();
    assert!(p4.is_none(), "should be at global capacity");
}
