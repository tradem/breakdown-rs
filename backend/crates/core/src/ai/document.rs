// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Canonical document-structure IR (ADR-041 `D1`, issue #958).
//!
//! The IR is how `core` reasons about an uploaded script or shooting schedule
//! **after** a [`DocumentStructureExtractor`](super::ports::DocumentStructureExtractor)
//! has read it and **before** any LLM call: pages with their physical size,
//! reading-order blocks with normalized geometry, and the block's verbatim
//! text. It is deliberately free of infrastructure types — no subprocess
//! handles, no HTTP clients, no `sqlx` — so the zoning (`D3`), cast-directory
//! (`D5`) and schedule (`D6`) passes that consume it stay pure domain logic.
//!
//! Two properties are load-bearing and must not be "optimized away":
//!
//! * **Normalized geometry (`0.0..=1.0`).** Screenplay semantics live in the
//!   layout: scene headings and action sit at the left margin, character cues
//!   are centered, dialogue is indented, and running headers occupy the top
//!   band. A flat string throws those columns away, so the bbox is preserved
//!   even though the text is what a prompt finally reads.
//! * **No page images.** The IR carries text and geometry only; images come
//!   from the port's on-demand `render_page`, so a page-by-page caller retains
//!   one page's bytes instead of a whole document's (ADR-041 `D1`).

use std::fmt;

/// Structural role of one [`DocumentBlock`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BlockKind {
    /// Running header band (`"Block 098"`, `"Ep.: 292/1"`, `"<N> CONTINUED:"`).
    PageHeader,
    /// Footer band, typically the page number.
    PageFooter,
    /// Section heading (`"SYNOPSIS"`, `"SCRIPT REPORT"`, an `INT./EXT.` slug).
    Heading,
    /// Body prose or dialogue.
    Paragraph,
    /// Tabular block; [`DocumentBlock::html_table`] carries the markup.
    Table,
    /// One list item of an enumerated block.
    ListItem,
}

impl BlockKind {
    /// Stable wire/log spelling. Used by the persisted structural anchor plan
    /// (issue #959) so a plan digest never depends on `Debug` formatting.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::PageHeader => "page_header",
            Self::PageFooter => "page_footer",
            Self::Heading => "heading",
            Self::Paragraph => "paragraph",
            Self::Table => "table",
            Self::ListItem => "list_item",
        }
    }
}

/// Address of one block inside a [`StructuredDocument`]: page number (1-based)
/// plus the block's ordinal on that page (0-based, reading order).
///
/// Renders as `P04.B03`, which is what the structural anchor plan (issue #959)
/// persists and what a chunk boundary names.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct BlockAnchor {
    pub page_number: u32,
    pub block_ordinal: u32,
}

impl BlockAnchor {
    #[must_use]
    pub const fn new(page_number: u32, block_ordinal: u32) -> Self {
        Self {
            page_number,
            block_ordinal,
        }
    }
}

impl fmt::Display for BlockAnchor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "P{:02}.B{:02}", self.page_number, self.block_ordinal)
    }
}

/// Axis-aligned block geometry, normalized against its page and clamped to
/// `0.0..=1.0`.
///
/// `x0` is the indentation signal (`0.10..0.15` margin, `0.35..0.45` character
/// cue, `0.25..0.32` dialogue), `y0`/`y1` separate the running-header band
/// (`y1 <= 0.09`) and the footer band (`y0 >= 0.91`) from the body.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NormalizedBBox {
    pub x0: f32,
    pub y0: f32,
    pub x1: f32,
    pub y1: f32,
}

impl NormalizedBBox {
    /// The whole page — the honest geometry for an extractor that has no
    /// spatial data (flat text, HTML from an HTTP sidecar).
    pub const FULL_PAGE: Self = Self {
        x0: 0.0,
        y0: 0.0,
        x1: 1.0,
        y1: 1.0,
    };

    /// Build a box from already-normalized coordinates, clamping each edge into
    /// `0.0..=1.0`. Non-finite inputs collapse to `0.0` — a NaN must never
    /// reach a comparison that decides a zone.
    #[must_use]
    pub fn new(x0: f32, y0: f32, x1: f32, y1: f32) -> Self {
        Self {
            x0: clamp_unit(x0),
            y0: clamp_unit(y0),
            x1: clamp_unit(x1),
            y1: clamp_unit(y1),
        }
    }

