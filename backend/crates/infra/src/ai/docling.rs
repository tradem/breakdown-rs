// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Optional HTTP document-structure adapter for a self-hosted `docling-serve`
//! sidecar (ADR-041 `D1`/`D2`, issue #958).
//!
//! `docling-serve` (MIT / Apache-2.0, LF AI & Data) adds what Poppler cannot
//! see on its own: layout classification and, above all, `<table>` markup with
//! `colspan`/`rowspan` — the multi-row shooting-schedule cells that a flat text
//! dump scrambles (ADR-041 `D3`/`D6`).
//!
//! Three properties of this adapter are deliberate:
//!
//! * **The `reqwest::Client` is held by value.** `reqwest::Client` already wraps
//!   an internal `Arc`, so `#[derive(Clone)]` on this struct is a pointer bump;
//!   wrapping it in another `Arc` (or boxing the adapter behind
//!   `Arc<dyn DocumentStructureExtractor>`) would add a second refcount and a
//!   vtable hop for nothing.
//! * **No credentials.** The sidecar is an internal service: the request
//!   carries the document and nothing else, and the client is built with
//!   `no_proxy` + the curated HTTPS-only redirect policy at the composition
//!   root. There is no bearer token to leak (ADR-024).
//! * **Page geometry is unknown.** Docling's HTML export flattens pages, so the
//!   adapter emits ONE synthetic page whose blocks claim the full page box —
//!   the honest statement "no geometry", not a fabricated column. Anything that
//!   needs real page boxes (page streaming in issue #960) renders and reads the
//!   PDF page directly.

use std::time::Duration;

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use breakdown_core::ai::{
    BlockKind, DocumentStructureExtractor, ExtractionOptions, NormalizedBBox, RenderOptions,
    RenderedPage, StructuredDocument, StructuredPage,
};
use breakdown_core::error::DomainError;
use futures::StreamExt;
use reqwest::Url;
use serde::Deserialize;

use super::markup::{collapse_whitespace, strip_tags};
use super::spatial_pdf::SpatialPdfExtractor;

#[cfg(test)]
#[path = "docling_tests.rs"]
mod docling_tests;

/// Stable identifier of the HTTP algorithm (ADR-041 `D7`).
pub const DOCLING_PARSER_FINGERPRINT: &str = "docling-http-v1";

/// `docling-serve` conversion endpoint, relative to the configured base URL.
pub const DOCLING_CONVERT_PATH: &str = "v1/convert/source";

/// One block parsed out of Docling's HTML export, before it is placed on the
/// synthetic page.
#[derive(Debug, Clone, PartialEq)]
pub struct DoclingBlock {
    pub kind: BlockKind,
    pub text: String,
    pub html_table: Option<String>,
}

/// Bounded `docling-serve` adapter.
#[derive(Clone, Debug)]
pub struct DoclingHttpAdapter {
    client: reqwest::Client,
    base_url: Url,
    /// Ceiling for the JSON response body.
    max_output_bytes: usize,
    timeout: Duration,
    /// Docling cannot render page images locally, so [`Self::render_page`]
    /// delegates to the same on-demand Poppler renderer the spatial adapter
    /// uses. Rendering is a local, zero-egress operation either way.
    renderer: SpatialPdfExtractor,
}

impl DoclingHttpAdapter {
    /// Build the adapter. `base_url` must be an absolute `http(s)` URL with a
    /// trailing slash (or any path prefix that ends in `/`).
    #[must_use]
    pub fn new(
        client: reqwest::Client,
        base_url: Url,
        max_output_bytes: usize,
        timeout: Duration,
    ) -> Self {
        Self {
            client,
            base_url,
            max_output_bytes,
            timeout,
            renderer: SpatialPdfExtractor::new(max_output_bytes, timeout),
        }
    }

    /// The configured sidecar base URL (for startup logging).
    #[must_use]
    pub fn base_url(&self) -> &Url {
        &self.base_url
    }

    fn convert_endpoint(&self) -> Result<Url, DomainError> {
        self.base_url.join(DOCLING_CONVERT_PATH).map_err(|error| {
            DomainError::validation(format!(
                "the docling base URL {} cannot be joined with {DOCLING_CONVERT_PATH}: {error}",
                self.base_url
            ))
        })
    }

