// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Spatial PDF adapter: Poppler `pdftotext -bbox-layout` (ADR-041 `D1`, issue
//! #958).
//!
//! `pdftotext -layout` throws away exactly what a screenplay encodes: the page
//! box, the running-header band and the horizontal indentation column of a
//! character cue versus dialogue. `-bbox-layout` keeps all of it as XHTML —
//! `<page width= height=>`, `<block xMin= yMin= xMax= yMax=>`, `<line>`,
//! `<word>` — which this adapter turns into the canonical
//! [`StructuredDocument`] with normalized `0.0..=1.0` geometry.
//!
//! Same subprocess discipline as the flat-text adapter (stdin in, bounded
//! stdout out, timeout with kill+reap); page images are *not* produced here
//! either — [`DocumentStructureExtractor::render_page`] renders one page on
//! demand so a page-streaming caller (issue #960) never holds a document's
//! worth of PNGs.

use std::time::Duration;

use breakdown_core::ai::{
    BlockKind, DocumentStructureExtractor, ExtractionOptions, NormalizedBBox, RenderOptions,
    RenderedPage, StructuredDocument, StructuredPage,
};
use breakdown_core::error::DomainError;

use super::markup::decode_entities;
use super::subprocess::{render_page_png, run_bounded};

#[cfg(test)]
#[path = "spatial_pdf_tests.rs"]
mod spatial_pdf_tests;

/// Stable identifier of the spatial algorithm (ADR-041 `D7`).
pub const SPATIAL_PARSER_FINGERPRINT: &str = "poppler-spatial-v1";

/// Bounded spatial PDF adapter: `pdftotext -bbox-layout` for structure,
/// `pdftocairo` for on-demand page renders. PDF bytes travel through stdin, so
/// no temporary document is ever persisted.
///
/// `Copy` on purpose — two machine words of configuration held **by value** by
/// whoever needs it. Never wrap it in an `Arc`: there is no shared state.
#[derive(Clone, Copy, Debug)]
pub struct SpatialPdfExtractor {
    /// Ceiling for the `-bbox-layout` XHTML. A word-level dump of a 100-page
    /// script is a few MiB, so this must scale with `AI_IMPORT_MAX_DOCUMENT_BYTES`
    /// rather than with the old flat-text ceiling.
    pub max_output_bytes: usize,
    pub timeout: Duration,
}

impl SpatialPdfExtractor {
    #[must_use]
    pub const fn new(max_output_bytes: usize, timeout: Duration) -> Self {
        Self {
            max_output_bytes,
            timeout,
        }
    }

    /// The raw `-bbox-layout` XHTML, kept as a named seam for diagnostics.
    pub async fn extract_bbox_xml(&self, pdf_bytes: &[u8]) -> Result<String, DomainError> {
        if pdf_bytes.is_empty() {
            return Err(DomainError::validation("PDF document must not be empty"));
        }
        let output = run_bounded(
            "pdftotext",
            &["-q", "-bbox-layout", "-", "-"],
            pdf_bytes,
            self.max_output_bytes,
            self.timeout,
        )
        .await?;
        String::from_utf8(output).map_err(|error| {
            DomainError::validation(format!("pdftotext emitted invalid UTF-8: {error}"))
        })
    }
}

impl DocumentStructureExtractor for SpatialPdfExtractor {
    fn parser_fingerprint(&self) -> &'static str {
        SPATIAL_PARSER_FINGERPRINT
    }

    async fn extract(
        &self,
        bytes: &[u8],
        _options: ExtractionOptions,
    ) -> Result<StructuredDocument, DomainError> {
        let xml = self.extract_bbox_xml(bytes).await?;
        Ok(StructuredDocument::new(
            SPATIAL_PARSER_FINGERPRINT,
            parse_bbox_layout(&xml)?,
        ))
    }

    async fn render_page(
        &self,
        bytes: &[u8],
        page_number: u32,
        options: RenderOptions,
    ) -> Result<RenderedPage, DomainError> {
        if bytes.is_empty() {
            return Err(DomainError::validation("PDF document must not be empty"));
        }
        let png_bytes = render_page_png(
            bytes,
            page_number,
            options.target_dpi,
            options.max_bytes,
            self.timeout,
        )
        .await?;
        Ok(RenderedPage::new(page_number, png_bytes))
    }
}

// ===========================================================================
// `-bbox-layout` XHTML parsing
// ===========================================================================
//
// Hand-rolled on purpose: the document is machine-generated XHTML with a tiny,
// fixed element set (`page`/`flow`/`block`/`line`/`word`), so a pull parser
// dependency would buy robustness this input cannot need while adding a crate
// to the ban list review. The parser is total (never panics): an unparsable
// element is skipped, and a document with no page at all is a validation error
// — that is a real extraction failure, not an empty document.

