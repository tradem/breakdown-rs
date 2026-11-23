// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for the flat-text (`pdftotext -layout`) adapter.
//!
//! The subprocess-error cases (empty input, oversized output, timeout) are
//! covered here; the shared kill/reap/output-cap plumbing they route through is
//! tested in `subprocess_tests.rs`, so these tests assert the *adapter's*
//! contract instead of re-testing the plumbing.

use std::time::Duration;

use breakdown_core::ai::{
    BlockKind, DocumentStructureExtractor, ExtractionOptions, NormalizedBBox, RenderOptions,
};
use breakdown_core::error::DomainError;

use super::{LEGACY_PARSER_FINGERPRINT, LegacyPdfToTextAdapter, pages_from_layout_text};

// ===========================================================================
// Construction & fingerprint
// ===========================================================================

#[test]
fn new_creates_extractor() {
    let extractor = LegacyPdfToTextAdapter::new(1024, Duration::from_secs(30));
    assert_eq!(extractor.max_output_bytes, 1024);
    assert_eq!(extractor.timeout, Duration::from_secs(30));
}

#[test]
fn the_fingerprint_names_the_legacy_algorithm() {
    let extractor = LegacyPdfToTextAdapter::new(1024, Duration::from_secs(30));
    assert_eq!(extractor.parser_fingerprint(), "legacy-pdftotext-v1");
    assert_eq!(extractor.parser_fingerprint(), LEGACY_PARSER_FINGERPRINT);
}

#[test]
fn the_adapter_is_copy() {
    // A worker holds it by value; wrapping it in an `Arc` would be a second
    // refcount for two machine words of configuration.
    let extractor = LegacyPdfToTextAdapter::new(1024, Duration::from_secs(30));
    let copy = extractor;
    assert_eq!(extractor.max_output_bytes, copy.max_output_bytes);
    assert_eq!(extractor.timeout, copy.timeout);
}

// ===========================================================================
// Page reconstruction
// ===========================================================================

#[test]
fn layout_text_splits_into_one_based_pages_on_the_form_feed() {
    let pages = pages_from_layout_text("Page one\n\u{c}Page two\n\u{c}");
    assert_eq!(pages.len(), 3);
    assert_eq!(pages[0].page_number, 1);
    assert_eq!(pages[1].page_number, 2);
    assert_eq!(pages[2].page_number, 3);
    assert_eq!(pages[0].blocks[0].text, "Page one\n");
    assert_eq!(pages[1].blocks[0].text, "Page two\n");
    // The trailing form feed yields an empty final page rather than dropping
    // bytes: the flattened view must stay byte-identical.
    assert_eq!(pages[2].blocks[0].text, "");
}

#[test]
fn layout_pages_carry_no_fabricated_geometry() {
    let pages = pages_from_layout_text("Block 098\nINT. WOHNUNG - TAG\n\u{c}");
    for page in &pages {
        assert!(!page.has_geometry(), "flat text has no page size");
        let block = &page.blocks[0];
        assert_eq!(block.kind, BlockKind::Paragraph);
        assert_eq!(block.bbox, NormalizedBBox::FULL_PAGE);
        assert_eq!(block.id.page_number, page.page_number);
        assert_eq!(block.id.block_ordinal, 0);
        assert!(block.html_table.is_none());
    }
}

#[test]
fn an_empty_layout_text_is_one_empty_page() {
    assert_eq!(pages_from_layout_text("").len(), 1);
}

// ===========================================================================
// extract — adapter contract
// ===========================================================================

#[tokio::test]
async fn extract_rejects_empty_pdf() {
    let extractor = LegacyPdfToTextAdapter::new(1024, Duration::from_secs(30));
    let result = extractor.extract(&[], ExtractionOptions::default()).await;
    assert!(result.is_err(), "empty PDF should fail");

    let err = result.expect_err("empty PDF must fail");
    assert!(
        err.to_string().contains("must not be empty"),
        "error should mention empty: {err}"
    );
}

#[tokio::test]
async fn extract_fails_for_invalid_content() {
    let extractor = LegacyPdfToTextAdapter::new(1024, Duration::from_secs(30));
    // pdftotext will reject this, but the error must be a validation error
    let result = extractor
        .extract(b"not a pdf", ExtractionOptions::default())
        .await;
    let err = result.expect_err("invalid content must fail");
    assert!(matches!(err, DomainError::Validation { .. }));
}

#[tokio::test]
async fn extract_timeout_is_respected() {
    let extractor = LegacyPdfToTextAdapter::new(1024, Duration::from_millis(1));
    let result = extractor
        .extract(b"%PDF-1.4", ExtractionOptions::default())
        .await;
    assert!(result.is_err());
}

#[tokio::test]
async fn render_page_is_refused_by_name() {
    let extractor = LegacyPdfToTextAdapter::new(1024, Duration::from_secs(30));
    let error = extractor
        .render_page(b"%PDF-1.4", 3, RenderOptions::default())
        .await
        .expect_err("the flat-text adapter renders no images");
    assert!(error.to_string().contains("spatial"), "unexpected: {error}");
    assert!(error.to_string().contains("page 3"), "unexpected: {error}");
}
