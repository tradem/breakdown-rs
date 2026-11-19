// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Call-count tests for the provider breaker gate (issue #871, task 2.11).
//!
//! The design's promise is a **count**, not a duration: an open breaker costs
//! *zero* paid calls, and the check runs before every attempt (the first
//! included) and again before every backoff sleep. Wall clock is paused
//! (`tokio::test(start_paused = true)`), so the backoff in the "opens during the
//! loop" case completes instantly and no assertion depends on real time
//! (AGENTS.md §4, D-X4).

#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use async_trait::async_trait;
use breakdown_core::ai::ports::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportQueue, ProviderBreakerSnapshot,
};
use breakdown_core::ai::views::{ProviderBreakerState, ProviderHold};
use breakdown_core::ai::{AiImportJob, AiImportJobId, DocumentKind, LlmProvider, Telemetry};
use breakdown_core::error::DomainError;

use super::{ProviderGate, retry_bounded};
use crate::ai::provider_health::{breaker_open_error, is_breaker_open};
use crate::ai::workers::CallFailure;

/// A queue whose only job is to report a breaker verdict — the six required
/// trait methods are unreachable stubs, because these tests never claim.
struct BreakerQueue {
    state: std::sync::Mutex<ProviderBreakerState>,
    /// When set, `provider_breaker` fails — the "database hiccup" case.
    fail_reads: bool,
    /// Outcomes the gate recorded, in order (issue #871 review: the write side
    /// must be observable, or "the breaker can open" is untested).
    recorded: std::sync::Mutex<Vec<(&'static str, bool)>>,
    /// The fake's consecutive-failure counter, kept ONCE and returned in the
    /// decision. Recounting the `recorded` log instead (an earlier draft) made the
    /// decision disagree with the state, and taking the `recorded` lock while
    /// holding the `state` lock introduced a lock-ordering hazard for no reason.
    failures: std::sync::atomic::AtomicU32,
    /// How many failures it takes to open (the fake's own threshold).
    opens_after: u32,
}

impl BreakerQueue {
    fn new(state: ProviderBreakerState) -> Arc<Self> {
        Arc::new(Self {
            state: std::sync::Mutex::new(state),
            fail_reads: false,
            recorded: std::sync::Mutex::new(Vec::new()),
            failures: std::sync::atomic::AtomicU32::new(0),
            opens_after: u32::MAX,
        })
    }

    fn unreadable() -> Self {
        Self {
            state: std::sync::Mutex::new(ProviderBreakerState::Closed),
            fail_reads: true,
            recorded: std::sync::Mutex::new(Vec::new()),
            failures: std::sync::atomic::AtomicU32::new(0),
            opens_after: u32::MAX,
        }
    }

    fn recorded(&self) -> Vec<(&'static str, bool)> {
        self.recorded.lock().unwrap().clone()
    }

    fn set(&self, state: ProviderBreakerState) {
        *self.state.lock().unwrap() = state;
    }
}

#[async_trait]
impl AiImportQueue for BreakerQueue {
    async fn enqueue(
        &self,
        _request: AiImportEnqueueRequest,
    ) -> Result<AiImportEnqueueResult, DomainError> {
        unreachable!("the gate tests never enqueue")
    }

    async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
        unreachable!("the gate tests never claim")
    }

