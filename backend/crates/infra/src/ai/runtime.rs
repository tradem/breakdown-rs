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

use super::pg_concurrency::PgAiConcurrencyLimiter;
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
        let result = operation().await;
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
