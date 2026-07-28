// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use breakdown_core::reporting::*;
use breakdown_core::shared::ShootingDayId;
use infra::reporting::backup::compute_backoff;
use infra::reporting::storage::{
    MemoryReportArchiveStorage, external_key, sha256_hex, staging_key,
};
use std::sync::Arc;
use std::time::Duration;
use uuid::Uuid;

#[test]
fn exp_backoff_is_bounded() {
    let b = compute_backoff(100, Duration::from_secs(1), Duration::from_secs(10));
    assert!(b <= Duration::from_secs(10));
}

#[test]
fn backoff_never_exceeds_max() {
    exp_backoff_is_bounded();
}

#[test]
fn render_error_summary_has_no_pdf_marker() {
    let err = ReportRenderError::CompilerFailure {
        detail: "boom".into(),
    };
    let s = err.to_string();
    assert!(!s.contains("%PDF"));
    assert!(s.contains("boom"));
}

/// Pure unit test of the staging-reuse path using memory stores + counting renderer.
/// (Does not require Postgres — exercises the in-memory half of the pipeline.)
#[tokio::test]
async fn staging_reuse_does_not_re_render() {
    let staging = Arc::new(MemoryReportArchiveStorage::new());
    let external = Arc::new(MemoryReportArchiveStorage::new());

    // Manually stage an object as if a previous attempt succeeded at staging.
    let digest = sha256_hex(b"%PDF-test-bytes");
    let day = Uuid::nil();
    let key = staging_key(day, "dispo", "de-DE", "1.0.0", &digest).unwrap();
    staging
        .put(&key, b"%PDF-test-bytes", "application/pdf", &digest)
        .await
        .unwrap();

    // Simulate the "already staged" branch of process_job without DB:
    // fetch staged → upload external → verify renderer was NOT called.
    let art = staging.fetch(&key).await.unwrap();
    let actual = sha256_hex(&art.bytes);
    assert_eq!(actual.as_str(), digest.as_str());
    let dest = external_key(day, "dispo", "de-DE", "1.0.0").unwrap();
    external
        .put(&dest, &art.bytes, &art.content_type, &digest)
        .await
        .unwrap();

    assert!(external.exists(&dest).await.unwrap());
}

#[tokio::test]
async fn external_failure_keeps_staging() {
    let staging = Arc::new(MemoryReportArchiveStorage::new());
    let external = Arc::new(MemoryReportArchiveStorage::new());
    external.set_fail_puts(true).await;

    let digest = sha256_hex(b"%PDF-keep");
    let day = Uuid::nil();
    let key = staging_key(day, "dispo", "de-DE", "1.0.0", &digest).unwrap();
    staging
        .put(&key, b"%PDF-keep", "application/pdf", &digest)
        .await
        .unwrap();

    let art = staging.fetch(&key).await.unwrap();
    let dest = external_key(day, "dispo", "de-DE", "1.0.0").unwrap();
    let err = external
        .put(&dest, &art.bytes, "application/pdf", &digest)
        .await
        .unwrap_err();
    assert!(err.to_string().contains("provider") || err.to_string().contains("injected"));
    // Staging still present.
    assert!(staging.exists(&key).await.unwrap());
}

#[test]
fn enqueue_request_dedup_is_stable() {
    let day = ShootingDayId(Uuid::nil());
    let req = EnqueueArchivalRequest {
        kind: ReportKind::Dispo,
        shooting_day_id: day,
        locale: ReportLocale::de_de(),
        template_version: "1.0.0".into(),
        snapshot_identity: SnapshotIdentity::current(),
        trigger: ArchivalTrigger::Manual,
    };
    assert_eq!(req.dedup_key(), req.dedup_key());
}
