// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy4-flash-free (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: gemini-4-argon (opencode-go)

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

use crate::character::category::CharacterCategory;

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
    /// The compatibility seam of the pre-ADR-041 line-based path, kept for two
    /// callers: the **flat-text segmentation seam**
    /// (`preview::SegmentedScript::from_flat_text`, which must keep seeing
    /// exactly the string the string-level unit tests pin — for the legacy
    /// `pdftotext -layout` adapter that is byte-identical to its raw output) and
    /// the line-based schedule reader. Script segmentation itself no longer uses
    /// it: `preview::extract_scenes_from_structured` slices the blocks verbatim
    /// per page (ADR-041 `D3`, issue #959).
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

/// Environment variable overriding the document-wide cumulative rendered-PNG
/// byte ceiling across a page-streaming run (ADR-041 `D1`, issue #960).
pub const AI_IMPORT_MAX_RENDERED_TOTAL_BYTES_ENV: &str = "AI_IMPORT_MAX_RENDERED_TOTAL_BYTES";

/// Default document-wide cumulative byte ceiling for rendered PNG pages (64 MiB).
///
/// Coupled to [`DEFAULT_MAX_RENDER_BYTES`] so the document-wide ceiling can
/// never be smaller than a single page's default ceiling.
pub const DEFAULT_MAX_RENDERED_TOTAL_BYTES: usize = 8 * DEFAULT_MAX_RENDER_BYTES;

/// Hard upper clamp for [`AI_IMPORT_MAX_RENDERED_TOTAL_BYTES_ENV`] (512 MiB).
pub const MAX_RENDERED_TOTAL_BYTES_LIMIT: usize = 512 * 1024 * 1024;

const _RENDER_CEILING_INVARIANT: () = assert!(
    DEFAULT_MAX_RENDERED_TOTAL_BYTES >= DEFAULT_MAX_RENDER_BYTES
        && MAX_RENDERED_TOTAL_BYTES_LIMIT >= DEFAULT_MAX_RENDERED_TOTAL_BYTES
);

/// Parse one [`AI_IMPORT_MAX_RENDERED_TOTAL_BYTES_ENV`] value, falling back to
/// [`DEFAULT_MAX_RENDERED_TOTAL_BYTES`] on absent, zero, non-numeric, or
/// out-of-range values.
#[must_use]
pub fn parse_max_rendered_total_bytes(raw: Option<&str>) -> usize {
    raw.and_then(|value| value.trim().parse::<usize>().ok())
        .filter(|&bytes| (1..=MAX_RENDERED_TOTAL_BYTES_LIMIT).contains(&bytes))
        .unwrap_or(DEFAULT_MAX_RENDERED_TOTAL_BYTES)
}

/// Read the document-wide rendered-PNG ceiling from
/// [`AI_IMPORT_MAX_RENDERED_TOTAL_BYTES_ENV`].
#[must_use]
pub fn max_rendered_total_bytes_from_env() -> usize {
    let raw = std::env::var(AI_IMPORT_MAX_RENDERED_TOTAL_BYTES_ENV).ok();
    parse_max_rendered_total_bytes(raw.as_deref())
}

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

// ===========================================================================
// Pass 0 — page zoning (ADR-041 `D3`/`D4`, issue #959)
// ===========================================================================
//
// A real broadcast screenplay is not one text: it opens with a cover page, a
// cast directory, a `"SCRIPT REPORT"` scene index and several pages of
// `"SYNOPSIS"` prose before the first scene. Scanning that flat string from
// line 1 glues the synopsis onto the last index entry, and the index entries
// themselves double every scene until the duplicate merge folds them back. The
// zone pass therefore labels each page ONCE, and the segmentation that follows
// reads only `SceneBody` prose (see `crate::ai::preview`).

/// Semantic zone of one page (ADR-041 `D3`).
///
/// The spelling of [`Self::as_str`] is part of the persisted structural plan, so
/// it must never be renamed without a plan-digest change (which is exactly what
/// the digest is for).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PageZone {
    /// Cover page: production/episode metadata, no scene and no dialogue.
    TitlePage,
    /// Cast directory page (`"PERSONEN/ HAUPTCAST"`, `"KOMPARSEN"`, …).
    CastList,
    /// Scene index / manifest (`"SCRIPT REPORT"`, heading-only entries).
    SceneIndex,
    /// Narrative front matter that carries no scenes (`"SYNOPSIS"`,
    /// `"MEDIZINISCHE FÄLLE"`, character bios).
    FrontMatter,
    /// The script itself: scene headings with action and dialogue.
    ScriptBody,
}

impl PageZone {
    /// Stable spelling for the persisted structural plan (issue #959).
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::TitlePage => "title_page",
            Self::CastList => "cast_list",
            Self::SceneIndex => "scene_index",
            Self::FrontMatter => "front_matter",
            Self::ScriptBody => "script_body",
        }
    }

    /// Whether this page may emit scene prose.
    #[must_use]
    pub const fn is_script_body(self) -> bool {
        matches!(self, Self::ScriptBody)
    }
}

/// The role one line plays inside its block, after the Pass 0 filter.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LineRole {
    /// Prose the scene chunk may contain: a heading, action or dialogue line.
    Body,
    /// Running-header band (`"Block 098"`, `"Ep.: 292/1"`): harvested for
    /// metadata, never part of scene prose.
    Header,
    /// Footer band, typically the page number.
    Footer,
    /// Page-turn continuation banner (`"2 CONTINUED: (2)"`, `"FORTSETZUNG"`).
    Continuation,
}

impl LineRole {
    /// Whether this line may enter a [`crate::ai::preview::SceneChunk`]'s text.
    #[must_use]
    pub const fn is_body(self) -> bool {
        matches!(self, Self::Body)
    }
}