    async fn claim_next_kind(
        &self,
        _worker_id: &str,
        _kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError> {
        unreachable!("the gate tests never claim")
    }

    async fn get(&self, _id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
        unreachable!("the gate tests never read")
    }

    async fn mark_running(&self, _id: AiImportJobId, _worker_id: &str) -> Result<(), DomainError> {
        unreachable!("the gate tests never write")
    }

    async fn mark_succeeded(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _preview_handle: &str,
    ) -> Result<(), DomainError> {
        unreachable!("the gate tests never write")
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
        unreachable!("the gate tests never write")
    }

    async fn mark_held(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _hold: ProviderHold,
        _hold_window_secs: u64,
        _evidence: Option<&breakdown_core::ai::HoldEvidence>,
    ) -> Result<(), DomainError> {
        unreachable!("the gate tests never write")
    }

    async fn record_worker_telemetry(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        unreachable!("the gate tests never record telemetry")
    }

    async fn record_telemetry(
        &self,
        _id: AiImportJobId,
        _telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        unreachable!("the gate tests never record telemetry")
    }

    async fn record_provider_outcome(
        &self,
        _provider: LlmProvider,
        _model: &str,
        outcome: breakdown_core::ai::ProviderOutcome,
        _threshold: u32,
    ) -> Result<breakdown_core::ai::BreakerDecision, DomainError> {
        use breakdown_core::ai::{BreakerDecision, ProviderOutcome};
        use std::sync::atomic::Ordering;
        // One counter, incremented on a retryable failure and reset on a success,
        // and no lock is ever held while another is acquired.
        let consecutive_failures = match outcome {
            ProviderOutcome::RetryableFailure { retry_after: _ } => {
                let failures = self.failures.fetch_add(1, Ordering::SeqCst) + 1;
                self.recorded.lock().unwrap().push(("failure", true));
                if failures >= self.opens_after {
                    *self.state.lock().unwrap() = ProviderBreakerState::Open;
                }
                failures
            }
            ProviderOutcome::Success => {
                self.failures.store(0, Ordering::SeqCst);
                self.recorded.lock().unwrap().push(("success", false));
                *self.state.lock().unwrap() = ProviderBreakerState::Closed;
                0
            }
            // A permanent failure is not reported to the counter at all (D-A1),
            // so it leaves both the counter and the state untouched.
            ProviderOutcome::PermanentFailure => self.failures.load(Ordering::SeqCst),
        };
        let state = *self.state.lock().unwrap();
        Ok(BreakerDecision {
            state,
            consecutive_failures,
            flap_count: 0,
            retry_at: None,
            opened: matches!(state, ProviderBreakerState::Open),
            closed: matches!(state, ProviderBreakerState::Closed),
        })
    }

    /// The one method under test.
    async fn provider_breaker(
        &self,
        _provider: LlmProvider,
        _model: &str,
    ) -> Result<ProviderBreakerSnapshot, DomainError> {
        if self.fail_reads {
            return Err(DomainError::service_unavailable("database pool timed out"));
        }
        Ok(ProviderBreakerSnapshot {
            state: *self.state.lock().unwrap(),
            consecutive_failures: 3,
            flap_count: 0,
            retry_at: None,
        })
    }
}

fn transient() -> anyhow::Error {
    anyhow::Error::new(DomainError::llm_provider_unavailable("HTTP 503"))
}

#[tokio::test(start_paused = true)]
async fn an_open_breaker_costs_zero_calls() {
    let queue = BreakerQueue::new(ProviderBreakerState::Open);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 3,
        enabled: true,
    };
    let calls = AtomicUsize::new(0);

    let result: Result<(), CallFailure> = retry_bounded(
        || async {
            calls.fetch_add(1, Ordering::SeqCst);
            Ok(())
        },
        5,
        &gate,
    )
    .await;

    assert_eq!(
        calls.load(Ordering::SeqCst),
        0,
        "an open breaker must cost ZERO paid calls, including the first attempt"
    );
    let failure = result.expect_err("the gate must refuse");
    let domain = failure.error;
    assert!(
        is_breaker_open(&domain),
        "the refusal must be the breaker sentinel, not a retryable failure"
    );
}

#[tokio::test(start_paused = true)]
async fn a_half_open_breaker_also_costs_zero_calls() {
    // `half_open` admits no claim either (D-A2), and the gate derives from the
    // same predicate — one semantics, two call sites.
    let queue = BreakerQueue::new(ProviderBreakerState::HalfOpen);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 3,
        enabled: true,
    };
    let calls = AtomicUsize::new(0);

    let _ = retry_bounded(
        || async {
            calls.fetch_add(1, Ordering::SeqCst);
            Ok(())
        },
        5,
        &gate,
    )
    .await;

    assert_eq!(calls.load(Ordering::SeqCst), 0);
}

#[tokio::test(start_paused = true)]
async fn a_closed_breaker_does_not_interfere_with_the_retry_loop() {
    let queue = BreakerQueue::new(ProviderBreakerState::Closed);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 3,
        enabled: true,
    };
    let calls = AtomicUsize::new(0);

    // A transient failure that succeeds on the third attempt: the ordinary path
    // must still be able to use its whole budget.
    let result: Result<(), CallFailure> = retry_bounded(
        || async {
            let attempt = calls.fetch_add(1, Ordering::SeqCst) + 1;
            if attempt < 3 {
                Err(transient())
            } else {
                Ok(())
            }
        },
        2,
        &gate,
    )
    .await;

    assert!(
        result.is_ok(),
        "a closed breaker must not block the retries"
    );
    assert_eq!(calls.load(Ordering::SeqCst), 3, "1 + max_retries attempts");
}

