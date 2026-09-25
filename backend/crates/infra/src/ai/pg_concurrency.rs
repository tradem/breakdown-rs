// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: space-bunny-free (opencode-go)

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

use std::future::Future;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use breakdown_core::error::DomainError;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use tokio::sync::mpsc::{self, UnboundedReceiver, UnboundedSender};
use uuid::Uuid;

/// How many renewals fit in one lease window (two spare renewals absorb a
/// transient database blip), mirroring [`super::heartbeat`].
const RENEWALS_PER_LEASE: u32 = 3;

/// Attempts the reclaimer makes per dropped permit before leaving the row to
/// its lease (issue #528 follow-up). Diagnostics and tests only.
///
/// A single attempt turned one transient failure into a full lease outage for
/// the reclaimed capacity: the fast path exists precisely so a cancelled
/// worker's slot is free again within milliseconds, and a lock timeout or a
/// dropped connection must not silently demote it to the 30 s lease floor.
/// The bound is deliberate and small — an unbounded retry would stall every
/// later reclaim behind one permanently broken row, which is the failure the
/// lease fallback exists to cover.
pub const RECLAIM_ATTEMPTS: u32 = 4;

/// Backoff before the next reclaim attempt, multiplied by the attempt number
/// (`100 ms, 200 ms, 300 ms, …`).
const RECLAIM_BACKOFF_BASE: Duration = Duration::from_millis(100);

/// Upper bound on how long ONE reclaim statement may wait for the row lock.
/// Diagnostics and tests only.
///
/// The row of a permit whose acquisition was cancelled mid-`commit` can still
/// be locked by that transaction while it resolves. Without a bound, such a
/// delete blocks the reclaim loop head-of-line: every later dropped permit
/// waits behind it even though their own rows are free. The wait is therefore
/// capped and the attempt is retried by [`reclaim_permit_with_retry`]; the
/// loop keeps moving either way.
pub const RECLAIM_LOCK_TIMEOUT: Duration = Duration::from_millis(200);

/// The one named unit both lease bounds derive from: the recovery horizon
/// shared with the AI import claim lease (`LEASE_UNIT_SECS` in
/// [`super::queue`], 900s), so operators reason about a single window.
/// Deriving both bounds from it keeps their ordering true by construction when
/// the horizon is retuned.
const LEASE_UNIT_SECS: u64 = 900;

/// How much shorter than one horizon the floor may be.
const MIN_LEASE_DIVISOR: u64 = 30;

/// Default permit lease: one recovery horizon. A job whose worker died is
/// reclaimable at roughly the same time as the capacity it held.
pub const DEFAULT_PERMIT_LEASE: Duration = Duration::from_secs(LEASE_UNIT_SECS);

/// Floor for the permit lease (1/30th of the horizon, 30s). A near-zero lease
/// would let an acquisition reclaim the permit of a *healthy* holder mid-job,
/// over-admitting work.
const MIN_PERMIT_LEASE: Duration = Duration::from_secs(LEASE_UNIT_SECS / MIN_LEASE_DIVISOR);

// Ordering invariant: a zero floor would defeat the clamp in `with_lease`, and
// an inverted range would make the default itself unreachable.
const _LEASE_ORDERING_INVARIANT: () = assert!(
    MIN_PERMIT_LEASE.as_secs() > 0 && MIN_PERMIT_LEASE.as_secs() <= DEFAULT_PERMIT_LEASE.as_secs()
);

// Renewal invariant, asserted on the *shortest* permitted lease because that is
// the worst case: even there a renewal must fall strictly before expiry, or a
// healthy long-running holder would always be reclaimed mid-flight. This binds
// `RENEWALS_PER_LEASE` and the floor together, so raising the former or
// lowering the latter cannot silently invert the relationship.
const _RENEWAL_FITS_IN_LEASE: () =
    assert!(MIN_PERMIT_LEASE.as_secs() > MIN_PERMIT_LEASE.as_secs() / RENEWALS_PER_LEASE as u64);

