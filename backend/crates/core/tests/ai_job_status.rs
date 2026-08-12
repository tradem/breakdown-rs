// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

//! Restart-recovery classification of AI import job statuses (issue #181).
//!
//! Two consumers depend on these predicates and would silently do the wrong
//! thing if they drifted:
//!
//! * payload GC keys retention off `is_terminal`, so classifying the
//!   *retryable* `Failed` state as terminal would delete the source document
//!   of a job that is still scheduled to run;
//! * the workers key the non-resumable transition off `PayloadUnavailable`,
//!   which must stay distinct from `DeadLetter` so an operator can tell "the
//!   work failed" from "we lost the input".

#![allow(
    // A violated contract must abort the test rather than be threaded
    // through a Result.
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic
)]

use std::future::Future;
use std::pin::pin;
use std::sync::Mutex;
use std::task::{Context, Poll, Waker};

use async_trait::async_trait;
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId, AiImportQueue,
    DocumentKind, JobStatus, Telemetry,
};
use breakdown_core::error::DomainError;

/// Drive a future to completion on the current thread.
///
/// `core` must not depend on `tokio` (architecture rule, ADR-017 — the
/// `FORBIDDEN_CORE_DEPS` list), so `#[tokio::test]` is unavailable here. The
/// futures under test never yield: they are `async fn`s over in-memory state
/// with no IO, so a single poll always completes them and no reactor is
/// needed. The loop is a guard, not a spin-wait.
fn block_on<F: Future>(future: F) -> F::Output {
    let mut future = pin!(future);
    let mut context = Context::from_waker(Waker::noop());
    loop {
        if let Poll::Ready(output) = future.as_mut().poll(&mut context) {
            return output;
        }
    }
}

/// Every status the operational lifecycle knows. Kept explicit (rather than
/// derived) so adding a variant forces a decision about its classification
/// here instead of silently inheriting a default.
const ALL: [JobStatus; 6] = [
    JobStatus::Pending,
    JobStatus::Running,
    JobStatus::Succeeded,
    JobStatus::Failed,
    JobStatus::DeadLetter,
    JobStatus::PayloadUnavailable,
];

#[test]
fn status_strings_are_stable_and_unique() {
    // The strings are a persistence contract: they are stored in
    // `ai_import.ai_import_job.status` and constrained by a CHECK.
    assert_eq!(JobStatus::Pending.as_str(), "pending");
    assert_eq!(JobStatus::Running.as_str(), "running");
    assert_eq!(JobStatus::Succeeded.as_str(), "succeeded");
    assert_eq!(JobStatus::Failed.as_str(), "failed");
    assert_eq!(JobStatus::DeadLetter.as_str(), "dead_letter");
    assert_eq!(
        JobStatus::PayloadUnavailable.as_str(),
        "payload_unavailable"
    );

    let mut seen: Vec<&str> = ALL.iter().map(|status| status.as_str()).collect();
    seen.sort_unstable();
    let count = seen.len();
    seen.dedup();
    assert_eq!(seen.len(), count, "status strings must be unique");
}

#[test]
fn serde_representation_matches_as_str() {
    // The wire form (OpenAPI / job status endpoint) and the persisted form
    // must not diverge.
    for status in ALL {
        let json = serde_json::to_string(&status).unwrap();
        assert_eq!(json, format!("\"{}\"", status.as_str()));
        let back: JobStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(back, status);
    }
}

#[test]
fn failed_is_not_terminal_because_it_is_the_retry_state() {
    // The regression this guards: payload GC swept `failed` rows, deleting
    // the source document of jobs that were still within their retry budget.
    assert!(!JobStatus::Failed.is_terminal());
    assert!(!JobStatus::Pending.is_terminal());
    assert!(!JobStatus::Running.is_terminal());
}

#[test]
fn terminal_statuses_are_exactly_the_unclaimable_ones() {
    assert!(JobStatus::Succeeded.is_terminal());
    assert!(JobStatus::DeadLetter.is_terminal());
    assert!(JobStatus::PayloadUnavailable.is_terminal());

    let terminal: Vec<JobStatus> = ALL
        .into_iter()
        .filter(|status| status.is_terminal())
        .collect();
    assert_eq!(
        terminal,
        vec![
            JobStatus::Succeeded,
            JobStatus::DeadLetter,
            JobStatus::PayloadUnavailable
        ]
    );
}

#[test]
fn only_payload_unavailable_is_non_resumable() {
    // `DeadLetter` exhausted its retries against a real failure and could in
    // principle be re-driven by an operator; `PayloadUnavailable` cannot,
    // because there is no input left to re-drive it with.
    for status in ALL {
        assert_eq!(
            status.is_non_resumable(),
            status == JobStatus::PayloadUnavailable,
            "{status:?} classified incorrectly"
        );
    }
}

