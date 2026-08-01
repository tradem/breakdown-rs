// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

//! Integration tests for the shared in-transit TLS helpers
//! (ADR-024 / issue #156): checked root-CA path resolution used by the S3
//! adapters (photo storage + report archival).

use infra::tls::from_value;

#[test]
fn from_value_blank_is_none() {
    assert!(from_value("  ").unwrap().is_none());
}

#[test]
fn from_value_missing_file_errors() {
    assert!(from_value("/nonexistent/root_ca.crt").is_err());
}

#[test]
fn from_value_existing_file_is_some() {
    let dir = std::env::temp_dir().join("breakdown-tls-test");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("root_ca.crt");
    std::fs::write(
        &path,
        b"-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n",
    )
    .unwrap();
    let res = from_value(path.to_str().unwrap()).unwrap();
    assert_eq!(res, Some(path.clone()));
    std::fs::remove_file(&path).ok();
}
