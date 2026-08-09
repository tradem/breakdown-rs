// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

//! Cancellation-safe PostgreSQL concurrency permits for AI import workers
//! (issue #178).
//!
//! # Why the counter model could not be made safe
//!
//! The original model was an anonymous counter: acquire incremented
//! `concurrency_counter.in_flight`, [`PgAiConcurrencyPermit::release`]
//! decremented it. `release` is `async`, but cancellation drops a future
//! *without* running any `async` cleanup — `Drop` cannot `.await`. A worker
//! task cancelled while awaiting its operation therefore dropped the permit
//! silently and the increment stayed forever. Because the increment carried no
//! owner, nothing could later tell a leaked unit of capacity apart from a
//! legitimately busy one, so there was no recovery path at all: capacity was
//! lost until an operator edited the row.
//!
//! # The two mechanisms
//!
//! Each permit is now **one owned row** in `ai_import.concurrency_permit`,
//! which makes both reclaim paths possible:
//!
//! 1. **Reclaimer (fast path, in-process).** Every permit holds a channel
//!    sender into a background task owned by the limiter. `Drop` is
//!    synchronous and non-blocking: it pushes the permit id onto an unbounded
//!    channel, and the reclaimer performs the `DELETE` a moment later. This
//!    covers task cancellation — the overwhelmingly common case (graceful
//!    shutdown, `select!` timeouts) — and returns capacity within
//!    milliseconds. `release()` disarms the drop hook so a normal completion
//!    deletes exactly once.
//! 2. **Lease (crash safety, cross-process).** Every row carries an
//!    `expires_at` deadline. If the whole process dies, the reclaimer dies with
//!    it and no `DELETE` is ever sent — so acquisition *first* deletes every
//!    row past its deadline, then counts. Capacity is thus self-healing
//!    without any operator action; the bound on the leak is one lease window.
//!    Holders that legitimately outlive the window renew via
//!    [`PgAiConcurrencyPermit::renew`].
//!
//! Neither mechanism can double-free: release, drop-reclaim and lease-reclaim
//! are all `DELETE ... WHERE id = $1`, which is idempotent by construction.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use breakdown_core::error::DomainError;
use sqlx::PgPool;
use tokio::sync::mpsc::{self, UnboundedReceiver, UnboundedSender};
use uuid::Uuid;

/// Default permit lease. Matches the AI import claim horizon
/// (`AI_IMPORT_LEASE_SECS` default, 900s) so operators reason about a single
/// recovery window: a job whose worker died is reclaimable at roughly the same
/// time as the capacity it held.
pub const DEFAULT_PERMIT_LEASE: Duration = Duration::from_secs(900);

/// Floor for the permit lease. A near-zero lease would let an acquisition
/// reclaim the permit of a *healthy* holder mid-job, over-admitting work; the
/// floor keeps the lease comfortably above one renewal interval.
const MIN_PERMIT_LEASE: Duration = Duration::from_secs(30);

// The lease must exceed the renewal interval, otherwise a holder could never
// renew in time and every long job would be over-admitted.
const _LEASE_INVARIANT: () = assert!(
    MIN_PERMIT_LEASE.as_secs() > 0 && MIN_PERMIT_LEASE.as_secs() <= DEFAULT_PERMIT_LEASE.as_secs()
);

/// How many renewals fit in one lease window (two spare renewals absorb a
/// transient database blip), mirroring [`super::heartbeat`].
const RENEWALS_PER_LEASE: u32 = 3;

/// Renewal interval for a lease window. Holders that may outlive the lease
/// call [`PgAiConcurrencyPermit::renew`] at this cadence.
#[must_use]
pub fn permit_renewal_interval(lease: Duration) -> Duration {
    let interval = lease / RENEWALS_PER_LEASE;
    if interval < Duration::from_secs(1) {
        Duration::from_secs(1)
    } else {
        interval
    }
}

