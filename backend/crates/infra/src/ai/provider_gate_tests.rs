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
    ) -> Result<(), DomainError> {
        unreachable!("the gate tests never write")
    }

    async fn mark_held(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _hold: ProviderHold,
        _hold_window_secs: u64,
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
            ProviderOutcome::RetryableFailure => {
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

    let result: Result<(), anyhow::Error> = retry_bounded(
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
    let error = result.expect_err("the gate must refuse");
    let domain = error
        .downcast::<DomainError>()
        .expect("the sentinel is a DomainError");
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
    let result: Result<(), anyhow::Error> = retry_bounded(
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

    let result: Result<(), anyhow::Error> = retry_bounded(
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
    let error = result.expect_err("refused");
    let domain = error.downcast::<DomainError>().expect("sentinel");
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

    let _: Result<(), anyhow::Error> = retry_bounded(
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

    let _: Result<(), anyhow::Error> = retry_bounded(
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

    let _: Result<(), anyhow::Error> = retry_bounded(|| async { Ok(()) }, 2, &gate).await;
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
    assert!(!gate.record_failure().await);
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

    let result: Result<(), anyhow::Error> = retry_bounded(
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
    let domain = result
        .expect_err("refused")
        .downcast::<DomainError>()
        .expect("sentinel");
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
    let result: Result<(), anyhow::Error> = retry_bounded(
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
    let domain = result
        .expect_err("refused")
        .downcast::<DomainError>()
        .expect("sentinel");
    assert!(
        is_breaker_open(&domain),
        "the last-permitted failure must return the sentinel, not the raw error"
    );
}
