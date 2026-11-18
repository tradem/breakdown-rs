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

#[test]
fn artifact_key_rejects_empty_and_traversal() {
    assert!(ReportArtifactKey::new("").is_err());
    assert!(ReportArtifactKey::new("../etc/passwd").is_err());
    assert!(ReportArtifactKey::new("/abs").is_err());
    assert!(ReportArtifactKey::new(r"a\b").is_err());
    let k = ReportArtifactKey::new("reports/day/dispo.pdf").unwrap();
    assert_eq!(k.as_str(), "reports/day/dispo.pdf");
}

#[test]
fn content_digest_validates_hex() {
    assert!(ContentDigest::new("").is_err());
    assert!(ContentDigest::new("zz").is_err());
    let d = ContentDigest::new("AbCd").unwrap();
    assert_eq!(d.as_str(), "abcd");
}

#[test]
fn storage_error_carries_no_bytes_in_display() {
    let err = ReportStorageError::provider_failure("timeout talking to backend");
    let s = err.to_string();
    assert!(!s.contains("%PDF"));
    assert!(s.contains("timeout"));
}

#[test]
fn storage_error_redacts_credentialish_detail() {
    let err = ReportStorageError::provider_failure("token=super-secret-value");
    assert_eq!(
        err.to_string(),
        "report storage provider failure: redacted provider error"
    );
}

#[test]
fn storage_error_serialization_roundtrip() {
    let err = ReportStorageError::NotFound { key: "k".into() };
    let json = serde_json::to_string(&err).unwrap();
    let deserialized: ReportStorageError = serde_json::from_str(&json).unwrap();
    assert_eq!(err, deserialized);
}

#[test]
fn artifact_key_display() {
    let k = ReportArtifactKey::new("test/key").unwrap();
    assert_eq!(format!("{k}"), "test/key");
}

#[test]
fn content_digest_display() {
    let d = ContentDigest::new("ABCDEF").unwrap();
    assert_eq!(format!("{d}"), "abcdef");
}

#[test]
fn artifact_len_and_empty() {
    let mut artifact = ReportArtifact {
        bytes: vec![1, 2, 3],
        content_type: "application/pdf".into(),
        digest: None,
    };
    assert_eq!(artifact.len(), 3);
    assert!(!artifact.is_empty());

    artifact.bytes.clear();
    assert!(artifact.is_empty());
}