    /// Read the response body through a hard byte ceiling.
    ///
    /// Read incrementally rather than with `bytes()`: an unbounded `bytes()`
    /// call would allocate whatever the sidecar sends before the size check
    /// could reject it.
    async fn read_bounded(&self, response: reqwest::Response) -> Result<Vec<u8>, DomainError> {
        let mut body = Vec::new();
        let mut stream = response.bytes_stream();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|error| {
                DomainError::service_unavailable(format!(
                    "the docling response body could not be read: {error}"
                ))
            })?;
            if body.len().saturating_add(chunk.len()) > self.max_output_bytes {
                return Err(DomainError::validation(
                    "the docling response exceeds the configured bound",
                ));
            }
            body.extend_from_slice(&chunk);
        }
        Ok(body)
    }
}

impl DocumentStructureExtractor for DoclingHttpAdapter {
    fn parser_fingerprint(&self) -> &'static str {
        DOCLING_PARSER_FINGERPRINT
    }

    async fn extract(
        &self,
        bytes: &[u8],
        _options: ExtractionOptions,
    ) -> Result<StructuredDocument, DomainError> {
        if bytes.is_empty() {
            return Err(DomainError::validation("PDF document must not be empty"));
        }
        let endpoint = self.convert_endpoint()?;
        let request = serde_json::json!({
            "options": {
                // HTML is the only export that preserves `colspan`/`rowspan`
                // table markup, which is the whole reason to call Docling.
                "to_formats": ["html"],
                "image_export_mode": "placeholder"
            },
            "file_sources": [{
                "base64_string": BASE64.encode(bytes),
                "filename": "document.pdf"
            }]
        });
        let response = self
            .client
            .post(endpoint)
            .json(&request)
            .timeout(self.timeout)
            .send()
            .await
            .map_err(|error| {
                // Transport failures are transient by contract (#165): the job
                // retries instead of dying on a sidecar restart.
                DomainError::service_unavailable(format!(
                    "the docling sidecar could not be reached: {error}"
                ))
            })?;
        let status = response.status();
        let body = self.read_bounded(response).await?;
        if !status.is_success() {
            let detail = String::from_utf8_lossy(&body);
            let detail = detail.chars().take(200).collect::<String>();
            return Err(if status.is_client_error() {
                DomainError::validation(format!("docling rejected the document: {detail}"))
            } else {
                DomainError::service_unavailable(format!(
                    "the docling sidecar answered {status}: {detail}"
                ))
            });
        }
        let parsed: DoclingConvertResponse = serde_json::from_slice(&body).map_err(|error| {
            DomainError::validation(format!(
                "the docling response is not convertible JSON: {error}"
            ))
        })?;
        if let Some(status) = parsed.status.as_deref()
            && status != "success"
        {
            let errors = parsed.errors.unwrap_or_default().join("; ");
            return Err(DomainError::validation(format!(
                "docling reported {status} for the document: {errors}"
            )));
        }
        let html = parsed
            .document
            .and_then(|document| document.html_content)
            .ok_or_else(|| {
                DomainError::validation(
                    "docling returned no html_content; the sidecar must be called with \
                     options.to_formats = [\"html\"]",
                )
            })?;
        Ok(StructuredDocument::new(
            DOCLING_PARSER_FINGERPRINT,
            vec![page_from_docling_html(&html)],
        ))
    }

    async fn render_page(
        &self,
        bytes: &[u8],
        page_number: u32,
        options: RenderOptions,
    ) -> Result<RenderedPage, DomainError> {
        self.renderer.render_page(bytes, page_number, options).await
    }
}

