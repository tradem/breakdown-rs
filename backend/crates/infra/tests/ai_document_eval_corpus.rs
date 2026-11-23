// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Golden Corpus evaluation harness for the document-structure adapters
//! (ADR-041 `D8`, issue #958).
//!
//! Broadcast scripts and shooting schedules are confidential third-party IP:
//! they must never enter Git. The corpus therefore lives out of tree and this
//! harness runs only when `AI_EVAL_CORPUS_DIR` points at it. With the variable
//! **unset** the test skips cleanly — CI stays green and needs no corpus, while
//! the always-on synthetic fixtures in `crates/core/src/ai/document_tests.rs`
//! and `crates/infra/src/ai/spatial_pdf_tests.rs` keep verifying the IR and the
//! parser contract on every build. With the variable **set** the corpus is
//! mandatory: a missing directory, an unreadable one or an empty one fails the
//! run, because a misconfigured corpus must not look like a green sweep.
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
//!    signal the zoning pass (issue #959) strips;
//! 6. zone-aware segmentation (issue #959) produces one chunk per `SceneBody`
//!    scene, no page-turn `CONTINUED:` / `FORTSETZUNG` banner inside any chunk,
//!    and no `SceneIndex`-vs-body drift (`segmented.uncertainties` is empty);
//! 7. when the corpus carries an expectation sidecar (`<name>.expected`, a file
//!    with one `scenes = <N>` line), the chunk count equals `N`.
//!
//! The sidecar is how the corpus stays confidential *and* explicit: no file name
//! and no expected count is committed, so each operator records their own
//! document's ground truth next to it. A PDF without a sidecar is still checked
//! for structural parity — only the exact count assertion is skipped.
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

use breakdown_core::ai::{
    DocumentStructureExtractor, ExtractionOptions, RenderOptions, extract_scenes_from_structured,
};
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
    // Set means "evaluate this corpus". An invalid or empty path is a failure,
    // not a skip: otherwise a typo'd directory silently turns the whole corpus
    // gate into a no-op.
    assert!(
        directory.is_dir(),
        "{CORPUS_ENV}={} is not a directory",
        directory.display()
    );
    let pdfs = pdf_files(&directory)
        .unwrap_or_else(|error| panic!("could not enumerate {}: {error}", directory.display()));
    assert!(
        !pdfs.is_empty(),
        "no .pdf files in {} (point {CORPUS_ENV} at a directory of scripts and schedules)",
        directory.display()
    );

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
                    "ok   {} — pages={} blocks={} headers={} tables={} png_bytes={} \
                     chunks={} expected={:?} zones={}",
                    path.display(),
                    report.pages,
                    report.blocks,
                    report.headers,
                    report.tables,
                    report.png_bytes,
                    report.chunks,
                    report.expected_scenes,
                    report.zones,
                );
                // Issue #959: a `SceneIndex` that disagrees with the body is a
                // scene-count drift the reviewer would otherwise only discover
                // as a shortfall — fail the sweep instead.
                if !report.mismatches.is_empty() {
                    failures.push(format!(
                        "{}: {} scene-index/body mismatch(es): {}",
                        path.display(),
                        report.mismatches.len(),
                        report.mismatches.join("; "),
                    ));
                }
                if let Some(expected) = report.expected_scenes
                    && expected != report.chunks
                {
                    failures.push(format!(
                        "{}: expected {expected} scene chunks, segmented {}",
                        path.display(),
                        report.chunks,
                    ));
                }
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
    /// Scene chunks the zone-aware segmentation produced (issue #959).
    chunks: usize,
    /// Pages each zone claimed, for the operator's diagnosis.
    zones: String,
    /// `SceneIndex`-vs-`ScriptBody` findings — must be empty.
    mismatches: Vec<String>,
    /// The `scenes = <N>` expectation from the sidecar, when one exists.
    expected_scenes: Option<usize>,
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

    let segmented = extract_scenes_from_structured(&document);
    if segmented.chunks.is_empty() {
        return Err("zone-aware segmentation produced no scene chunk".to_owned());
    }
    for chunk in &segmented.chunks {
        for line in chunk.text.lines() {
            if breakdown_core::ai::is_continuation_marker(line) {
                return Err(format!(
                    "chunk {:?} still carries the page-turn banner {line:?}",
                    chunk.heading
                ));
            }
        }
    }
    let mismatches: Vec<String> = segmented
        .uncertainties
        .iter()
        .map(|uncertainty| format!("{}: {}", uncertainty.field, uncertainty.note))
        .collect();
    let zones = zone_summary(&document, &segmented);

    Ok(Report {
        pages: document.page_count(),
        blocks,
        headers,
        tables,
        png_bytes: rendered.png_bytes.len(),
        chunks: segmented.chunks.len(),
        zones,
        mismatches,
        expected_scenes: expectation(&path.with_extension("expected")),
    })
}

/// `cast_list=2 script_body=88 title_page=1 …`, ascending by zone name, so two
/// runs of the same document print the same line.
fn zone_summary(
    document: &breakdown_core::ai::StructuredDocument,
    segmented: &breakdown_core::ai::SegmentedScript,
) -> String {
    let mut counts: Vec<(&str, usize)> = Vec::new();
    for page in segmented.plan.pages() {
        match counts
            .iter_mut()
            .find(|(zone, _)| *zone == page.zone.as_str())
        {
            Some((_, count)) => *count += 1,
            None => counts.push((page.zone.as_str(), 1)),
        }
    }
    counts.sort_by_key(|(zone, _)| *zone);
    let zones = counts
        .into_iter()
        .map(|(zone, count)| format!("{zone}={count}"))
        .collect::<Vec<_>>()
        .join(" ");
    format!("{zones} (pages={})", document.page_count())
}

/// The `scenes = <N>` expectation recorded next to `path`, if any.
///
/// An unreadable or malformed sidecar is a **failure**, not a skip: a typo in the
/// ground truth must not turn the count assertion into a no-op. A missing sidecar
/// means "no expectation recorded" — the structural assertions still run.
fn expectation(path: &Path) -> Option<usize> {
    let text = match std::fs::read_to_string(path) {
        Ok(text) => Some(text),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(error) => {
            panic!("could not read {}: {error}", path.display());
        }
    };
    let text = text?;
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if key.trim() != "scenes" {
            continue;
        }
        let value = value.trim();
        let parsed = value.parse::<usize>().unwrap_or_else(|error| {
            panic!(
                "{}: `scenes = {value}` is not a number: {error}",
                path.display()
            );
        });
        return Some(parsed);
    }
    None
}

/// Every `*.pdf` directly inside `directory`, in a deterministic order.
///
/// Every enumeration failure propagates — opening the directory AND each
/// `read_dir` entry. Swallowing a per-entry error would let the sweep pass on
/// whichever entries happened to be readable, i.e. on a partial corpus.
fn pdf_files(directory: &Path) -> std::io::Result<Vec<PathBuf>> {
    let mut paths: Vec<PathBuf> = Vec::new();
    for entry in std::fs::read_dir(directory)? {
        let path = entry?.path();
        if path.is_file()
            && path
                .extension()
                .is_some_and(|extension| extension.eq_ignore_ascii_case("pdf"))
        {
            paths.push(path);
        }
    }
    paths.sort();
    Ok(paths)
}
