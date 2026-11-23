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
    BlockAnchor, BlockKind, CAST_SECTION_MAPPING, CastDirectory, CastDirectoryEntry,
    DEFAULT_MAX_RENDER_BYTES, DEFAULT_TARGET_DPI, DocumentBlock, DocumentZones, ExtractionOptions,
    FOOTER_BAND_MIN_Y0, HEADER_BAND_MAX_Y1, LineRole, NormalizedBBox, PageZone, RenderOptions,
    RenderedPage, StructuralPlan, StructuredDocument, StructuredPage, classify_document_zones,
    is_continuation_marker, normalize_kerning, parse_cast_directory_from_text, zoned_lines,
};
use crate::character::category::CharacterCategory;

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
    // Zero, negative, infinite and NaN page sizes all mean "this page carries
    // no usable geometry" — never a division by zero and never a bogus zero box.
    for (width, height) in [
        (0.0, 842.0),
        (595.0, 0.0),
        (-5.0, 842.0),
        (f32::NAN, 842.0),
        (f32::INFINITY, 842.0),
    ] {
        assert_eq!(
            NormalizedBBox::from_page_points(10.0, 10.0, 20.0, 20.0, width, height),
            NormalizedBBox::FULL_PAGE,
            "page size {width}x{height} should not normalize"
        );
    }
}

#[test]
fn bbox_from_page_points_rejects_inverted_edges() {
    // A reversed `yMin`/`yMax` pair would otherwise be BOTH a header candidate
    // and a footer candidate, and the spatial adapter's header branch runs
    // first — malformed geometry would be stored as `PageHeader`.
    let reversed_y = NormalizedBBox::from_page_points(10.0, 800.0, 20.0, 40.0, 595.0, 842.0);
    assert_eq!(reversed_y, NormalizedBBox::FULL_PAGE);
    assert!(!reversed_y.is_header_band());
    assert!(!reversed_y.is_footer_band());

    let reversed_x = NormalizedBBox::from_page_points(20.0, 10.0, 10.0, 20.0, 595.0, 842.0);
    assert_eq!(reversed_x, NormalizedBBox::FULL_PAGE);
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
    // Same finite-and-positive rule as `from_page_points`: an infinite page box
    // normalizes every block to `FULL_PAGE`, so it must not report geometry.
    assert!(!StructuredPage::new(1, f32::INFINITY, 842.0).has_geometry());
    assert!(!StructuredPage::new(1, 595.0, f32::NAN).has_geometry());
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

// ===========================================================================
// Pass 0 — page zoning and the structural anchor plan (ADR-041 D3/D4, #959)
// ===========================================================================

/// A page whose single block holds `text` in the body band.
fn text_page(page_number: u32, text: &str) -> StructuredPage {
    let mut page = StructuredPage::new(page_number, 595.0, 842.0);
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.12, 0.90, 0.85),
        text,
    );
    page
}

/// A stub heading detector for the zoning tests: an index/body heading is a line
/// that starts with digits (the `SCRIPT REPORT` and broadcast short form). The
/// real detector lives in `preview`; the zone pass takes it as a parameter, which
/// is exactly what lets this fixture run without a script parser.
fn is_heading(line: &str) -> bool {
    line.chars().next().is_some_and(|c| c.is_ascii_digit())
}

