// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    unsafe_code // test-only env seeding (std::env::set_var is unsafe in edition 2024)
)]
//! Deterministic unit tests for the recoverable photo storage adapter
//! (issue #165): the SSE-C key is resolved lazily and re-resolved on demand,
//! so a Vault outage at boot does not permanently disable photo storage.

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use breakdown_core::error::DomainError;
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::shared::{PhotoId, PhotoVariant};
use infra::photo::storage::{OpenDalPhotoStorage, PhotoStorageKeySource};
use tokio::sync::Mutex;
use zeroize::Zeroizing;

/// Serializes tests that mutate the process-global `S3_*` env vars.
static ENV_LOCK: Mutex<()> = Mutex::const_new(());

/// Fake key source: fails with `ServiceUnavailable` for the first `failures`
/// calls, then returns a fixed 32-byte SSE-C key.
#[derive(Debug)]
struct FlakyKeySource {
    failures: usize,
    calls: AtomicUsize,
}

#[async_trait::async_trait]
impl PhotoStorageKeySource for FlakyKeySource {
    async fn resolve(&self) -> Result<Zeroizing<Vec<u8>>, DomainError> {
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        if call < self.failures {
            Err(DomainError::service_unavailable("vault down"))
        } else {
            Ok(Zeroizing::new(vec![0x42; 32]))
        }
    }
}

#[tokio::test]
async fn storage_recovers_after_key_source_becomes_available() {
    let _guard = ENV_LOCK.lock().await;
    // SAFETY: process-global env is only touched inside this test, and
    // ENV_LOCK serializes it against the other env-mutating test.
    unsafe {
        std::env::set_var("S3_ENDPOINT", "http://127.0.0.1:9");
        std::env::set_var("S3_ACCESS_KEY", "test-key");
        std::env::set_var("S3_SECRET_KEY", "test-secret");
        std::env::set_var("S3_BUCKET", "test-bucket");
    }

    let key_source = Arc::new(FlakyKeySource {
        failures: 2,
        calls: AtomicUsize::new(0),
    });
    let storage = OpenDalPhotoStorage::recoverable(key_source.clone());
    let id = PhotoId::new();

    // Fail closed (503) while the key source is unavailable. The operator is
    // never constructed, so no storage op succeeds (an operator would fail at
    // the S3 network layer with a non-ServiceUnavailable error instead).
    let err = storage
        .store(
            id,
            PhotoVariant::Original,
            b"x".to_vec(),
            "image/jpeg".into(),
        )
        .await
        .unwrap_err();
    assert!(matches!(err, DomainError::ServiceUnavailable { .. }));

    let err = storage
        .store(
            id,
            PhotoVariant::Original,
            b"x".to_vec(),
            "image/jpeg".into(),
        )
        .await
        .unwrap_err();
    assert!(matches!(err, DomainError::ServiceUnavailable { .. }));

    // The key source recovers: the SSE-C operator is now built (S3 connects
    // lazily, so the build itself succeeds) and cached. The op now fails at
    // the network layer (unroutable endpoint), which OpenDAL flags as a
    // temporary error — the error message proves the storage op ran instead
    // of failing at key resolution ("vault down").
    let err = storage
        .store(
            id,
            PhotoVariant::Original,
            b"x".to_vec(),
            "image/jpeg".into(),
        )
        .await
        .unwrap_err();
    assert!(
        err.to_string().contains("Temporary storage failure for "),
        "storage op must reach the S3 network layer after key recovery, got: {err}"
    );

    // The cached operator is reused: a further op does not trigger another
    // key resolution (exactly 2 failed + 1 successful resolution happened).
    let _ = storage
        .store(
            id,
            PhotoVariant::Original,
            b"x".to_vec(),
            "image/jpeg".into(),
        )
        .await;
    assert_eq!(key_source.calls.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn unavailable_storage_fails_closed_without_key_source() {
    let storage = OpenDalPhotoStorage::unavailable("vault unreachable");
    let err = storage
        .store(
            PhotoId::new(),
            PhotoVariant::Original,
            b"x".to_vec(),
            "image/jpeg".into(),
        )
        .await
        .unwrap_err();
    assert!(matches!(err, DomainError::ServiceUnavailable { .. }));
}
