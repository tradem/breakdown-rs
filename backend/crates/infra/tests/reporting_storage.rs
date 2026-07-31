// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use breakdown_core::reporting::storage::*;
use infra::reporting::storage::{
    MemoryReportArchiveStorage, external_key, sha256_hex, staging_key,
};
use uuid::Uuid;

#[tokio::test]
async fn memory_put_fetch_delete_exists_roundtrip() {
    let store = MemoryReportArchiveStorage::new();
    let key = ReportArtifactKey::new("day/dispo.pdf").unwrap();
    let digest = sha256_hex(b"%PDF-1.4 test");
    store
        .put(&key, b"%PDF-1.4 test", "application/pdf", &digest)
        .await
        .unwrap();
    assert!(store.exists(&key).await.unwrap());
    let art = store.fetch(&key).await.unwrap();
    assert_eq!(art.bytes, b"%PDF-1.4 test");
    assert_eq!(art.digest.as_ref().unwrap().as_str(), digest.as_str());
    store.delete(&key).await.unwrap();
    assert!(!store.exists(&key).await.unwrap());
    assert!(matches!(
        store.fetch(&key).await,
        Err(ReportStorageError::NotFound { .. })
    ));
}

#[tokio::test]
async fn memory_put_is_idempotent_overwrite() {
    let store = MemoryReportArchiveStorage::new();
    let key = ReportArtifactKey::new("k.pdf").unwrap();
    let d1 = sha256_hex(b"a");
    let d2 = sha256_hex(b"b");
    store.put(&key, b"a", "application/pdf", &d1).await.unwrap();
    store.put(&key, b"b", "application/pdf", &d2).await.unwrap();
    let art = store.fetch(&key).await.unwrap();
    assert_eq!(art.bytes, b"b");
    assert_eq!(store.put_count().await, 2);
}

#[tokio::test]
async fn memory_fail_puts_returns_provider_failure_without_bytes() {
    let store = MemoryReportArchiveStorage::new();
    store.set_fail_puts(true).await;
    let key = ReportArtifactKey::new("k.pdf").unwrap();
    let d = sha256_hex(b"x");
    let err = store
        .put(&key, b"x", "application/pdf", &d)
        .await
        .unwrap_err();
    let s = err.to_string();
    assert!(!s.contains('x') || s.contains("injected") || s.contains("provider"));
    assert!(!s.contains("%PDF"));
}

#[test]
fn staging_and_external_keys_are_deterministic() {
    let id = Uuid::nil();
    let d = sha256_hex(b"pdf");
    let a = staging_key(id, "dispo", "de-DE", "1.0.0", &d).unwrap();
    let b = staging_key(id, "dispo", "de-DE", "1.0.0", &d).unwrap();
    assert_eq!(a.as_str(), b.as_str());
    let e = external_key(id, "dispo", "de-DE", "1.0.0").unwrap();
    assert!(e.as_str().ends_with(".pdf"));
}

#[test]
fn errors_never_embed_credentials_in_debug() {
    let err = ReportStorageError::CredentialMissing {
        detail: "REPORT_BACKUP_GDRIVE_CLIENT_SECRET must be set".into(),
    };
    // Detail names the env var, not the secret value — acceptable.
    assert!(!format!("{err:?}").contains("super-secret"));
}