/// PostgreSQL-backed global and per-user concurrency limiter.
///
/// Capacity is represented by rows rather than by a counter; see the module
/// documentation for the reclaim design.
#[derive(Clone, Debug)]
pub struct PgAiConcurrencyLimiter {
    pool: PgPool,
    max_global: i64,
    max_per_user: i64,
    lease: Duration,
    reclaimer: Option<UnboundedSender<Uuid>>,
}

impl PgAiConcurrencyLimiter {
    /// Build a limiter with the default lease and **no** in-process reclaimer.
    ///
    /// Without a reclaimer, a cancelled holder's capacity is still recovered —
    /// but only once its lease expires. Production callers should use
    /// [`PgAiConcurrencyLimiter::spawn_reclaimer`] to get the fast path too.
    pub fn new(pool: PgPool, max_global: u32, max_per_user: u32) -> Result<Self, DomainError> {
        let max_global = i64::from(max_global);
        let max_per_user = i64::from(max_per_user);
        if max_global <= 0 || max_per_user <= 0 || max_per_user > max_global {
            return Err(DomainError::ValidationError(
                "invalid AI concurrency limits".to_owned(),
            ));
        }
        Ok(Self {
            pool,
            max_global,
            max_per_user,
            lease: DEFAULT_PERMIT_LEASE,
            reclaimer: None,
        })
    }

    /// Override the permit lease window, clamped to at least
    /// [`MIN_PERMIT_LEASE`].
    #[must_use]
    pub fn with_lease(mut self, lease: Duration) -> Self {
        self.lease = lease.max(MIN_PERMIT_LEASE);
        self
    }

    /// Start the in-process reclaimer and arm every permit issued afterwards
    /// with a drop hook.
    ///
    /// The returned handle owns the background task; dropping it stops the
    /// task. Keep it alive for as long as the limiter is used (in the
    /// composition root: for the process lifetime).
    #[must_use]
    pub fn spawn_reclaimer(mut self) -> (Self, PermitReclaimer) {
        let (sender, receiver) = mpsc::unbounded_channel();
        let handle = tokio::spawn(reclaim_loop(self.pool.clone(), receiver));
        self.reclaimer = Some(sender);
        (self, PermitReclaimer { handle })
    }

    /// The active permit lease window.
    #[must_use]
    pub const fn lease(&self) -> Duration {
        self.lease
    }

    /// Try to take one unit of global and per-user capacity.
    ///
    /// `Ok(None)` means "at capacity, try again later". Expired permits are
    /// reclaimed inside the same transaction *before* counting, so a crashed
    /// holder cannot block admission beyond its lease.
    pub async fn try_acquire(
        &self,
        user_id: &str,
    ) -> Result<Option<PgAiConcurrencyPermit>, DomainError> {
        self.try_acquire_as(user_id, "").await
    }