    /// Normalize page-space points (`pdftotext -bbox-layout` reports PDF points)
    /// against the page size.
    ///
    /// A page whose width or height is not a usable positive number (a
    /// malformed `<page>` element, a degenerate PDF) yields
    /// [`Self::FULL_PAGE`]: the caller learns that this page carries no usable
    /// geometry rather than a bogus zero box, and nothing divides by zero.
    ///
    /// A box with inverted edges (`x1 < x0` or `y1 < y0`) also yields
    /// [`Self::FULL_PAGE`]. [`Self::new`] clamps but cannot un-invert, and an
    /// inverted box satisfies *both* band predicates at once (`y0 = 0.95`,
    /// `y1 = 0.05`), so keeping it would classify malformed geometry as a page
    /// header instead of falling back to body text.
    #[must_use]
    pub fn from_page_points(
        x0: f32,
        y0: f32,
        x1: f32,
        y1: f32,
        width_pt: f32,
        height_pt: f32,
    ) -> Self {
        if !usable_dimension(width_pt) || !usable_dimension(height_pt) {
            return Self::FULL_PAGE;
        }
        if x1 < x0 || y1 < y0 {
            return Self::FULL_PAGE;
        }
        Self::new(x0 / width_pt, y0 / height_pt, x1 / width_pt, y1 / height_pt)
    }

    /// Normalized width.
    #[must_use]
    pub fn width(self) -> f32 {
        (self.x1 - self.x0).max(0.0)
    }

    /// Normalized height.
    #[must_use]
    pub fn height(self) -> f32 {
        (self.y1 - self.y0).max(0.0)
    }

    /// Whether this block ends inside the running-header band.
    #[must_use]
    pub fn is_header_band(self) -> bool {
        self.y1 <= HEADER_BAND_MAX_Y1
    }

    /// Whether this block starts inside the footer band.
    #[must_use]
    pub fn is_footer_band(self) -> bool {
        self.y0 >= FOOTER_BAND_MIN_Y0
    }
}

impl Default for NormalizedBBox {
    fn default() -> Self {
        Self::FULL_PAGE
    }
}

/// Normalized `y1` ceiling of the running-header band.
///
/// Broadcast scripts print their running header (`"Block 098"`, `"Ep.: 292/1"`,
/// `"<N> CONTINUED:"`) in the top ~6 % of the page; a block that *ends* above
/// this line is a header candidate, one that merely starts there is body text
/// with a tight leading. Shared with the zoning pass (issue #959) so header
/// stripping and header classification cannot drift apart.
pub const HEADER_BAND_MAX_Y1: f32 = 0.09;

/// Normalized `y0` floor of the footer band (mirror of [`HEADER_BAND_MAX_Y1`]).
pub const FOOTER_BAND_MIN_Y0: f32 = 0.91;

fn clamp_unit(value: f32) -> f32 {
    if value.is_finite() {
        value.clamp(0.0, 1.0)
    } else {
        0.0
    }
}

/// Whether a page dimension can be measured against.
///
/// Shared by [`NormalizedBBox::from_page_points`] and
/// [`StructuredPage::has_geometry`] so "this page has real geometry" and "this
/// block can be normalized" cannot disagree: an infinite width is not
/// measurable, and a box normalized against it is [`NormalizedBBox::FULL_PAGE`],
/// not a measured coordinate.
fn usable_dimension(value: f32) -> bool {
    value.is_finite() && value > f32::EPSILON
}

/// One reading-order block of a page: its address, role, geometry and verbatim
/// text.
#[derive(Debug, Clone, PartialEq)]
pub struct DocumentBlock {
    pub id: BlockAnchor,
    pub kind: BlockKind,
    pub bbox: NormalizedBBox,
    /// Verbatim UTF-8 text of the block. Downstream passes slice this text —
    /// they never ask a model to re-transcribe it (ADR-041 `D3`/`D4`), which is
    /// what keeps `verify_draft_outfits`' verbatim `source_quote` check honest.
    pub text: String,
    /// Original `<table>` markup including `colspan`/`rowspan`, when the
    /// extractor could preserve it. `None` for every non-`Table` block.
    pub html_table: Option<String>,
}

