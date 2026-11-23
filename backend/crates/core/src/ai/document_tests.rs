// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for the canonical document-structure IR (issue #958).
//!
//! These are the always-on CI fixtures the ADR-041 `D8` harness complements:
//! the synthetic multi-zone document built here needs no PDF corpus, so the IR
//! contract (1-based pages, monotonic anchors, normalized geometry, flattened
//! text round-trip) is verified on every build.

use super::{
    BlockAnchor, BlockKind, DEFAULT_MAX_RENDER_BYTES, DEFAULT_TARGET_DPI, DocumentBlock,
    ExtractionOptions, FOOTER_BAND_MIN_Y0, HEADER_BAND_MAX_Y1, NormalizedBBox, RenderOptions,
    RenderedPage, StructuredDocument, StructuredPage,
};

/// A three-page synthetic document: a title page, a `SYNOPSIS` front-matter page
/// and one script-body page with a running header band and an indented cue.
fn multi_zone_fixture() -> StructuredDocument {
    let mut title = StructuredPage::new(1, 595.0, 842.0);
    title.push_block(
        BlockKind::Heading,
        NormalizedBBox::new(0.15, 0.30, 0.85, 0.34),
        "MEDIZINISCHE FÄLLE",
    );

    let mut synopsis = StructuredPage::new(2, 595.0, 842.0);
    synopsis.push_block(
        BlockKind::Heading,
        NormalizedBBox::new(0.10, 0.10, 0.40, 0.12),
        "SYNOPSIS",
    );
    synopsis.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.15, 0.90, 0.60),
        "Die junge Ärztin kehrt in ihre Heimatstadt zurück.",
    );

    let mut body = StructuredPage::new(3, 595.0, 842.0);
    body.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.10, 0.04, 0.30, 0.06),
        "Block 098",
    );
    body.push_block(
        BlockKind::Heading,
        NormalizedBBox::new(0.10, 0.15, 0.55, 0.17),
        "1 A+I/T Wohnung Leyla - Tag",
    );
    body.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.18, 0.85, 0.24),
        "Leyla räumt die Küche auf.",
    );
    body.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.35, 0.26, 0.55, 0.28),
        "LEYLA",
    );
    body.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.25, 0.29, 0.70, 0.33),
        "Wer hat das gemacht?",
    );

    StructuredDocument::new("test-fixture-v1", vec![title, synopsis, body])
}

// ===========================================================================
// Geometry
// ===========================================================================

#[test]
fn bbox_clamps_out_of_range_coordinates() {
    let bbox = NormalizedBBox::new(-0.5, 1.4, 2.0, 0.5);
    assert_eq!(bbox.x0, 0.0);
    assert_eq!(bbox.y0, 1.0);
    assert_eq!(bbox.x1, 1.0);
    assert_eq!(bbox.y1, 0.5);
}

#[test]
fn bbox_collapses_non_finite_coordinates_to_zero() {
    // A NaN must never reach a comparison that decides a zone.
    let bbox = NormalizedBBox::new(f32::NAN, f32::INFINITY, f32::NEG_INFINITY, 0.25);
    assert_eq!(bbox, NormalizedBBox::new(0.0, 0.0, 0.0, 0.25));
}

#[test]
fn bbox_from_page_points_normalizes_against_page_size() {
    let bbox = NormalizedBBox::from_page_points(59.5, 42.1, 535.5, 84.2, 595.0, 842.0);
    assert!((bbox.x0 - 0.1).abs() < 0.001, "x0 was {}", bbox.x0);
    assert!(
        (bbox.width() - 0.8).abs() < 0.001,
        "width was {}",
        bbox.width()
    );
    assert!(
        (bbox.height() - 0.05).abs() < 0.001,
        "height was {}",
        bbox.height()
    );
}

#[test]
fn bbox_from_page_points_without_usable_geometry_falls_back_to_full_page() {
    // Zero, negative and NaN page sizes all mean "this page carries no usable
    // geometry" — never a division by zero and never a bogus zero box.
    for (width, height) in [(0.0, 842.0), (595.0, 0.0), (-5.0, 842.0), (f32::NAN, 842.0)] {
        assert_eq!(
            NormalizedBBox::from_page_points(10.0, 10.0, 20.0, 20.0, width, height),
            NormalizedBBox::FULL_PAGE,
            "page size {width}x{height} should not normalize"
        );
    }
}