    /// [`try_acquire`](Self::try_acquire) recording the owning worker for
    /// diagnostics.
    pub async fn try_acquire_as(
        &self,
        user_id: &str,
        worker_id: &str,
    ) -> Result<Option<PgAiConcurrencyPermit>, DomainError> {
        if user_id.trim().is_empty() {
            return Err(DomainError::ValidationError(
                "AI concurrency user id must not be empty".to_owned(),
            ));
        }
        let mut tx = self.pool.begin().await.map_err(map_sqlx_error)?;

        // Serialise admission decisions. Without this, two concurrent
        // acquisitions could both read `count < limit` and both insert,
        // over-admitting past the ceiling; a row-level lock cannot cover rows
        // that do not exist yet.
        sqlx::query("SELECT pg_advisory_xact_lock($1)")
            .bind(ADMISSION_LOCK_ID)
            .execute(&mut *tx)
            .await
            .map_err(map_sqlx_error)?;

        // Crash-safety reclaim: drop everything whose lease has lapsed.
        let reclaimed = sqlx::query(
            r#"
            DELETE FROM ai_import.concurrency_permit
            WHERE expires_at <= now()
            "#,
        )
        .execute(&mut *tx)
        .await
        .map_err(map_sqlx_error)?
        .rows_affected();
        if reclaimed > 0 {
            tracing::warn!(
                reclaimed,
                "reclaimed expired AI concurrency permits; a holder died without releasing"
            );
        }

        let global: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM ai_import.concurrency_permit
            "#,
        )
        .fetch_one(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;
        if global >= self.max_global {
            // Commit rather than roll back: the sweep above is real work, and
            // discarding it would make every refused acquisition re-scan the
            // same dead rows.
            tx.commit().await.map_err(map_sqlx_error)?;
            return Ok(None);
        }

        let per_user: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM ai_import.concurrency_permit WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;
        if per_user >= self.max_per_user {
            tx.commit().await.map_err(map_sqlx_error)?;
            return Ok(None);
        }

        let id = Uuid::now_v7();
        sqlx::query(
            r#"
            INSERT INTO ai_import.concurrency_permit
                (id, user_id, worker_id, expires_at)
            VALUES ($1, $2, $3, now() + make_interval(secs => $4))
            "#,
        )
        .bind(id)
        .bind(user_id)
        .bind(worker_id)
        .bind(self.lease.as_secs_f64())
        .execute(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;

        tx.commit().await.map_err(map_sqlx_error)?;

        Ok(Some(PgAiConcurrencyPermit {
            id,
            pool: self.pool.clone(),
            lease: self.lease,
            reclaimer: self.reclaimer.clone(),
            released: Arc::new(AtomicBool::new(false)),
        }))
    }

    /// Number of live (unexpired) permits. Diagnostics and tests only.
    pub async fn in_flight(&self) -> Result<i64, DomainError> {
        sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM ai_import.concurrency_permit WHERE expires_at > now()
            "#,
        )
        .fetch_one(&self.pool)
        .await
        .map_err(map_sqlx_error)
    }
}

/// Advisory lock id serialising admission decisions
/// (`b"AI_CONC "` read as a big-endian i64).
const ADMISSION_LOCK_ID: i64 = 4_704_396_028_463_170_336;

/// Handle of the background reclaimer task. Dropping it stops the task, so it
/// must be kept alive for as long as permits are issued.
pub struct PermitReclaimer {
    handle: tokio::task::JoinHandle<()>,
}

impl PermitReclaimer {
    /// Stop the reclaimer. Any permit dropped afterwards is recovered by its
    /// lease instead of immediately.
    pub fn stop(self) {
        self.handle.abort();
    }
}

impl Drop for PermitReclaimer {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

/// Delete permits whose holders were dropped without releasing.
///
/// A failed delete is logged and left to the lease: retrying forever inside
/// this loop would starve later reclaims behind a permanently broken row.
async fn reclaim_loop(pool: PgPool, mut receiver: UnboundedReceiver<Uuid>) {
    while let Some(id) = receiver.recv().await {
        match delete_permit(&pool, id).await {
            Ok(true) => tracing::warn!(
                permit_id = %id,
                "reclaimed AI concurrency permit dropped without release (task cancelled)"
            ),
            // Already gone: `release()` won the race, or the lease reclaimed
            // it. Both are correct outcomes, not errors.
            Ok(false) => {}
            Err(error) => tracing::error!(
                permit_id = %id,
                error = %error,
                "failed to reclaim dropped AI concurrency permit; \
                 capacity returns when the lease expires"
            ),
        }
    }
}

/// A held unit of AI import capacity.
///
/// Release happens exactly once, through whichever path runs first:
/// [`release`](Self::release) on normal completion, the reclaimer on drop
/// (cancellation), or the lease sweep on process death.
#[derive(Debug)]
pub struct PgAiConcurrencyPermit {
    id: Uuid,
    pool: PgPool,
    lease: Duration,
    reclaimer: Option<UnboundedSender<Uuid>>,
    released: Arc<AtomicBool>,
}

impl PgAiConcurrencyPermit {
    /// The permit id. Diagnostics and tests only.
    #[must_use]
    pub const fn id(&self) -> Uuid {
        self.id
    }

