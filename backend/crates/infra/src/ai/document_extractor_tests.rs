// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for the parser selection and the `ConfiguredDocumentExtractor`
//! enum (issue #958).

use breakdown_core::ai::{
    AiImportBounds, DocumentStructureExtractor, ExtractionOptions, RenderOptions,
};

use super::{AI_DOCLING_ENDPOINT_ENV, ConfiguredDocumentExtractor, DocumentParser};

// ===========================================================================
// Selection
// ===========================================================================

#[test]
fn the_default_parser_is_spatial() {
    assert_eq!(DocumentParser::default(), DocumentParser::Spatial);
    assert_eq!(DocumentParser::default().as_str(), "spatial");
}

#[test]
fn every_documented_spelling_resolves() {
    for (raw, expected) in [
        ("spatial", DocumentParser::Spatial),
        ("  SPATIAL ", DocumentParser::Spatial),
        ("poppler-spatial", DocumentParser::Spatial),
        ("docling", DocumentParser::Docling),
        ("docling-http", DocumentParser::Docling),
        ("legacy-pdftotext", DocumentParser::LegacyPdfToText),
        ("legacy", DocumentParser::LegacyPdfToText),
        // An empty value keeps the default instead of selecting nothing.
        ("", DocumentParser::Spatial),
    ] {
        assert_eq!(DocumentParser::parse(raw), Some(expected), "value {raw:?}");
    }
}

#[test]
fn an_unknown_parser_spelling_is_not_silently_accepted() {
    // A typo must fail startup rather than quietly switch the extraction path.
    assert_eq!(DocumentParser::parse("spatial-pdf"), None);
    assert_eq!(DocumentParser::parse("tesseract"), None);
}

#[test]
fn every_parser_round_trips_through_its_env_spelling() {
    for parser in [
        DocumentParser::Spatial,
        DocumentParser::Docling,
        DocumentParser::LegacyPdfToText,
    ] {
        assert_eq!(DocumentParser::parse(parser.as_str()), Some(parser));
    }
}

// ===========================================================================
// Extractor construction
// ===========================================================================

#[test]
fn the_spatial_extractor_takes_its_bounds_from_the_pipeline() {
    let bounds = AiImportBounds {
        max_document_bytes: 4096,
        request_timeout_secs: 7,
        ..AiImportBounds::default()
    };
    let extractor = ConfiguredDocumentExtractor::from_parser(DocumentParser::Spatial, &bounds)
        .expect("spatial always builds");
    assert_eq!(extractor.parser(), DocumentParser::Spatial);
    assert_eq!(extractor.parser_fingerprint(), "poppler-spatial-v1");
}

#[test]
fn the_legacy_extractor_takes_its_bounds_from_the_pipeline() {
    let bounds = AiImportBounds::default();
    let extractor =
        ConfiguredDocumentExtractor::from_parser(DocumentParser::LegacyPdfToText, &bounds)
            .expect("legacy always builds");
    assert_eq!(extractor.parser(), DocumentParser::LegacyPdfToText);
    assert_eq!(extractor.parser_fingerprint(), "legacy-pdftotext-v1");
}

#[test]
fn the_configured_extractor_is_cheap_to_clone() {
    // `WorkerDeps` holds it by value and clones it per job tick; a `Copy`
    // adapter must not be hidden behind an `Arc`.
    let bounds = AiImportBounds::default();
    let extractor = ConfiguredDocumentExtractor::from_parser(DocumentParser::Spatial, &bounds)
        .expect("spatial always builds");
    let clone = extractor.clone();
    assert_eq!(clone.parser_fingerprint(), extractor.parser_fingerprint());
}

#[test]
fn docling_without_an_endpoint_is_a_startup_error() {
    // The builder takes the endpoint explicitly, so this needs no process-global
    // environment mutation.
    let error = ConfiguredDocumentExtractor::build(
        DocumentParser::Docling,
        &AiImportBounds::default(),
        None,
    )
    .expect_err("docling needs a sidecar URL");
    assert!(error.to_string().contains(AI_DOCLING_ENDPOINT_ENV));
}

#[test]
fn docling_with_an_invalid_endpoint_is_a_startup_error() {
    let error = ConfiguredDocumentExtractor::build(
        DocumentParser::Docling,
        &AiImportBounds::default(),
        Some("not a url"),
    )
    .expect_err("an unparsable URL must fail startup");
    assert!(error.to_string().contains(AI_DOCLING_ENDPOINT_ENV));
}

#[test]
fn docling_with_an_endpoint_builds_the_http_adapter() {
    let extractor = ConfiguredDocumentExtractor::build(
        DocumentParser::Docling,
        &AiImportBounds::default(),
        Some("http://docling:5001/"),
    )
    .expect("a valid endpoint builds");
    assert_eq!(extractor.parser(), DocumentParser::Docling);
    assert_eq!(extractor.parser_fingerprint(), "docling-http-v1");
}

// ===========================================================================
// Delegation
// ===========================================================================

#[tokio::test]
async fn delegation_reaches_the_selected_adapter() {
    let bounds = AiImportBounds::default();
    let extractor = ConfiguredDocumentExtractor::from_parser(DocumentParser::Spatial, &bounds)
        .expect("spatial always builds");
    // The empty-document guard is the adapter's, so a validation error proves
    // the call reached it rather than a stub.
    let error = extractor
        .extract(&[], ExtractionOptions::default())
        .await
        .expect_err("an empty document must be rejected");
    assert!(error.to_string().contains("must not be empty"));

    let legacy = ConfiguredDocumentExtractor::from_parser(DocumentParser::LegacyPdfToText, &bounds)
        .expect("legacy always builds");
    let error = legacy
        .render_page(&[], 1, RenderOptions::default())
        .await
        .expect_err("the legacy adapter renders no pages");
    assert!(error.to_string().contains("spatial"));
}