/// The observed broadcast layout: cover, cast list, `SCRIPT REPORT` index, two
/// `SYNOPSIS` pages, then the script body.
fn observed_broadcast_document() -> StructuredDocument {
    let mut title = StructuredPage::new(1, 595.0, 842.0);
    title.push_block(
        BlockKind::Heading,
        NormalizedBBox::new(0.15, 0.30, 0.85, 0.34),
        "MEDIZINISCHE FÄLLE",
    );
    title.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.15, 0.40, 0.85, 0.44),
        "Block 098 / Ep.: 292/1",
    );

    let cast = text_page(
        2,
        "PERSONEN/ HAUPTCAST\nDr. Koch\nLEYLA\nEPISODENHAUPTROLLEN\nJonas",
    );

    let mut index = text_page(
        3,
        "SCRIPT REPORT\n1 A/T - BAUERNHOF\nTag 1\n2 I/T - KLINIKUM\nTag 1",
    );
    index.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.10, 0.03, 0.60, 0.06),
        "Block 098 Ep.: 292/1",
    );

    let synopsis_one = text_page(
        4,
        "SYNOPSIS\nLeyla kehrt nach zwanzig Jahren in die Klinik zurück und trifft dort\nauf den Mann, der ihr Leben zerstört hat.",
    );
    let synopsis_two = text_page(
        5,
        "MEDIZINISCHE FÄLLE\nDie junge Ärztin übernimmt die Station und gerät zwischen die Fronten\nder beiden Chefärzte.",
    );

    let mut body = text_page(
        6,
        "1 A/T - BAUERNHOF\nLeyla steigt aus dem Wagen und blickt über den Hof.",
    );
    body.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.10, 0.03, 0.60, 0.06),
        "Block 098 Ep.: 292/1",
    );
    body.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.35, 0.40, 0.60, 0.44),
        "LEYLA\nJannis? Jannis!",
    );

    StructuredDocument::new(
        "poppler-spatial-v1",
        vec![title, cast, index, synopsis_one, synopsis_two, body],
    )
}

#[test]
fn an_observed_broadcast_layout_is_classified_page_by_page() {
    let document = observed_broadcast_document();
    let zones = classify_document_zones(&document, is_heading);
    let zones_of: Vec<PageZone> = zones.pages().iter().map(|page| page.zone).collect();
    assert_eq!(
        zones_of,
        vec![
            PageZone::TitlePage,
            PageZone::CastList,
            PageZone::SceneIndex,
            PageZone::FrontMatter,
            PageZone::FrontMatter,
            PageZone::ScriptBody,
        ],
        "the cover, the cast list, the index and the two synopsis pages must not be script prose"
    );
    assert!(zones.has_script_body());
    assert!(!zones.fell_back_to_script_body());
    assert_eq!(
        zones.page(3).and_then(|page| page.banner.as_deref()),
        Some("SCRIPT REPORT")
    );
}

