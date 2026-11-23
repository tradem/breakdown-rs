// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for the spatial PDF adapter and its `-bbox-layout` parser
//! (issue #958).
//!
//! The parser tests run against a committed synthetic XHTML fixture, so they
//! pass on any machine. The adapter tests need the real `pdftotext` binary
//! (poppler-utils, installed in CI and in the runtime image) and skip
//! gracefully where it is missing — a developer laptop without poppler must not
//! see a red suite for an environment gap.

use std::time::Duration;

use breakdown_core::ai::{
    BlockKind, DocumentStructureExtractor, ExtractionOptions, NormalizedBBox, RenderOptions,
    StructuredDocument, extract_scenes_from_structured,
};
use breakdown_core::error::DomainError;

use super::{SPATIAL_PARSER_FINGERPRINT, SpatialPdfExtractor, parse_bbox_layout};
use crate::ai::markup::decode_entities;

// ===========================================================================
// Synthetic multi-zone `-bbox-layout` fixture (always runs)
// ===========================================================================

/// Two pages: page 1 has a running header, a scene heading at the left margin
/// and a centered character cue; page 2 has a footer and body prose.
const BBOX_FIXTURE: &str = r#"<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"><html xmlns="http://www.w3.org/1999/xhtml">
<body>
<doc>
  <page width="612.000000" height="792.000000">
    <flow>
      <block xMin="61.200000" yMin="20.000000" xMax="183.600000" yMax="31.000000">
        <line xMin="61.200000" yMin="20.000000" xMax="183.600000" yMax="31.000000">
          <word xMin="61.200000" yMin="20.000000" xMax="100.000000" yMax="31.000000">Block</word>
          <word xMin="103.000000" yMin="20.000000" xMax="183.600000" yMax="31.000000">098</word>
        </line>
      </block>
      <block xMin="61.200000" yMin="118.800000" xMax="336.600000" yMax="132.000000">
        <line xMin="61.200000" yMin="118.800000" xMax="336.600000" yMax="132.000000">
          <word xMin="61.200000" yMin="118.800000" xMax="73.000000" yMax="132.000000">1</word>
          <word xMin="76.000000" yMin="118.800000" xMax="118.000000" yMax="132.000000">INT.</word>
          <word xMin="121.000000" yMin="118.800000" xMax="220.000000" yMax="132.000000">K&#252;che</word>
        </line>
        <line xMin="61.200000" yMin="134.000000" xMax="336.600000" yMax="147.000000">
          <word xMin="61.200000" yMin="134.000000" xMax="120.000000" yMax="147.000000">&amp;</word>
          <word xMin="124.000000" yMin="134.000000" xMax="200.000000" yMax="147.000000">Wohnung</word>
        </line>
      </block>
      <block xMin="214.200000" yMin="180.000000" xMax="336.600000" yMax="193.000000">
        <line xMin="214.200000" yMin="180.000000" xMax="336.600000" yMax="193.000000">
          <word xMin="214.200000" yMin="180.000000" xMax="290.000000" yMax="193.000000">LEYLA</word>
        </line>
      </block>
      <block xMin="61.200000" yMin="200.000000" xMax="80.000000" yMax="213.000000">
        <line xMin="61.200000" yMin="200.000000" xMax="80.000000" yMax="213.000000">
          <word xMin="61.200000" yMin="200.000000" xMax="80.000000" yMax="213.000000"></word>
        </line>
      </block>
    </flow>
  </page>
  <page width="612.000000" height="792.000000">
    <flow>
      <block xMin="61.200000" yMin="300.000000" xMax="550.000000" yMax="340.000000">
        <line xMin="61.200000" yMin="300.000000" xMax="550.000000" yMax="313.000000">
          <word xMin="61.200000" yMin="300.000000" xMax="150.000000" yMax="313.000000">Wer</word>
          <word xMin="154.000000" yMin="300.000000" xMax="220.000000" yMax="313.000000">hat</word>
        </line>
      </block>
      <block xMin="280.000000" yMin="750.000000" xMax="300.000000" yMax="762.000000">
        <line xMin="280.000000" yMin="750.000000" xMax="300.000000" yMax="762.000000">
          <word xMin="280.000000" yMin="750.000000" xMax="300.000000" yMax="762.000000">2</word>
        </line>
      </block>
    </flow>
  </page>