/// What the Pass 0 scan found on one page.
///
/// The counters are kept (not just the verdict) because they are what makes a
/// wrong zone explainable in a log line or a corpus report: `"page 12: 0
/// headings, 0 dialogue lines → front_matter"` is a diagnosis, `front_matter`
/// alone is a mystery.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PageZoneRecord {
    pub page_number: u32,
    pub zone: PageZone,
    /// Lines that look like scene headings (the caller supplies the detector).
    pub heading_lines: u32,
    /// Indented cue/dialogue lines (geometry) or cue-shaped lines (flat text).
    pub dialogue_lines: u32,
    /// The banner that decided the zone (`"SCRIPT REPORT"`, `"SYNOPSIS"`…).
    pub banner: Option<String>,
}

/// The Pass 0 verdict: one [`PageZoneRecord`] per page, in document order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentZones {
    pages: Vec<PageZoneRecord>,
    /// Set when the deterministic pass recognised no `ScriptBody` page at all
    /// and every page was therefore treated as script prose (see
    /// [`Self::fell_back_to_script_body`]).
    fell_back: bool,
}

impl DocumentZones {
    /// A uniform verdict: every page `1..=page_count` gets `zone`.
    ///
    /// This is the flat-text seam's verdict (`preview::SegmentedScript::from_flat_text`
    /// wraps one string in one page and must keep scanning it exactly as the
    /// pre-#959 line scanner did — classifying that page by banner or heading
    /// shape would *change* the string-level behaviour the existing unit tests
    /// pin). The counters stay `0`, which is honest: no page was examined.
    #[must_use]
    pub fn uniform(page_count: u32, zone: PageZone) -> Self {
        Self {
            pages: (1..=page_count)
                .map(|page_number| PageZoneRecord {
                    page_number,
                    zone,
                    heading_lines: 0,
                    dialogue_lines: 0,
                    banner: None,
                })
                .collect(),
            fell_back: false,
        }
    }

    /// The record of one 1-based page.
    #[must_use]
    pub fn page(&self, page_number: u32) -> Option<&PageZoneRecord> {
        self.pages
            .iter()
            .find(|page| page.page_number == page_number)
    }

    /// The zone of a page; [`PageZone::ScriptBody`] for a page the pass never
    /// saw (a caller asking about a page outside the document gets the honest
    /// "treat it as prose" answer, never a silently dropped page).
    #[must_use]
    pub fn zone_of(&self, page_number: u32) -> PageZone {
        self.page(page_number)
            .map_or(PageZone::ScriptBody, |record| record.zone)
    }

    /// Every page record, in document order.
    #[must_use]
    pub fn pages(&self) -> &[PageZoneRecord] {
        &self.pages
    }

    /// Whether at least one page was classified as script body.
    #[must_use]
    pub fn has_script_body(&self) -> bool {
        self.pages.iter().any(|page| page.zone.is_script_body())
    }

    /// Whether the deterministic pass recognised no script page and the caller
    /// fell back to "every page is prose".
    ///
    /// This is the honest degradation the ADR-041 `D3` fallback seam names: an
    /// unfamiliar template must produce scene prose (possibly noisy, trimmed by
    /// the continuation filter) instead of an empty preview. A caller that
    /// observes this flag is the one expected to reach for the VLM structural
    /// pass (issue #960) — until it exists, the flag is the signal to log.
    #[must_use]
    pub fn fell_back_to_script_body(&self) -> bool {
        self.fell_back
    }

    /// Widen every page to [`PageZone::ScriptBody`].
    ///
    /// Called by the segmentation when [`Self::has_script_body`] is `false`: a
    /// document whose cover/cast/synopsis banners were all recognised but whose
    /// body used a heading convention this build does not know would otherwise
    /// segment to zero scenes and fail the whole import. Widening degrades to
    /// the pre-#959 behaviour (one flat scan) instead of refusing the document.
    pub fn widen_to_script_body(&mut self) {
        for page in &mut self.pages {
            page.zone = PageZone::ScriptBody;
            page.banner = None;
        }
        self.fell_back = true;
    }
}

/// One line of the document together with the zoning it received.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ZonedLine<'a> {
    pub page_number: u32,
    pub zone: PageZone,
    /// The block this line came from — the anchor a structural plan records.
    pub anchor: BlockAnchor,
    pub role: LineRole,
    pub text: &'a str,
}

impl ZonedLine<'_> {
    /// Whether this line may enter scene prose: it must sit in the script body
    /// AND be a body line (not a header, footer or continuation banner).
    #[must_use]
    pub fn is_scene_prose(self) -> bool {
        self.zone.is_script_body() && self.role.is_body()
    }
}

/// Page banners that mark a scene index / manifest page. Compared against the
/// trimmed uppercase line start, as a whole word.
const SCENE_INDEX_BANNERS: [&str; 2] = ["SCRIPT REPORT", "SZENENÜBERSICHT"];

/// Page banners that open a cast directory section.
const CAST_LIST_BANNERS: [&str; 9] = [
    "PERSONEN",
    "HAUPTCAST",
    "EPISODENHAUPTROLLEN",
    "HAUPTROLLEN",
    "GASTROLLEN",
    "DARSTELLER",
    "KOMPARSEN",
    "STATISTEN",
    "CAST",
];