#[test]
fn a_body_less_heading_page_is_an_index_even_without_a_banner() {
    // `>= 6` headings, no dialogue line, no full-length prose line.
    let mut index = StructuredPage::new(1, 595.0, 842.0);
    for scene in 1..=6_u32 {
        index.push_block(
            BlockKind::Paragraph,
            NormalizedBBox::new(0.10, 0.10, 0.60, 0.12),
            format!("{scene} A/T - ORT"),
        );
        index.push_block(
            BlockKind::Paragraph,
            NormalizedBBox::new(0.12, 0.13, 0.40, 0.15),
            "Tag 1",
        );
    }
    let document = StructuredDocument::new("t", vec![index]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(zones.zone_of(1), PageZone::SceneIndex);
    assert_eq!(zones.page(1).map(|page| page.heading_lines), Some(6));
}

#[test]
fn an_action_only_script_page_is_not_mistaken_for_an_index() {
    // Six short scenes with full action sentences and no dialogue: a body page,
    // NOT an index — and the distinction decides whether those scenes survive.
    let mut body = StructuredPage::new(1, 595.0, 842.0);
    for scene in 1..=6_u32 {
        body.push_block(
            BlockKind::Paragraph,
            NormalizedBBox::new(0.10, 0.10, 0.60, 0.12),
            format!("{scene} A/T - ORT"),
        );
        body.push_block(
            BlockKind::Paragraph,
            NormalizedBBox::new(0.10, 0.13, 0.90, 0.15),
            "Sie geht langsam über den Hof und bleibt vor der Tür stehen.",
        );
    }
    let document = StructuredDocument::new("t", vec![body]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(zones.zone_of(1), PageZone::ScriptBody);
}

#[test]
fn a_short_action_page_after_the_body_started_stays_script_body() {
    // CodeRabbit review: six short scenes whose action lines are shorter than
    // `PROSE_MIN_CHARS` (`Sie nickt.`) and that carry no dialogue are exactly the
    // shape the banner-less index rule looks for. ONCE THE SCRIPT RUNS, such a
    // page is a body page — reading it as an index drops all six scenes.
    let body = text_page(
        1,
        "1 A/T - BAUERNHOF\nLeyla steigt aus dem Wagen und blickt über den Hof.",
    );
    let mut short = StructuredPage::new(2, 595.0, 842.0);
    for scene in 2..=7_u32 {
        short.push_block(
            BlockKind::Paragraph,
            NormalizedBBox::new(0.10, 0.10, 0.60, 0.12),
            format!("{scene} A/T - ORT"),
        );
        short.push_block(
            BlockKind::Paragraph,
            NormalizedBBox::new(0.10, 0.13, 0.90, 0.15),
            "Sie nickt.",
        );
    }
    let document = StructuredDocument::new("t", vec![body, short]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(zones.zone_of(1), PageZone::ScriptBody);
    assert_eq!(
        zones.zone_of(2),
        PageZone::ScriptBody,
        "a short-action page after the script started is body prose, not an index"
    );
}

#[test]
fn a_signal_free_page_after_the_body_stays_script_body() {
    // A scene running over a page break: no heading, no banner — dropping it
    // would delete that scene's dialogue.
    let body = text_page(1, "1 A/T - BAUERNHOF\nLeyla steigt aus dem Wagen.");
    let continuation = text_page(2, "Sie blickt über den Hof und schweigt.");
    let document = StructuredDocument::new("t", vec![body, continuation]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(zones.zone_of(2), PageZone::ScriptBody);
}

#[test]
fn header_band_and_continuation_lines_never_reach_the_body() {
    let mut body = StructuredPage::new(1, 595.0, 842.0);
    body.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.10, 0.03, 0.60, 0.06),
        "Block 098 Ep.: 292/1",
    );
    body.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.12, 0.90, 0.40),
        "1 A/T - BAUERNHOF\nLeyla steigt aus.\n2 CONTINUED: (2)\nSie schweigt.",
    );
    body.push_block(
        BlockKind::PageFooter,
        NormalizedBBox::new(0.45, 0.95, 0.55, 0.97),
        "12",
    );
    let document = StructuredDocument::new("t", vec![body]);
    let zones = classify_document_zones(&document, is_heading);
    let lines = zoned_lines(&document, &zones, is_heading);
    let roles: Vec<(LineRole, &str)> = lines.iter().map(|line| (line.role, line.text)).collect();
    assert_eq!(
        roles,
        vec![
            (LineRole::Header, "Block 098 Ep.: 292/1"),
            (LineRole::Body, "1 A/T - BAUERNHOF"),
            (LineRole::Body, "Leyla steigt aus."),
            (LineRole::Continuation, "2 CONTINUED: (2)"),
            (LineRole::Body, "Sie schweigt."),
            (LineRole::Footer, "12"),
        ]
    );
    assert!(!lines[0].is_scene_prose());
    assert!(!lines[3].is_scene_prose());
    assert!(lines[1].is_scene_prose());
}

#[test]
fn continuation_markers_are_recognized_without_swallowing_prose() {
    for marker in [
        "2 CONTINUED:",
        "2 CONTINUED: (2)",
        "CONTINUED:",
        "12 FORTSETZUNG",
        "(2) CONTINUED",
        "  FORTSETZUNG  ",
    ] {
        assert!(is_continuation_marker(marker), "must strip {marker:?}");
    }
    for prose in [
        "Fortsetzung folgt.",
        "Sie sagt: continued tomorrow.",
        "2 CONTINUED INTO THE NIGHT",
        "",
        "Leyla kommt zurück.",
    ] {
        assert!(!is_continuation_marker(prose), "must keep {prose:?}");
    }
}

