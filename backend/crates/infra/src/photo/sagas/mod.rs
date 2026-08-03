// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.2 (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)

pub mod bytes_cleanup;
pub mod continuity_deletion;
pub mod deletion;
pub mod thumbnail;

use std::time::Duration;

use anyhow::Result;
use breakdown_core::error::DomainError;
use futures::Future;

use crate::projectors::supervisor;

pub use bytes_cleanup::{PhotoBytesCleanupSaga, spawn_photo_bytes_cleanup_saga};
pub use continuity_deletion::{ContinuityDeletionSaga, spawn_continuity_deletion_saga};
pub use deletion::{PhotoDeletionSaga, spawn_photo_deletion_saga};
pub use thumbnail::{PhotoThumbnailSaga, spawn_photo_thumbnail_saga};

/// Upper bound for a single backoff delay when retrying transient saga work.
const TRANSIENT_MAX_DELAY: Duration = Duration::from_secs(30);

/// Retry an operation while it fails with a transient
/// `DomainError::ServiceUnavailable` (e.g. Vault unavailable for the photo
/// SSE-C key).
///
/// Transient failures are retried with exponential backoff **without a hard
/// attempt budget**: the underlying SierraDB subscription is ephemeral, so
/// abandoning the event would permanently drop the saga work. The loop fails
/// closed (returning `ServiceUnavailable`) until the dependency recovers and
/// the operation succeeds. Non-transient errors propagate immediately.
pub async fn retry_transient<F, Fut>(op: F) -> Result<()>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<()>>,
{
    let mut op = op;
    let mut attempt: usize = 0;
    loop {
        match op().await {
            Ok(()) => return Ok(()),
            Err(err) if is_transient(&err) => {
                attempt += 1;
                let delay = supervisor::compute_backoff(attempt, TRANSIENT_MAX_DELAY);
                tracing::warn!(
                    attempt,
                    delay_ms = delay.as_millis(),
                    error = %err,
                    "transient storage dependency failure; retrying saga work"
                );
                tokio::time::sleep(delay).await;
            }
            Err(err) => return Err(err),
        }
    }
}

/// Whether the error chain contains a transient `DomainError::ServiceUnavailable`.
///
/// Public so external tests (and future callers) can reuse the classification
/// used by [`retry_transient`].
pub fn is_transient(err: &anyhow::Error) -> bool {
    err.downcast_ref::<DomainError>()
        .is_some_and(|e| matches!(e, DomainError::ServiceUnavailable(_)))
}