/// Deterministic section-header → role mapping (issue #961, ADR-041 `D5`).
///
/// A `'static` slice, not a `HashMap`/`LazyLock`: a ~20-entry linear scan costs
/// nothing next to a page of text and keeps `core` free of allocation on the
/// hot path. Headers are uppercased and whitespace-folded before lookup.
pub const CAST_SECTION_MAPPING: &[(&str, CharacterCategory)] = &[
    ("PERSONEN", CharacterCategory::MainCast),
    ("PERSONEN/ HAUPTCAST", CharacterCategory::MainCast),
    ("HAUPTCAST", CharacterCategory::MainCast),
    ("HAUPTROLLEN", CharacterCategory::MainCast),
    ("DURCHGEHENDE ROLLEN", CharacterCategory::MainCast),
    ("DARSTELLER", CharacterCategory::MainCast),
    ("MAIN CAST", CharacterCategory::MainCast),
    ("CAST", CharacterCategory::MainCast),
    ("EPISODENHAUPTROLLEN", CharacterCategory::Guest),
    ("EPISODENROLLEN", CharacterCategory::Guest),
    ("GASTROLLEN", CharacterCategory::Guest),
    ("GASTDARSTELLER", CharacterCategory::Guest),
    ("CROSS", CharacterCategory::Guest),
    ("GUEST CAST", CharacterCategory::Guest),
    ("KOMPARSEN", CharacterCategory::Extra),
    ("KOMPARSERIE", CharacterCategory::Extra),
    ("STATISTEN", CharacterCategory::Extra),
    ("STATISTERIE", CharacterCategory::Extra),
    ("KLEINDARSTELLER", CharacterCategory::Extra),
    ("TAGESROLLEN", CharacterCategory::Extra),
    ("EXTRAS", CharacterCategory::Extra),
];

/// One figure declared on a `PageZone::CastList` page (issue #961).
///
/// `declared_category` is the section the document put the name in. It stays
/// authoritative even when the same line carries an `(OT)` parenthetical:
/// `"Jonas Weber (8, OT)"` under `EPISODENHAUPTROLLEN` is a silent episodic
/// lead (`guest`), not a background performer. `inline_ot` is retained as the
/// fact it is, for prompt context and debugging — never as a vote that outranks
/// the section.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CastDirectoryEntry {
    pub canonical_name: String,
    pub normalized_identity: String,
    pub declared_category: CharacterCategory,
    pub raw_section: String,
    pub inline_ot: bool,
}

/// The parsed front-matter cast list of one document. Plain owned data, built
/// once per import and borrowed by every chunk/post-processing step — never
/// wrapped in `Arc` (issue #961).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CastDirectory {
    pub entries: Vec<CastDirectoryEntry>,
}