#[test]
fn a_top_band_scene_heading_is_not_page_furniture() {
    // CodeRabbit review: the bbox band alone turned a scene heading that ends
    // inside the running-header band (`y1 <= 0.09`) into a `Header` line, which is
    // excluded from prose — the scene would silently disappear. An adapter that
    // says `Heading` knows more than the band does.
    let mut page = StructuredPage::new(1, 595.0, 842.0);
    page.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.10, 0.03, 0.60, 0.05),
        "Block 098 Ep.: 292/1",
    );
    page.push_block(
        BlockKind::Heading,
        NormalizedBBox::new(0.10, 0.06, 0.90, 0.08),
        "1 A/T - BAUERNHOF",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.60, 0.06, 0.90, 0.08),
        "Seite 3",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.12, 0.90, 0.40),
        "Leyla steigt aus dem Wagen.",
    );
    let document = StructuredDocument::new("t", vec![page]);
    let zones = classify_document_zones(&document, is_heading);
    let lines = zoned_lines(&document, &zones, is_heading);
    let roles: Vec<(LineRole, &str)> = lines.iter().map(|line| (line.role, line.text)).collect();
    assert_eq!(
        roles,
        vec![
            (LineRole::Header, "Block 098 Ep.: 292/1"),
            (LineRole::Body, "1 A/T - BAUERNHOF"),
            // A `Paragraph` in the same band stays furniture: the exemption is
            // for structured headings only.
            (LineRole::Header, "Seite 3"),
            (LineRole::Body, "Leyla steigt aus dem Wagen."),
        ]
    );
    assert!(
        lines[1].is_scene_prose(),
        "the top-band slug must reach the scene scanner"
    );
    assert_eq!(zones.page(1).map(|page| page.heading_lines), Some(1));
    assert_eq!(zones.zone_of(1), PageZone::ScriptBody);
}

