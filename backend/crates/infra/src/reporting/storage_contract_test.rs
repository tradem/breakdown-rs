// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: grok-4.5 (opencode-go)
// Co-authored-by: gpt-5.6-luna (opencode-go)

//! Contract tests for `ReportArchiveStorage` semantics.
//!
//! These run against the in-memory adapter (always) and optionally against a
//! a fail-closed GDrive target when the Settings/Vault binding is unavailable.

use breakdown_core::reporting::{ReportArchiveStorage, ReportArtifactKey};

use super::storage::{MemoryReportArchiveStorage, sha256_hex};

async fn contract_upload_overwrite_fetch_delete<S: ReportArchiveStorage>(store: &S) {
    let key = ReportArtifactKey::new("contract/test-report.pdf").unwrap();
    let bytes_v1 = b"%PDF-1.4 v1".as_slice();
    let bytes_v2 = b"%PDF-1.4 v2-longer".as_slice();
    let d1 = sha256_hex(bytes_v1);
    let d2 = sha256_hex(bytes_v2);

    store
        .put(&key, bytes_v1, "application/pdf", &d1)
        .await
        .expect("put v1");
    assert!(store.exists(&key).await.unwrap());

    // Idempotent overwrite
    store
        .put(&key, bytes_v2, "application/pdf", &d2)
        .await
        .expect("put v2 overwrite");
    let art = store.fetch(&key).await.expect("fetch after overwrite");
    assert_eq!(art.bytes, bytes_v2);

    store.delete(&key).await.expect("delete");
    assert!(!store.exists(&key).await.unwrap());
    // Idempotent delete
    store.delete(&key).await.expect("delete again");
}

#[tokio::test]
async fn memory_contract_upload_overwrite_fetch_delete() {
    let store = MemoryReportArchiveStorage::new();
    contract_upload_overwrite_fetch_delete(&store).await;
}

/// GDrive must be configured through Settings/Vault. A missing Vault binding
/// is represented by the fail-closed storage adapter rather than memory.
#[tokio::test]
async fn gdrive_unavailable_storage_fails_closed() {
    let store = super::UnavailableReportArchiveStorage::new("Vault unavailable");
    let key = ReportArtifactKey::new("contract/test-report.pdf").unwrap();
    let digest = super::sha256_hex(b"pdf");
    let error = store
        .put(&key, b"pdf", "application/pdf", &digest)
        .await
        .expect_err("unavailable provider must fail closed");
    assert!(error.to_string().contains("Vault unavailable"));
}

#[test]
fn error_display_never_contains_pdf_magic() {
    use breakdown_core::reporting::ReportStorageError;
    let err = ReportStorageError::provider_failure("upstream 503");
    assert!(!err.to_string().contains("%PDF"));
    let dbg = format!("{err:?}");
    assert!(!dbg.contains("%PDF"));
}
