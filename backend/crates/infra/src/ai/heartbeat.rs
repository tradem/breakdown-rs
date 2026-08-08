// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

//! Lease heartbeat for claimed AI import jobs (issue #177, review round 2).
//!
//! A claim lease is finite (default 900s), but a single script job is not: the
//! worker makes one LLM call per scene chunk, up to
//! `max_chunks_per_script` (default 128) calls of up to
//! `request_timeout_secs` (default 120s) each. At defaults the lease would
//! expire after roughly seven chunks, another worker would reclaim the job and
//! redo all the (paid) LLM work, and the original worker's terminal write
//! would then be rejected by the owner fence.
//!
//! [`LeaseHeartbeat`] keeps the claim alive for as long as the worker is
//! genuinely working: a background task calls the owner-fenced
//! `mark_running(id, worker_id)` at a fraction of the lease window. Because
//! the renewal is owner-fenced, a heartbeat can never resurrect a claim the
//! worker already lost — it simply stops.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use breakdown_core::ai::{AiImportJobId, AiImportQueue};
use tokio::task::JoinHandle;

/// How many renewals fit inside one lease window.
///
/// Three gives two spare renewals before the lease would lapse, so a single
/// transient database blip does not cost the claim. Deriving the interval from
/// this one constant keeps "interval < lease" true by construction.
const RENEWALS_PER_LEASE: u32 = 3;

// The interval must be a strict fraction of the lease, otherwise the heartbeat
// would fire no earlier than the expiry it is meant to prevent.
const _RENEWAL_INVARIANT: () = assert!(RENEWALS_PER_LEASE >= 2);

/// Renewal interval for a given lease window, floored at one second so a
/// pathologically short lease cannot spin the task.
pub fn renewal_interval(lease: Duration) -> Duration {
    let interval = lease / RENEWALS_PER_LEASE;
    if interval < Duration::from_secs(1) {
        Duration::from_secs(1)
    } else {
        interval
    }
}

/// A running heartbeat. Dropping it stops the renewals, so a worker that
/// returns early (via `?`) can never leak the task.
pub struct LeaseHeartbeat {
    handle: JoinHandle<()>,
    lost_claim: Arc<AtomicBool>,
}

impl LeaseHeartbeat {
    /// Start renewing `job_id`'s lease on behalf of `worker_id`.
    ///
    /// `lease` is the window the queue was configured with; the renewal
    /// interval is derived from it. A zero lease disables the heartbeat: that
    /// value only occurs in tests that deliberately simulate an already-dead
    /// worker.
    pub fn start<Q>(
        queue: Arc<Q>,
        job_id: AiImportJobId,
        worker_id: &str,
        lease: Duration,
    ) -> Option<Self>
    where
        Q: AiImportQueue + 'static,
    {
        if lease.is_zero() {
            return None;
        }
        let interval = renewal_interval(lease);
        let worker_id = worker_id.to_owned();
        let lost_claim = Arc::new(AtomicBool::new(false));
        let flag = Arc::clone(&lost_claim);

        let handle = tokio::spawn(async move {
            loop {
                tokio::time::sleep(interval).await;
                match queue.mark_running(job_id, &worker_id).await {
                    Ok(()) => {}
                    Err(breakdown_core::error::DomainError::Conflict(reason)) => {
                        // The claim is gone (lease lapsed and someone else
                        // reclaimed, or the job already reached a terminal
                        // state). Renewing again would be pointless, and the
                        // worker needs to know its work is now orphaned.
                        tracing::warn!(
                            job_id = %job_id.as_uuid(),
                            worker_id = %worker_id,
                            reason = %reason,
                            "AI import lease heartbeat lost the claim; stopping renewals"
                        );
                        flag.store(true, Ordering::Release);
                        return;
                    }
                    Err(error) => {
                        // A transient database error must not abandon the
                        // claim: the lease still has (RENEWALS_PER_LEASE - 1)
                        // intervals of headroom, so retry on the next tick.
                        tracing::warn!(
                            job_id = %job_id.as_uuid(),
                            worker_id = %worker_id,
                            error = %error,
                            "AI import lease renewal failed; retrying on next tick"
                        );
                    }
                }
            }
        });

        Some(Self { handle, lost_claim })
    }

    /// Whether the heartbeat observed that the claim was lost. Workers check
    /// this before doing further billable work.
    pub fn claim_lost(&self) -> bool {
        self.lost_claim.load(Ordering::Acquire)
    }

    /// Stop renewing. Called before the terminal lifecycle write so the
    /// heartbeat cannot race the completion.
    pub fn stop(self) {
        self.handle.abort();
    }
}

impl Drop for LeaseHeartbeat {
    fn drop(&mut self) {
        // Covers the early-return (`?`) paths: no renewal task outlives the
        // job it belongs to.
        self.handle.abort();
    }
}

/// Convenience wrapper: `None` when no heartbeat is running.
pub fn claim_lost(heartbeat: Option<&LeaseHeartbeat>) -> bool {
    heartbeat.is_some_and(LeaseHeartbeat::claim_lost)
}

#[cfg(test)]
mod tests {
    use super::{RENEWALS_PER_LEASE, renewal_interval};
    use std::time::Duration;

    #[test]
    fn renewal_interval_is_a_strict_fraction_of_the_lease() {
        let lease = Duration::from_secs(900);
        let interval = renewal_interval(lease);
        assert_eq!(interval, lease / RENEWALS_PER_LEASE);
        // Derived analytically, not by sleeping: the lease must survive a
        // missed renewal.
        assert!(
            interval * 2 < lease,
            "two renewal intervals must still fit inside the lease"
        );
    }

    #[test]
    fn renewal_interval_is_floored_for_tiny_leases() {
        // A 1s lease would otherwise produce a 333ms spin loop.
        assert_eq!(
            renewal_interval(Duration::from_secs(1)),
            Duration::from_secs(1)
        );
    }
}
