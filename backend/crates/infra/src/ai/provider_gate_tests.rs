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
}

impl BreakerQueue {
    fn new(state: ProviderBreakerState) -> Arc<Self> {
        Arc::new(Self {
            state: std::sync::Mutex::new(state),
            fail_reads: false,
        })
    }

    fn unreadable() -> Self {
        Self {
            state: std::sync::Mutex::new(ProviderBreakerState::Closed),
            fail_reads: true,
        }
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
    };
    assert!(
        gate.admits().await,
        "an unreadable breaker must admit, or one database hiccup stops every import"
    );
    // And the sentinel stays a distinct shape.
    assert!(is_breaker_open(&breaker_open_error()));
}