#[test]
fn bbox_width_and_height_never_go_negative() {
    let bbox = NormalizedBBox::new(0.8, 0.8, 0.2, 0.3);
    assert_eq!(bbox.width(), 0.0);
    assert_eq!(bbox.height(), 0.0);
}

#[test]
fn band_predicates_split_header_footer_from_body() {
    let header = NormalizedBBox::new(0.10, 0.04, 0.30, 0.06);
    assert!(header.is_header_band());
    assert!(!header.is_footer_band());
    let footer = NormalizedBBox::new(0.45, 0.95, 0.55, 0.97);
    assert!(footer.is_footer_band());
    assert!(!footer.is_header_band());
    let body = NormalizedBBox::new(0.10, 0.15, 0.90, 0.20);
    assert!(!body.is_header_band());
    assert!(!body.is_footer_band());
    // The band edges are inclusive ceilings/floors, never off-by-one surprises.
    assert!(NormalizedBBox::new(0.0, 0.0, 1.0, HEADER_BAND_MAX_Y1).is_header_band());
    assert!(NormalizedBBox::new(0.0, FOOTER_BAND_MIN_Y0, 1.0, 1.0).is_footer_band());
    // A block starting high but ending low is body text, not a header.
    assert!(!NormalizedBBox::new(0.10, 0.05, 0.90, 0.30).is_header_band());
}

#[test]
fn full_page_is_the_default() {
    assert_eq!(NormalizedBBox::default(), NormalizedBBox::FULL_PAGE);
    assert_eq!(
        DocumentBlock::text(
            BlockAnchor::new(1, 0),
            BlockKind::Table,
            NormalizedBBox::default(),
            "x"
        )
        .bbox,
        NormalizedBBox::FULL_PAGE
    );
}

// ===========================================================================
// Anchors
// ===========================================================================

#[test]
fn block_anchor_renders_the_anchor_plan_spelling() {
    assert_eq!(BlockAnchor::new(4, 3).to_string(), "P04.B03");
    assert_eq!(BlockAnchor::new(12, 105).to_string(), "P12.B105");
    assert_eq!(BlockAnchor::new(1, 0).to_string(), "P01.B00");
}

#[test]
fn push_block_stamps_monotonic_ordinals_on_the_page() {
    let mut page = StructuredPage::new(7, 595.0, 842.0);
    page.push_block(BlockKind::Paragraph, NormalizedBBox::FULL_PAGE, "a");
    page.push_block(BlockKind::Paragraph, NormalizedBBox::FULL_PAGE, "b");
    page.push_block(BlockKind::Paragraph, NormalizedBBox::FULL_PAGE, "c");
    let anchors: Vec<_> = page.blocks.iter().map(|block| block.id).collect();
    assert_eq!(
        anchors,
        vec![
            BlockAnchor::new(7, 0),
            BlockAnchor::new(7, 1),
            BlockAnchor::new(7, 2)
        ]
    );
}

#[test]
fn block_kind_spellings_are_stable() {
    // The persisted structural anchor plan (#959) hashes these strings, so a
    // rename here would silently invalidate every stored plan digest.
    assert_eq!(BlockKind::PageHeader.as_str(), "page_header");
    assert_eq!(BlockKind::PageFooter.as_str(), "page_footer");
    assert_eq!(BlockKind::Heading.as_str(), "heading");
    assert_eq!(BlockKind::Paragraph.as_str(), "paragraph");
    assert_eq!(BlockKind::Table.as_str(), "table");
    assert_eq!(BlockKind::ListItem.as_str(), "list_item");
}

// ===========================================================================
// Document
// ===========================================================================

#[test]
fn flattened_text_round_trips_the_line_based_view() {
    let document = multi_zone_fixture();
    let text = document.flattened_text();
    // Pages are form-feed separated so the pre-ADR-041 line scanner sees the
    // same page breaks `pdftotext -layout` emitted.
    assert_eq!(text.matches('\u{c}').count(), 2);
    assert!(text.starts_with("MEDIZINISCHE FÄLLE"));
    assert!(text.contains("SYNOPSIS\nDie junge Ärztin"));
    assert!(text.contains("Block 098\n1 A+I/T Wohnung Leyla - Tag\nLeyla"));
    assert!(text.ends_with("Wer hat das gemacht?"));
}