impl CastDirectory {
    #[must_use]
    pub fn new(entries: Vec<CastDirectoryEntry>) -> Self {
        Self { entries }
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

/// Uppercase, fold runs of whitespace, drop a trailing section colon.
fn cast_header_key(line: &str) -> String {
    let mut out = String::with_capacity(line.len());
    let mut pending_space = false;
    for character in line.trim().trim_end_matches(':').chars() {
        if character.is_whitespace() {
            pending_space = !out.is_empty();
            continue;
        }
        if pending_space {
            out.push(' ');
            pending_space = false;
        }
        out.extend(character.to_uppercase());
    }
    out
}

fn cast_section(line: &str) -> Option<(CharacterCategory, String)> {
    let key = cast_header_key(line);
    CAST_SECTION_MAPPING
        .iter()
        .find(|(header, _)| *header == key)
        .map(|(header, category)| (*category, (*header).to_owned()))
}

/// Only case and whitespace are folded — the same identity rule the outfit
/// mapping uses, so a cast-list name binds to the same figures downstream.
fn cast_identity(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    let mut pending_space = false;
    for character in name.chars() {
        if character.is_whitespace() {
            pending_space = !out.is_empty();
            continue;
        }
        if pending_space {
            out.push(' ');
            pending_space = false;
        }
        out.extend(character.to_lowercase());
    }
    out
}

/// Strip ONE trailing parenthetical, recording whether it carried an `(OT)`
/// marker. `"Jonas Weber (8, OT)"` → (`"Jonas Weber"`, `true`).
fn strip_cast_parenthetical(raw: &str) -> (&str, bool) {
    let trimmed = raw.trim();
    let Some(open) = trimmed.rfind('(') else {
        return (trimmed, false);
    };
    if !trimmed.ends_with(')') || open == 0 {
        return (trimmed, false);
    }
    let inside = &trimmed[open + 1..trimmed.len() - 1];
    if inside.len() > 40 || inside.contains('(') || inside.contains(')') {
        return (trimmed, false);
    }
    let compact = inside.replace('.', "");
    let inline_ot = compact
        .split(|character: char| !character.is_alphanumeric())
        .any(|token| token.eq_ignore_ascii_case("OT"));
    (trimmed[..open].trim(), inline_ot)
}

fn looks_like_cast_name(name: &str) -> bool {
    let letters = name
        .chars()
        .filter(|character| character.is_alphabetic())
        .count();
    letters >= 2 && name.chars().count() <= 80 && !name.to_ascii_uppercase().contains("CONTINUED")
}

/// A `KOMPARSEN` page often lists several extras on one comma-separated line.
/// Commas INSIDE a parenthetical (`"Jonas Weber (8, OT)"`) are not separators,
/// so split only at depth zero.
fn cast_name_candidates(line: &str) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut start = 0usize;
    let mut depth = 0u32;
    for (offset, character) in line.char_indices() {
        match character {
            '(' => depth += 1,
            ')' => depth = depth.saturating_sub(1),
            ',' if depth == 0 => {
                parts.push(line[start..offset].trim());
                start = offset + 1;
            }
            _ => {}
        }
    }
    parts.push(line[start..].trim());
    parts
}

/// Parse cast entries from the lines the zone classifier marked `CastList`.
///
/// Only lines after a known section banner become entries, so a stray name in
/// a title page or an action line can never enter the directory. The parse is
/// deterministic and pure: no model call, no I/O, no state beyond the current
/// section.
#[must_use]
pub fn parse_cast_directory(lines: &[ZonedLine<'_>]) -> CastDirectory {
    let mut entries = Vec::new();
    let mut current: Option<(CharacterCategory, String)> = None;
    for line in lines {
        if line.zone != PageZone::CastList {
            continue;
        }
        let text = line.text.trim();
        if text.is_empty() {
            continue;
        }
        if let Some(section) = cast_section(text) {
            current = Some(section);
            continue;
        }
        let Some((category, raw_section)) = current.as_ref() else {
            continue;
        };
        for candidate in cast_name_candidates(text) {
            let (canonical_name, inline_ot) = strip_cast_parenthetical(candidate);
            if !looks_like_cast_name(canonical_name) {
                continue;
            }
            let normalized_identity = cast_identity(canonical_name);
            entries.push(CastDirectoryEntry {
                canonical_name: canonical_name.to_owned(),
                normalized_identity,
                declared_category: *category,
                raw_section: raw_section.clone(),
                inline_ot,
            });
        }
    }
    CastDirectory::new(entries)
}

/// Flat-text seam for the legacy `pdftotext -layout` adapter: fabricate
/// `CastList` lines from a plain string so the same parser (and the same
/// section table) serves both extraction paths (issue #961). A cast section
/// stays open until a scene heading or another known banner appears.
#[must_use]
pub fn parse_cast_directory_from_text(
    text: &str,
    is_scene_heading: impl Fn(&str) -> bool,
) -> CastDirectory {
    let mut lines: Vec<ZonedLine<'_>> = Vec::new();
    let mut in_cast = false;
    for (offset, line) in text.lines().enumerate() {
        if cast_section(line).is_some() {
            in_cast = true;
        } else if in_cast
            && page_banner(line, true).is_some_and(|(zone, _)| zone != PageZone::CastList)
        {
            // A recognized non-cast banner (`SYNOPSIS`, `SCRIPT REPORT`, ...)
            // ends the directory. `page_banner` requires a section-shaped line,
            // so shouty prose (`CAST OFF!`) and a valid `KOMPARSEN` header are
            // not mistaken for one another.
            in_cast = false;
        } else if in_cast && is_scene_heading(line) {
            in_cast = false;
        }
        if in_cast {
            lines.push(ZonedLine {
                page_number: 1,
                zone: PageZone::CastList,
                anchor: BlockAnchor::new(1, u32::try_from(offset).unwrap_or(u32::MAX)),
                role: LineRole::Body,
                text: line,
            });
        }
    }
    parse_cast_directory(&lines)
}

fn collapsed_name(name: &str) -> String {
    name.chars()
        .filter(|character| !character.is_whitespace())
        .flat_map(char::to_lowercase)
        .collect()
}

/// The kerning dictionary contains full names AND their multi-character name
/// tokens — `"Mikko Rantala"` licenses both `"Mik k o Rantala"` and a bare
/// `"Mik k o"`. Abbreviations (`"Dr."`) are excluded: joining prose around
/// them would be free-form spellchecking, which issue #961 forbids.
fn kerning_dictionary(directory: &CastDirectory) -> Vec<(String, String)> {
    let mut dictionary: Vec<(String, String)> = Vec::new();
    for entry in &directory.entries {
        let mut add = |collapsed: String, canonical: &str| {
            if collapsed.len() >= 2 && !dictionary.iter().any(|(known, _)| known == &collapsed) {
                dictionary.push((collapsed, canonical.to_owned()));
            }
        };
        add(collapsed_name(&entry.canonical_name), &entry.canonical_name);
        for token in entry.canonical_name.split_whitespace() {
            if token.ends_with('.')
                || token
                    .chars()
                    .filter(|character| character.is_alphabetic())
                    .count()
                    < 2
            {
                continue;
            }
            add(collapsed_name(token), token);
        }
    }
    dictionary
}

/// Repair Ghostscript/PDF24 intra-word kerning splits (`"Mik k o"` →
/// `"Mikko"`) **only** when the whitespace-collapsed run equals a name in
/// `directory` (issue #961). Ordinary German prose and names not in the cast
/// list are left byte-for-byte alone.
///
/// The result is a prompt-facing view, not a replacement for the chunk's
/// verbatim text: `verify_draft_outfits` checks quotes against both the raw
/// and the normalized view so a grounded outfit is never dropped.
#[must_use]
pub fn normalize_kerning(text: &str, directory: &CastDirectory) -> String {
    if directory.is_empty() {
        return text.to_owned();
    }
    let dictionary = kerning_dictionary(directory);
    if dictionary.is_empty() {
        return text.to_owned();
    }
    let mut out = String::with_capacity(text.len());
    for line in text.split_inclusive('\n') {
        let (body, newline) = line
            .strip_suffix('\n')
            .map_or((line, ""), |rest| (rest, "\n"));
        let words: Vec<&str> = body.split(' ').collect();
        let mut index = 0usize;
        while index < words.len() {
            if words[index].is_empty() {
                index += 1;
                if index < words.len() {
                    out.push(' ');
                }
                continue;
            }
            let mut matched = false;
            // Four tokens cover `"Le yla Sher baz"`; longer runs are far
            // more likely to be an ordinary phrase than a kerning split.
            for take in (2..=4).rev() {
                let Some(segment) = words.get(index..index + take) else {
                    continue;
                };
                if segment
                    .iter()
                    .any(|word| word.is_empty() || word.contains('\t'))
                {
                    continue;
                }
                let collapsed: String = segment.concat();
                let collapsed_key = collapsed_name(&collapsed);
                let original = segment.join(" ");
                let Some(canonical) = dictionary
                    .iter()
                    .find(|(known, _)| known == &collapsed_key)
                    .map(|(_, canonical)| canonical)
                else {
                    continue;
                };
                if original == *canonical {
                    continue;
                }
                out.push_str(canonical);
                index += take;
                // One separator per split token: an empty token emits the
                // next one itself, so repeated spaces in unrelated prose
                // survive byte-for-byte.
                if index < words.len() {
                    out.push(' ');
                }
                matched = true;
                break;
            }
            if !matched {
                out.push_str(words[index]);
                index += 1;
                if index < words.len() {
                    out.push(' ');
                }
            }
        }
        out.push_str(newline);
    }
    out
}

/// Page banners that open narrative front matter carrying no scenes.
const FRONT_MATTER_BANNERS: [&str; 4] = ["SYNOPSIS", "EXPOSÉ", "EXPOSE", "MEDIZINISCHE FÄLLE"];

/// A page needs at least this many heading lines — and zero dialogue lines — to
/// be read as an index without a banner. Below it, a heading-only page is a
/// script page whose scene simply continues (two- or three-scene pages are the
/// norm in the body).
const MIN_INDEX_HEADINGS: u32 = 6;

/// Left edge (`bbox.x0`) from which a block counts as indented — the character
/// cue (`0.35..0.45`) and dialogue (`0.25..0.32`) columns of a screenplay.
const INDENT_MIN_X0: f32 = 0.22;

/// Longest line still accepted as a character cue by the flat-text heuristic.
const CHARACTER_CUE_MAX_CHARS: usize = 32;

/// Shortest line that still counts as prose when deciding whether a page is a
/// body-less index. A scene-index entry is a heading plus a short day column
/// (`"Tag 1"`, `"1. Spieltag"`); a script page carries full action sentences.
const PROSE_MIN_CHARS: usize = 32;

/// Classify every page of `document` into a [`PageZone`] (ADR-041 `D3`, issue
/// #959).
///
/// Deterministic and pure: no LLM, no I/O, and no token cost — two linear
/// passes over the block text of a 100-page script. `is_scene_heading` is
/// injected rather than re-implemented here, so the zoning verdict and the
/// chunker's split decision can never disagree about what a heading is (the
/// caller passes `preview::is_scene_heading`; tests pass a stub).
///
/// The signals, in the order they decide a page:
///
/// 1. a scene-index banner (`"SCRIPT REPORT"`) → [`PageZone::SceneIndex`];
/// 2. a cast-directory banner (`"PERSONEN/ HAUPTCAST"`, `"KOMPARSEN"`) →
///    [`PageZone::CastList`];
/// 3. `>= 6` heading lines and **no** prose or dialogue line, **before** the
///    script body has started → [`PageZone::SceneIndex`] (the banner-less
///    `SCRIPT REPORT`);
/// 4. the first page, with neither headings nor dialogue → [`PageZone::TitlePage`];
/// 5. a front-matter banner (`"SYNOPSIS"`, `"MEDIZINISCHE FÄLLE"`) →
///    [`PageZone::FrontMatter`];
/// 6. any heading or dialogue line → [`PageZone::ScriptBody`];
/// 7. otherwise [`PageZone::FrontMatter`] — weak, and demoted back to script
///    body when a script page precedes it (see below).
///
/// The last step is the one that keeps a synopsis from being silently dropped in
/// the middle of the script: a page that carries no scene signal but follows a
/// `ScriptBody` page is a continuation page (a scene running over a page break),
/// not front matter. Only the weak verdicts (`FrontMatter`, `TitlePage`) are
/// demoted; a banner stays authoritative wherever it appears.
#[must_use]
pub fn classify_document_zones(
    document: &StructuredDocument,
    is_scene_heading: impl Fn(&str) -> bool,
) -> DocumentZones {
    let mut pages: Vec<PageZoneRecord> = Vec::with_capacity(document.pages.len());
    let mut seen_script_body = false;
    for (index, page) in document.pages.iter().enumerate() {
        let is_first_page = index == 0;
        let mut heading_lines = 0_u32;
        let mut dialogue_lines = 0_u32;
        let mut prose_lines = 0_u32;
        let mut banner: Option<(PageZone, &'static str)> = None;
        let mut first_text_line = true;
        for block in &page.blocks {
            let band = block_role(block.bbox, block.kind);
            for line in block.text.split('\n') {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                // A banner may sit in the running-header band or be the page's
                // first line; a phrase in the middle of body prose must never
                // relabel the page.
                let banner_slot = band == LineRole::Header || first_text_line;
                first_text_line = false;
                // The banner is looked for in EVERY band, because in the real
                // documents it IS a running header (`BL98/294-SCRIPT REPORT`,
                // `DJÄ_BL98_294_DREH210805 -- SCRIPT REPORT  2`): skipping the
                // header band would leave the index pages unrecognised and every
                // index entry would parse as a scene.
                if banner.is_none()
                    && let Some(found) = page_banner(trimmed, banner_slot)
                {
                    banner = Some(found);
                }
                // The band excludes PAGE FURNITURE. A line the heading detector
                // recognises is scene CONTENT even when it sits in the top band:
                // the spatial adapter tags every top-band block `PageHeader`, and
                // a slug printed at the very top of a page would otherwise be
                // dropped before the scene scanner ever saw it.
                let band = promote_top_band_heading(band, trimmed, &is_scene_heading);
                if band != LineRole::Body {
                    continue;
                }
                if is_scene_heading(trimmed) {
                    heading_lines = heading_lines.saturating_add(1);
                } else if is_dialogue_line(block.bbox, page.has_geometry(), trimmed) {
                    dialogue_lines = dialogue_lines.saturating_add(1);
                } else if trimmed.chars().count() >= PROSE_MIN_CHARS {
                    prose_lines = prose_lines.saturating_add(1);
                }
            }
        }
        let bannered = match banner {
            // A series title on the cover (`"MEDIZINISCHE FÄLLE"`) is not a
            // section banner: the first page is the title page unless it also
            // carries a scene signal. Both verdicts exclude the page from prose,
            // but the honest label matters for the plan and the log.
            Some((PageZone::FrontMatter, _)) if is_first_page && heading_lines == 0 => None,
            Some((zone, _)) => Some(zone),
            None => None,
        };
        let zone = match bannered {
            Some(zone) => zone,
            // The banner-less index: a heading-only page, and only while the
            // script body has not started yet. The extra conditions are what
            // keep an ACTION-only script page (six short scenes, whose action
            // lines are shorter than `PROSE_MIN_CHARS`) from being mistaken for
            // an index — such a page still carries full-length action lines.
            // The `seen_script_body` guard covers the remaining shape: short
            // action (`Sie nickt.`) after the body started is a body page, and
            // dropping it would lose every scene on it. A banner stays
            // authoritative wherever it appears (branch above).
            None if !seen_script_body
                && heading_lines >= MIN_INDEX_HEADINGS
                && dialogue_lines == 0
                && prose_lines == 0 =>
            {
                PageZone::SceneIndex
            }
            // A real scene page starts with a heading. Indentation alone is NOT
            // a scene signal: a cover page's centred title block sits in exactly
            // the columns a character cue uses (`x0` around 0.30), so counting it
            // as dialogue turned the title page of every real script into prose.
            None if heading_lines > 0 => PageZone::ScriptBody,
            None => {
                if seen_script_body {
                    // No heading, but the script is running: a continuation page
                    // (a scene over a page break). Dropping it would delete that
                    // scene's text.
                    PageZone::ScriptBody
                } else if is_first_page {
                    PageZone::TitlePage
                } else {
                    PageZone::FrontMatter
                }
            }
        };
        // Demote a weak verdict once the script has started: only banners stay
        // authoritative there, so a cover-like page inside the body cannot lose
        // its prose to `TitlePage`/`FrontMatter`.
        let zone = if seen_script_body
            && bannered.is_none()
            && matches!(zone, PageZone::FrontMatter | PageZone::TitlePage)
        {
            PageZone::ScriptBody
        } else {
            zone
        };
        if zone.is_script_body() {
            seen_script_body = true;
        }
        pages.push(PageZoneRecord {
            page_number: page.page_number,
            zone,
            heading_lines,
            dialogue_lines,
            banner: banner.map(|(_, keyword)| keyword.to_owned()),
        });
    }
    DocumentZones {
        pages,
        fell_back: false,
    }
}

/// Every line of `document` in reading order, tagged with the zone its page got
/// and the role its block gave it.
///
/// Block text is split on `\n`: the IR stores a block's verbatim text, and the
/// line is the unit the heading detector, the marker scans and the chunk text
/// all work on. Blank lines are kept — they separate action paragraphs inside a
/// scene, and the chunk text must stay the document's text.
#[must_use]
pub fn zoned_lines<'a>(
    document: &'a StructuredDocument,
    zones: &DocumentZones,
    is_scene_heading: impl Fn(&str) -> bool,
) -> Vec<ZonedLine<'a>> {
    let mut lines: Vec<ZonedLine<'a>> = Vec::new();
    for page in &document.pages {
        let zone = zones.zone_of(page.page_number);
        push_page_lines(&mut lines, page, zone, &is_scene_heading);
    }
    lines
}

/// [`zoned_lines`] for a caller that has no zoning pass: every page is treated
/// as [`PageZone::ScriptBody`].
///
/// This is the flat-text seam (`preview::extract_scenes(&str)`): the pre-#959
/// line scanner saw one undifferentiated text, and the wrapper that keeps the
/// existing string-level unit tests valid must keep seeing exactly that. The
/// header/footer and continuation filter still applies — those are properties
/// of a *line*, not of a zone.
#[must_use]
pub fn zoned_lines_as_script_body(
    document: &StructuredDocument,
    is_scene_heading: impl Fn(&str) -> bool,
) -> Vec<ZonedLine<'_>> {
    let mut lines: Vec<ZonedLine<'_>> = Vec::new();
    for page in &document.pages {
        push_page_lines(&mut lines, page, PageZone::ScriptBody, &is_scene_heading);
    }
    lines
}

