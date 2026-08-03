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
fn is_transient(err: &anyhow::Error) -> bool {
    err.downcast_ref::<DomainError>()
        .is_some_and(|e| matches!(e, DomainError::ServiceUnavailable(_)))
}

#[cfg(test)]
mod tests {
    use super::{is_transient, retry_transient};
    use breakdown_core::error::DomainError;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[tokio::test]
    async fn transient_service_unavailable_is_retried_until_success() {
        let attempts = AtomicUsize::new(0);
        let result = retry_transient(|| {
            let attempts = &attempts;
            async move {
                if attempts.fetch_add(1, Ordering::SeqCst) < 3 {
                    Err(anyhow::Error::new(DomainError::ServiceUnavailable(
                        "vault down".into(),
                    )))
                } else {
                    Ok(())
                }
            }
        })
        .await;
        assert!(result.is_ok());
        assert_eq!(attempts.load(Ordering::SeqCst), 4);
    }

    #[tokio::test]
    async fn permanent_errors_propagate_immediately() {
        let attempts = AtomicUsize::new(0);
        let result = retry_transient(|| {
            let attempts = &attempts;
            async move {
                attempts.fetch_add(1, Ordering::SeqCst);
                Err(anyhow::anyhow!("corrupt image"))
            }
        })
        .await;
        assert!(result.is_err());
        assert_eq!(
            attempts.load(Ordering::SeqCst),
            1,
            "no retry for permanent errors"
        );
        assert!(result.unwrap_err().to_string().contains("corrupt image"));
    }

    #[test]
    fn is_transient_detects_service_unavailable_through_the_error_chain() {
        let plain: anyhow::Error = DomainError::ServiceUnavailable("down".into()).into();
        assert!(is_transient(&plain));

        // The saga wraps storage errors with context; the DomainError must
        // still be found in the chain.
        let chained = plain.context("fetching original bytes");
        assert!(is_transient(&chained));

        let validation: anyhow::Error = DomainError::ValidationError("nope".into()).into();
        assert!(!is_transient(&validation));
        assert!(!is_transient(&anyhow::anyhow!("corrupt image")));
    }
}
