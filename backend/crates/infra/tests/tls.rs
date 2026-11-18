// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    unsafe_code // test-only env seeding (std::env::set_var is unsafe in edition 2024)
)]

use std::io::{Read, Write};

use http::HeaderMap;
use infra::tls::{
    effective_content_length, from_value, is_temporary_error, root_cert_from_env, should_send_body,
};
use opendal::Buffer;

// ---------------------------------------------------------------------------
// from_value (already covered, kept for regression)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// root_cert_from_env  (kills: replace → Ok(None), delete !, guard mutations)
// ---------------------------------------------------------------------------

#[test]
fn root_cert_from_env_unset_returns_none() {
    let result = root_cert_from_env("BREAKDOWN_TEST_TLS_UNSET_VAR_XYZZY").unwrap();
    assert!(result.is_none());
}

#[test]
fn root_cert_from_env_empty_string_returns_none() {
    unsafe {
        std::env::set_var("BREAKDOWN_TEST_TLS_EMPTY_VAR", "");
    }
    let result = root_cert_from_env("BREAKDOWN_TEST_TLS_EMPTY_VAR").unwrap();
    assert!(result.is_none());
    unsafe {
        std::env::remove_var("BREAKDOWN_TEST_TLS_EMPTY_VAR");
    }
}

#[test]
fn root_cert_from_env_whitespace_only_returns_none() {
    unsafe {
        std::env::set_var("BREAKDOWN_TEST_TLS_WS_VAR", "   \t  ");
    }
    let result = root_cert_from_env("BREAKDOWN_TEST_TLS_WS_VAR").unwrap();
    assert!(result.is_none());
    unsafe {
        std::env::remove_var("BREAKDOWN_TEST_TLS_WS_VAR");
    }
}

#[test]
fn root_cert_from_env_missing_file_errors() {
    unsafe {
        std::env::set_var(
            "BREAKDOWN_TEST_TLS_MISSING",
            "/nonexistent/breakdown-root-ca.pem",
        );
    }
    let result = root_cert_from_env("BREAKDOWN_TEST_TLS_MISSING");
    assert!(result.is_err());
    unsafe {
        std::env::remove_var("BREAKDOWN_TEST_TLS_MISSING");
    }
}

#[test]
fn root_cert_from_env_valid_file_returns_some() {
    let dir = std::env::temp_dir().join("breakdown-tls-env-test");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("root_ca.pem");
    std::fs::write(
        &path,
        b"-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n",
    )
    .unwrap();
    unsafe {
        std::env::set_var("BREAKDOWN_TEST_TLS_VALID", path.to_str().unwrap());
    }
    let result = root_cert_from_env("BREAKDOWN_TEST_TLS_VALID").unwrap();
    assert_eq!(result, Some(path.clone()));
    std::fs::remove_file(&path).ok();
    unsafe {
        std::env::remove_var("BREAKDOWN_TEST_TLS_VALID");
    }
}

// ---------------------------------------------------------------------------
// is_temporary_error  (kills: replace → true/false, || → &&)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn is_temporary_request_error() {
    // A request to an unreachable port triggers `is_request()`.
    let err = reqwest::get("http://[::1]:1").await.unwrap_err();
    assert!(err.is_request(), "expected is_request() error");
    assert!(
        is_temporary_error(&err),
        "connection error should be temporary"
    );
}

#[tokio::test]
async fn is_temporary_body_error() {
    // Start a TCP server that sends a valid HTTP status line with
    // content-length: 100 but closes immediately (no body) — the client
    // will fail while reading the body, triggering `is_body()`.
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    std::thread::spawn(move || {
        let mut stream = listener.incoming().next().unwrap().unwrap();
        // Read the full request headers
        let mut buf = [0u8; 4096];
        loop {
            let n = stream.read(&mut buf).unwrap();
            if n == 0 || buf[..n].windows(4).any(|w| w == b"\r\n\r\n") {
                break;
            }
        }
        // Send status line + headers, then immediately close (no body)
        stream
            .write_all(b"HTTP/1.1 200 OK\r\ncontent-length: 100\r\n\r\n")
            .unwrap();
        drop(stream);
    });
    let resp = reqwest::get(format!("http://{addr}")).await.unwrap();
    // Reading the body should fail because the server closed early.
    let err = resp.bytes().await.unwrap_err();
    assert!(
        err.is_body() || err.is_decode(),
        "expected is_body() or is_decode() error, got: {err:?}"
    );
    assert!(is_temporary_error(&err), "body error should be temporary");
}

#[tokio::test]
async fn is_not_temporary_for_http_status_error() {
    // Start a TCP server that returns a 4xx response.
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    std::thread::spawn(move || {
        let mut stream = listener.incoming().next().unwrap().unwrap();
        let mut buf = [0u8; 4096];
        loop {
            let n = stream.read(&mut buf).unwrap();
            if n == 0 || buf[..n].windows(4).any(|w| w == b"\r\n\r\n") {
                break;
            }
        }
        stream
            .write_all(b"HTTP/1.1 403 Forbidden\r\ncontent-length: 0\r\n\r\n")
            .unwrap();
    });
    let resp = reqwest::get(format!("http://{addr}")).await.unwrap();
    let err = resp.error_for_status().unwrap_err();
    assert!(err.is_status(), "expected is_status() error");
    assert!(
        !is_temporary_error(&err),
        "HTTP status error should NOT be temporary"
    );
}

// ---------------------------------------------------------------------------
// effective_content_length — kills == → != and delete ! mutants
// ---------------------------------------------------------------------------

#[test]
fn content_length_none_for_head() {
    let mut headers = HeaderMap::new();
    headers.insert("content-length", "42".parse().unwrap());
    assert_eq!(effective_content_length(true, &headers).unwrap(), None);
}

#[test]
fn content_length_none_when_content_encoding_present() {
    let mut headers = HeaderMap::new();
    headers.insert("content-length", "100".parse().unwrap());
    headers.insert("content-encoding", "gzip".parse().unwrap());
    assert_eq!(effective_content_length(false, &headers).unwrap(), None);
}

#[test]
fn content_length_some_for_normal_response() {
    let mut headers = HeaderMap::new();
    headers.insert("content-length", "42".parse().unwrap());
    assert_eq!(effective_content_length(false, &headers).unwrap(), Some(42));
}

#[test]
fn content_length_none_when_no_header() {
    let headers = HeaderMap::new();
    assert_eq!(effective_content_length(false, &headers).unwrap(), None);
}

// ---------------------------------------------------------------------------
// should_send_body — kills delete ! and || → && mutants
// ---------------------------------------------------------------------------

#[test]
fn send_body_false_for_head() {
    let body = Buffer::from(vec![1u8, 2, 3]);
    assert!(!should_send_body(true, &body));
}

#[test]
fn send_body_false_for_empty_body() {
    let body = Buffer::from(Vec::<u8>::new());
    assert!(!should_send_body(false, &body));
}

#[test]
fn send_body_true_for_non_empty_non_head() {
    let body = Buffer::from(vec![1u8, 2, 3]);
    assert!(should_send_body(false, &body));
}
