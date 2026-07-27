// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: grok-4.5 (opencode-go)

//! Contract tests for `ReportArchiveStorage` semantics.
//!
//! These run against the in-memory adapter (always) and optionally against a
//! live Google Drive target when `REPORT_BACKUP_PROVIDER=gdrive` and the
//! required credentials are present (`#[ignore]` by default).
use breakdown_core::reporting::{ReportArchiveStorage, ReportArtifactKey};
use super::storage::{MemoryReportArchiveStorage, OpenDalReportArchiveStorage, sha256_hex};
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
        .put(&key, bytes_v2, "application/pdf", &d2)
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
/// Live Google Drive contract — skips gracefully when credentials are absent.
///
/// In CI, the workflow passes `REPORT_BACKUP_GDRIVE_*` secrets via env vars
/// (see `.github/workflows/integration-tests.yml`). When unset, the test
/// prints a skip message and returns — it never fails on missing credentials.
async fn gdrive_contract_upload_overwrite_fetch_delete() {
    // Check that the env var is both present AND non-empty.
    // An empty string (e.g. from a missing GitHub secret) is treated as unconfigured.
    if !std::env::var("REPORT_BACKUP_GDRIVE_CLIENT_ID")
        .map(|v| !v.is_empty())
        .unwrap_or(false)
    {
        println!("SKIP: GDrive credentials not configured (set REPORT_BACKUP_GDRIVE_* env vars)");
        return;
    }
    let store = OpenDalReportArchiveStorage::external_from_env()
        .expect("external_from_env with gdrive credentials");
#[test]
fn error_display_never_contains_pdf_magic() {
    use breakdown_core::reporting::ReportStorageError;
    let err = ReportStorageError::provider_failure("upstream 503");
    assert!(!err.to_string().contains("%PDF"));
    let dbg = format!("{err:?}");
    assert!(!dbg.contains("%PDF"));
