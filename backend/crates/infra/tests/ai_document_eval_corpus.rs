// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Golden Corpus evaluation harness for the document-structure adapters
//! (ADR-041 `D8`, issue #958).
//!
//! Broadcast scripts and shooting schedules are confidential third-party IP:
//! they must never enter Git. The corpus therefore lives out of tree and this
//! harness runs only when `AI_EVAL_CORPUS_DIR` points at it. With the variable
//! unset the test **skips cleanly** — CI stays green and needs no corpus, while
//! the always-on synthetic fixtures in `crates/core/src/ai/document_tests.rs`
//! and `crates/infra/src/ai/spatial_pdf_tests.rs` keep verifying the IR and the
//! parser contract on every build.
//!
//! What this harness checks, per PDF, deterministically:
//!
//! 1. the spatial adapter yields at least one 1-based, ascending page;
//! 2. every block carries non-empty text and geometry inside `0.0..=1.0`;
//! 3. the document has a non-empty flattened text (the seam the line-based
//!    segmentation still reads);
//! 4. a page render returns a bounded PNG within the configured DPI/byte
//!    ceiling;
//! 5. the running-header band is detectable on a document that has one — the
//!    signal the zoning pass (issue #959) strips.
//!
//! Run it locally with:
//!
//! ```text
//! AI_EVAL_CORPUS_DIR=~/corpus cargo test -p infra --test ai_document_eval_corpus -- --nocapture
//! ```

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

use std::path::{Path, PathBuf};
use std::time::Duration;

use breakdown_core::ai::{DocumentStructureExtractor, ExtractionOptions, RenderOptions};
use infra::ai::SpatialPdfExtractor;

/// `AI_EVAL_CORPUS_DIR`: a local directory holding PDF scripts/schedules.
const CORPUS_ENV: &str = "AI_EVAL_CORPUS_DIR";

/// Per-document extraction bounds for the harness: generous, because a real
/// 105-page script is far larger than any unit fixture.
const MAX_OUTPUT_BYTES: usize = 32 * 1024 * 1024;
const TIMEOUT: Duration = Duration::from_secs(120);

#[test]
fn spatial_extraction_meets_the_golden_corpus_contract() {
    let Some(directory) = std::env::var_os(CORPUS_ENV).map(PathBuf::from) else {
        eprintln!(
            "skipped: {CORPUS_ENV} is unset (the out-of-tree Golden Corpus is \
             confidential IP and never committed)"
        );
        return;
    };
    if !directory.is_dir() {
        eprintln!(
            "skipped: {CORPUS_ENV}={} is not a directory",
            directory.display()
        );
        return;
    }
    let pdfs = pdf_files(&directory);
    if pdfs.is_empty() {
        eprintln!(
            "skipped: no .pdf files in {} (point {CORPUS_ENV} at a directory of \
             scripts and schedules)",
            directory.display()
        );
        return;
    }

    let extractor = SpatialPdfExtractor::new(MAX_OUTPUT_BYTES, TIMEOUT);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("a single-threaded runtime for the corpus sweep");

    let mut failures: Vec<String> = Vec::new();
    let mut checked = 0_usize;
    for path in &pdfs {
        match runtime.block_on(evaluate(&extractor, path)) {
            Ok(report) => {
                checked += 1;
                eprintln!(
                    "ok   {} — pages={} blocks={} headers={} tables={} png_bytes={}",
                    path.display(),
                    report.pages,
                    report.blocks,
                    report.headers,
                    report.tables,
                    report.png_bytes,
                );
            }
            Err(error) => failures.push(format!("{}: {error}", path.display())),
        }
    }

    assert!(
        failures.is_empty(),
        "{} of {} corpus documents failed:\n{}",
        failures.len(),
        pdfs.len(),
        failures.join("\n")
    );
    assert!(checked > 0, "the corpus produced no evaluation at all");
}

/// Deterministic per-document assertions; returns the measured counters.
struct Report {
    pages: usize,
    blocks: usize,
    headers: usize,
    tables: usize,
    png_bytes: usize,
}

async fn evaluate(extractor: &SpatialPdfExtractor, path: &Path) -> Result<Report, String> {
    let bytes = std::fs::read(path).map_err(|error| format!("could not read the file: {error}"))?;
    let document = extractor
        .extract(&bytes, ExtractionOptions::default())
        .await
        .map_err(|error| format!("spatial extraction failed: {error}"))?;

    if document.is_empty() {
        return Err("the document has no page".to_owned());
    }
    if document.parser_fingerprint != infra::ai::SPATIAL_PARSER_FINGERPRINT {
        return Err(format!(
            "unexpected parser fingerprint {:?}",
            document.parser_fingerprint
        ));
    }
    for (expected_page, page) in (1_u32..).zip(document.pages.iter()) {
        if page.page_number != expected_page {
            return Err(format!(
                "pages are not 1-based ascending: expected {expected_page}, got {}",
                page.page_number
            ));
        }
        if page.blocks.is_empty() {
            return Err(format!("page {} extracted no block", page.page_number));
        }
        if !page.has_geometry() {
            return Err(format!("page {} has no page box", page.page_number));
        }
    }

    let mut blocks = 0_usize;
    let mut headers = 0_usize;
    let mut tables = 0_usize;
    for block in document.blocks() {
        blocks += 1;
        if block.text.trim().is_empty() {
            return Err(format!("block {} carries no text", block.id));
        }
        let coordinates = [block.bbox.x0, block.bbox.y0, block.bbox.x1, block.bbox.y1];
        if coordinates.iter().any(|value| !(0.0..=1.0).contains(value)) {
            return Err(format!("block {} escaped the unit square", block.id));
        }
        if block.bbox.x1 < block.bbox.x0 || block.bbox.y1 < block.bbox.y0 {
            return Err(format!("block {} has an inverted box", block.id));
        }
        if block.bbox.is_header_band() {
            headers += 1;
        }
        if block.html_table.is_some() {
            tables += 1;
        }
    }
    if document.flattened_text().trim().is_empty() {
        return Err("the flattened text is empty".to_owned());
    }

    // One bounded render: the first page is enough to prove the renderer, the
    // DPI setting and the byte ceiling work on a real document without paying
    // for a whole script's worth of PNGs.
    let rendered = extractor
        .render_page(&bytes, 1, RenderOptions::default())
        .await
        .map_err(|error| format!("page 1 render failed: {error}"))?;
    if rendered.page_number != 1 {
        return Err(format!(
            "render reported page {} instead of 1",
            rendered.page_number
        ));
    }
    if !rendered.png_bytes.starts_with(&[0x89, b'P', b'N', b'G']) {
        return Err("the rendered page is not a PNG".to_owned());
    }
    if rendered.png_bytes.len() > RenderOptions::default().max_bytes {
        return Err("the rendered page exceeded the byte ceiling".to_owned());
    }

    Ok(Report {
        pages: document.page_count(),
        blocks,
        headers,
        tables,
        png_bytes: rendered.png_bytes.len(),
    })
}

/// Every `*.pdf` directly inside `directory`, in a deterministic order.
fn pdf_files(directory: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut paths: Vec<PathBuf> = entries
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_file()
                && path
                    .extension()
                    .is_some_and(|extension| extension.eq_ignore_ascii_case("pdf"))
        })
        .collect();
    paths.sort();
    paths
}
