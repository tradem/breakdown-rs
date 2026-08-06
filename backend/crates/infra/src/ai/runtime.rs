// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::future::Future;
use std::sync::Arc;

use breakdown_core::error::DomainError;

use super::pg_concurrency::PgAiConcurrencyLimiter;
use super::shutdown::AiWorkerLifecycle;

/// Runtime wrapper for a queue worker operation. It combines the PostgreSQL
/// global/per-user counter with an in-flight lifecycle guard.
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
        let Some(permit) = self.concurrency.try_acquire(user_id).await? else {
            return Ok(None);
        };
        let guard = self.lifecycle.start_job();
        let result = operation().await;
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