impl DocumentBlock {
    /// A plain text block with no table markup.
    #[must_use]
    pub fn text(
        id: BlockAnchor,
        kind: BlockKind,
        bbox: NormalizedBBox,
        text: impl Into<String>,
    ) -> Self {
        Self {
            id,
            kind,
            bbox,
            text: text.into(),
            html_table: None,
        }
    }

    /// Whether the block carries no characters at all.
    #[must_use]
    pub fn is_blank(&self) -> bool {
        self.text.trim().is_empty()
    }
}

/// One page of the source document.
#[derive(Debug, Clone, PartialEq)]
pub struct StructuredPage {
    /// 1-based page number, matching the PDF readers and `pdftoppm -f/-l`.
    pub page_number: u32,
    /// Page width in PDF points (`0.0` when the extractor has no geometry).
    pub width_pt: f32,
    /// Page height in PDF points (`0.0` when the extractor has no geometry).
    pub height_pt: f32,
    /// Blocks in reading order; `block_ordinal` is the index into this vector.
    pub blocks: Vec<DocumentBlock>,
}

impl StructuredPage {
    #[must_use]
    pub fn new(page_number: u32, width_pt: f32, height_pt: f32) -> Self {
        Self {
            page_number,
            width_pt,
            height_pt,
            blocks: Vec::new(),
        }
    }

    /// Append a block, stamping its `block_ordinal` from the current length so
    /// callers cannot create an anchor that disagrees with the vector index.
    pub fn push_block(&mut self, kind: BlockKind, bbox: NormalizedBBox, text: impl Into<String>) {
        self.push_block_with_table(kind, bbox, text, None);
    }

    /// [`Self::push_block`] for a block that preserves its original `<table>`
    /// markup (`colspan`/`rowspan`).
    ///
    /// `html_table` is forced to `None` for every non-[`BlockKind::Table`]
    /// block: table markup on a paragraph is a caller bug, and silently keeping
    /// it would let a later pass treat prose as tabular data.
    pub fn push_block_with_table(
        &mut self,
        kind: BlockKind,
        bbox: NormalizedBBox,
        text: impl Into<String>,
        html_table: Option<String>,
    ) {
        let ordinal = u32::try_from(self.blocks.len()).unwrap_or(u32::MAX);
        self.blocks.push(DocumentBlock {
            id: BlockAnchor::new(self.page_number, ordinal),
            kind,
            bbox,
            text: text.into(),
            html_table: if kind == BlockKind::Table {
                html_table
            } else {
                None
            },
        });
    }

    /// Whether the extractor reported usable page geometry.
    ///
    /// Uses the same finite-and-positive test as
    /// [`NormalizedBBox::from_page_points`]: a page whose width is infinite
    /// normalizes every block to [`NormalizedBBox::FULL_PAGE`], so reporting it
    /// as "has geometry" would present a fallback box as a measurement.
    #[must_use]
    pub fn has_geometry(&self) -> bool {
        usable_dimension(self.width_pt) && usable_dimension(self.height_pt)
    }
}

/// A whole extracted document: the producing parser's fingerprint plus its
/// pages in ascending order.
#[derive(Debug, Clone, PartialEq)]
pub struct StructuredDocument {
    /// The [`parser_fingerprint`](super::ports::DocumentStructureExtractor::parser_fingerprint)
    /// of the adapter that produced this document. Folded into the `#871`
    /// chunk fingerprint so a cached chunk prefix never resumes across two
    /// different structure extractors (ADR-041 `D7`).
    pub parser_fingerprint: String,
    pub pages: Vec<StructuredPage>,
}

impl StructuredDocument {
    #[must_use]
    pub fn new(parser_fingerprint: impl Into<String>, pages: Vec<StructuredPage>) -> Self {
        Self {
            parser_fingerprint: parser_fingerprint.into(),
            pages,
        }
    }