#[test]
fn flattened_text_of_an_empty_document_is_empty() {
    let document = StructuredDocument::new("empty-v1", Vec::new());
    assert!(document.is_empty());
    assert_eq!(document.page_count(), 0);
    assert_eq!(document.flattened_text(), "");
    assert_eq!(document.blocks().count(), 0);
}

#[test]
fn pages_are_addressed_one_based() {
    let document = multi_zone_fixture();
    assert_eq!(document.page_count(), 3);
    assert_eq!(document.page(1).map(|page| page.page_number), Some(1));
    assert_eq!(document.page(3).map(|page| page.page_number), Some(3));
    // 0 is not a page number.
    assert!(document.page(0).is_none());
    assert!(document.page(4).is_none());
}

#[test]
fn blocks_iterator_walks_pages_in_reading_order() {
    let document = multi_zone_fixture();
    let first: Vec<_> = document.blocks().take(2).map(|b| b.text.as_str()).collect();
    assert_eq!(first, vec!["MEDIZINISCHE FÄLLE", "SYNOPSIS"]);
    assert_eq!(document.blocks().count(), 8);
}

#[test]
fn header_and_footer_bands_are_spatially_distinguishable() {
    let document = multi_zone_fixture();
    let page = document.page(3).expect("fixture has a third page");
    let header = page.blocks.first().expect("fixture has a header block");
    assert_eq!(header.kind, BlockKind::PageHeader);
    assert!(header.bbox.y1 <= 0.09, "header y1 was {}", header.bbox.y1);
    // The dialogue column is indented further than the action column.
    let action = &page.blocks[2];
    let cue = &page.blocks[3];
    assert!(
        cue.bbox.x0 > action.bbox.x0,
        "cue {} must be indented past the margin {}",
        cue.bbox.x0,
        action.bbox.x0
    );
}

#[test]
fn blank_blocks_are_recognised() {
    let blank = DocumentBlock::text(
        BlockAnchor::new(1, 0),
        BlockKind::Paragraph,
        NormalizedBBox::FULL_PAGE,
        "  \n\t ",
    );
    assert!(blank.is_blank());
    let mut table = blank.clone();
    table.text = "| a | b |".to_owned();
    table.kind = BlockKind::Table;
    table.html_table = Some("<table><tr><td>a</td></tr></table>".to_owned());
    assert!(!table.is_blank());
    assert!(
        table
            .html_table
            .is_some_and(|html| html.contains("<table>"))
    );
}

#[test]
fn page_geometry_presence_is_reported() {
    assert!(StructuredPage::new(1, 595.0, 842.0).has_geometry());
    assert!(!StructuredPage::new(1, 0.0, 842.0).has_geometry());
}

// ===========================================================================
// Options
// ===========================================================================

#[test]
fn extraction_defaults_never_eagerly_render_pages() {
    let options = ExtractionOptions::default();
    assert!(
        !options.render_pages_png,
        "D1 forbids retaining page images"
    );
    assert_eq!(options.target_dpi, DEFAULT_TARGET_DPI);
    assert_eq!(DEFAULT_TARGET_DPI, 150);
}

#[test]
fn render_options_default_to_the_bounded_page_ceiling() {
    let options = RenderOptions::default();
    assert_eq!(options.target_dpi, DEFAULT_TARGET_DPI);
    assert_eq!(options.max_bytes, DEFAULT_MAX_RENDER_BYTES);
    assert_eq!(
        RenderOptions::new(120, 4096),
        RenderOptions {
            target_dpi: 120,
            max_bytes: 4096
        }
    );
}

#[test]
fn rendered_page_keeps_its_one_based_number() {
    let page = RenderedPage::new(4, vec![0x89, b'P', b'N', b'G']);
    assert_eq!(page.page_number, 4);
    assert_eq!(page.png_bytes.len(), 4);
}
