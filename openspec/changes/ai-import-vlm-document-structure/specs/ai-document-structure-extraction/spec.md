<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-carbon (google) -->

# ai-document-structure-extraction Specification

## ADDED Requirements

### Requirement: Hexagonal DocumentStructureExtractor port produces StructuredDocument IR
`crates/core::ai::ports` SHALL define a `DocumentStructureExtractor` port trait (static dispatch, no `#[async_trait]` boxing) that converts raw document bytes into a canonical `StructuredDocument` intermediate representation containing 1-based `StructuredPage` entries, reading-order `DocumentBlock`s with normalized bounding boxes (`0.0..=1.0`), structural block kinds (`PageHeader`, `PageFooter`, `Heading`, `Paragraph`, `Table`, `ListItem`), optional HTML table markup preserving `colspan` and `rowspan`, and optional bounded PNG page renders. `ScriptImportWorker<Q, C, E>` and `ScheduleImportWorker<Q, C, E>` SHALL parameterize `extractor: E` over `E: DocumentStructureExtractor` (wired at the composition root via a `Clone` enum `ConfiguredDocumentExtractor` in `WorkerDeps` without `Arc<dyn ...>` or double-`Arc` wrapping) rather than hardwiring a single concrete `pdftotext` struct.

#### Scenario: Digital PDF yields pages with spatial block coordinates
- **WHEN** a multi-page digital PDF is passed to `SpatialPdfExtractor::extract`
- **THEN** the returned `StructuredDocument` contains one `StructuredPage` per PDF page in ascending order
- **AND** each `DocumentBlock` carries normalized `x0, y0, x1, y1` coordinates preserving horizontal indentation and top-band running headers

#### Scenario: Page rendering obeys timeout and byte bounds
- **WHEN** `extract` is called with page rendering enabled on a schedule PDF
- **THEN** each `StructuredPage.rendered_png` is populated within the configured DPI and byte ceiling
- **AND** a timed-out or failed child renderer process is killed and reaped without leaking OS processes

### Requirement: Parser fingerprint participates in chunk-store resume invalidation
Every `DocumentStructureExtractor` implementation SHALL return a non-empty static identifier from `parser_fingerprint(&self) -> &str`, and the durable `#871` chunk-store fingerprint (`fingerprint_key`) SHALL incorporate both `CHUNKER_VERSION` and `parser_fingerprint()`.

#### Scenario: Switching structure extractors invalidates cached chunks
- **WHEN** a script import job stored partial chunks under `parser_fingerprint = "legacy-pdftotext-v1"`
- **AND** the job is retried by a worker configured with `parser_fingerprint = "poppler-spatial-v1"`
- **THEN** `open_chunk_set` detects the fingerprint mismatch, deletes the stale partial chunks, and restarts extraction cleanly at chunk `0`

### Requirement: OSI-open local extraction and GDPR Zero-Data-Retention multimodal vision routing
All bundled document-structure adapters and recommended model profiles SHALL use OSI-approved open licenses (`MIT`, `Apache-2.0`, or `AGPL-3.0`-compatible) without revenue caps or territory restrictions. `LlmClient` SHALL expose a schema-constrained multimodal vision method (`chat_vision_constrained`) supporting base64 PNG page inputs alongside spatial text hints across both OpenAI-compatible vision endpoints (including `EURouter` and EU Zero-Data-Retention providers) and local `Ollama` multimodal models.

#### Scenario: Multimodal request routes to OpenAI-compatible EU provider with circuit-breaker accounting
- **WHEN** `chat_vision_constrained` executes against an OpenAI-compatible `LlmProvider` with one rendered page PNG and a JSON response schema
- **THEN** the client sends `image_url` (`data:image/png;base64,...`) and text content parts with the configured descriptive `User-Agent`
- **AND** token usage and provider health outcomes are recorded identically to `chat_constrained`

#### Scenario: Multimodal request executes offline against local Ollama
- **WHEN** `chat_vision_constrained` executes against `LlmProvider::Ollama`
- **THEN** the client sends the page PNG in Ollama's `images` field with structured JSON formatting and no bearer-token Vault lookup

### Requirement: Env-gated Golden Corpus evaluation harness verifies document structure out-of-tree
The backend test suite SHALL provide an evaluation harness driven by `AI_EVAL_CORPUS_DIR` that executes deterministic pass/fail assertions (scene count parity, zero synopsis leakage, cast-category accuracy, and schedule row alignment) against local out-of-tree PDF corpora, complemented by always-on unit tests over synthetic multi-zone fixtures committed in-repo.

#### Scenario: CI runs without external corpus directory
- **WHEN** `AI_EVAL_CORPUS_DIR` is unset during standard CI test execution
- **THEN** the synthetic multi-zone fixture suite executes and passes
- **AND** the out-of-tree corpus runner skips cleanly without failing the build nor requiring copyrighted PDFs in Git

#### Scenario: Local developer runs Golden Corpus evaluation
- **WHEN** `AI_EVAL_CORPUS_DIR` points to a local directory of broadcast scripts and shooting schedules
- **THEN** the harness evaluates each document against its expected scene count, zone separation, cast classifications, and schedule rows and reports per-assertion pass/fail metrics