/// `docling-serve`'s conversion envelope (only the fields this adapter reads).
#[derive(Debug, Deserialize)]
struct DoclingConvertResponse {
    document: Option<DoclingDocument>,
    status: Option<String>,
    errors: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct DoclingDocument {
    html_content: Option<String>,
}

/// Wrap the HTML export in the synthetic single page (see the module docs for
/// why Docling cannot supply page geometry).
#[must_use]
pub fn page_from_docling_html(html: &str) -> StructuredPage {
    let mut page = StructuredPage::new(1, 0.0, 0.0);
    for block in blocks_from_docling_html(html) {
        page.push_block_with_table(
            block.kind,
            NormalizedBBox::FULL_PAGE,
            block.text,
            block.html_table,
        );
    }
    page
}

/// Parse Docling's HTML export into blocks, preserving `<table>` markup.
///
/// Recognised structure: `<table>` → [`BlockKind::Table`] (verbatim markup, so
/// `colspan`/`rowspan` survive), `<h1>`…`<h6>` → [`BlockKind::Heading`],
/// everything else → [`BlockKind::Paragraph`] text. Docling HTML carries no
/// list semantics this adapter can trust, so no [`BlockKind::ListItem`] is
/// invented.
#[must_use]
pub fn blocks_from_docling_html(html: &str) -> Vec<DoclingBlock> {
    let mut blocks = Vec::new();
    let mut cursor = 0;
    while let Some((start, tag)) = next_structural_tag(html, cursor) {
        push_paragraph(&mut blocks, &html[cursor..start]);
        let Some(open_end) = html[start..].find('>').map(|index| start + index + 1) else {
            break;
        };
        let close_tag = format!("</{tag}>");
        let Some(close) = html[open_end..]
            .find(&close_tag)
            .map(|index| open_end + index)
        else {
            // Unterminated element: treat the rest as text rather than dropping
            // a document tail.
            push_paragraph(&mut blocks, &html[open_end..]);
            return blocks;
        };
        let inner = &html[open_end..close];
        if tag == "table" {
            blocks.push(DoclingBlock {
                kind: BlockKind::Table,
                text: table_text(inner),
                html_table: Some(html[start..close + close_tag.len()].to_owned()),
            });
        } else {
            let text = collapse_whitespace(&strip_tags(inner));
            if !text.is_empty() {
                blocks.push(DoclingBlock {
                    kind: BlockKind::Heading,
                    text,
                    html_table: None,
                });
            }
        }
        cursor = close + close_tag.len();
    }
    push_paragraph(&mut blocks, &html[cursor.min(html.len())..]);
    blocks
}

/// The earliest `<table>`/`<h1>`…`<h6>` opening tag at or after `cursor`.
fn next_structural_tag(html: &str, cursor: usize) -> Option<(usize, &'static str)> {
    const TAGS: [&str; 7] = ["table", "h1", "h2", "h3", "h4", "h5", "h6"];
    let mut best: Option<(usize, &'static str)> = None;
    for tag in TAGS {
        let needle = format!("<{tag}");
        if let Some(offset) = html[cursor..].find(&needle) {
            let start = cursor + offset;
            if best.is_none_or(|(best_start, _)| start < best_start) {
                best = Some((start, tag));
            }
        }
    }
    best
}

fn push_paragraph(blocks: &mut Vec<DoclingBlock>, markup: &str) {
    let text = collapse_whitespace(&strip_tags(markup));
    if text.is_empty() {
        return;
    }
    blocks.push(DoclingBlock {
        kind: BlockKind::Paragraph,
        text,
        html_table: None,
    });
}

/// Table cell texts as rows joined by newlines and cells by ` | `.
///
/// This is the **text hint** a multimodal caller can send along with the page
/// image; the authoritative cell structure lives in the preserved markup.
fn table_text(inner: &str) -> String {
    let mut rows: Vec<String> = Vec::new();
    let mut rest = inner;
    while let Some(row_start) = rest.find("<tr") {
        let Some(open_end) = rest[row_start..]
            .find('>')
            .map(|index| row_start + index + 1)
        else {
            break;
        };
        let body = &rest[open_end..];
        let row_len = body.find("</tr>").unwrap_or(body.len());
        let cells = cells_in_row(&body[..row_len]);
        if !cells.is_empty() {
            rows.push(cells.join(" | "));
        }
        rest = &body[row_len.min(body.len())..];
    }
    rows.join("\n")
}

fn cells_in_row(row: &str) -> Vec<String> {
    let mut cells = Vec::new();
    let mut rest = row;
    loop {
        // Header cells (`<th>`) are as load-bearing as body cells: the `ROLLEN`
        // legend's first row is exactly that.
        let cell = match (rest.find("<td"), rest.find("<th")) {
            (Some(td), Some(th)) => Some(if td < th { (td, "td") } else { (th, "th") }),
            (Some(td), None) => Some((td, "td")),
            (None, Some(th)) => Some((th, "th")),
            (None, None) => None,
        };
        let Some((cell_start, tag)) = cell else {
            break;
        };
        let Some(open_end) = rest[cell_start..]
            .find('>')
            .map(|index| cell_start + index + 1)
        else {
            break;
        };
        let close_tag = format!("</{tag}>");
        let body = &rest[open_end..];
        let cell_len = body.find(&close_tag).unwrap_or(body.len());
        cells.push(collapse_whitespace(&strip_tags(&body[..cell_len])));
        rest = &body[cell_len.min(body.len())..];
    }
    cells
}