    /// Number of pages.
    #[must_use]
    pub fn page_count(&self) -> usize {
        self.pages.len()
    }

    /// Whether the document has no pages at all.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.pages.is_empty()
    }

    /// The page with this 1-based number.
    #[must_use]
    pub fn page(&self, page_number: u32) -> Option<&StructuredPage> {
        self.pages
            .iter()
            .find(|page| page.page_number == page_number)
    }

    /// Every block of the document in reading order.
    pub fn blocks(&self) -> impl Iterator<Item = &DocumentBlock> {
        self.pages.iter().flat_map(|page| page.blocks.iter())
    }

    /// The document as flat text: block texts joined by a newline inside a page
    /// and pages separated by a form feed (`\u{c}`).
    ///
    /// This is the compatibility seam for the pre-ADR-041 line-based path: for
    /// the legacy `pdftotext -layout` adapter the result is byte-identical to
    /// that adapter's raw output, so `extract_scenes(&str)` keeps seeing
    /// exactly what it saw before the hexagonal split. Zone-aware segmentation
    /// (issue #959) replaces this with verbatim block slicing and deletes these
    /// call sites.
    #[must_use]
    pub fn flattened_text(&self) -> String {
        let mut out = String::new();
        for (index, page) in self.pages.iter().enumerate() {
            if index > 0 {
                out.push('\u{c}');
            }
            for (block_index, block) in page.blocks.iter().enumerate() {
                if block_index > 0 {
                    out.push('\n');
                }
                out.push_str(&block.text);
            }
        }
        out
    }
}

/// Knobs for one [`extract`](super::ports::DocumentStructureExtractor::extract)
/// call.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExtractionOptions {
    /// Accepted for forward compatibility and deliberately inert in the P1
    /// adapters: the IR never embeds page images, because callers request them
    /// one at a time through `render_page` (ADR-041 `D1`). A flag that silently
    /// accumulated `K` PNGs into the document is exactly what `D1` forbids.
    pub render_pages_png: bool,
    /// Render resolution for the on-demand `render_page` calls of the same
    /// adapter. Defaults to [`DEFAULT_TARGET_DPI`].
    pub target_dpi: u16,
}

/// Default page-render resolution (ADR-041: 150 dpi is enough for a VLM to read
/// grid lines and `"ROLLEN"` legends while keeping one A4 page near ~200 KiB).
pub const DEFAULT_TARGET_DPI: u16 = 150;

/// Default per-page byte ceiling for one rendered PNG (8 MiB).
pub const DEFAULT_MAX_RENDER_BYTES: usize = 8 * 1024 * 1024;

impl Default for ExtractionOptions {
    fn default() -> Self {
        Self {
            render_pages_png: false,
            target_dpi: DEFAULT_TARGET_DPI,
        }
    }
}

/// Knobs for one [`render_page`](super::ports::DocumentStructureExtractor::render_page)
/// call: the resolution and the per-page byte ceiling the renderer enforces.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RenderOptions {
    pub target_dpi: u16,
    /// Hard ceiling for this page's PNG. A renderer that exceeds it kills and
    /// reaps its child and returns a validation error instead of handing back
    /// an unbounded image.
    pub max_bytes: usize,
}

impl Default for RenderOptions {
    fn default() -> Self {
        Self {
            target_dpi: DEFAULT_TARGET_DPI,
            max_bytes: DEFAULT_MAX_RENDER_BYTES,
        }
    }
}

impl RenderOptions {
    #[must_use]
    pub const fn new(target_dpi: u16, max_bytes: usize) -> Self {
        Self {
            target_dpi,
            max_bytes,
        }
    }
}

/// One rendered page image. Never stored in [`StructuredDocument`]: the caller
/// renders, sends and drops it before rendering the next page.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderedPage {
    /// 1-based page number this image belongs to.
    pub page_number: u32,
    pub png_bytes: Vec<u8>,
}

impl RenderedPage {
    #[must_use]
    pub fn new(page_number: u32, png_bytes: Vec<u8>) -> Self {
        Self {
            page_number,
            png_bytes,
        }
    }
}

#[cfg(test)]
#[path = "document_tests.rs"]
mod document_tests;