#[test]
fn non_resumable_implies_terminal() {
    for status in ALL.into_iter().filter(|s| s.is_non_resumable()) {
        assert!(
            status.is_terminal(),
            "{status:?} is non-resumable but not terminal, so a claim \
             predicate could still pick it up"
        );
    }
}

// ---------------------------------------------------------------------------
// The defaulted `mark_payload_unavailable` port method
// ---------------------------------------------------------------------------

/// Terminal write observed on a queue.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Write {
    Failed { summary: String, retryable: bool },
}

/// Minimal queue that implements only the required methods, so the default
/// body of `mark_payload_unavailable` is the one under test.
///
/// `Mutex` (not `RefCell`) because `AiImportQueue` requires `Send + Sync`;
/// there is no contention here — the test is single-threaded (see
/// [`block_on`]).
#[derive(Default)]
struct DefaultingQueue {
    writes: Mutex<Vec<Write>>,
}

#[async_trait]
impl AiImportQueue for DefaultingQueue {
    async fn enqueue(
        &self,
        request: AiImportEnqueueRequest,
    ) -> Result<AiImportEnqueueResult, DomainError> {
        Ok(AiImportEnqueueResult::Enqueued(request.id))
    }

    async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn claim_next_kind(
        &self,
        _worker_id: &str,
        _kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn get(&self, _id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn mark_running(&self, _id: AiImportJobId, _worker_id: &str) -> Result<(), DomainError> {
        Ok(())
    }

    async fn mark_succeeded(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _preview_handle: &str,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    async fn mark_failed(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        error_summary: &str,
        retryable: bool,
    ) -> Result<(), DomainError> {
        self.writes.lock().unwrap().push(Write::Failed {
            summary: error_summary.to_owned(),
            retryable,
        });
        Ok(())
    }

    async fn record_worker_telemetry(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    async fn record_telemetry(
        &self,
        _id: AiImportJobId,
        _telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        Ok(())
    }
}

/// A queue whose `mark_failed` fails, to prove the default body propagates
/// rather than swallowing.
#[derive(Default)]
struct FailingQueue;

#[async_trait]
impl AiImportQueue for FailingQueue {
    async fn enqueue(
        &self,
        request: AiImportEnqueueRequest,
    ) -> Result<AiImportEnqueueResult, DomainError> {
        Ok(AiImportEnqueueResult::Enqueued(request.id))
    }

    async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn claim_next_kind(
        &self,
        _worker_id: &str,
        _kind: DocumentKind,
    ) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn get(&self, _id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
        Ok(None)
    }

    async fn mark_running(&self, _id: AiImportJobId, _worker_id: &str) -> Result<(), DomainError> {
        Ok(())
    }

    async fn mark_succeeded(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _preview_handle: &str,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    async fn mark_failed(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        _error_summary: &str,
        _retryable: bool,
    ) -> Result<(), DomainError> {
        Err(DomainError::conflict(format!(
            "worker {worker_id} no longer owns job {}",
            id.as_uuid()
        )))
    }

    async fn record_worker_telemetry(
        &self,
        _id: AiImportJobId,
        _worker_id: &str,
        _telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        Ok(())
    }

    async fn record_telemetry(
        &self,
        _id: AiImportJobId,
        _telemetry: Telemetry,
    ) -> Result<(), DomainError> {
        Ok(())
    }
}

#[test]
fn default_mark_payload_unavailable_records_a_non_retryable_failure() {
    // Backends without the distinct status (in-memory and test queues) must
    // still terminate the job. A default that quietly succeeded without
    // writing anything would leave the job `running` until its lease lapsed,
    // then hand it to another worker to rediscover the same missing payload.
    let queue = DefaultingQueue::default();
    let id = AiImportJobId::new();

    block_on(queue.mark_payload_unavailable(id, "worker-a", "source document is gone")).unwrap();

    assert_eq!(
        queue.writes.into_inner().unwrap(),
        vec![Write::Failed {
            summary: "source document is gone".to_owned(),
            // Retryable would burn the whole budget rediscovering the same
            // absence — the exact regression this method exists to prevent.
            retryable: false,
        }]
    );
}

#[test]
fn default_mark_payload_unavailable_propagates_the_fence_error() {
    // The write is owner-fenced. A default that swallowed the `Conflict`
    // would let a displaced worker believe it had terminated a job that the
    // new owner is still running.
    let queue = FailingQueue;
    let result = block_on(queue.mark_payload_unavailable(
        AiImportJobId::new(),
        "stale-worker",
        "source document is gone",
    ));

    assert!(
        matches!(result, Err(DomainError::Conflict { .. })),
        "expected the fence error to propagate, got {result:?}"
    );
}