/// Issue #942 W2: a breaker refusal must hand the hold site the failure that
/// fired it — a bare sentinel left the operator with `ai-import.llm-provider-
/// unavailable` and no way to tell a client timeout from an HTTP status from a
/// bounded provider body.
#[tokio::test(start_paused = true)]
async fn a_breaker_refusal_carries_the_failure_that_fired_it() {
    let queue = BreakerQueue::new(ProviderBreakerState::Closed);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::EURouter,
        model: "mistral-large-3",
        threshold: 1,
        enabled: true,
    };
    let calls = AtomicUsize::new(0);

    let failure: CallFailure = retry_bounded(
        || async {
            calls.fetch_add(1, Ordering::SeqCst);
            // The "third failure opens it" case, folded into one call: the fake
            // queue does not count, so the transition is driven directly —
            // exactly the shape the real `record_failure` produces when the
            // threshold is reached.
            queue.set(ProviderBreakerState::Open);
            Err::<(), anyhow::Error>(anyhow::Error::new(DomainError::llm_provider_unavailable(
                "LLM provider transport unavailable: operation timed out after 120s",
            )))
        },
        2,
        &gate,
    )
    .await
    .expect_err("the open breaker refuses");

    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "one call, then the sentinel"
    );
    assert!(
        is_breaker_open(&failure.error),
        "the caller still sees the sentinel it branches on"
    );
    let evidence = failure
        .evidence
        .expect("a hold must never be parked without its reason (issue #942 W2)");
    assert!(
        evidence.summary.contains("timed out after 120s"),
        "the persisted narrative must name the CLIENT timeout: {}",
        evidence.summary
    );
    assert_eq!(
        evidence.code.as_deref(),
        Some("ai-import.llm-provider-unavailable"),
        "the attempt row's code is the registered provider code"
    );
}

/// The complement: a failure the loop does NOT convert into a hold (the real
/// error is returned to `mark_failed`) carries no hold evidence, so the failure
/// path stays exactly as it was.
#[tokio::test(start_paused = true)]
async fn an_exhausted_retry_budget_returns_no_hold_evidence() {
    let queue = BreakerQueue::new(ProviderBreakerState::Closed);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenAI,
        model: "m",
        // High enough that the counter never opens within the budget.
        threshold: 10,
        enabled: true,
    };

    let failure: CallFailure =
        retry_bounded(|| async { Err::<(), anyhow::Error>(transient()) }, 0, &gate)
            .await
            .expect_err("the budget is spent");

    assert!(!is_breaker_open(&failure.error));
    assert!(
        failure.evidence.is_none(),
        "no hold follows this failure, so nothing may be persisted as a hold reason"
    );
}

/// Issue #942 W2: the summary is BOUNDED before it leaves the worker. The
/// classifier already caps the provider detail, so this guards the other layer:
/// no call site may persist an unbounded body.
#[test]
fn the_hold_evidence_is_bounded() {
    let huge = anyhow::Error::new(DomainError::validation("x".repeat(50_000)));
    let evidence = super::hold_evidence(&huge);
    assert_eq!(
        evidence.summary.chars().count(),
        super::MAX_HOLD_SUMMARY_CHARS
    );
    assert_eq!(evidence.code.as_deref(), Some("domain.validation"));
}

#[tokio::test(start_paused = true)]
async fn a_breaker_that_opens_during_the_backoff_stops_before_the_next_call() {
    // The property the pre-sleep re-check exists for: another worker can open the
    // breaker while this loop is sleeping, and the loop must then NOT call again.
    let queue = BreakerQueue::new(ProviderBreakerState::Closed);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 3,
        enabled: true,
    };
    let calls = AtomicUsize::new(0);

    let result: Result<(), CallFailure> = retry_bounded(
        || async {
            calls.fetch_add(1, Ordering::SeqCst);
            // The "other worker" opens the breaker after this failure.
            queue.set(ProviderBreakerState::Open);
            Err(transient())
        },
        5,
        &gate,
    )
    .await;

    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "the loop must re-check after the backoff and stop, not call into a dead endpoint"
    );
    let failure = result.expect_err("refused");
    let domain = failure.error;
    assert!(is_breaker_open(&domain));
    // Keep the sentinel helper honest: the refusal is not a retryable shape,
    // which is the bug the breaker removes.
    assert!(!matches!(domain, DomainError::ServiceUnavailable { .. }));
}