#[test]
fn a_sentence_starting_with_cast_opens_no_cast_list() {
    // CodeRabbit review: `CAST` matched as a line PREFIX, so `"Cast the net before
    // sunrise."` — the first line of a script page — zoned the page `CastList`,
    // which removes it from scene prose entirely.
    let body = text_page(
        1,
        "1 A/T - BAUERNHOF\nLeyla steigt aus dem Wagen und blickt über den Hof.",
    );
    let prose = text_page(
        2,
        "Cast the net before sunrise.\nLeyla geht langsam über den Hof und bleibt vor der Tür stehen.",
    );
    let document = StructuredDocument::new("t", vec![body.clone(), prose.clone()]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(zones.zone_of(2), PageZone::ScriptBody);
    assert_eq!(zones.page(2).and_then(|page| page.banner.as_deref()), None);

    // A front-matter keyword inside a sentence is prose too.
    let mixed = text_page(2, "Wie in der Synopsis beschrieben geht sie über den Hof.");
    let document = StructuredDocument::new("t", vec![body.clone(), mixed]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(zones.page(2).and_then(|page| page.banner.as_deref()), None);

    // UPPERCASE prose is still prose: a shouty action line is not rare in a
    // broadcast script, and it must not cost the page its scenes.
    for shouty_prose in [
        "CAST THE NET BEFORE SUNRISE.",
        "CAST THE NET",
        // Two words only: a word cap cannot separate this from a section
        // heading — the vocabulary check does.
        "CAST OFF!",
        "CAST THE LINE, LEYLA!",
        "SYNOPSIS DER FOLGE: LEYLA KOMMT ZURÜCK",
    ] {
        let shouty = text_page(2, shouty_prose);
        let document = StructuredDocument::new("t", vec![body.clone(), shouty]);
        let zones = classify_document_zones(&document, is_heading);
        assert_eq!(
            zones.page(2).and_then(|page| page.banner.as_deref()),
            None,
            "{shouty_prose:?} is a sentence, not a section heading"
        );
        assert_eq!(
            zones.zone_of(2),
            PageZone::ScriptBody,
            "{shouty_prose:?} must not remove the page from scene prose"
        );
    }
}

#[test]
fn an_all_caps_section_opening_still_opens_the_cast_list() {
    // The counterpart: a shouty section heading is a banner wherever it sits — it
    // is neither the page's first line nor in the header band here.
    let body = text_page(
        1,
        "1 A/T - BAUERNHOF\nLeyla steigt aus dem Wagen und blickt über den Hof.",
    );
    let cast = text_page(
        2,
        "Dr. Leyla Sherbaz (44)\nDr. Matteo Moreau (44)\nKOMPARSEN\nJonas Hauser",
    );
    let document = StructuredDocument::new("t", vec![body.clone(), cast]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(zones.zone_of(2), PageZone::CastList);
    assert_eq!(
        zones.page(2).and_then(|page| page.banner.as_deref()),
        Some("KOMPARSEN")
    );

    // Section vocabulary with a connective and a separator is still a banner.
    for banner in ["PERSONEN UND HAUPTCAST", "PERSONEN/ HAUPTCAST", "CAST:"] {
        let page = text_page(2, &format!("{banner}\nDr. Koch\nLEYLA"));
        let document = StructuredDocument::new("t", vec![body.clone(), page]);
        let zones = classify_document_zones(&document, is_heading);
        assert_eq!(
            zones.zone_of(2),
            PageZone::CastList,
            "{banner:?} is a section heading"
        );
    }
}

#[test]
fn a_document_without_a_script_page_widens_instead_of_losing_every_scene() {
    // Unfamiliar template: only front-matter banners. Widening is the honest
    // degradation (the VLM structural pass of #960 is the real fallback).
    let front = text_page(
        1,
        "SYNOPSIS\nIrgendein anderer Aufbau ohne erkennbare Szenen.",
    );
    let rest = text_page(2, "Und noch ein Absatz Prosa ohne Kopfzeile.");
    let mut document = StructuredDocument::new("t", vec![front, rest]);
    let zones = classify_document_zones(&document, |_| false);
    assert!(!zones.has_script_body());

    let mut widened = zones.clone();
    widened.widen_to_script_body();
    assert!(widened.has_script_body());
    assert!(widened.fell_back_to_script_body());
    assert_eq!(widened.zone_of(2), PageZone::ScriptBody);

    // Line roles are unaffected by widening: a banner is still a banner.
    document.pages[0].push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.50, 0.90, 0.52),
        "1 CONTINUED:",
    );
    let lines = zoned_lines(&document, &widened, is_heading);
    assert!(lines.iter().any(|line| line.role == LineRole::Continuation));
}

#[test]
fn the_plan_renders_canonically_and_rejects_non_ascending_anchors() {
    let document = observed_broadcast_document();
    let zones = classify_document_zones(&document, is_heading);
    let mut plan = StructuralPlan::from_zones(&zones);
    assert_eq!(
        plan.canonical_form(),
        "P01|title_page|\nP02|cast_list|\nP03|scene_index|\nP04|front_matter|\n\
         P05|front_matter|\nP06|script_body|\n"
    );
    assert!(plan.record_anchor(BlockAnchor::new(6, 1)));
    assert!(plan.record_anchor(BlockAnchor::new(6, 3)));
    // A duplicate and a descending anchor would make the canonical form
    // ambiguous, so both are refused rather than silently reordered.
    assert!(!plan.record_anchor(BlockAnchor::new(6, 3)));
    assert!(!plan.record_anchor(BlockAnchor::new(6, 2)));
    // A page the pass never saw cannot be anchored.
    assert!(!plan.record_anchor(BlockAnchor::new(99, 0)));
    assert_eq!(
        plan.canonical_form(),
        "P01|title_page|\nP02|cast_list|\nP03|scene_index|\nP04|front_matter|\n\
         P05|front_matter|\nP06|script_body|P06.B01,P06.B03\n"
    );
    assert_eq!(plan.canonical_form(), plan.canonical_form());
}

// ---------------------------------------------------------------------------
// Regressions the real broadcast corpus (294.pdf et al.) produced
// ---------------------------------------------------------------------------

#[test]
fn a_script_report_running_header_names_the_index_page() {
    // The real banner is a RUNNING HEADER, not a section heading:
    // `BL98/294-SCRIPT REPORT` / `DJÄ_BL98_294_DREH210805 -- SCRIPT REPORT  2`.
    // A prefix match missed both, every index entry then parsed as a scene and
    // the preview doubled — measured against the corpus before this fix.
    let mut index = StructuredPage::new(3, 595.0, 842.0);
    index.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.05, 0.03, 0.60, 0.05),
        "BL98/294-SCRIPT REPORT",
    );
    index.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.05, 0.10, 0.90, 0.40),
        "1 A/T - MALERISCHER BAUERNHOF\nTag 1\n2 I/T - KLINIKUM / EINGANG\nTag 1",
    );
    let document = StructuredDocument::new("t", vec![index]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(
        zones.zone_of(3),
        PageZone::SceneIndex,
        "the running-header banner must be read from the header band"
    );
    assert_eq!(
        zones.page(3).and_then(|page| page.banner.as_deref()),
        Some("SCRIPT REPORT")
    );
}