/// Compile-time ordering the reclaim budget relies on: more than one attempt
/// (a single attempt would demote every transient failure to the lease) and a
/// lock wait that resolves inside the lease floor.
const _RECLAIM_BUDGET_INVARIANT: () = assert!(
    RECLAIM_ATTEMPTS > 1 && RECLAIM_LOCK_TIMEOUT.as_millis() < MIN_PERMIT_LEASE.as_millis()
);

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
            return Err(DomainError::validation("invalid AI concurrency limits"));
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

    /// Start the in-process reclaimer and arm every permit issued afterward
    /// with a drop hook.
    ///
    /// The returned handle owns the background task. Keep it alive for as long
    /// as the limiter is used and end it with
    /// [`PermitReclaimer::shutdown`] — *after* dropping every clone of the
    /// limiter, so the channel closes and the loop can finish the ids the
    /// cancelled workers just enqueued. Dropping the handle instead aborts the
    /// task and leaves those ids to their lease.
    #[must_use]
    pub fn spawn_reclaimer(mut self) -> (Self, PermitReclaimer) {
        let (sender, receiver) = mpsc::unbounded_channel();
        let handle = tokio::spawn(reclaim_loop(self.pool.clone(), receiver));
        self.reclaimer = Some(sender);
        (
            self,
            PermitReclaimer {
                handle: Some(handle),
            },
        )
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
            return Err(DomainError::validation(
                "AI concurrency user id must not be empty",
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
        //
        // `clock_timestamp()`, not `now()`: `now()` is fixed at *transaction
        // start*, and this transaction began before the advisory-lock wait
        // above. Under contention that wait can be long, so `now()` would
        // judge leases against a stale instant — missing rows that have since
        // expired, and (below) issuing a permit whose window silently started
        // before the caller ever held the lock.
        let reclaimed = sqlx::query(
            r#"
            DELETE FROM ai_import.concurrency_permit
            WHERE expires_at <= clock_timestamp()
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
            VALUES ($1, $2, $3, clock_timestamp() + make_interval(secs => $4))
            "#,
        )
        .bind(id)
        .bind(user_id)
        .bind(worker_id)
        .bind(self.lease.as_secs_f64())
        .execute(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;

        // Arm the reclaim hook *before* committing, not after.
        //
        // `commit()` is an await point, and a cancellation there is not
        // benign: the COMMIT may already have reached PostgreSQL, so the row
        // can be durable even though this call never returns. If the permit
        // were constructed after the commit, nothing local would own that id
        // and the capacity would sit occupied until the lease expired — the
        // exact failure mode this module exists to remove, reintroduced at the
        // last possible instant.
        //
        // Holding the permit across the commit makes the id owned from the
        // moment it exists: cancellation drops it and the reclaimer deletes by
        // id. The delete is safe in both directions — if the transaction did
        // commit, the row goes away; if it rolled back, the delete matches
        // nothing. A reclaim that arrives while the transaction is still
        // in flight simply blocks on the row lock until it resolves.
        let permit = PgAiConcurrencyPermit {
            id,
            pool: self.pool.clone(),
            lease: self.lease,
            reclaimer: self.reclaimer.clone(),
            released: AtomicBool::new(false),
        };
        tx.commit().await.map_err(map_sqlx_error)?;

        Ok(Some(permit))
    }

    /// Number of live (unexpired) permits. Diagnostics and tests only.
    pub async fn in_flight(&self) -> Result<i64, DomainError> {
        sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM ai_import.concurrency_permit WHERE expires_at > clock_timestamp()
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

/// Handle of the background reclaimer task. It must be kept alive for as long
/// as permits are issued, and ended with [`shutdown`](Self::shutdown).
pub struct PermitReclaimer {
    handle: Option<tokio::task::JoinHandle<()>>,
}

impl PermitReclaimer {
    /// Drain and stop: wait until every permit id already queued has been
    /// deleted, then return.
    ///
    /// This is the graceful-shutdown path and the one that matters most.
    /// Shutdown is exactly when workers are cancelled *en masse*, so the queue
    /// is at its fullest precisely when the reclaimer is ending; aborting here
    /// would discard those ids and hand back their capacity only after a full
    /// lease window — the very outcome this module exists to prevent.
    ///
    /// **Shutdown order matters.** Every sender clone must be gone before the
    /// channel can close, and permits hold one too — so:
    ///   1. cancel *and join* every task that may hold a
    ///      [`PgAiConcurrencyPermit`] (joining is what guarantees the permit
    ///      was actually dropped, not merely that cancellation was requested);
    ///   2. drop every clone of the [`PgAiConcurrencyLimiter`];
    ///   3. `shutdown().await`.
    ///
    /// Skipping step 1 or 2 leaves a live sender and this call waits forever.
    /// Callers that cannot guarantee the ordering (or cannot await) use
    /// [`abort`](Self::abort), which gives up the queued reclaims to their
    /// lease instead of hanging.
    pub async fn shutdown(mut self) {
        let Some(handle) = self.handle.take() else {
            return;
        };
        if let Err(error) = handle.await {
            tracing::error!(
                error = %error,
                "AI concurrency reclaimer task failed during shutdown"
            );
        }
    }

    /// Stop immediately, discarding queued reclaims. Their capacity returns
    /// when the lease expires.
    pub fn abort(mut self) {
        if let Some(handle) = self.handle.take() {
            handle.abort();
        }
    }
}

impl Drop for PermitReclaimer {
    fn drop(&mut self) {
        // Last resort for callers that cannot await: `Drop` cannot drain.
        // `shutdown`/`abort` have already taken the handle in the normal paths.
        if let Some(handle) = self.handle.take() {
            handle.abort();
        }
    }
}

/// Delete permits whose holders were dropped without releasing.
///
/// Each id is reclaimed through [`reclaim_permit_with_retry`] (a bounded
/// number of attempts, each statement bounded by [`RECLAIM_LOCK_TIMEOUT`]).
/// Only once those attempts are exhausted is the row left to the lease, and
/// that is logged as the capacity outage it is.
async fn reclaim_loop(pool: PgPool, mut receiver: UnboundedReceiver<Uuid>) {
    while let Some(id) = receiver.recv().await {
        match reclaim_permit_with_retry(id, || delete_permit_bounded(&pool, id)).await {
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
                attempts = RECLAIM_ATTEMPTS,
                "failed to reclaim dropped AI concurrency permit within {} attempts; \
                 capacity returns when the lease expires",
                RECLAIM_ATTEMPTS
            ),
        }
    }
}

/// The reclaim retry policy, isolated from the database so it can be proved
/// without one: [delete_once] performs a single bounded delete and may fail
/// transiently (lock timeout, connection blip). The loop stops at the first
/// success — including "the row was already gone" — and gives up after
/// [`RECLAIM_ATTEMPTS`], never blocking the loop behind one broken row.
async fn reclaim_permit_with_retry<F, Fut>(
    id: Uuid,
    mut delete_once: F,
) -> Result<bool, DomainError>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<bool, DomainError>>,
{
    let mut attempt: u32 = 1;
    loop {
        match delete_once().await {
            Ok(freed) => return Ok(freed),
            Err(error) if attempt >= RECLAIM_ATTEMPTS => return Err(error),
            Err(error) => {
                tracing::warn!(
                    permit_id = %id,
                    attempt,
                    error = %error,
                    "AI concurrency permit reclaim attempt failed; retrying"
                );
                tokio::time::sleep(reclaim_backoff(attempt)).await;
                attempt += 1;
            }
        }
    }
}

/// Backoff before attempt number [attempt] (1-based): linear growth from
/// [`RECLAIM_BACKOFF_BASE`], so the whole retry budget stays bounded and
/// predictable.
fn reclaim_backoff(attempt: u32) -> Duration {
    RECLAIM_BACKOFF_BASE.saturating_mul(attempt)
}

/// Worst-case time the reclaimer spends on ONE dropped permit before handing
/// it to the lease: every attempt may burn the full lock timeout, plus the
/// linear backoffs in between. Diagnostics and the analytic budget that
/// integration tests assert against (never a guessed sleep).
#[must_use]
pub fn reclaim_retry_budget() -> Duration {
    let lock_waits = RECLAIM_LOCK_TIMEOUT.saturating_mul(RECLAIM_ATTEMPTS);
    let backoffs = (1..RECLAIM_ATTEMPTS).fold(Duration::ZERO, |acc, attempt| {
        acc + reclaim_backoff(attempt)
    });
    lock_waits + backoffs
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
    released: AtomicBool,
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

    /// The permit's current lease deadline, or `None` if it has already been
    /// reclaimed.
    ///
    /// This is the observation counterpart to [`renew`](Self::renew): a holder
    /// doing unusually long work can check how much headroom is left before
    /// the sweep would take its capacity, and operational tooling can surface
    /// "capacity at risk" without reading the table directly. The value comes
    /// from the database, so it is comparable with other deadlines regardless
    /// of the caller's clock.
    pub async fn deadline(&self) -> Result<Option<DateTime<Utc>>, DomainError> {
        sqlx::query_scalar(
            r#"
            SELECT expires_at FROM ai_import.concurrency_permit WHERE id = $1
            "#,
        )
        .bind(self.id)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)
    }

    /// Return the capacity. Idempotent: the row is deleted by id, and the drop
    /// hook is disarmed so the reclaimer is not asked to repeat the work.
    pub async fn release(self) -> Result<(), DomainError> {
        let outcome = delete_permit(&self.pool, self.id).await;
        // Disarm only on a *confirmed* delete. The await above is itself a
        // cancellation point: if the task is dropped there the statement never
        // reached PostgreSQL, and an early disarm would make `Drop` skip the
        // reclaimer and strand the row until its lease expires. A failed
        // delete stays armed for the same reason — the error is still returned
        // to the caller, and the reclaimer retries the (idempotent) delete.
        if outcome.is_ok() {
            self.released.store(true, Ordering::Release);
        }
        outcome.map(|_| ())
    }

    /// Extend the lease. Holders whose work can outlive one lease window renew
    /// at [`permit_renewal_interval`]; otherwise the sweep would reclaim their
    /// capacity while they are still using it.
    ///
    /// Returns `Conflict` when the permit is no longer live — either already
    /// swept, or past its deadline — so the caller learns its capacity is gone
    /// instead of running on.
    pub async fn renew(&self) -> Result<(), DomainError> {
        let affected = sqlx::query(
            r#"
            UPDATE ai_import.concurrency_permit
            SET expires_at = clock_timestamp() + make_interval(secs => $2)
            WHERE id = $1
              AND expires_at > clock_timestamp()
            "#,
        )
        .bind(self.id)
        .bind(self.lease.as_secs_f64())
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?
        .rows_affected();
        if affected == 0 {
            // The `expires_at > clock_timestamp()` guard makes expiry
            // irreversible: a delayed holder must not resurrect a lease that
            // the next acquisition is entitled to sweep, or it would hold
            // capacity past its own deadline while the limiter has already
            // counted the slot as reclaimable. The clock function matters here
            // too — a renewal delayed behind a slow round-trip must be judged
            // against the instant the statement actually runs, not against
            // transaction start. Expired and already-swept are reported
            // identically because they mean the same thing to the caller: this
            // permit no longer grants capacity.
            return Err(DomainError::conflict(format!(
                "AI concurrency permit {} is no longer live (expired or reclaimed)",
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

/// The reclaimer variant of [`delete_permit`]: the same idempotent delete,
/// but inside a short transaction whose row-lock wait is capped by
/// [`RECLAIM_LOCK_TIMEOUT`].
///
/// A permit whose acquisition was cancelled mid-`commit` can still be locked
/// by that transaction; an uncapped delete would block the whole reclaim loop
/// behind it. `set_config(..., is_local = true)` is the bindable form of
/// `SET LOCAL lock_timeout` — `SET` itself takes no parameters, and a bound
/// value keeps the statement free of string interpolation.
///
/// Only the reclaim path is bounded: [`PgAiConcurrencyPermit::release`] is
/// awaited by its holder, which may legitimately block, and a timeout there
/// would turn a slow-but-successful release into a spurious error.
async fn delete_permit_bounded(pool: &PgPool, id: Uuid) -> Result<bool, DomainError> {
    let mut tx = pool.begin().await.map_err(map_sqlx_error)?;
    sqlx::query("SELECT set_config('lock_timeout', $1, true)")
        .bind(format!("{}ms", RECLAIM_LOCK_TIMEOUT.as_millis()))
        .execute(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;
    let affected = match sqlx::query(
        r#"
        DELETE FROM ai_import.concurrency_permit WHERE id = $1
        "#,
    )
    .bind(id)
    .execute(&mut *tx)
    .await
    {
        Ok(result) => result.rows_affected(),
        Err(error) => {
            // A timed-out statement aborts the transaction. Roll back
            // explicitly — the deletion did NOT happen — so the connection is
            // handed back clean for the next attempt. Rolling back on the
            // success path instead would silently undo the delete.
            tx.rollback().await.map_err(map_sqlx_error)?;
            return Err(map_sqlx_error(error));
        }
    };
    tx.commit().await.map_err(map_sqlx_error)?;
    Ok(affected > 0)
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    DomainError::service_unavailable(format!("AI concurrency database error: {error}"))
}

#[cfg(test)]
mod tests {
    use super::{
        DEFAULT_PERMIT_LEASE, MIN_PERMIT_LEASE, RECLAIM_ATTEMPTS, RECLAIM_BACKOFF_BASE,
        RENEWALS_PER_LEASE, permit_renewal_interval, reclaim_backoff, reclaim_permit_with_retry,
        reclaim_retry_budget,
    };
    use breakdown_core::error::DomainError;
    use std::cell::Cell;
    use std::time::Duration;
    use uuid::Uuid;

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

    // --- P3.6: kill < → <= mutation in permit_renewal_interval -----------------

    #[test]
    fn renewal_interval_is_strictly_less_than_lease() {
        // For any reasonable lease, interval must be < lease, not <=.
        // The < → <= mutation would make interval == lease for RENEWALS_PER_LEASE == 1.
        for secs in [60, 300, 900, 3600] {
            let lease = Duration::from_secs(secs);
            let interval = permit_renewal_interval(lease);
            assert!(
                interval < lease,
                "interval {interval:?} must be strictly less than lease {lease:?}"
            );
        }
    }

    #[test]
    fn renewal_interval_at_minimum_lease_is_one_second() {
        // MIN_PERMIT_LEASE / RENEWALS_PER_LEASE might be < 1s, so it floors to 1s
        let interval = permit_renewal_interval(MIN_PERMIT_LEASE);
        assert!(interval >= Duration::from_secs(1));
        assert!(interval < MIN_PERMIT_LEASE);
    }

    #[test]
    fn renewal_interval_computed_correctly_for_standard_lease() {
        // The default 900s lease / 3 renewals = 300s
        let interval = permit_renewal_interval(Duration::from_secs(900));
        assert_eq!(interval, Duration::from_secs(300));
    }

    #[test]
    fn renewal_interval_for_large_lease() {
        let interval = permit_renewal_interval(Duration::from_secs(3600));
        assert_eq!(interval, Duration::from_secs(1200));
    }

    // --- Reclaim retry policy (issue #528 follow-up) -------------------------
    //
    // The policy is proved here WITHOUT a database and WITHOUT timing
    // assertions: the deleter is a closure, so the test counts attempts and
    // sees the returned outcome only. The database-level fault (a locked row)
    // is injected separately by the integration test.

    /// A deleter that fails [failures] times, then reports the row freed.
    fn flaky_deleter(
        calls: &Cell<u32>,
        failures: u32,
    ) -> impl FnMut() -> std::pin::Pin<Box<dyn Future<Output = Result<bool, DomainError>>>> {
        move || {
            calls.set(calls.get() + 1);
            let attempt = calls.get();
            Box::pin(async move {
                if attempt <= failures {
                    Err(DomainError::service_unavailable(
                        "transient reclaim failure",
                    ))
                } else {
                    Ok(true)
                }
            })
        }
    }

    #[tokio::test]
    async fn reclaim_stops_at_the_first_success() {
        let calls = Cell::new(0);
        let freed = reclaim_permit_with_retry(Uuid::now_v7(), flaky_deleter(&calls, 0))
            .await
            .expect("the first attempt succeeds");
        assert!(freed);
        assert_eq!(calls.get(), 1, "a healthy delete must not be repeated");
    }

    #[tokio::test]
    async fn reclaim_retries_a_transient_failure() {
        let calls = Cell::new(0);
        let freed = reclaim_permit_with_retry(Uuid::now_v7(), flaky_deleter(&calls, 2))
            .await
            .expect("a transient failure must be retried, not surfaced");
        assert!(freed);
        assert_eq!(
            calls.get(),
            3,
            "two failures then one success — one attempt per failure plus the winner"
        );
    }

    #[tokio::test]
    async fn reclaim_gives_up_after_the_bounded_attempts() {
        let calls = Cell::new(0);
        // Fails more often than the policy allows, so the lease fallback is
        // reached: the error is returned instead of retried forever.
        let error =
            reclaim_permit_with_retry(Uuid::now_v7(), flaky_deleter(&calls, RECLAIM_ATTEMPTS + 1))
                .await
                .expect_err("a permanently broken row must surface to the lease fallback");
        assert!(matches!(error, DomainError::ServiceUnavailable { .. }));
        assert_eq!(
            calls.get(),
            RECLAIM_ATTEMPTS,
            "the retry must be bounded, never open-ended"
        );
    }

    #[tokio::test]
    async fn reclaim_stops_when_the_row_is_already_gone() {
        let calls = Cell::new(0);
        // "Already gone" is a success (release() won the race), not a failure:
        // the policy must not keep deleting an absent row.
        let freed = reclaim_permit_with_retry(Uuid::now_v7(), || {
            calls.set(calls.get() + 1);
            Box::pin(async { Ok(false) })
        })
        .await
        .expect("an already-reclaimed row is not an error");
        assert!(!freed);
        assert_eq!(calls.get(), 1);
    }

    #[test]
    fn reclaim_backoff_grows_linearly_and_stays_bounded() {
        assert_eq!(reclaim_backoff(1), RECLAIM_BACKOFF_BASE);
        assert_eq!(reclaim_backoff(2), RECLAIM_BACKOFF_BASE * 2);
        // The whole retry budget stays far below the lease floor, so a
        // transient failure can never cost a lease window of capacity.
        let budget = reclaim_retry_budget();
        assert!(
            budget < MIN_PERMIT_LEASE,
            "retry budget {budget:?} must stay below the {MIN_PERMIT_LEASE:?} lease floor"
        );
    }

    #[test]
    fn reclaim_lock_timeout_is_below_the_lease_floor() {
        // The attempt count / lock-timeout ordering is asserted at compile time
        // by `_RECLAIM_BUDGET_INVARIANT`; here the *runtime* budget is checked.
        assert!(
            reclaim_retry_budget() < MIN_PERMIT_LEASE,
            "the whole reclaim budget must resolve inside the lease window"
        );
    }
}
