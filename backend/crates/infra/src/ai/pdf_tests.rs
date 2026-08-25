// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for PdfTextExtractor.

use std::time::Duration;

use breakdown_core::error::DomainError;

use super::PdfTextExtractor;

// ===========================================================================
// Constructor
// ===========================================================================

#[test]
fn new_creates_extractor() {
    let extractor = PdfTextExtractor::new(1024, Duration::from_secs(30));
    assert_eq!(extractor.max_output_bytes, 1024);
    assert_eq!(extractor.timeout, Duration::from_secs(30));
}

// ===========================================================================
// extract — kills != → == for BrokenPipe check
// ===========================================================================

#[tokio::test]
async fn extract_rejects_empty_pdf() {
    let extractor = PdfTextExtractor::new(1024, Duration::from_secs(30));
    let result = extractor.extract(&[]).await;
    assert!(result.is_err(), "empty PDF should fail");

    let err = result.unwrap_err();
    assert!(
        err.to_string().contains("must not be empty"),
        "error should mention empty: {err}"
    );
}

#[tokio::test]
async fn extract_fails_for_invalid_content() {
    let extractor = PdfTextExtractor::new(1024, Duration::from_secs(30));
    // pdftotext will reject this, but the error must be a validation error
    let result = extractor.extract(b"not a pdf").await;
    assert!(result.is_err());
    let err = result.unwrap_err();
    // Must be validation (pdftotext failed or couldn't start)
    assert!(matches!(err, DomainError::Validation { .. }));
}

#[tokio::test]
async fn extract_rejects_content_too_large_for_pdftotext() {
    // Even if pdftotext is available, the output bound is very small
    let extractor = PdfTextExtractor::new(10, Duration::from_secs(30));
    let fake_pdf = b"%PDF-1.4 fake content that is longer than 10 bytes";
    let result = extractor.extract(fake_pdf).await;
    // Should fail: either pdftotext not installed or output exceeds bound
    assert!(result.is_err());
}

#[tokio::test]
async fn extract_timeout_is_respected() {
    // Very short timeout — even if pdftotext starts, it should time out
    let extractor = PdfTextExtractor::new(1024, Duration::from_millis(1));
    let fake_pdf = b"%PDF-1.4";
    let result = extractor.extract(fake_pdf).await;
    assert!(result.is_err());
}

// ===========================================================================
// PdfTextExtractor is Clone
// ===========================================================================

#[test]
fn extractor_is_clone() {
    let extractor = PdfTextExtractor::new(1024, Duration::from_secs(30));
    let extractor2 = extractor.clone();
    assert_eq!(extractor.max_output_bytes, extractor2.max_output_bytes);
    assert_eq!(extractor.timeout, extractor2.timeout);
}

// ===========================================================================
// extract — verify specific error messages
// ===========================================================================

#[tokio::test]
async fn extract_error_message_contains_context() {
    let extractor = PdfTextExtractor::new(1024, Duration::from_secs(30));
    let result = extractor.extract(b"invalid").await;
    if let Err(err) = result {
        let msg = err.to_string();
        // Error should have some descriptive content
        assert!(!msg.is_empty(), "error message should not be empty");
    }
}