#[test]
fn a_phrase_in_mid_page_prose_never_relabels_the_page() {
    // The anywhere-match is restricted to a banner slot: a line deep inside the
    // script that merely mentions the phrase must not turn a scene page into an
    // index (which would delete its scenes).
    let body = text_page(
        1,
        "1 A/T - BAUERNHOF\nLEYLA\nLaut SCRIPT REPORT fehlt hier eine Szene, oder?",
    );
    let document = StructuredDocument::new("t", vec![body]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(zones.zone_of(1), PageZone::ScriptBody);
}

#[test]
fn a_centred_cover_page_is_the_title_page_not_prose() {
    // A cover page's centred title block sits in exactly the columns a character
    // cue occupies (`x0` around 0.30), so an indentation-based dialogue signal
    // alone classified the title page of every real script as script prose.
    let mut cover = StructuredPage::new(1, 595.0, 842.0);
    cover.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.30, 0.10, 0.70, 0.12),
        "(294) \"Freundschaft\"",
    );
    cover.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.32, 0.20, 0.68, 0.22),
        "Eine Serie für den ARD-Vorabend",
    );
    cover.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.30, 0.30, 0.70, 0.32),
        "von Laura Wagner",
    );
    let document = StructuredDocument::new("t", vec![cover]);
    let zones = classify_document_zones(&document, is_heading);
    assert_eq!(zones.zone_of(1), PageZone::TitlePage);
    assert_eq!(zones.page(1).map(|page| page.heading_lines), Some(0));
}

#[test]
fn synopsis_continuation_pages_between_cover_and_body_are_front_matter() {
    // The real layout puts five or six `SYNOPSIS` / `MEDIZINISCHE FÄLLE` pages
    // between the index and the first scene, and only the first of them carries
    // the banner. Without a heading none of them may become script prose — that
    // is the six-page contamination of the last scene this issue exists for.
    let cover = text_page(1, "Block: 098/Ep.: 294");
    let index = text_page(2, "SCRIPT REPORT\n1 A/T - ORT\nTag 1");
    let synopsis = text_page(
        3,
        "SYNOPSIS\nLeyla kehrt nach zwanzig Jahren in die Klinik zurück und trifft dort auf den Mann, der ihr Leben zerstört hat.",
    );
    let continuation = text_page(
        4,
        "furchtbare Sorgen. Als ihr Telefon klingelt, streckt sie sich danach, in der Hoffnung, es sei ihr Bruder.",
    );
    let medical = text_page(
        5,
        "MEDIZINISCHE FÄLLE\nMEERA HAUSER (18): Oberschenkelbruch mit Arterienverletzung, gebrochene Rippen, Lungenkontusion.",
    );
    let mut body = StructuredPage::new(6, 595.0, 842.0);
    body.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.12, 0.90, 0.40),
        "1 A/T - MALERISCHER BAUERNHOF\nLeyla steigt aus dem Wagen und blickt über den Hof.",
    );
    body.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.35, 0.45, 0.60, 0.47),
        "LEYLA\nJannis?",
    );
    let document = StructuredDocument::new(
        "t",
        vec![cover, index, synopsis, continuation, medical, body],
    );
    let zones = classify_document_zones(&document, is_heading);
    let zones_of: Vec<PageZone> = zones.pages().iter().map(|page| page.zone).collect();
    assert_eq!(
        zones_of,
        vec![
            PageZone::TitlePage,
            PageZone::SceneIndex,
            PageZone::FrontMatter,
            PageZone::FrontMatter,
            PageZone::FrontMatter,
            PageZone::ScriptBody,
        ]
    );
}