</doc>
</body>
</html>
"#;

#[test]
fn the_bbox_fixture_yields_one_page_per_page_element() {
    let pages = parse_bbox_layout(BBOX_FIXTURE).expect("fixture parses");
    assert_eq!(pages.len(), 2);
    assert_eq!(pages[0].page_number, 1);
    assert_eq!(pages[1].page_number, 2);
    assert_eq!(pages[0].width_pt, 612.0);
    assert_eq!(pages[0].height_pt, 792.0);
    assert!(pages[0].has_geometry());
}

#[test]
fn block_text_joins_words_by_space_and_lines_by_newline() {
    let pages = parse_bbox_layout(BBOX_FIXTURE).expect("fixture parses");
    let heading = &pages[0].blocks[1];
    assert_eq!(
        heading.text, "1 INT. Küche\n& Wohnung",
        "lines are newline-joined, words space-joined, entities decoded"
    );
}

#[test]
fn the_running_header_lands_in_the_header_band() {
    let pages = parse_bbox_layout(BBOX_FIXTURE).expect("fixture parses");
    let header = &pages[0].blocks[0];
    assert_eq!(header.kind, BlockKind::PageHeader);
    assert_eq!(header.text, "Block 098");
    assert!(header.bbox.is_header_band());
    // 20..31 of a 792pt page.
    assert!(
        (header.bbox.y0 - 0.0253).abs() < 0.001,
        "y0 {}",
        header.bbox.y0
    );
}

#[test]
fn the_footer_band_is_classified_on_the_last_page() {
    let pages = parse_bbox_layout(BBOX_FIXTURE).expect("fixture parses");
    let footer = pages[1].blocks.last().expect("page 2 has a footer");
    assert_eq!(footer.kind, BlockKind::PageFooter);
    assert_eq!(footer.text, "2");
}

#[test]
fn horizontal_indentation_is_normalized_and_preserved() {
    let pages = parse_bbox_layout(BBOX_FIXTURE).expect("fixture parses");
    let margin = &pages[0].blocks[1];
    let cue = &pages[0].blocks[2];
    // The margin column sits at 61.2/612 = 0.10, the centered cue at 214.2/612 = 0.35.
    assert!(
        (margin.bbox.x0 - 0.1).abs() < 0.001,
        "x0 {}",
        margin.bbox.x0
    );
    assert!((cue.bbox.x0 - 0.35).abs() < 0.001, "x0 {}", cue.bbox.x0);
    assert!(cue.bbox.x0 > margin.bbox.x0);
    // And the cue is a Paragraph here: this format has no semantic markup.
    assert_eq!(cue.kind, BlockKind::Paragraph);
}

#[test]
fn geometry_stays_inside_the_unit_square() {
    let pages = parse_bbox_layout(BBOX_FIXTURE).expect("fixture parses");
    for block in pages.iter().flat_map(|page| page.blocks.iter()) {
        for value in [block.bbox.x0, block.bbox.y0, block.bbox.x1, block.bbox.y1] {
            assert!(
                (0.0..=1.0).contains(&value),
                "{} escaped the unit square",
                block.id
            );
        }
    }
}

#[test]
fn anchors_are_dense_and_stamped_from_the_page() {
    let pages = parse_bbox_layout(BBOX_FIXTURE).expect("fixture parses");
    // The empty block of page 1 carries no text and is dropped, so the ordinals
    // of the remaining blocks stay dense and the cue keeps ordinal 2.
    let ordinals: Vec<u32> = pages[0].blocks.iter().map(|b| b.id.block_ordinal).collect();
    assert_eq!(ordinals, vec![0, 1, 2]);
    assert_eq!(pages[0].blocks[2].id.to_string(), "P01.B02");
    assert!(pages[0].blocks.iter().all(|b| b.id.page_number == 1));
    assert!(pages[1].blocks.iter().all(|b| b.id.page_number == 2));
}

#[test]
fn a_document_without_a_page_element_is_a_validation_error() {
    let error = parse_bbox_layout("<html><body></body></html>").expect_err("no pages");
    assert!(matches!(error, DomainError::Validation { .. }));
    assert!(error.to_string().contains("no page element"));
}

