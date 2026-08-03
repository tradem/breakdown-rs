// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
//! Deterministic unit tests for the photo saga transient-failure retry
//! (issue #165): `retry_transient` retries `ServiceUnavailable` with backoff
//! and propagates permanent errors immediately, so a Vault outage never
//! permanently drops saga work.

use std::sync::atomic::{AtomicUsize, Ordering};

use breakdown_core::error::DomainError;
use infra::photo::sagas::{is_transient, retry_transient};

#[tokio::test]
async fn transient_service_unavailable_is_retried_until_success() {
    let attempts = AtomicUsize::new(0);
    let result = retry_transient(|| {
        let attempts = &attempts;
        async move {
            if attempts.fetch_add(1, Ordering::SeqCst) < 1 {
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
    assert_eq!(attempts.load(Ordering::SeqCst), 2);
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