fn push_page_lines<'a>(
    lines: &mut Vec<ZonedLine<'a>>,
    page: &'a StructuredPage,
    zone: PageZone,
    is_scene_heading: &impl Fn(&str) -> bool,
) {
    for block in &page.blocks {
        let band = block_role(block.bbox, block.kind);
        for line in block.text.split('\n') {
            let band = promote_top_band_heading(band, line, is_scene_heading);
            let role = if band == LineRole::Body && is_continuation_marker(line) {
                LineRole::Continuation
            } else {
                band
            };
            lines.push(ZonedLine {
                page_number: page.page_number,
                zone,
                anchor: block.id,
                role,
                text: line,
            });
        }
    }
}

/// [`LineRole::Header`] becomes [`LineRole::Body`] when the line is a scene
/// heading: the band is a geometric heuristic for page furniture, and the spatial
/// adapter applies it to EVERY top-band block — including a slug printed at the
/// top of the page. Running metadata (`"Block 098 Ep.: 294/1"`) is no heading, so
/// it stays excluded.
fn promote_top_band_heading(
    band: LineRole,
    line: &str,
    is_scene_heading: &impl Fn(&str) -> bool,
) -> LineRole {
    if band == LineRole::Header && is_scene_heading(line) {
        LineRole::Body
    } else {
        band
    }
}

