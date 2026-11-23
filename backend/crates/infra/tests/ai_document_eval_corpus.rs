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
//! 7. the manifest (`config/ai_eval_corpus.tsv`) lists every document with its
//!    kind and expected scene count; a script's chunk count must equal that
//!    number, and a listed file that is missing from the directory is a failure.
//!
//! The manifest is the one place that defines "the corpus", so a local run and a
//! CI run assert exactly the same thing — the PDFs stay out of Git, the
//! expectations do not. A PDF the manifest does not list is still checked
//! structurally; it just carries no count expectation.
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
    CastDirectory, DocumentStructureExtractor, ExtractionOptions, RenderOptions,
    extract_scenes_from_structured, resolve_character_category,
};
use breakdown_core::character::category::CharacterCategory;
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
    // The manifest is the contract, so a corpus that is missing a document it
    // lists is INCOMPLETE — checking only the files that happen to be there
    // would let a partial checkout pass as a green sweep.
    let expectations = read_manifest(&manifest_path());
    assert!(
        !expectations.is_empty(),
        "{} lists no document",
        manifest_path().display()
    );
    let mut absent: Vec<String> = Vec::new();
    for expectation in &expectations {
        if !pdfs
            .iter()
            .any(|pdf| pdf.file_name().and_then(|name| name.to_str()) == Some(&expectation.file))
        {
            absent.push(format!("{} ({})", expectation.file, expectation.note));
        }
    }

    let extractor = SpatialPdfExtractor::new(MAX_OUTPUT_BYTES, TIMEOUT);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("a single-threaded runtime for the corpus sweep");

    let mut failures: Vec<String> = Vec::new();
    if !absent.is_empty() {
        failures.push(format!(
            "the corpus is incomplete — missing {}: {}",
            absent.len(),
            absent.join(", "),
        ));
    }
    let mut checked = 0_usize;
    for path in &pdfs {
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("");
        let expectation = expectations
            .iter()
            .find(|entry| entry.file == name)
            .cloned();
        match runtime.block_on(evaluate(&extractor, path, expectation)) {
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
                    report.expectation.as_ref().map(|entry| entry.scenes),
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
                if !report.cast_failures.is_empty() {
                    failures.push(format!(
                        "{}: {} cast-category assertion(s) failed: {}",
                        path.display(),
                        report.cast_failures.len(),
                        report.cast_failures.join("; "),
                    ));
                }
                if let Some(expectation) = &report.expectation
                    && expectation.kind == DocumentClass::Script
                    && expectation.scenes != report.chunks
                {
                    failures.push(format!(
                        "{}: manifest expects {} scene chunks ({}), segmented {}",
                        path.display(),
                        expectation.scenes,
                        expectation.kind.as_str(),
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
    /// Cast-directory category assertions that did not resolve as declared.
    cast_failures: Vec<String>,
    /// The manifest's entry for this file, when the manifest lists it.
    expectation: Option<Expectation>,
}

/// One `config/ai_eval_corpus.tsv` record: what the corpus owner states about a
/// document.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Expectation {
    file: String,
    kind: DocumentClass,
    scenes: usize,
    note: String,
    /// `name:category` assertions checked against the parsed `CastDirectory`
    /// (issue #961). The name may be a short scene cue; the deterministic
    /// resolver applies the documented given-name/surname rule.
    cast: Vec<CastAssertion>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CastAssertion {
    name: String,
    category: CharacterCategory,
}

impl CastAssertion {
    fn parse(value: &str, path: &Path, line: usize) -> Vec<Self> {
        let value = value.trim();
        if value.is_empty() || value == "-" {
            return Vec::new();
        }
        let Some(list) = value.strip_prefix("cast=") else {
            panic!(
                "{}:{line}: expected `cast=<name>:<category>,…`, got {value:?}",
                path.display()
            );
        };
        list.split(',')
            .map(|entry| {
                let (name, category) = entry.trim().split_once(':').unwrap_or_else(|| {
                    panic!(
                        "{}:{line}: cast assertion {entry:?} needs `name:category`",
                        path.display()
                    )
                });
                let category = match category.trim() {
                    "main_cast" => CharacterCategory::MainCast,
                    "guest" => CharacterCategory::Guest,
                    "extra" => CharacterCategory::Extra,
                    other => panic!("{}:{line}: unknown cast category {other:?}", path.display()),
                };
                Self {
                    name: name.trim().to_owned(),
                    category,
                }
            })
            .collect()
    }
}

/// Resolve the manifest assertions through the SAME pure resolver the worker
/// uses; a corpus that passes here proves the deterministic ladder, not a
/// hand-written lookup in the harness.
fn cast_failures(directory: &CastDirectory, assertions: &[CastAssertion]) -> Vec<String> {
    assertions
        .iter()
        .filter_map(|assertion| {
            let (resolved, uncertainty) =
                resolve_character_category(&assertion.name, 0, directory, &[], &[]);
            if resolved == assertion.category && uncertainty.is_none() {
                None
            } else {
                Some(format!(
                    "cast {:?}: expected {:?}, resolved {:?}",
                    assertion.name, assertion.category, resolved
                ))
            }
        })
        .collect()
}

/// What kind of document an expectation describes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DocumentClass {
    /// A screenplay: the zone-aware segmentation assertions apply.
    Script,
    /// A shooting schedule: read by the schedule worker, so the script assertions
    /// (scene chunks, index parity) do not.
    Schedule,
}

impl DocumentClass {
    fn parse(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "script" => Some(Self::Script),
            "schedule" => Some(Self::Schedule),
            _ => None,
        }
    }

    const fn as_str(self) -> &'static str {
        match self {
            Self::Script => "script",
            Self::Schedule => "schedule",
        }
    }
}

async fn evaluate(
    extractor: &SpatialPdfExtractor,
    path: &Path,
    expectation: Option<Expectation>,
) -> Result<Report, String> {
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

    // A schedule is read by the schedule worker, never by the script
    // segmentation: segmenting it here would report a scene count for a document
    // that has none, and asserting scene chunks on it would be a false contract.
    // Its structural IR assertions above still run.
    let is_script = expectation
        .as_ref()
        .is_none_or(|expectation| expectation.kind == DocumentClass::Script);
    let (chunks, zones, mismatches, cast_failures) = if is_script {
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
        let cast_failures = expectation
            .as_ref()
            .map(|entry| cast_failures(&segmented.cast_directory, &entry.cast))
            .unwrap_or_default();
        (
            segmented.chunks.len(),
            zone_summary(&document, &segmented),
            mismatches,
            cast_failures,
        )
    } else {
        (
            0,
            "schedule (script segmentation not applied)".to_owned(),
            Vec::new(),
            Vec::new(),
        )
    };

    Ok(Report {
        pages: document.page_count(),
        blocks,
        headers,
        tables,
        png_bytes: rendered.png_bytes.len(),
        chunks,
        zones,
        mismatches,
        cast_failures,
        expectation,
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

/// The manifest that defines the corpus (`config/ai_eval_corpus.tsv`).
///
/// One file for local and CI runs: the PDFs stay confidential and out of Git, the
/// expectations do not. Overridable with `AI_EVAL_CORPUS_MANIFEST` for an
/// out-of-tree corpus layout.
fn manifest_path() -> PathBuf {
    match std::env::var_os("AI_EVAL_CORPUS_MANIFEST").map(PathBuf::from) {
        Some(path) => path,
        None => Path::new(env!("CARGO_MANIFEST_DIR")).join("../../config/ai_eval_corpus.tsv"),
    }
}

/// Every expectation the manifest states, in file order.
///
/// A malformed record is a **failure**, not a skip: silently ignoring a typo
/// would turn a count assertion into a no-op.
fn read_manifest(path: &Path) -> Vec<Expectation> {
    let text = std::fs::read_to_string(path)
        .unwrap_or_else(|error| panic!("could not read {}: {error}", path.display()));
    let mut expectations: Vec<Expectation> = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let line = line.trim_end();
        if line.trim().is_empty() || line.trim_start().starts_with('#') {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 3 {
            panic!(
                "{}:{}: expected `file<TAB>kind<TAB>scenes[<TAB>note]`, got {line:?}",
                path.display(),
                index + 1
            );
        }
        let file = fields[0].trim();
        let kind = DocumentClass::parse(fields[1]).unwrap_or_else(|| {
            panic!(
                "{}:{}: unknown document kind {:?} (script|schedule)",
                path.display(),
                index + 1,
                fields[1]
            )
        });
        let scenes = fields[2].trim().parse::<usize>().unwrap_or_else(|error| {
            panic!(
                "{}:{}: scene count {:?} is not a number: {error}",
                path.display(),
                index + 1,
                fields[2]
            )
        });
        expectations.push(Expectation {
            file: file.to_owned(),
            kind,
            scenes,
            note: fields
                .get(3)
                .map(|note| note.trim().to_owned())
                .unwrap_or_default(),
            cast: CastAssertion::parse(fields.get(4).copied().unwrap_or("-"), path, index + 1),
        });
    }
    expectations
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