#[tokio::test(start_paused = true)]
async fn a_failing_breaker_read_admits() {
    // Fail open: the consult only ever SAVES money, so a database hiccup must
    // not stop the pipeline.
    let queue = BreakerQueue::unreadable();
    let gate = ProviderGate {
        queue: &queue,
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 3,
        enabled: true,
    };
    assert!(
        gate.admits().await,
        "an unreadable breaker must admit, or one database hiccup stops every import"
    );
    // And the sentinel stays a distinct shape.
    assert!(is_breaker_open(&breaker_open_error()));
}

// ---------------------------------------------------------------------------
// Issue #871 review: the breaker's WRITE side. Without these, "the breaker can
// open from real traffic" was an untested claim.
// ---------------------------------------------------------------------------

fn provider_failure() -> anyhow::Error {
    anyhow::Error::new(DomainError::llm_provider_unavailable("HTTP 503"))
}

#[tokio::test(start_paused = true)]
async fn the_last_failure_of_a_chunk_is_recorded_too() {
    // The regression CodeRabbit caught: recording only inside the retry arm made
    // the FINAL failure invisible, so a deployment with `max_attempt_retries = 0`
    // never incremented the counter and the breaker could never open.
    let queue = BreakerQueue::new(ProviderBreakerState::Closed);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 99, // never opens, so every failure must still be recorded
        enabled: true,
    };
    let calls = AtomicUsize::new(0);

    let _: Result<(), CallFailure> = retry_bounded(
        || async {
            calls.fetch_add(1, Ordering::SeqCst);
            Err(provider_failure())
        },
        0, // no in-attempt retries: exactly ONE attempt, which must be counted
        &gate,
    )
    .await;

    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert_eq!(
        queue.recorded(),
        vec![("failure", true)],
        "the single (and last) failure must reach the breaker counter"
    );
}

#[tokio::test(start_paused = true)]
async fn a_generic_service_outage_never_moves_the_counter() {
    // `is_transient` also matches the mapping DB, payload storage and the pricing
    // read model. Only the provider's own code may move the counter (D-A1).
    let queue = BreakerQueue::new(ProviderBreakerState::Closed);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 1,
        enabled: true,
    };

    let _: Result<(), CallFailure> = retry_bounded(
        || async {
            Err::<(), anyhow::Error>(anyhow::Error::new(DomainError::service_unavailable(
                "mapping DB",
            )))
        },
        2,
        &gate,
    )
    .await;

    assert!(
        queue.recorded().is_empty(),
        "a storage outage must not open a breaker for a healthy provider"
    );
    assert_eq!(
        queue.state.lock().unwrap().clone(),
        ProviderBreakerState::Closed
    );
}

#[tokio::test(start_paused = true)]
async fn a_successful_call_is_recorded_as_success() {
    let queue = BreakerQueue::new(ProviderBreakerState::Closed);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 3,
        enabled: true,
    };

    let _: Result<(), CallFailure> = retry_bounded(|| async { Ok(()) }, 2, &gate).await;
    assert_eq!(queue.recorded(), vec![("success", false)]);
    assert_eq!(
        queue.failures.load(Ordering::SeqCst),
        0,
        "a success resets the counter, so the next failure starts from zero"
    );
}

#[tokio::test(start_paused = true)]
async fn the_kill_switch_records_nothing() {
    // `AI_IMPORT_BREAKER_ENABLED=false`: no verdict, no counter, no hold.
    let queue = BreakerQueue::new(ProviderBreakerState::Open);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 1,
        enabled: false,
    };

    // Admits despite the open state, and records nothing at all.
    assert!(gate.admits().await);
    assert!(!gate.record_failure(None).await);
    gate.record_success().await;
    assert!(queue.recorded().is_empty());
}

#[tokio::test(start_paused = true)]
async fn a_failure_that_opens_the_breaker_stops_the_loop_at_once() {
    // The branch the retry loop relies on: opening on THIS failure must return the
    // sentinel immediately instead of sleeping and calling again.
    let queue = Arc::new(BreakerQueue {
        state: std::sync::Mutex::new(ProviderBreakerState::Closed),
        fail_reads: false,
        recorded: std::sync::Mutex::new(Vec::new()),
        failures: std::sync::atomic::AtomicU32::new(0),
        opens_after: 1,
    });
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 1,
        enabled: true,
    };
    let calls = AtomicUsize::new(0);

    let result: Result<(), CallFailure> = retry_bounded(
        || async {
            calls.fetch_add(1, Ordering::SeqCst);
            Err(provider_failure())
        },
        5,
        &gate,
    )
    .await;

    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "no second call after the open"
    );
    let domain = result.expect_err("refused").error;
    assert!(is_breaker_open(&domain));
}