#[test]
fn a_page_without_usable_size_falls_back_to_full_page_geometry() {
    let xml = r#"<doc><page width="0" height="0"><flow>
      <block xMin="10" yMin="10" xMax="20" yMax="20"><line><word>Hi</word></line></block>
    </flow></page></doc>"#;
    let pages = parse_bbox_layout(xml).expect("degenerate page still parses");
    assert!(!pages[0].has_geometry());
    assert_eq!(pages[0].blocks[0].bbox, NormalizedBBox::FULL_PAGE);
    assert_eq!(pages[0].blocks[0].text, "Hi");
}

#[test]
fn unknown_entities_are_preserved_verbatim() {
    // A verbatim `source_quote` check must not silently lose text to an entity
    // the decoder does not know.
    assert_eq!(decode_entities("a &foo; b"), "a &foo; b");
    assert_eq!(decode_entities("a &amp;lt; b"), "a &lt; b");
    assert_eq!(decode_entities("&#65;&#x42;&#xZZ;"), "AB&#xZZ;");
    assert_eq!(decode_entities("plain"), "plain");
    assert_eq!(decode_entities("dangling &"), "dangling &");
}

// ===========================================================================
// Adapter (needs the real poppler binary)
// ===========================================================================

/// A two-page PDF: page 1 carries a running header plus a scene heading, page 2
/// carries dialogue.
fn tiny_two_page_pdf() -> Vec<u8> {
    let mut pdf = b"%PDF-1.4\n".to_vec();
    let mut offsets = Vec::new();
    let mut add_object = |pdf: &mut Vec<u8>, object: String| {
        offsets.push(pdf.len());
        pdf.extend_from_slice(object.as_bytes());
    };
    add_object(
        &mut pdf,
        "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n".to_owned(),
    );
    add_object(
        &mut pdf,
        "2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>\nendobj\n".to_owned(),
    );
    for (number, contents) in [(3, 5), (4, 6)] {
        add_object(
            &mut pdf,
            format!(
                "{number} 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] \
                 /Resources << /Font << /F1 7 0 R >> >> /Contents {contents} 0 R >>\nendobj\n"
            ),
        );
    }
    let page_one = "BT /F1 10 Tf 61 760 Td (Block 098) Tj ET \
                    BT /F1 12 Tf 61 660 Td (1. INT. KITCHEN - DAY) Tj ET";
    let page_two = "BT /F1 12 Tf 61 600 Td (LEYLA) Tj ET";
    for (number, stream) in [(5, page_one), (6, page_two)] {
        add_object(
            &mut pdf,
            format!(
                "{number} 0 obj\n<< /Length {} >>\nstream\n{stream}\nendstream\nendobj\n",
                stream.len()
            ),
        );
    }
    add_object(
        &mut pdf,
        "7 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n".to_owned(),
    );
    let xref_offset = pdf.len();
    pdf.extend_from_slice(b"xref\n0 8\n0000000000 65535 f \n");
    for offset in offsets {
        pdf.extend_from_slice(format!("{offset:010} 00000 n \n").as_bytes());
    }
    pdf.extend_from_slice(
        format!("trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n").as_bytes(),
    );
    pdf
}

fn poppler_missing(error: &DomainError) -> bool {
    error.to_string().contains("could not start")
}

#[test]
fn the_fingerprint_names_the_spatial_algorithm() {
    let extractor = SpatialPdfExtractor::new(1024, Duration::from_secs(30));
    assert_eq!(extractor.parser_fingerprint(), "poppler-spatial-v1");
    assert_eq!(extractor.parser_fingerprint(), SPATIAL_PARSER_FINGERPRINT);
}

#[tokio::test]
async fn extract_rejects_an_empty_document() {
    let extractor = SpatialPdfExtractor::new(1024, Duration::from_secs(30));
    let error = extractor
        .extract(&[], ExtractionOptions::default())
        .await
        .expect_err("an empty document must not reach pdftotext");
    assert!(error.to_string().contains("must not be empty"));
}

#[tokio::test]
async fn extract_reports_invalid_content_as_a_validation_error() {
    let extractor = SpatialPdfExtractor::new(1024 * 1024, Duration::from_secs(30));
    let error = extractor
        .extract(b"not a pdf", ExtractionOptions::default())
        .await
        .expect_err("garbage must not extract");
    if poppler_missing(&error) {
        return;
    }
    assert!(matches!(error, DomainError::Validation { .. }));
}

