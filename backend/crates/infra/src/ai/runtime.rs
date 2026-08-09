// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

//! Runtime wrapper that pairs a PostgreSQL concurrency permit with the
//! in-flight lifecycle guard used by graceful shutdown.
//!
//! # Cancellation safety (issue #178)
//!
//! `operation().await` is a cancellation point: during shutdown the enclosing
//! task can be dropped there, and the permit is then dropped *without*
//! `release()` ever being awaited. That is unavoidable — `Drop` cannot
//! `.await` — so the recovery is pushed into the permit itself
//! ([`super::pg_concurrency`]): its drop hook hands the permit id to an
//! in-process reclaimer, and an `expires_at` lease reclaims it even if the
//! whole process dies. This module therefore only has to keep the permit alive
//! for exactly the operation's lifetime and release it on the normal path.

use std::future::Future;
use std::sync::Arc;

use breakdown_core::error::DomainError;

use super::pg_concurrency::{
    PgAiConcurrencyLimiter, PgAiConcurrencyPermit, permit_renewal_interval,
};
use super::shutdown::AiWorkerLifecycle;

/// Runtime wrapper for a queue worker operation. It combines the PostgreSQL
/// permit table with an in-flight lifecycle guard.
#[derive(Clone)]
pub struct AiWorkerRuntime {
    pub concurrency: Arc<PgAiConcurrencyLimiter>,
    pub lifecycle: AiWorkerLifecycle,
}

impl AiWorkerRuntime {
    pub fn new(concurrency: Arc<PgAiConcurrencyLimiter>) -> Self {
        Self {
            concurrency,
            lifecycle: AiWorkerLifecycle::default(),
        }
    }

    /// Run one claimed job if capacity is available. `None` means the caller
    /// should leave/requeue the job and try again later.
    pub async fn run_job<F, Fut, T>(
        &self,
        user_id: &str,
        operation: F,
    ) -> Result<Option<T>, DomainError>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<T, DomainError>>,
    {
        self.run_job_as(user_id, "", operation).await
    }

    /// [`run_job`](Self::run_job) recording the claiming worker on the permit
    /// so a stuck slot can be attributed during an incident.
    pub async fn run_job_as<F, Fut, T>(
        &self,
        user_id: &str,
        worker_id: &str,
        operation: F,
    ) -> Result<Option<T>, DomainError>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<T, DomainError>>,
    {
        let Some(permit) = self.concurrency.try_acquire_as(user_id, worker_id).await? else {
            return Ok(None);
        };
        // The guard is taken after the permit so that a failed acquisition
        // never registers an in-flight job that shutdown would then wait for.
        // If the task is cancelled below, both the guard and the permit are
        // dropped: the guard decrements the in-flight count synchronously, and
        // the permit's drop hook reclaims the database row.
        let guard = self.lifecycle.start_job();
        let result = run_with_renewal(&permit, operation()).await;
        // Reached only when the operation ran to completion — on the normal
        // path capacity is returned here, exactly once, and the permit's drop
        // hook is disarmed by `release`.
        let release_result = permit.release().await;
        drop(guard);

        match (result, release_result) {
            (Ok(value), Ok(())) => Ok(Some(value)),
            (Err(error), Ok(())) => Err(error),
            (Ok(_), Err(error)) => Err(error),
            (Err(error), Err(release_error)) => {
                tracing::error!(
                    error = %release_error,
                    "failed to release AI concurrency slot after job failure"
                );
                Err(error)
            }
        }
    }

    /// Wait for all claimed operations to reach a terminal state before the
    /// worker runner returns successfully during graceful shutdown.
    pub async fn drain(&self) {
        self.lifecycle.drain().await;
    }
}

/// Drive `operation` while keeping the permit's lease alive.
///
/// A script job makes one LLM call per scene chunk — at defaults up to 128
/// calls of up to 120s, i.e. hours — while the permit lease is 900s. Without
/// renewal the sweep in `try_acquire` would reclaim the row of a *healthy*
/// holder and admit another job on top of it, over-admitting past the ceiling
/// the limiter exists to enforce. This mirrors [`super::heartbeat`], which
/// solves the same problem for the queue claim.
///
/// The renewal runs in the same task as the operation (a `select!` loop rather
/// than a spawned heartbeat) for two reasons: it needs only a `&` borrow of
/// the permit, so no `Arc`/clone is required, and it is inherently
/// cancellation-correct — cancelling the caller cancels the renewal with it,
/// leaving nothing to join or abort.
///
/// A `Conflict` means the permit is gone (expired and swept). The operation is
/// abandoned rather than allowed to continue on capacity the limiter has
/// already handed to someone else — the same rule the queue heartbeat applies
/// to a lost claim.
///
/// A transient renewal error is retried, but **only inside the lease the last
/// confirmed renewal bought**. Retrying blindly on a fixed cadence would let a
/// run of slow failures carry the loop past the deadline, and the operation
/// would then keep running on capacity another acquisition is already entitled
/// to sweep. The loop therefore tracks the confirmed deadline and gives up
/// before it rather than after.
async fn run_with_renewal<Fut, T>(
    permit: &PgAiConcurrencyPermit,
    operation: Fut,
) -> Result<T, DomainError>
where
    Fut: Future<Output = Result<T, DomainError>>,
{
    renew_while(permit.lease(), || permit.renew(), || permit.id(), operation).await
}