/// Whether `haystack` contains `phrase` as a whole word sequence (no
/// alphanumeric character directly before or after it).
fn contains_phrase(haystack: &str, phrase: &str) -> bool {
    let mut from = 0_usize;
    while let Some(offset) = haystack[from..].find(phrase) {
        let start = from + offset;
        let end = start + phrase.len();
        let left_ok = haystack[..start]
            .chars()
            .next_back()
            .is_none_or(|c| !c.is_alphanumeric());
        let right_ok = haystack[end..]
            .chars()
            .next()
            .is_none_or(|c| !c.is_alphanumeric());
        if left_ok && right_ok {
            return true;
        }
        from = end;
    }
    false
}

/// The band role the block's geometry and kind assign: header, footer or body.
///
/// The band bounds are the extractor contract from issue #958
/// ([`HEADER_BAND_MAX_Y1`] / [`FOOTER_BAND_MIN_Y0`]): whichever adapter produced
/// the IR already tagged the top-band blocks `PageHeader`, and this function is
/// what turns that tag into "excluded from prose". A page-leading line that sits
/// inside the band is therefore excluded too — the corpus harness's
/// expected-scene-count assertion (issue #959) is what surfaces that as a scene
/// shortfall instead of a silent loss.
///
/// The geometry fallback deliberately spares [`BlockKind::Heading`]: an adapter
/// that classified a block as a heading knows more than the band does, and a
/// scene heading that happens to END inside the top band (`y1 <= 0.09`, e.g. a
/// slug directly under the running header) is still the first line of its scene.
/// Only the *page furniture* bands exclude by position, and the extractor tags
/// that furniture `PageHeader` anyway.
fn block_role(bbox: NormalizedBBox, kind: BlockKind) -> LineRole {
    if kind == BlockKind::PageHeader {
        return LineRole::Header;
    }
    if bbox.is_header_band() && kind != BlockKind::Heading {
        return LineRole::Header;
    }
    if kind == BlockKind::PageFooter || bbox.is_footer_band() {
        return LineRole::Footer;
    }
    LineRole::Body
}

