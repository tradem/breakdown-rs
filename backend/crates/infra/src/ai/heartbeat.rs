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
//!
//! The same pattern carries the **apply run's** slot (issue #911, see
//! [`with_apply_run_lease`]): the apply slot is judged by silence too, and a
//! schedule apply publishes no frames while it merges — so it renews its claim
//! stamp from inside the run's own future instead of from a spawned task.

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
                    Err(breakdown_core::error::DomainError::Conflict { reason, .. }) => {
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

/// The lease window one apply run renews against (issue #911).
///
/// It *is* the window the single-flight predicates judge silence by, so the
/// renewal cadence and the steal decision cannot drift apart. Derived here once
/// instead of at the call site: `STALE_AFTER` is a fixed positive constant, so
/// the conversion cannot fail, and the fallback keeps the function panic-free
/// (the same rule `workers::apply_heartbeat_interval` follows).
pub fn apply_run_lease_window() -> Duration {
    breakdown_core::ai::ApplyProgress::STALE_AFTER
        .to_std()
        .unwrap_or(Duration::from_secs(600))
}

/// Keep one apply run's slot claimed while `run` executes (issue #911).
///
/// Why this is not a spawned task with a `JoinHandle` like [`LeaseHeartbeat`]:
/// the apply run itself is a future the caller owns (a worker task, or a
/// test's), so the renewal runs **inside the same future**. Cancellation is
/// then structural rather than bookkeeping: dropping the run drops the renewal
/// with it, which is exactly the property the crash recovery depends on — a
/// dead owner's renewals die with its task, so the staleness window still
/// expires and the slot becomes stealable.
///
/// Cadence is [`renewal_interval`] of `window` (a third, floored at one second),
/// three renewals per window, so one transient database blip cannot cost the
/// claim. A `false` from the queue means the slot moved on (taken over, or the
/// run already reached its terminal transition): the loop stops renewing and
/// still returns the run's own outcome — the run's fenced writes fail the same
/// way, and its result must not be turned into an error here.
///
/// A zero `window` disables the renewal entirely (the test-only "already dead
/// owner" case), which is why the helper needs no `Option` at the call site.
pub async fn with_apply_run_lease<Q, F, T>(
    queue: &Q,
    job_id: AiImportJobId,
    run_id: breakdown_core::ai::ApplyRunId,
    window: Duration,
    run: F,
) -> T
where
    Q: AiImportQueue + ?Sized,
    F: std::future::Future<Output = T>,
{
    if window.is_zero() {
        return run.await;
    }
    let mut ticker = tokio::time::interval(renewal_interval(window));
    // A missed tick must not produce a burst of catch-up writes.
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    // The claim (or the adoption) just stamped the slot, so the immediate first
    // tick has nothing to renew.
    ticker.tick().await;
    tokio::pin!(run);
    loop {
        tokio::select! {
            outcome = &mut run => return outcome,
            _ = ticker.tick() => {
                if !renew_apply_run_once(queue, job_id, run_id).await {
                    // The slot is provably gone: keep waiting for the run (its
                    // outcome is still the caller's), but stop renewing.
                    break;
                }
            }
        }
    }
    run.await
}

/// One renewal attempt: `true` means keep renewing.
///
/// A transient database error keeps the loop alive (the window still has
/// `RENEWALS_PER_LEASE - 1` intervals of headroom) — abandoning the claim over a
/// blip would hand a live run's slot to the next poll, which is the failure this
/// whole mechanism exists to prevent.
async fn renew_apply_run_once<Q>(
    queue: &Q,
    job_id: AiImportJobId,
    run_id: breakdown_core::ai::ApplyRunId,
) -> bool
where
    Q: AiImportQueue + ?Sized,
{
    match queue.renew_apply_run(job_id, run_id).await {
        Ok(true) => true,
        Ok(false) => {
            tracing::warn!(
                job_id = %job_id.as_uuid(),
                run_id = %run_id.as_uuid(),
                "the AI import apply run no longer owns its slot; stopping the lease renewal"
            );
            false
        }
        Err(error) => {
            tracing::warn!(
                job_id = %job_id.as_uuid(),
                run_id = %run_id.as_uuid(),
                %error,
                "AI import apply-run lease renewal failed; retrying on the next tick"
            );
            true
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        LeaseHeartbeat, RENEWALS_PER_LEASE, apply_run_lease_window, renewal_interval,
        with_apply_run_lease,
    };
    use async_trait::async_trait;
    use breakdown_core::ai::{
        AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId, AiImportQueue,
        ApplyRunId, DocumentKind, Telemetry,
    };
    use breakdown_core::error::DomainError;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;
    use tokio::sync::Notify;

    /// Scripted answer of `renew_apply_run` (issue #911).
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    enum ApplyRunRenewal {
        /// The run still owns its slot.
        Keep,
        /// The slot moved on (taken over, or the run already finished).
        Lost,
        /// A transient database error — the loop must keep renewing.
        Transient,
    }

    /// Queue whose `mark_running` returns a scripted outcome, so the
    /// heartbeat's state machine can be driven deterministically.
    struct ScriptedQueue {
        /// Error returned by every renewal; `None` means success.
        outcome: Option<DomainError>,
        renewals: AtomicUsize,
        /// Signalled after each renewal so tests can await the event itself
        /// instead of guessing how many task switches it takes.
        renewed: Notify,
        /// Scripted answer of `renew_apply_run` (issue #911) and how often it
        /// was asked. Separate from the lease above: the apply slot is a
        /// different claim with a different outcome vocabulary.
        apply_renewal: ApplyRunRenewal,
        apply_renewals: AtomicUsize,
    }

    impl ScriptedQueue {
        fn failing_with(error: DomainError) -> Arc<Self> {
            Arc::new(Self {
                outcome: Some(error),
                renewals: AtomicUsize::new(0),
                renewed: Notify::new(),
                apply_renewal: ApplyRunRenewal::Keep,
                apply_renewals: AtomicUsize::new(0),
            })
        }

        fn renewing(renewal: ApplyRunRenewal) -> Arc<Self> {
            Arc::new(Self {
                outcome: None,
                renewals: AtomicUsize::new(0),
                renewed: Notify::new(),
                apply_renewal: renewal,
                apply_renewals: AtomicUsize::new(0),
            })
        }

        fn renewals(&self) -> usize {
            self.renewals.load(Ordering::Acquire)
        }

        fn apply_renewals(&self) -> usize {
            self.apply_renewals.load(Ordering::Acquire)
        }
    }

    #[async_trait]
    impl AiImportQueue for ScriptedQueue {
        async fn enqueue(
            &self,
            _request: AiImportEnqueueRequest,
        ) -> Result<AiImportEnqueueResult, DomainError> {
            unimplemented!("not exercised by the heartbeat")
        }
        async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
            unimplemented!("not exercised by the heartbeat")
        }
        async fn claim_next_kind(
            &self,
            _worker_id: &str,
            _kind: DocumentKind,
        ) -> Result<Option<AiImportJob>, DomainError> {
            unimplemented!("not exercised by the heartbeat")
        }
        async fn get(&self, _id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
            unimplemented!("not exercised by the heartbeat")
        }
        async fn mark_running(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
        ) -> Result<(), DomainError> {
            self.renewals.fetch_add(1, Ordering::AcqRel);
            self.renewed.notify_waiters();
            match &self.outcome {
                None => Ok(()),
                Some(DomainError::Conflict { reason, .. }) => {
                    Err(DomainError::conflict(reason.clone()))
                }
                Some(other) => Err(DomainError::service_unavailable(other.to_string())),
            }
        }
        async fn mark_succeeded(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
            _preview_handle: &str,
        ) -> Result<(), DomainError> {
            unimplemented!("not exercised by the heartbeat")
        }
        async fn mark_failed(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
            _error_summary: &str,
            _error_code: Option<&str>,
            _retryable: bool,
            _retry_after: Option<std::time::Duration>,
        ) -> Result<(), DomainError> {
            unimplemented!("not exercised by the heartbeat")
        }
        async fn record_worker_telemetry(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
            _telemetry: Telemetry,
        ) -> Result<(), DomainError> {
            unimplemented!("not exercised by the heartbeat")
        }
        async fn record_telemetry(
            &self,
            _id: AiImportJobId,
            _telemetry: Telemetry,
        ) -> Result<(), DomainError> {
            unimplemented!("not exercised by the heartbeat")
        }

        /// The apply-slot lease (issue #911): scripted outcome + a counter, so a
        /// test can assert the cadence AND the stop conditions without a clock.
        async fn renew_apply_run(
            &self,
            _id: AiImportJobId,
            _run_id: ApplyRunId,
        ) -> Result<bool, DomainError> {
            self.apply_renewals.fetch_add(1, Ordering::AcqRel);
            match self.apply_renewal {
                ApplyRunRenewal::Keep => Ok(true),
                ApplyRunRenewal::Lost => Ok(false),
                ApplyRunRenewal::Transient => Err(DomainError::service_unavailable("db blip")),
            }
        }
    }

    /// One lease window; the heartbeat renews at a third of it.
    const TEST_LEASE: Duration = Duration::from_secs(900);

    /// Advance the paused clock until `expected` renewals have *actually*
    /// completed, awaiting the queue's notification for each one.
    ///
    /// Synchronising on the renewal event rather than on a fixed number of
    /// `yield_now()` calls is what makes this deterministic: `yield_now` does
    /// not guarantee a task switch, so a yield budget could pass or fail on
    /// scheduler timing alone.
    async fn await_renewals(queue: &ScriptedQueue, expected: usize) {
        let step = renewal_interval(TEST_LEASE);
        for _ in 0..expected {
            // Register interest BEFORE advancing: a notification fired between
            // the advance and the await would otherwise be missed and this
            // would hang.
            let renewed = queue.renewed.notified();
            tokio::pin!(renewed);
            // The spawned task arms its sleep timer only on its first poll, so
            // hand control over once before moving the clock.
            tokio::task::yield_now().await;
            tokio::time::advance(step + Duration::from_millis(1)).await;
            renewed.await;
        }
    }

    /// Advance past `ticks` intervals without expecting any renewal, then
    /// confirm none happened. Used to prove a stopped heartbeat stays stopped.
    async fn advance_expecting_no_renewal(queue: &ScriptedQueue, ticks: u32) {
        let step = renewal_interval(TEST_LEASE);
        let before = queue.renewals();
        for _ in 0..ticks {
            tokio::task::yield_now().await;
            tokio::time::advance(step + Duration::from_millis(1)).await;
            tokio::task::yield_now().await;
        }
        assert_eq!(
            queue.renewals(),
            before,
            "no renewal may happen after the heartbeat stopped"
        );
    }

    #[tokio::test(flavor = "current_thread", start_paused = true)]
    async fn conflict_renewal_flags_the_claim_as_lost_and_stops() {
        let queue = ScriptedQueue::failing_with(DomainError::conflict("reclaimed"));
        let heartbeat = LeaseHeartbeat::start(
            Arc::clone(&queue),
            AiImportJobId::new(),
            "worker-a",
            TEST_LEASE,
        )
        .expect("a non-zero lease starts a heartbeat");

        assert!(!heartbeat.claim_lost(), "no renewal has happened yet");

        await_renewals(&queue, 1).await;
        assert!(
            heartbeat.claim_lost(),
            "a Conflict renewal must flag the claim as lost — this is the signal \
             process_text uses to stop before the next LLM call"
        );

        // Renewals must stop: continuing would hammer the database for a claim
        // that is provably gone.
        advance_expecting_no_renewal(&queue, 3).await;
    }

    #[tokio::test(flavor = "current_thread", start_paused = true)]
    async fn transient_renewal_failure_keeps_the_claim_and_retries() {
        let queue = ScriptedQueue::failing_with(DomainError::service_unavailable("db blip"));
        let heartbeat = LeaseHeartbeat::start(
            Arc::clone(&queue),
            AiImportJobId::new(),
            "worker-a",
            TEST_LEASE,
        )
        .expect("a non-zero lease starts a heartbeat");

        // Awaiting three renewals *is* the proof that it kept retrying: the
        // helper would hang (and the test time out) if the task had stopped.
        await_renewals(&queue, 3).await;

        assert!(
            !heartbeat.claim_lost(),
            "a transient error must not abandon a still-valid claim"
        );
        assert_eq!(
            queue.renewals(),
            3,
            "the heartbeat must keep retrying after a transient failure"
        );
    }

    #[tokio::test(flavor = "current_thread", start_paused = true)]
    async fn a_zero_lease_starts_no_heartbeat() {
        let queue = ScriptedQueue::failing_with(DomainError::conflict("unused"));
        // Duration::ZERO is the test-only "already dead worker" case; renewing
        // it would be meaningless.
        assert!(
            LeaseHeartbeat::start(queue, AiImportJobId::new(), "worker-a", Duration::ZERO)
                .is_none()
        );
    }

    #[tokio::test(flavor = "current_thread", start_paused = true)]
    async fn stopping_the_heartbeat_ends_renewals() {
        let queue = ScriptedQueue::failing_with(DomainError::service_unavailable("x"));
        let heartbeat = LeaseHeartbeat::start(
            Arc::clone(&queue),
            AiImportJobId::new(),
            "worker-a",
            TEST_LEASE,
        )
        .expect("a non-zero lease starts a heartbeat");

        await_renewals(&queue, 1).await;
        heartbeat.stop();

        // No renewal may race a terminal write after stop().
        advance_expecting_no_renewal(&queue, 3).await;
    }

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

    // --- apply-run lease (issue #911) -----------------------------------

    /// One apply-slot window; the renewal fires at a third of it. Read from the
    /// adapter's own accessor, never a literal, so retuning the stream's staleness
    /// window retunes the cadence and this test with it.
    fn test_apply_window() -> Duration {
        apply_run_lease_window()
    }

    /// A run that outlives the window: the motivating case is a schedule apply
    /// (a single merge loop that publishes no progress frames at all). The
    /// virtual clock is advanced by the runtime, never by sleeping (AGENTS.md
    /// §4), so the assertion is a bound on the cadence, not on wall time.
    async fn run_outliving_the_window(window: Duration) -> u8 {
        tokio::time::sleep(window * 2 + Duration::from_secs(1)).await;
        7
    }

    /// Issue #911 acceptance: a run that takes longer than the staleness window
    /// keeps renewing its slot, and the renewal never touches the run itself.
    #[tokio::test(start_paused = true)]
    async fn the_apply_lease_renews_while_the_run_executes() {
        let queue = ScriptedQueue::renewing(ApplyRunRenewal::Keep);
        let outcome = with_apply_run_lease(
            queue.as_ref(),
            AiImportJobId::new(),
            ApplyRunId::new(),
            test_apply_window(),
            run_outliving_the_window(test_apply_window()),
        )
        .await;

        assert_eq!(outcome, 7, "the run's own outcome is returned unchanged");
        // Two windows at a third of a window per renewal: six ticks fit, with
        // the exact count left to the scheduler (a tick and the run's sleep can
        // become ready in the same poll).
        assert!(
            (5..=6).contains(&queue.apply_renewals()),
            "a live run must renew once per cadence, got {}",
            queue.apply_renewals()
        );
    }

    /// Issue #911: once the slot has moved on, renewing again is pointless —
    /// but the run keeps its own outcome (a superseded run still reports what it
    /// did; only its fenced writes are refused).
    #[tokio::test(start_paused = true)]
    async fn a_lost_slot_stops_the_renewal_and_keeps_the_run() {
        let queue = ScriptedQueue::renewing(ApplyRunRenewal::Lost);
        let outcome = with_apply_run_lease(
            queue.as_ref(),
            AiImportJobId::new(),
            ApplyRunId::new(),
            test_apply_window(),
            run_outliving_the_window(test_apply_window()),
        )
        .await;

        assert_eq!(outcome, 7, "the run still reports its own outcome");
        assert_eq!(
            queue.apply_renewals(),
            1,
            "a provably lost slot is never retried"
        );
    }

    /// Issue #911: a transient database error must not abandon a still-valid
    /// claim — the window has two more intervals of headroom.
    #[tokio::test(start_paused = true)]
    async fn a_transient_apply_renewal_failure_keeps_renewing() {
        let queue = ScriptedQueue::renewing(ApplyRunRenewal::Transient);
        let outcome = with_apply_run_lease(
            queue.as_ref(),
            AiImportJobId::new(),
            ApplyRunId::new(),
            test_apply_window(),
            run_outliving_the_window(test_apply_window()),
        )
        .await;

        assert_eq!(outcome, 7);
        assert!(
            queue.apply_renewals() >= 5,
            "a transient failure must be retried on the next tick, got {} renewals",
            queue.apply_renewals()
        );
    }

    /// A zero window disables the renewal: the test-only "already dead owner"
    /// case, where renewing would be meaningless.
    #[tokio::test(start_paused = true)]
    async fn a_zero_window_wraps_the_run_without_renewing() {
        let queue = ScriptedQueue::renewing(ApplyRunRenewal::Keep);
        let outcome = with_apply_run_lease(
            queue.as_ref(),
            AiImportJobId::new(),
            ApplyRunId::new(),
            Duration::ZERO,
            async { 7u8 },
        )
        .await;

        assert_eq!(outcome, 7);
        assert_eq!(queue.apply_renewals(), 0, "no window, no renewal");
    }

    #[test]
    fn the_apply_lease_window_is_the_apply_staleness_window() {
        // One definition, two readers: retuning the stream's window must retune
        // the renewal cadence and the steal predicate with it.
        assert_eq!(
            test_apply_window(),
            breakdown_core::ai::ApplyProgress::STALE_AFTER
                .to_std()
                .expect("the staleness window is a positive duration")
        );
        assert!(
            renewal_interval(test_apply_window()) * 2 < test_apply_window(),
            "at least two renewals must fit inside the window"
        );
    }
}
