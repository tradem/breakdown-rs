// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

//! Distributed per-day wrap-finality lock (PR #389 review follow-up).
//!
//! Serializes a shooting day's `WrapShootingDay` transition against every
//! frozen `SceneShoot` mutation on that day. The SceneShoot command adapter
//! holds the day's advisory lock across its **[write-side probe → event
//! append]** critical section, and `ShootingDayCommandsImpl::wrap` holds the
//! same lock across its append. A wrap therefore cannot commit while a
//! frozen mutation is being appended (and vice versa), which closes the
//! residual check-then-act interleave window that the event-stream probe
//! alone leaves open: after `wrap` completes, no execution mutation can be
//! appended for that day any more.
//!
//! The lock is a session-scoped PostgreSQL advisory lock taken inside a
//! dedicated transaction: `pg_advisory_xact_lock` is held until the
//! transaction ends, so dropping the guard always releases the lock —
//! including on task cancellation or process death (the database reclaims
//! the lock when the session dies). The wait is bounded with a
//! transaction-local `lock_timeout` (5s) so lock contention cannot pin
//! application-pool connections indefinitely; timeout expiry maps to the
//! retryable `DomainError::ServiceUnavailable`. This matches the established
//! advisory-lock patterns in this crate (photo GC sweep, AI import permits)
//! and works across API instances.
//!
//! The lock key is derived from the day id; key collisions (64 bits of a
//! UUIDv7) would only over-serialize independent days, never weaken the
//! guarantee. This is a lock, **not** a read-model projection query — the
//! CQRS boundary hard rule is untouched.

use breakdown_core::error::DomainError;
use breakdown_core::shared::ShootingDayId;
use sqlx::Postgres;
use sqlx::Transaction;

/// Per-day wrap-finality lock gate. Cloneable; backed by the shared
/// application connection pool.
#[derive(Clone, Debug)]
pub struct WrapFinalityGate {
    pool: sqlx::PgPool,
}

impl WrapFinalityGate {
    pub fn new(pool: sqlx::PgPool) -> Self {
        Self { pool }
    }

    /// Acquires the advisory lock for `day_id`, blocking until it is free
    /// (bounded by a 5s transaction-local `lock_timeout` — see the module
    /// docs). Hold the returned guard across the critical section; dropping
    /// it releases the lock (transaction rollback).
    pub async fn lock_day(&self, day_id: ShootingDayId) -> Result<WrapDayLockGuard, DomainError> {
        let mut tx = self.pool.begin().await.map_err(|e| {
            DomainError::service_unavailable(format!(
                "wrap-finality lock: cannot begin transaction: {e}"
            ))
        })?;
        // Bound the wait: `pg_advisory_xact_lock` blocks indefinitely, and
        // each waiter holds a connection from the shared application pool —
        // unbounded waits could exhaust it and stall unrelated requests
        // (PR #389 review). `SET LOCAL` scopes the timeout to this
        // transaction; on expiry the advisory-lock statement fails and maps
        // to the retryable `ServiceUnavailable` below.
        sqlx::query("SET LOCAL lock_timeout = '5s'")
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                DomainError::service_unavailable(format!(
                    "wrap-finality lock: cannot set lock_timeout: {e}"
                ))
            })?;
        sqlx::query("SELECT pg_advisory_xact_lock($1)")
            .bind(lock_key(day_id))
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                DomainError::service_unavailable(format!(
                    "wrap-finality lock: advisory lock failed: {e}"
                ))
            })?;
        Ok(WrapDayLockGuard { tx })
    }
}

/// Held transaction that keeps the per-day advisory lock. Dropping the guard
/// rolls the (empty) transaction back, releasing the lock.
#[derive(Debug)]
pub struct WrapDayLockGuard {
    /// Held purely for its `Drop` side effect: rolling back the (empty)
    /// transaction releases the advisory lock. Never read directly.
    #[allow(dead_code)] // lock-release side effect, not a data field
    tx: Transaction<'static, Postgres>,
}

/// Derives the advisory-lock key from the day id. Both UUIDv7 halves are
/// mixed (XOR) because the **high** 64 bits alone are not discriminative:
/// they carry the 48-bit millisecond timestamp (plus version/rand_a), so
/// ids generated within the same millisecond can share them — a pure
/// high-bit key would self-deadlock two different days created in the same
/// millisecond. Collisions of the mixed key would only over-serialize,
/// never under-serialize.
fn lock_key(day_id: ShootingDayId) -> i64 {
    let u = day_id.0.as_u128();
    ((u >> 64) ^ u) as i64
}