/// The zone a banner line names, if any.
///
/// Whole-word matching against the trimmed uppercase line: `"PERSONEN/ HAUPTCAST"`
/// matches `"PERSONEN"` (the next character is a separator), while `"PERSONAL"`
/// does not, and `"CASTING"` does not match `"CAST"`.
fn page_banner(line: &str, banner_slot: bool) -> Option<(PageZone, &'static str)> {
    let upper = line.trim().to_ascii_uppercase();
    // The scene-index banner is matched ANYWHERE on a banner line (running header
    // or the page's first line), as a whole phrase: in the real documents it is a
    // running header, not a section heading — `BL98/294-SCRIPT REPORT`,
    // `DJÄ_BL98_294_DREH210805 -- SCRIPT REPORT  2`. A prefix match misses both,
    // and then every index entry parses as a scene (exactly the doubled,
    // synopsis-contaminated preview this pass exists to stop). Restricting the
    // anywhere-match to a banner line is what keeps a dialogue sentence that
    // merely mentions the phrase from relabelling a script page.
    for keyword in SCENE_INDEX_BANNERS {
        if banner_slot && contains_phrase(&upper, keyword) {
            return Some((PageZone::SceneIndex, keyword));
        }
    }
    // Cast-list and front-matter banners ARE section headings, so they must start
    // the line: matching them anywhere would let a synopsis sentence
    // ("... wie in der SYNOPSIS beschrieben") relabel a whole page. Starting the
    // line is not enough on its own either — `"Cast the net before sunrise."`
    // starts with `CAST` and is the first line of a script page — so the line must
    // also LOOK like a section heading — shouty and carrying no word beyond the
    // section vocabulary, the way `"PERSONEN/ HAUPTCAST"` and `"MEDIZINISCHE
    // FÄLLE"` do and a sentence does not. Getting this wrong is expensive: a
    // `CastList` verdict removes the whole page from scene prose.
    for (zone, keywords) in [
        (PageZone::CastList, CAST_LIST_BANNERS.as_slice()),
        (PageZone::FrontMatter, FRONT_MATTER_BANNERS.as_slice()),
    ] {
        for keyword in keywords {
            if let Some(rest) = upper.strip_prefix(keyword)
                && rest
                    .chars()
                    .next()
                    .is_none_or(|next| !next.is_alphanumeric())
                && is_section_heading(line, rest)
            {
                return Some((zone, keyword));
            }
        }
    }
    None
}

/// Connectives that may appear between two section words
/// (`"PERSONEN UND HAUPTCAST"`).
const BANNER_CONNECTIVES: [&str; 2] = ["UND", "AND"];

/// Whether a line whose `keyword` prefix matched is still shaped like a section
/// banner: shouty (no lowercase letter) and — after the keyword — carrying nothing
/// but separators and further section vocabulary.
///
/// A banner NAMES a section (`"PERSONEN/ HAUPTCAST"`, `"MEDIZINISCHE FÄLLE"`,
/// `"KOMPARSEN"`, `"CAST:"`); an uppercase SENTENCE (`"CAST THE NET BEFORE
/// SUNRISE."`, `"CAST OFF!"`) is prose, and a shouty action line is not rare in a
/// broadcast script. Neither the case check nor a word cap separates the two
/// (`"CAST OFF!"` is only two words) — the vocabulary does: a banner adds no other
/// word.
///
/// A `CastList` verdict removes the whole page from scene prose, so this is worth
/// being strict about.
fn is_section_heading(line: &str, rest: &str) -> bool {
    !line.trim().chars().any(char::is_lowercase)
        && rest.split_whitespace().all(|word| {
            let bare = word.trim_matches(|c: char| !c.is_alphanumeric());
            bare.is_empty() || is_section_word(bare)
        })
}

/// Whether `word` is part of the cast/front-matter vocabulary (banner keywords
/// and the connectives between them).
fn is_section_word(word: &str) -> bool {
    CAST_LIST_BANNERS
        .iter()
        .chain(FRONT_MATTER_BANNERS.iter())
        .chain(BANNER_CONNECTIVES.iter())
        .any(|keyword| keyword.eq_ignore_ascii_case(word))
}