#[tokio::test]
async fn extract_keeps_pages_and_the_header_band_of_a_real_pdf() {
    let extractor = SpatialPdfExtractor::new(4 * 1024 * 1024, Duration::from_secs(30));
    let document = match extractor
        .extract(&tiny_two_page_pdf(), ExtractionOptions::default())
        .await
    {
        Ok(document) => document,
        Err(error) if poppler_missing(&error) => return,
        Err(error) => panic!("spatial extraction failed: {error}"),
    };
    assert_eq!(document.parser_fingerprint, SPATIAL_PARSER_FINGERPRINT);
    assert_eq!(document.page_count(), 2, "one StructuredPage per PDF page");
    assert_eq!(document.pages[0].page_number, 1);
    assert_eq!(document.pages[1].page_number, 2);
    // PDF points survive: a 612x792 US-Letter box.
    assert!((document.pages[0].width_pt - 612.0).abs() < 0.5);
    assert!((document.pages[0].height_pt - 792.0).abs() < 0.5);
    let header = document
        .blocks()
        .find(|block| block.text.contains("Block 098"))
        .expect("the running header must survive extraction");
    assert_eq!(header.kind, BlockKind::PageHeader);
    assert!(header.bbox.is_header_band());
    let heading = document
        .blocks()
        .find(|block| block.text.contains("KITCHEN"))
        .expect("the scene heading must survive extraction");
    assert!(
        (heading.bbox.x0 - 0.1).abs() < 0.02,
        "x0 {}",
        heading.bbox.x0
    );
}

#[tokio::test]
async fn render_page_returns_a_bounded_png_for_one_page() {
    let extractor = SpatialPdfExtractor::new(4 * 1024 * 1024, Duration::from_secs(30));
    let pdf = tiny_two_page_pdf();
    let rendered = match extractor
        .render_page(&pdf, 2, RenderOptions::new(72, 2 * 1024 * 1024))
        .await
    {
        Ok(rendered) => rendered,
        Err(error) if poppler_missing(&error) => return,
        Err(error) => panic!("page render failed: {error}"),
    };
    assert_eq!(rendered.page_number, 2);
    assert!(rendered.png_bytes.starts_with(&[0x89, b'P', b'N', b'G']));
    assert!(rendered.png_bytes.len() < 2 * 1024 * 1024);
}

#[tokio::test]
async fn render_page_enforces_the_per_page_byte_ceiling() {
    let extractor = SpatialPdfExtractor::new(4 * 1024 * 1024, Duration::from_secs(30));
    let error = extractor
        .render_page(&tiny_two_page_pdf(), 1, RenderOptions::new(150, 16))
        .await
        .expect_err("a 16-byte ceiling cannot hold a PNG");
    if poppler_missing(&error) {
        return;
    }
    assert!(
        error.to_string().contains("exceeds the configured bound"),
        "unexpected: {error}"
    );
}

#[tokio::test]
async fn render_page_rejects_a_page_the_document_does_not_have() {
    let extractor = SpatialPdfExtractor::new(4 * 1024 * 1024, Duration::from_secs(30));
    let error = match extractor
        .render_page(&tiny_two_page_pdf(), 9, RenderOptions::default())
        .await
    {
        Ok(rendered) => panic!(
            "page 9 of a two-page document must not render, got {} bytes",
            rendered.png_bytes.len()
        ),
        Err(error) if poppler_missing(&error) => return,
        Err(error) => error,
    };
    assert!(matches!(error, DomainError::Validation { .. }));
}

// ===========================================================================
// Adapter → segmentation: a slug in the top band is scene content, not
// furniture (CodeRabbit review, issue #959).
// ===========================================================================

