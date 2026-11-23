// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! Flat-text PDF adapter: `pdftotext -q -layout` (ADR-041, issue #958).
//!
//! This is the pre-ADR-041 extraction path behind the
//! [`DocumentStructureExtractor`] port. It exists for two reasons and no
//! others: it is the **rollback target** (`AI_DOCUMENT_PARSER=legacy-pdftotext`)
//! if the spatial adapter misreads a real document, and it keeps the whole
//! existing test corpus meaningful — every worker test that drives a PDF keeps
//! working against a real port implementation, unchanged.
//!
//! The layout text carries no geometry and no page size, so pages are
//! reconstructed from the form feeds `pdftotext` emits. That limitation is the
//! reason the spatial adapter exists: zoning (issue #959) needs coordinates and
//! page sizes, which this adapter cannot invent.

use std::time::Duration;

use breakdown_core::ai::{
    BlockKind, DocumentStructureExtractor, ExtractionOptions, NormalizedBBox, RenderOptions,
    RenderedPage, StructuredDocument, StructuredPage,
};
use breakdown_core::error::DomainError;

use super::subprocess::run_bounded;

#[cfg(test)]
#[path = "pdf_tests.rs"]
mod pdf_tests;

/// Stable identifier of the flat-text algorithm (ADR-041 `D7`). Folded into
/// the `#871` chunk fingerprint, so switching to or away from this adapter
/// restarts extraction at chunk `0`.
pub const LEGACY_PARSER_FINGERPRINT: &str = "legacy-pdftotext-v1";

/// The form feed `pdftotext` writes between pages.
const PAGE_BREAK: char = '\u{c}';

/// Bounded `pdftotext -layout` adapter. PDF bytes are sent through stdin so no
/// temporary document is persisted by this adapter.
///
/// `Copy` on purpose: it is two machine words of configuration, so a worker
/// holds it by value. It must never be wrapped in an `Arc` — there is no
/// shared state to share.
#[derive(Clone, Copy, Debug)]
pub struct LegacyPdfToTextAdapter {
    pub max_output_bytes: usize,
    pub timeout: Duration,
}

impl LegacyPdfToTextAdapter {
    #[must_use]
    pub const fn new(max_output_bytes: usize, timeout: Duration) -> Self {
        Self {
            max_output_bytes,
            timeout,
        }
    }

    /// The raw `pdftotext -q -layout` output — the pre-ADR-041 return value,
    /// kept as a named seam so the existing line-based pipeline can be tested
    /// against exactly the bytes it always saw.
    pub async fn extract_layout_text(&self, pdf_bytes: &[u8]) -> Result<String, DomainError> {
        if pdf_bytes.is_empty() {
            return Err(DomainError::validation("PDF document must not be empty"));
        }
        let output = run_bounded(
            "pdftotext",
            &["-q", "-layout", "-", "-"],
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

/// Split flat layout text into 1-based pages on the form feed.
///
/// One block per page, with [`NormalizedBBox::FULL_PAGE`] geometry: this text
/// carries no coordinates, and a fabricated column would feed a wrong
/// indentation signal into the zoning pass. `width_pt`/`height_pt` stay `0.0`
/// for the same reason (see [`StructuredPage::has_geometry`]).
#[must_use]
pub fn pages_from_layout_text(text: &str) -> Vec<StructuredPage> {
    text.split(PAGE_BREAK)
        .enumerate()
        .map(|(index, chunk)| {
            let page_number = u32::try_from(index).unwrap_or(u32::MAX).saturating_add(1);
            let mut page = StructuredPage::new(page_number, 0.0, 0.0);
            page.push_block(BlockKind::Paragraph, NormalizedBBox::FULL_PAGE, chunk);
            page
        })
        .collect()
}

impl DocumentStructureExtractor for LegacyPdfToTextAdapter {
    fn parser_fingerprint(&self) -> &'static str {
        LEGACY_PARSER_FINGERPRINT
    }

    async fn extract(
        &self,
        bytes: &[u8],
        _options: ExtractionOptions,
    ) -> Result<StructuredDocument, DomainError> {
        let text = self.extract_layout_text(bytes).await?;
        Ok(StructuredDocument::new(
            LEGACY_PARSER_FINGERPRINT,
            pages_from_layout_text(&text),
        ))
    }

    async fn render_page(
        &self,
        _bytes: &[u8],
        page_number: u32,
        _options: RenderOptions,
    ) -> Result<RenderedPage, DomainError> {
        // Explicit rather than silently empty: a caller that needs page images
        // must select `AI_DOCUMENT_PARSER=spatial` instead of receiving nothing
        // and wondering why the multimodal call saw no image.
        Err(DomainError::validation(format!(
            "the legacy-pdftotext adapter cannot render page {page_number}; \
             select AI_DOCUMENT_PARSER=spatial for page images"
        )))
    }
}