/// The renewal state machine, expressed over a `renew` closure so it can be
/// unit-tested on tokio's paused clock without a database.
///
/// Invariant: the loop never waits past `confirmed_deadline`, the instant the
/// last confirmed acquisition/renewal is known to be valid until. Every wait is
/// therefore `min(interval, time left on the lease)`, and reaching the deadline
/// without a confirmation aborts — the permit is reclaimable from that moment
/// on, so continuing would over-admit.
async fn renew_while<R, RFut, I, Fut, T>(
    lease: std::time::Duration,
    mut renew: R,
    permit_id: I,
    operation: Fut,
) -> Result<T, DomainError>
where
    R: FnMut() -> RFut,
    RFut: Future<Output = Result<(), DomainError>>,
    I: Fn() -> uuid::Uuid,
    Fut: Future<Output = Result<T, DomainError>>,
{
    let interval = permit_renewal_interval(lease);
    // The permit was issued (or last renewed) now, so this is when it lapses.
    let mut confirmed_deadline = tokio::time::Instant::now() + lease;
    tokio::pin!(operation);
    loop {
        let now = tokio::time::Instant::now();
        if now >= confirmed_deadline {
            // Only reachable after repeated unconfirmed renewals: the lease we
            // last had confirmation for has run out, so the row is now fair
            // game for the sweep. Stop before that, not after.
            let reason = format!(
                "AI concurrency permit {} lease expired without a confirmed renewal",
                permit_id()
            );
            tracing::warn!(permit_id = %permit_id(), "{reason}");
            return Err(DomainError::Conflict(reason));
        }
        // Never sleep past the deadline, however slow the failures are.
        let wait = interval.min(confirmed_deadline - now);

        tokio::select! {
            // The operation is polled first: a job that finishes in the same
            // tick as a renewal must not be delayed by a database round-trip.
            biased;
            result = &mut operation => return result,
            () = tokio::time::sleep(wait) => {
                // The renewal call is bounded by the deadline too: a renewal
                // that hangs past it is indistinguishable from one that never
                // happened, and waiting for its answer would run the operation
                // on a lease nobody has confirmed.
                let renewal = tokio::time::timeout_at(confirmed_deadline, renew()).await;
                match renewal {
                    Ok(Ok(())) => {
                        // A confirmed renewal starts a fresh lease. Measured
                        // after the call returns, since that is the earliest
                        // instant the database could have applied it.
                        confirmed_deadline = tokio::time::Instant::now() + lease;
                    }
                    Ok(Err(DomainError::Conflict(reason))) => {
                        tracing::warn!(
                            permit_id = %permit_id(),
                            reason = %reason,
                            "AI concurrency permit lost while the job was running; aborting"
                        );
                        return Err(DomainError::Conflict(reason));
                    }
                    Ok(Err(error)) => tracing::warn!(
                        permit_id = %permit_id(),
                        error = %error,
                        "AI concurrency permit renewal failed; retrying within the remaining lease"
                    ),
                    // Timed out at the deadline: the next loop iteration sees
                    // `now >= confirmed_deadline` and aborts.
                    Err(_) => tracing::warn!(
                        permit_id = %permit_id(),
                        "AI concurrency permit renewal did not complete before the lease deadline"
                    ),
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{permit_renewal_interval, renew_while};
    use breakdown_core::error::DomainError;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;
    use uuid::Uuid;

    /// A 30s lease renews every 10s (1/3 of the window), leaving two spare
    /// renewals of headroom — the same shape as production.
    const LEASE: Duration = Duration::from_secs(30);

    fn interval() -> Duration {
        permit_renewal_interval(LEASE)
    }

    /// A job that outlives many renewal intervals must be renewed repeatedly
    /// and still return its own result. Driven on the paused clock, so the
    /// ticks are advanced instantly rather than slept out.
    #[tokio::test(start_paused = true)]
    async fn renews_until_the_operation_finishes() {
        let renewals = AtomicUsize::new(0);
        let id = Uuid::now_v7();

        let result = renew_while(
            LEASE,
            || {
                renewals.fetch_add(1, Ordering::AcqRel);
                std::future::ready(Ok(()))
            },
            || id,
            async {
                tokio::time::sleep(interval() * 5).await;
                Ok::<_, DomainError>("done")
            },
        )
        .await;

        assert_eq!(result, Ok("done"), "renewal must not disturb the result");
        assert!(
            renewals.load(Ordering::Acquire) >= 4,
            "a job spanning five intervals must be renewed on each of them, got {}",
            renewals.load(Ordering::Acquire)
        );
    }

    /// Losing the permit aborts the job: continuing would run on capacity the
    /// limiter has already handed to someone else.
    #[tokio::test(start_paused = true)]
    async fn conflict_aborts_the_operation() {
        let id = Uuid::now_v7();
        let result = renew_while(
            LEASE,
            || std::future::ready(Err(DomainError::Conflict("swept".to_owned()))),
            || id,
            async {
                // Would outlive the test if the conflict were ignored.
                tokio::time::sleep(interval() * 100).await;
                Ok::<_, DomainError>("must not be reached")
            },
        )
        .await;

        assert!(
            matches!(result, Err(DomainError::Conflict(ref reason)) if reason == "swept"),
            "a lost permit must abort the job, got {result:?}"
        );
    }

    /// A transient renewal error is headroom, not a loss: the lease still has
    /// spare renewals, so the loop retries on the next tick.
    #[tokio::test(start_paused = true)]
    async fn transient_renewal_error_does_not_abort() {
        let attempts = AtomicUsize::new(0);
        let id = Uuid::now_v7();

        let result = renew_while(
            LEASE,
            || {
                let attempt = attempts.fetch_add(1, Ordering::AcqRel);
                std::future::ready(if attempt == 0 {
                    Err(DomainError::ServiceUnavailable("blip".to_owned()))
                } else {
                    Ok(())
                })
            },
            || id,
            async {
                tokio::time::sleep(interval() * 3).await;
                Ok::<_, DomainError>(42)
            },
        )
        .await;

        assert_eq!(result, Ok(42), "a database blip must not fail the job");
        assert!(
            attempts.load(Ordering::Acquire) >= 2,
            "the loop must retry after a transient error"
        );
    }

    /// Retries must stay *inside* the lease the last confirmed renewal bought.
    /// A run of failures that outlasts the window means the row is reclaimable,
    /// so the operation has to stop before the deadline rather than keep
    /// running on capacity another acquisition may already have taken.
    #[tokio::test(start_paused = true)]
    async fn unconfirmed_renewals_abort_before_the_lease_expires() {
        let id = Uuid::now_v7();
        let started = tokio::time::Instant::now();

        let result = renew_while(
            LEASE,
            // Every renewal fails transiently, and slowly: each attempt eats
            // most of a renewal interval, so a fixed-cadence loop would drift
            // past the deadline and only notice afterwards.
            || async {
                tokio::time::sleep(interval() - Duration::from_secs(1)).await;
                Err(DomainError::ServiceUnavailable("still down".to_owned()))
            },
            || id,
            async {
                tokio::time::sleep(LEASE * 10).await;
                Ok::<_, DomainError>("must not be reached")
            },
        )
        .await;

        assert!(
            matches!(result, Err(DomainError::Conflict(_))),
            "an unconfirmed lease must abort the job, got {result:?}"
        );
        // The decisive property: it stopped *before* the row became
        // reclaimable, not after. Both instants come from the paused clock, so
        // this is exact rather than a timing tolerance.
        assert!(
            tokio::time::Instant::now() <= started + LEASE,
            "the loop ran past the confirmed lease deadline"
        );
    }

    /// A confirmed renewal must start a fresh lease — otherwise a long job
    /// would abort at the original deadline no matter how well renewal worked.
    #[tokio::test(start_paused = true)]
    async fn a_confirmed_renewal_extends_the_deadline() {
        let id = Uuid::now_v7();
        let result = renew_while(LEASE, || std::future::ready(Ok(())), || id, async {
            // Many times the original lease: only possible if each
            // confirmed renewal moves the deadline forward.
            tokio::time::sleep(LEASE * 10).await;
            Ok::<_, DomainError>("survived")
        })
        .await;

        assert_eq!(
            result,
            Ok("survived"),
            "confirmed renewals must keep extending the lease"
        );
    }

    /// An operation that completes immediately must not pay for a renewal.
    #[tokio::test(start_paused = true)]
    async fn short_operation_never_renews() {
        let renewals = AtomicUsize::new(0);
        let id = Uuid::now_v7();

        let result = renew_while(
            LEASE,
            || {
                renewals.fetch_add(1, Ordering::AcqRel);
                std::future::ready(Ok(()))
            },
            || id,
            std::future::ready(Ok::<_, DomainError>(())),
        )
        .await;

        assert_eq!(result, Ok(()));
        assert_eq!(
            renewals.load(Ordering::Acquire),
            0,
            "a job shorter than one interval must not touch the database"
        );
    }
}
