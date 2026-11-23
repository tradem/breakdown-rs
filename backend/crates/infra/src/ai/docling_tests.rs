// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Unit tests for the `docling-serve` HTTP adapter (issue #958).
//!
//! The HTML→blocks transform is tested directly; the HTTP path is driven against
//! a loopback mock so no sidecar is needed in CI.

use std::net::SocketAddr;
use std::time::Duration;

use breakdown_core::ai::{
    BlockKind, DocumentStructureExtractor, ExtractionOptions, NormalizedBBox, RenderOptions,
};
use breakdown_core::error::DomainError;
use reqwest::Url;

use super::{
    DOCLING_PARSER_FINGERPRINT, DoclingHttpAdapter, blocks_from_docling_html,
    page_from_docling_html,
};

// ===========================================================================
// HTML → blocks
// ===========================================================================

const DOCLING_HTML: &str = r#"<h1>ROLLEN</h1>
<p>Die Zahlen verweisen auf die Rollenliste.</p>
<table><tr><th>Nr</th><th>Rolle</th></tr>
<tr><td colspan="2" rowspan="2">300.33 &amp; 300.37</td></tr></table>
<h2>DREHPLAN</h2><p>Tag 1</p>"#;

#[test]
fn headings_tables_and_paragraphs_are_recognized() {
    let blocks = blocks_from_docling_html(DOCLING_HTML);
    let kinds: Vec<BlockKind> = blocks.iter().map(|block| block.kind).collect();
    assert_eq!(
        kinds,
        vec![
            BlockKind::Heading,
            BlockKind::Paragraph,
            BlockKind::Table,
            BlockKind::Heading,
            BlockKind::Paragraph,
        ]
    );
    assert_eq!(blocks[0].text, "ROLLEN");
    assert_eq!(blocks[3].text, "DREHPLAN");
}

#[test]
fn table_markup_preserves_colspan_and_rowspan() {
    let blocks = blocks_from_docling_html(DOCLING_HTML);
    let table = blocks
        .iter()
        .find(|block| block.kind == BlockKind::Table)
        .expect("the fixture has a table");
    let html = table.html_table.as_deref().expect("table markup is kept");
    assert!(html.contains("colspan=\"2\""), "html was {html}");
    assert!(html.contains("rowspan=\"2\""), "html was {html}");
    assert!(html.starts_with("<table>"));
}

#[test]
fn table_text_is_a_row_and_cell_hint() {
    let blocks = blocks_from_docling_html(DOCLING_HTML);
    let table = blocks
        .iter()
        .find(|block| block.kind == BlockKind::Table)
        .expect("the fixture has a table");
    assert_eq!(table.text, "Nr | Rolle\n300.33 & 300.37");
}

#[test]
fn paragraphs_collapse_whitespace_and_drop_empty_segments() {
    let blocks = blocks_from_docling_html(
        "<p>  a
       b </p>\n<div></div>\n",
    );
    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0].text, "a b");
}

#[test]
fn an_unterminated_table_does_not_swallow_the_document_tail() {
    let blocks = blocks_from_docling_html("<p>before</p><table><tr><td>cell");
    assert_eq!(blocks[0].text, "before");
    assert_eq!(blocks[1].kind, BlockKind::Paragraph);
    assert_eq!(blocks[1].text, "cell");
}

#[test]
fn an_empty_export_yields_no_blocks() {
    assert!(blocks_from_docling_html("").is_empty());
}

#[test]
fn the_synthetic_page_claims_no_geometry() {
    let page = page_from_docling_html(DOCLING_HTML);
    assert_eq!(page.page_number, 1);
    assert!(!page.has_geometry(), "docling HTML carries no page size");
    assert!(
        page.blocks
            .iter()
            .all(|b| b.bbox == NormalizedBBox::FULL_PAGE)
    );
    assert!(page.blocks.iter().all(|b| b.id.page_number == 1));
    let ordinals: Vec<u32> = page.blocks.iter().map(|b| b.id.block_ordinal).collect();
    assert_eq!(ordinals, vec![0, 1, 2, 3, 4]);
}

#[test]
fn only_tables_keep_table_markup() {
    let mut page = breakdown_core::ai::StructuredPage::new(1, 0.0, 0.0);
    page.push_block_with_table(
        BlockKind::Paragraph,
        NormalizedBBox::FULL_PAGE,
        "prose",
        Some("<table></table>".to_owned()),
    );
    assert!(page.blocks[0].html_table.is_none());
}

// ===========================================================================
// HTTP adapter
// ===========================================================================

#[test]
fn the_fingerprint_names_the_http_algorithm() {
    let adapter = DoclingHttpAdapter::new(
        reqwest::Client::new(),
        Url::parse("http://docling:5001/").expect("a valid URL"),
        1024,
        Duration::from_secs(5),
    );
    assert_eq!(adapter.parser_fingerprint(), "docling-http-v1");
    assert_eq!(adapter.parser_fingerprint(), DOCLING_PARSER_FINGERPRINT);
    assert_eq!(adapter.base_url().as_str(), "http://docling:5001/");
}