#[tokio::test(start_paused = true)]
async fn a_failure_that_opens_on_the_last_permitted_attempt_holds_the_job() {
    // The case CodeRabbit asked for explicitly: the budget is spent AND this very
    // failure opens the breaker. The sentinel must come back, so the worker takes
    // the held path instead of `mark_failed` — otherwise a job is charged a retry
    // for a call the breaker just proved pointless.
    let queue = Arc::new(BreakerQueue {
        state: std::sync::Mutex::new(ProviderBreakerState::Closed),
        fail_reads: false,
        recorded: std::sync::Mutex::new(Vec::new()),
        failures: std::sync::atomic::AtomicU32::new(0),
        opens_after: 2, // the SECOND failure opens it
    });
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 2,
        enabled: true,
    };
    let calls = AtomicUsize::new(0);

    // max_retries = 1 ⇒ two attempts: the second is both the last permitted one
    // and the one that opens the breaker.
    let result: Result<(), CallFailure> = retry_bounded(
        || async {
            calls.fetch_add(1, Ordering::SeqCst);
            Err(provider_failure())
        },
        1,
        &gate,
    )
    .await;

    assert_eq!(
        calls.load(Ordering::SeqCst),
        2,
        "both permitted attempts ran"
    );
    assert_eq!(
        queue.recorded().len(),
        2,
        "both failures reached the counter — N of N+1 was the bug"
    );
    let domain = result.expect_err("refused").error;
    assert!(
        is_breaker_open(&domain),
        "the last-permitted failure must return the sentinel, not the raw error"
    );
}

// ---------------------------------------------------------------------------
// Hint-aware in-attempt backoff (issue #926)
// ---------------------------------------------------------------------------

/// A retryable provider failure that carries the wait the provider asked for.
fn rate_limited(wait: std::time::Duration) -> anyhow::Error {
    anyhow::Error::new(DomainError::llm_provider_unavailable_with_hint(
        format!(
            "LLM provider returned HTTP 429 and asked to wait {}s",
            wait.as_secs()
        ),
        Some(wait),
    ))
}

/// Run `retry_bounded` on a paused clock and report the **virtual** time it
/// spent sleeping plus the number of calls it made.
///
/// A paused tokio clock auto-advances while every task is idle, so the elapsed
/// `Instant` is exactly the sum of the sleeps — no wall-clock budget, no
/// tolerance window (AGENTS.md §4).
async fn retry_cost<F>(make_error: F, max_retries: usize) -> (std::time::Duration, usize)
where
    F: Fn() -> anyhow::Error,
{
    let queue = BreakerQueue::new(ProviderBreakerState::Closed);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenCodeGo,
        model: "m",
        threshold: 3,
        enabled: true,
    };
    let calls = std::sync::atomic::AtomicUsize::new(0);
    let started = tokio::time::Instant::now();
    let _: Result<(), CallFailure> = retry_bounded(
        || async {
            calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            Err(make_error())
        },
        max_retries,
        &gate,
    )
    .await;
    (
        started.elapsed(),
        calls.load(std::sync::atomic::Ordering::SeqCst),
    )
}

#[tokio::test(start_paused = true)]
async fn a_provider_hint_above_the_computed_backoff_is_waited_out() {
    // The pre-#926 behaviour retried after the ~1 s the equal-jitter formula
    // yields for attempt 1, ignoring the 5 s the provider asked for.
    let (elapsed, calls) = retry_cost(|| rate_limited(std::time::Duration::from_secs(5)), 1).await;
    assert_eq!(calls, 2, "exactly one retry");
    assert_eq!(
        elapsed,
        std::time::Duration::from_secs(5),
        "the virtual clock must advance by the hint, not by the guessed backoff"
    );
}