/// Whether a non-heading line sits in a dialogue column.
///
/// With geometry, the block's `x0` decides: a screenplay indents every character
/// cue and dialogue run to the left of the action column. Without geometry (the
/// `legacy-pdftotext` adapter hands over one whole-page block at
/// [`NormalizedBBox::FULL_PAGE`]) the shape of the line has to stand in: a
/// shouty, short, digit-free all-caps line is a character cue (`"LEYLA"`,
/// `"DR. KOCH"`), while an index entry (`"1 A/T - BAUERNHOF"`) or a day column
/// (`"Tag 1"`) is not.
fn is_dialogue_line(bbox: NormalizedBBox, has_geometry: bool, line: &str) -> bool {
    if has_geometry {
        return bbox.x0 >= INDENT_MIN_X0;
    }
    looks_like_character_cue(line)
}

fn looks_like_character_cue(line: &str) -> bool {
    let trimmed = line.trim();
    if trimmed.is_empty() || trimmed.chars().count() > CHARACTER_CUE_MAX_CHARS {
        return false;
    }
    let mut letters = 0_usize;
    for c in trimmed.chars() {
        if c.is_ascii_uppercase() {
            letters += 1;
        } else if !matches!(c, ' ' | '.' | '-' | '\'' | '/') {
            // A digit, a lowercase letter or punctuation that prose uses
            // disqualifies the line: cues carry none of them.
            return false;
        }
    }
    letters >= 2
}

/// Whether the line is a page-turn continuation banner.
///
/// Recognised forms (the observed `pdftotext` output of a broadcast script):
/// `"2 CONTINUED:"`, `"2 CONTINUED: (2)"`, `"CONTINUED:"`, `"(2) CONTINUED"`,
/// `"2 FORTSETZUNG"`. The keyword must be followed by nothing but separators,
/// digits and parentheses, so a dialogue line (`"Fortsetzung folgt."`) is never
/// stripped: the filter exists to remove page-break noise, not prose.
#[must_use]
pub fn is_continuation_marker(line: &str) -> bool {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return false;
    }
    // A continuation banner may be prefixed by the scene number or the page
    // number, in either order: `2 CONTINUED: (2)`, `(2) CONTINUED`.
    let stripped = trimmed.trim_start_matches(|c: char| {
        c.is_ascii_digit()
            || c.is_whitespace()
            || c == '.'
            || c == '-'
            || c == ':'
            || c == '('
            || c == ')'
    });
    let upper = stripped.to_ascii_uppercase();
    for keyword in ["CONTINUED", "FORTSETZUNG"] {
        if let Some(rest) = upper.strip_prefix(keyword)
            && rest.chars().all(|c| {
                c.is_ascii_digit()
                    || c.is_whitespace()
                    || c == '.'
                    || c == '-'
                    || c == ':'
                    || c == '('
                    || c == ')'
            })
        {
            return true;
        }
    }
    false
}

/// The accepted structural anchor plan: the zones Pass 0 decided plus the block
/// anchors the chunker actually cut at (ADR-041 `D3`/`D7`, issue #959).
///
/// It is the one artefact whose change must restart a partially extracted
/// document instead of splicing two plans, so it has a canonical, deterministic
/// rendering ([`Self::canonical_form`]) that the `#871` fingerprint digests. No
/// map iteration, no `Debug` formatting, no locale-dependent ordering: ascending
/// page, ascending anchor, one record per line.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct StructuralPlan {
    pages: Vec<PlanPage>,
}

/// One page of a [`StructuralPlan`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanPage {
    pub page_number: u32,
    pub zone: PageZone,
    /// Block anchors where a `SceneChunk` starts on this page, ascending.
    pub anchors: Vec<BlockAnchor>,
}

impl StructuralPlan {
    /// The plan the zone pass alone defines (no cut anchors yet).
    #[must_use]
    pub fn from_zones(zones: &DocumentZones) -> Self {
        Self {
            pages: zones
                .pages
                .iter()
                .map(|record| PlanPage {
                    page_number: record.page_number,
                    zone: record.zone,
                    anchors: Vec::new(),
                })
                .collect(),
        }
    }

    /// The plan's pages, in document order.
    #[must_use]
    pub fn pages(&self) -> &[PlanPage] {
        &self.pages
    }

    /// Whether the plan has no page at all (an empty document).
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.pages.is_empty()
    }

    /// Record one chunk-start anchor.
    ///
    /// Anchors must arrive in document order; a duplicate or a descending anchor
    /// is ignored and reported as `false`, so a plan can never render two
    /// different canonical forms for the same document (which would invalidate a
    /// chunk set at random). A page the pass did not see is ignored for the same
    /// reason.
    pub fn record_anchor(&mut self, anchor: BlockAnchor) -> bool {
        let Some(page) = self
            .pages
            .iter_mut()
            .find(|page| page.page_number == anchor.page_number)
        else {
            return false;
        };
        if page.anchors.last().is_some_and(|last| *last >= anchor) {
            return false;
        }
        page.anchors.push(anchor);
        true
    }

    /// The canonical rendering the fingerprint digests: one line per page,
    /// `P<NN>|<zone>|<anchor>,<anchor>` — ascending page, ascending anchor.
    #[must_use]
    pub fn canonical_form(&self) -> String {
        let mut out = String::new();
        for page in &self.pages {
            out.push_str(&format!("P{:02}|{}|", page.page_number, page.zone.as_str()));
            for (index, anchor) in page.anchors.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                out.push_str(&format!("{anchor}"));
            }
            out.push('\n');
        }
        out
    }
}

#[cfg(test)]
#[path = "document_tests.rs"]
mod document_tests;