/// One page, `612x792` pt: the running header (`Block 098`, `Ep.: 294/1`) and a
/// scene slug all end inside the top band (`yMax <= 71.28` = 9 % of the height),
/// so `parse_bbox_layout` tags all three `PageHeader` by geometry alone.
const TOP_BAND_SLUG_FIXTURE: &str = r#"<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"><html xmlns="http://www.w3.org/1999/xhtml">
<body>
<doc>
  <page width="612.000000" height="792.000000">
    <flow>
      <block xMin="75.000000" yMin="26.000000" xMax="180.000000" yMax="38.000000">
        <line xMin="75.000000" yMin="26.000000" xMax="180.000000" yMax="38.000000">
          <word xMin="75.000000" yMin="26.000000" xMax="130.000000" yMax="38.000000">In</word>
          <word xMin="134.000000" yMin="26.000000" xMax="180.000000" yMax="38.000000">aller</word>
        </line>
      </block>
      <block xMin="475.000000" yMin="26.000000" xMax="551.000000" yMax="46.000000">
        <line xMin="475.000000" yMin="26.000000" xMax="551.000000" yMax="34.000000">
          <word xMin="475.000000" yMin="26.000000" xMax="551.000000" yMax="34.000000">Block</word>
          <word xMin="530.000000" yMin="26.000000" xMax="551.000000" yMax="34.000000">098</word>
        </line>
        <line xMin="475.000000" yMin="38.000000" xMax="551.000000" yMax="46.000000">
          <word xMin="475.000000" yMin="38.000000" xMax="540.000000" yMax="46.000000">Ep.:</word>
          <word xMin="543.000000" yMin="38.000000" xMax="551.000000" yMax="46.000000">294</word>
        </line>
      </block>
      <block xMin="61.000000" yMin="54.000000" xMax="520.000000" yMax="70.000000">
        <line xMin="61.000000" yMin="54.000000" xMax="520.000000" yMax="70.000000">
          <word xMin="61.000000" yMin="54.000000" xMax="75.000000" yMax="70.000000">12</word>
          <word xMin="80.000000" yMin="54.000000" xMax="104.000000" yMax="70.000000">A/T</word>
          <word xMin="108.000000" yMin="54.000000" xMax="118.000000" yMax="70.000000">-</word>
          <word xMin="122.000000" yMin="54.000000" xMax="250.000000" yMax="70.000000">MALERISCHER</word>
          <word xMin="254.000000" yMin="54.000000" xMax="390.000000" yMax="70.000000">BAUERNHOF</word>
        </line>
      </block>
      <block xMin="61.000000" yMin="120.000000" xMax="520.000000" yMax="160.000000">
        <line xMin="61.000000" yMin="120.000000" xMax="520.000000" yMax="134.000000">
          <word xMin="61.000000" yMin="120.000000" xMax="130.000000" yMax="134.000000">Leyla</word>
          <word xMin="134.000000" yMin="120.000000" xMax="180.000000" yMax="134.000000">steigt</word>
          <word xMin="184.000000" yMin="120.000000" xMax="215.000000" yMax="134.000000">aus</word>
          <word xMin="219.000000" yMin="120.000000" xMax="260.000000" yMax="134.000000">dem</word>
          <word xMin="264.000000" yMin="120.000000" xMax="300.000000" yMax="134.000000">Wagen</word>
        </line>
      </block>
    </flow>
  </page>
</doc>
</body>
</html>
"#;

#[test]
fn a_top_band_slug_from_the_bbox_parser_reaches_the_scene_scanner() {
    let pages = parse_bbox_layout(TOP_BAND_SLUG_FIXTURE).expect("fixture parses");
    // The premise: geometry alone cannot tell the slug from the running header.
    assert_eq!(pages[0].blocks[0].kind, BlockKind::PageHeader);
    assert_eq!(pages[0].blocks[1].kind, BlockKind::PageHeader);
    assert_eq!(
        pages[0].blocks[2].kind,
        BlockKind::PageHeader,
        "the slug ends inside the top band, so the adapter tags it a page header"
    );

    let document = StructuredDocument::new(SPATIAL_PARSER_FINGERPRINT, pages);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(segmented.chunks.len(), 1, "{:?}", segmented.chunks);
    assert_eq!(
        segmented.chunks[0].heading,
        "12 A/T - MALERISCHER BAUERNHOF"
    );
    assert_eq!(segmented.chunks[0].scene_number, Some(12));
    assert_eq!(segmented.chunks[0].mood.as_deref(), Some("A/T"));
    assert_eq!(segmented.chunks[0].text, "Leyla steigt aus dem Wagen");
    for leaked in ["Block", "098", "Ep.:", "aller Freundschaft"] {
        assert!(
            !segmented.chunks[0].text.contains(leaked),
            "running header leaked into the scene text: {:?}",
            segmented.chunks[0].text
        );
    }
}