#[tokio::test(start_paused = true)]
async fn a_provider_hint_below_the_computed_backoff_does_not_shorten_it() {
    // Attempt 1 of `EqualJitter { 500 ms, 30 s }` is 1000 ms + up to 250 ms of
    // jitter, so the window is analytic even though the jitter is random.
    let (elapsed, calls) =
        retry_cost(|| rate_limited(std::time::Duration::from_millis(1)), 1).await;
    assert_eq!(calls, 2);
    assert!(
        elapsed >= std::time::Duration::from_millis(1_000),
        "the hint is a floor, never a reduction: {elapsed:?}"
    );
    assert!(
        elapsed <= std::time::Duration::from_millis(1_250),
        "the computed backoff keeps its 25 % jitter cap: {elapsed:?}"
    );
}

#[tokio::test(start_paused = true)]
async fn an_absurd_provider_hint_is_clamped_to_the_permit_bound() {
    // `Retry-After: 3600` must not hold the concurrency permit for an hour. The
    // clamp is `core::ai::MAX_IN_ATTEMPT_HINT_SECS`, which is the number
    // `attempt_worst_case_secs` multiplies — this test is what keeps the
    // documented 22/28 min honest.
    let (elapsed, calls) =
        retry_cost(|| rate_limited(std::time::Duration::from_secs(3_600)), 1).await;
    assert_eq!(calls, 2);
    assert_eq!(
        elapsed,
        std::time::Duration::from_secs(breakdown_core::ai::MAX_IN_ATTEMPT_HINT_SECS),
        "a hint beyond the clamp waits the clamp and no longer"
    );
}

#[tokio::test(start_paused = true)]
async fn a_hint_less_failure_keeps_the_pre_926_timing() {
    // Byte-compatibility for every non-provider and hint-less failure: the same
    // analytic window as above, with nothing added.
    let (elapsed, calls) = retry_cost(transient, 1).await;
    assert_eq!(calls, 2);
    assert!(
        (std::time::Duration::from_millis(1_000)..=std::time::Duration::from_millis(1_250))
            .contains(&elapsed)
    );
}

#[tokio::test(start_paused = true)]
async fn a_hint_does_not_create_a_retry_the_budget_forbids() {
    // Zero in-attempt retries stays zero, even when the provider asks for a wait:
    // the hint schedules the EXISTING retries, it does not add any.
    let (elapsed, calls) = retry_cost(|| rate_limited(std::time::Duration::from_secs(5)), 0).await;
    assert_eq!(calls, 1, "no retry is granted by a hint");
    assert_eq!(elapsed, std::time::Duration::ZERO, "and nothing is slept");
}

/// Issue #927: a **terminal** provider verdict costs exactly one call, opens
/// nothing and records nothing.
///
/// A quota-exhausted `429` carries the provider code, so `is_provider_failure`
/// matches it. Recording it would let three such verdicts open the breaker, and
/// the hold that follows would park a job that has nothing left to wait for
/// instead of dead-lettering it — the exact opposite of what the verdict says.
#[tokio::test(start_paused = true)]
async fn a_quota_exhausted_provider_failure_is_terminal_and_does_not_move_the_breaker() {
    let queue = BreakerQueue::new(ProviderBreakerState::Closed);
    let gate = ProviderGate {
        queue: queue.as_ref(),
        provider: LlmProvider::OpenAI,
        model: "m",
        // Would open on the first recorded failure, so an unguarded
        // `record_failure` cannot hide behind a high threshold.
        threshold: 1,
        enabled: true,
    };
    let calls = AtomicUsize::new(0);

    let error: CallFailure = retry_bounded(
        || async {
            calls.fetch_add(1, Ordering::SeqCst);
            Err::<(), anyhow::Error>(anyhow::Error::new(
                DomainError::llm_provider_quota_exhausted("HTTP 429 — insufficient_quota"),
            ))
        },
        2, // a retry budget that must NOT be spent
        &gate,
    )
    .await
    .expect_err("a quota exhaustion is a failure");

    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "a terminal verdict must not consume in-attempt retries"
    );
    assert!(
        queue.recorded().is_empty(),
        "a terminal verdict must not move the breaker counter: {:?}",
        queue.recorded()
    );
    assert_eq!(
        queue.state.lock().unwrap().clone(),
        ProviderBreakerState::Closed
    );
    // The caller receives the TERMINAL error, not `breaker_open_error()` — that
    // is what lets the worker dead-letter it with the provider narrative.
    let domain = error.error;
    assert!(!domain.is_retryable());
    assert!(matches!(
        domain,
        DomainError::LlmProviderQuotaExhausted { .. }
    ));
}