/// Parse `pdftotext -bbox-layout` XHTML into pages with normalized geometry.
///
/// Block kinds are classified from the vertical band alone: this format carries
/// no semantic markup (unlike Docling's HTML), so a block in the top band is a
/// [`BlockKind::PageHeader`], one in the bottom band a
/// [`BlockKind::PageFooter`], everything else a [`BlockKind::Paragraph`].
/// `Table`/`ListItem` require markup this adapter cannot see — inventing them
/// from box geometry would be a guess presented as a fact.
pub fn parse_bbox_layout(xml: &str) -> Result<Vec<StructuredPage>, DomainError> {
    let mut pages = Vec::new();
    let mut rest = xml;
    while let Some(page_start) = rest.find("<page") {
        let Some(open_end) = rest[page_start..].find('>') else {
            break;
        };
        let open_tag = &rest[page_start..page_start + open_end];
        let body_start = page_start + open_end + 1;
        let body = &rest[body_start..];
        let body_len = body.find("</page>").unwrap_or(body.len());
        let page_body = &body[..body_len];

        let width_pt = tag_f32(open_tag, "width").unwrap_or(0.0);
        let height_pt = tag_f32(open_tag, "height").unwrap_or(0.0);
        let page_number = u32::try_from(pages.len())
            .unwrap_or(u32::MAX)
            .saturating_add(1);
        let mut page = StructuredPage::new(page_number, width_pt, height_pt);
        parse_blocks_into(&mut page, page_body);
        pages.push(page);

        rest = &body[body_len.min(body.len())..];
    }

    if pages.is_empty() {
        return Err(DomainError::validation(
            "pdftotext -bbox-layout returned no page element",
        ));
    }
    Ok(pages)
}

/// Parse the `<block>` elements of one `<page>` body into that page.
///
/// Blocks are appended through [`StructuredPage::push_block`], so their
/// `block_ordinal` is the vector index by construction and cannot disagree with
/// a persisted anchor plan.
fn parse_blocks_into(page: &mut StructuredPage, page_body: &str) {
    let width_pt = page.width_pt;
    let height_pt = page.height_pt;
    let mut rest = page_body;
    while let Some(block_start) = rest.find("<block") {
        let Some(open_end) = rest[block_start..].find('>') else {
            break;
        };
        let open_tag = &rest[block_start..block_start + open_end];
        let body = &rest[block_start + open_end + 1..];
        let body_len = body.find("</block>").unwrap_or(body.len());
        let block_body = &body[..body_len];

        let x0 = tag_f32(open_tag, "xMin").unwrap_or(0.0);
        let y0 = tag_f32(open_tag, "yMin").unwrap_or(0.0);
        let x1 = tag_f32(open_tag, "xMax").unwrap_or(width_pt);
        let y1 = tag_f32(open_tag, "yMax").unwrap_or(height_pt);
        let bbox = NormalizedBBox::from_page_points(x0, y0, x1, y1, width_pt, height_pt);
        let text = block_text(block_body);
        if text.trim().is_empty() {
            // An empty block carries no text for any downstream pass and would
            // only shift the `block_ordinal` of its neighbours.
            rest = &body[body_len.min(body.len())..];
            continue;
        }
        let kind = if bbox.is_header_band() {
            BlockKind::PageHeader
        } else if bbox.is_footer_band() {
            BlockKind::PageFooter
        } else {
            BlockKind::Paragraph
        };
        page.push_block(kind, bbox, text);
        rest = &body[body_len.min(body.len())..];
    }
}

/// One block's text: words joined by a space, lines joined by a newline.
fn block_text(block_body: &str) -> String {
    let mut lines: Vec<String> = Vec::new();
    let mut rest = block_body;
    while let Some(line_start) = rest.find("<line") {
        let Some(open_end) = rest[line_start..].find('>') else {
            break;
        };
        let body = &rest[line_start + open_end + 1..];
        let body_len = body.find("</line>").unwrap_or(body.len());
        let line = words_in_line(&body[..body_len]);
        if !line.is_empty() {
            lines.push(line);
        }
        rest = &body[body_len.min(body.len())..];
    }
    lines.join("\n")
}

/// One line's words joined by a space.
fn words_in_line(line: &str) -> String {
    let mut words: Vec<String> = Vec::new();
    let mut rest = line;
    while let Some(word_start) = rest.find("<word") {
        let Some(open_end) = rest[word_start..].find('>') else {
            break;
        };
        let body = &rest[word_start + open_end + 1..];
        let Some(close) = body.find("</word>") else {
            break;
        };
        let word = decode_entities(&body[..close]);
        if !word.trim().is_empty() {
            words.push(word.trim().to_owned());
        }
        rest = &body[close + "</word>".len()..];
    }
    words.join(" ")
}

/// Read one float attribute (`width="612.000000"`) from an element's open tag.
fn tag_f32(tag: &str, name: &str) -> Option<f32> {
    let value = tag_str(tag, name)?;
    value
        .parse::<f32>()
        .ok()
        .filter(|parsed| parsed.is_finite())
}

/// Read one string attribute from an element's open tag.
fn tag_str<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
    let needle = format!("{name}=\"");
    let start = tag.find(&needle)? + needle.len();
    let rest = &tag[start..];
    let end = rest.find('"')?;
    Some(&rest[..end])
}