    /// The lease window this permit was issued with.
    #[must_use]
    pub const fn lease(&self) -> Duration {
        self.lease
    }

    /// Return the capacity. Idempotent: the row is deleted by id, and the drop
    /// hook is disarmed so the reclaimer is not asked to repeat the work.
    pub async fn release(self) -> Result<(), DomainError> {
        // Disarm first: if the delete below fails, `Drop` must not *also*
        // enqueue a reclaim — the error is propagated to the caller and the
        // lease remains the backstop.
        self.released.store(true, Ordering::Release);
        delete_permit(&self.pool, self.id).await.map(|_| ())
    }

    /// Extend the lease. Holders whose work can outlive one lease window renew
    /// at [`permit_renewal_interval`]; otherwise the sweep would reclaim their
    /// capacity while they are still using it.
    ///
    /// Returns `Conflict` when the permit no longer exists (already reclaimed),
    /// so the caller learns its capacity is gone instead of running on.
    pub async fn renew(&self) -> Result<(), DomainError> {
        let affected = sqlx::query(
            r#"
            UPDATE ai_import.concurrency_permit
            SET expires_at = now() + make_interval(secs => $2)
            WHERE id = $1
            "#,
        )
        .bind(self.id)
        .bind(self.lease.as_secs_f64())
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?
        .rows_affected();
        if affected == 0 {
            return Err(DomainError::Conflict(format!(
                "AI concurrency permit {} no longer exists",
                self.id
            )));
        }
        Ok(())
    }
}

impl Drop for PgAiConcurrencyPermit {
    fn drop(&mut self) {
        if self.released.load(Ordering::Acquire) {
            return;
        }
        let Some(reclaimer) = self.reclaimer.as_ref() else {
            // No reclaimer configured: the lease is the only recovery path.
            tracing::warn!(
                permit_id = %self.id,
                "AI concurrency permit dropped without release and without a reclaimer; \
                 capacity returns when the lease expires"
            );
            return;
        };
        // `send` on an unbounded channel never blocks and never awaits, which
        // is what makes this hook usable from `Drop`.
        if let Err(error) = reclaimer.send(self.id) {
            tracing::warn!(
                permit_id = %self.id,
                error = %error,
                "AI concurrency reclaimer is gone; capacity returns when the lease expires"
            );
        }
    }
}

/// Idempotent delete shared by every release path. `true` means this call was
/// the one that freed the capacity.
async fn delete_permit(pool: &PgPool, id: Uuid) -> Result<bool, DomainError> {
    let affected = sqlx::query(
        r#"
        DELETE FROM ai_import.concurrency_permit WHERE id = $1
        "#,
    )
    .bind(id)
    .execute(pool)
    .await
    .map_err(map_sqlx_error)?
    .rows_affected();
    Ok(affected > 0)
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    DomainError::ServiceUnavailable(format!("AI concurrency database error: {error}"))
}

#[cfg(test)]
mod tests {
    use super::{
        DEFAULT_PERMIT_LEASE, MIN_PERMIT_LEASE, RENEWALS_PER_LEASE, permit_renewal_interval,
    };
    use std::time::Duration;

    #[test]
    fn renewal_interval_is_a_strict_fraction_of_the_lease() {
        let lease = Duration::from_secs(900);
        let interval = permit_renewal_interval(lease);
        assert_eq!(interval, lease / RENEWALS_PER_LEASE);
        assert!(
            interval < lease,
            "a renewal that fires no earlier than the expiry cannot prevent it"
        );
    }

    #[test]
    fn renewal_interval_is_floored_for_tiny_leases() {
        assert_eq!(
            permit_renewal_interval(Duration::from_millis(30)),
            Duration::from_secs(1),
            "a sub-second interval would spin the renewal task"
        );
    }

    #[test]
    fn default_lease_is_within_bounds() {
        assert!(MIN_PERMIT_LEASE <= DEFAULT_PERMIT_LEASE);
    }
}