#[test]
fn a_uniform_zone_verdict_has_no_counters() {
    let zones = DocumentZones::uniform(2, PageZone::ScriptBody);
    assert_eq!(zones.pages().len(), 2);
    assert!(zones.has_script_body());
    assert!(!zones.fell_back_to_script_body());
    assert_eq!(zones.page(1).map(|page| page.heading_lines), Some(0));
    // A page outside the document is treated as prose, never dropped.
    assert_eq!(zones.zone_of(7), PageZone::ScriptBody);
}

#[test]
fn cast_sections_split_comma_lists_and_record_inline_ot() {
    let text = "PERSONEN/ HAUPTCAST\nDr. Leyla Sherbaz (44)\nEPISODENHAUPTROLLEN\nJonas Weber (8, OT)\nCROSS\nDr. Kai Hoffmann\nKOMPARSEN\nHeiko Neubert, Anna Schmidt (MT)\n";
    let directory = parse_cast_directory_from_text(text, |_| false);
    assert_eq!(directory.entries.len(), 5);
    let jonas = directory
        .entries
        .iter()
        .find(|entry| entry.normalized_identity == "jonas weber")
        .expect("the episodic lead is a cast entry");
    assert_eq!(jonas.declared_category, CharacterCategory::Guest);
    assert_eq!(jonas.raw_section, "EPISODENHAUPTROLLEN");
    assert!(jonas.inline_ot);
    assert_eq!(jonas.canonical_name, "Jonas Weber");
    let heiko = directory
        .entries
        .iter()
        .find(|entry| entry.canonical_name == "Heiko Neubert")
        .expect("the first comma-separated extra is its own entry");
    assert_eq!(heiko.declared_category, CharacterCategory::Extra);
    assert!(!heiko.inline_ot);
    assert!(
        directory
            .entries
            .iter()
            .any(|entry| entry.canonical_name == "Anna Schmidt")
    );
    let kai = directory
        .entries
        .iter()
        .find(|entry| entry.canonical_name == "Dr. Kai Hoffmann")
        .expect("CROSS is a guest section");
    assert_eq!(kai.declared_category, CharacterCategory::Guest);
    assert!(
        CAST_SECTION_MAPPING
            .iter()
            .any(|(header, category)| *header == "EXTRAS" && *category == CharacterCategory::Extra)
    );
}

#[test]
fn kerning_normalization_is_dictionary_gated_and_never_spellchecks_prose() {
    let directory = CastDirectory::new(vec![CastDirectoryEntry {
        canonical_name: "Mikko Rantala".to_owned(),
        normalized_identity: "mikko rantala".to_owned(),
        declared_category: CharacterCategory::MainCast,
        raw_section: "PERSONEN".to_owned(),
        inline_ot: false,
    }]);
    let split = "Mik k o Rantala geht langsam. Der Arzt hilft.";
    assert_eq!(
        normalize_kerning(split, &directory),
        "Mikko Rantala geht langsam. Der Arzt hilft."
    );
    assert_eq!(normalize_kerning(split, &CastDirectory::default()), split);
}