/// One-shot loopback HTTP server, answering any request with `response`.
async fn mock_docling(response: String) -> (Url, SocketAddr) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("a loopback listener");
    let addr = listener.local_addr().expect("a bound address");
    tokio::spawn(async move {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let Ok((mut socket, _)) = listener.accept().await else {
            return;
        };
        let mut request = [0_u8; 8192];
        let _ = socket.read(&mut request).await;
        let _ = socket.write_all(response.as_bytes()).await;
        let _ = socket.flush().await;
    });
    (
        Url::parse(&format!("http://{addr}/")).expect("a valid URL"),
        addr,
    )
}

fn http_response(status: &str, body: &str) -> String {
    format!(
        "HTTP/1.1 {status}\r\ncontent-type: application/json\r\ncontent-length: {}\r\n\r\n{body}",
        body.len()
    )
}

fn adapter_for(url: Url) -> DoclingHttpAdapter {
    DoclingHttpAdapter::new(
        reqwest::Client::builder()
            .no_proxy()
            .build()
            .expect("a client"),
        url,
        1024 * 1024,
        Duration::from_secs(5),
    )
}

#[tokio::test]
async fn extract_parses_a_successful_conversion() {
    let body = r#"{"status":"success","document":{"html_content":"<h1>ROLLEN</h1>"}}"#;
    let (url, _addr) = mock_docling(http_response("200 OK", body)).await;
    let document = adapter_for(url)
        .extract(b"%PDF-1.4", ExtractionOptions::default())
        .await
        .expect("the mock answers a conversion");
    assert_eq!(document.parser_fingerprint, DOCLING_PARSER_FINGERPRINT);
    assert_eq!(document.page_count(), 1);
    assert_eq!(document.blocks().count(), 1);
    assert_eq!(document.flattened_text(), "ROLLEN");
}

#[tokio::test]
async fn extract_rejects_an_empty_document_before_any_request() {
    let (url, _addr) = mock_docling(http_response("200 OK", "{}")).await;
    let error = adapter_for(url)
        .extract(&[], ExtractionOptions::default())
        .await
        .expect_err("an empty document must not be uploaded");
    assert!(error.to_string().contains("must not be empty"));
}

#[tokio::test]
async fn a_client_error_from_the_sidecar_is_a_validation_error() {
    let (url, _addr) =
        mock_docling(http_response("400 Bad Request", r#"{"detail":"bad pdf"}"#)).await;
    let error = adapter_for(url)
        .extract(b"%PDF-1.4", ExtractionOptions::default())
        .await
        .expect_err("a 400 must fail");
    assert!(matches!(error, DomainError::Validation { .. }));
    assert!(error.to_string().contains("bad pdf"), "unexpected: {error}");
}

#[tokio::test]
async fn a_server_error_from_the_sidecar_is_transient() {
    let (url, _addr) = mock_docling(http_response("503 Service Unavailable", "{}")).await;
    let error = adapter_for(url)
        .extract(b"%PDF-1.4", ExtractionOptions::default())
        .await
        .expect_err("a 503 must fail");
    assert!(error.is_retryable(), "a sidecar restart must be retried");
}

#[tokio::test]
async fn a_failed_conversion_status_names_the_reported_errors() {
    let body = r#"{"status":"failure","errors":["unsupported layout"]}"#;
    let (url, _addr) = mock_docling(http_response("200 OK", body)).await;
    let error = adapter_for(url)
        .extract(b"%PDF-1.4", ExtractionOptions::default())
        .await
        .expect_err("a failure status must not pass silently");
    assert!(
        error.to_string().contains("unsupported layout"),
        "unexpected: {error}"
    );
}

#[tokio::test]
async fn a_response_without_html_content_is_a_validation_error() {
    let body = r##"{"status":"success","document":{"md_content":"# ROLLEN"}}"##;
    let (url, _addr) = mock_docling(http_response("200 OK", body)).await;
    let error = adapter_for(url)
        .extract(b"%PDF-1.4", ExtractionOptions::default())
        .await
        .expect_err("markdown is not the requested format");
    assert!(
        error.to_string().contains("html_content"),
        "unexpected: {error}"
    );
}

#[tokio::test]
async fn an_unreachable_sidecar_is_transient() {
    // Bind and immediately drop, so the address is (almost certainly) closed.
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("a loopback listener");
    let url = Url::parse(&format!(
        "http://{}/",
        listener.local_addr().expect("a bound address")
    ))
    .expect("a valid URL");
    drop(listener);
    let error = adapter_for(url)
        .extract(b"%PDF-1.4", ExtractionOptions::default())
        .await
        .expect_err("a closed port must fail");
    assert!(error.is_retryable(), "a sidecar restart must be retried");
}

#[tokio::test]
async fn render_page_delegates_to_the_local_renderer() {
    let adapter = DoclingHttpAdapter::new(
        reqwest::Client::new(),
        Url::parse("http://docling:5001/").expect("a valid URL"),
        1024,
        Duration::from_secs(5),
    );
    // No PDF bytes: the local renderer rejects before any subprocess starts, so
    // this asserts the delegation without needing poppler.
    let error = adapter
        .render_page(&[], 1, RenderOptions::default())
        .await
        .expect_err("an empty document cannot be rendered");
    assert!(error.to_string().contains("must not be empty"));
}
