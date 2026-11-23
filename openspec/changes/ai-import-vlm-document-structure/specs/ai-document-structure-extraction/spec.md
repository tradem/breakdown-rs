<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-carbon (google) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-document-structure-extraction Specification

## ADDED Requirements

### Requirement: Hexagonal DocumentStructureExtractor port produces StructuredDocument IR
`crates/core::ai::ports` SHALL define a `DocumentStructureExtractor` port trait (static dispatch, no `#[async_trait]` boxing) that converts raw document bytes into a canonical `StructuredDocument` intermediate representation containing 1-based `StructuredPage` entries, reading-order `DocumentBlock`s with normalized bounding boxes (`0.0..=1.0`), structural block kinds (`PageHeader`, `PageFooter`, `Heading`, `Paragraph`, `Table`, `ListItem`), and optional HTML table markup preserving `colspan` and `rowspan`. The IR SHALL NOT carry rendered page images: the same port SHALL expose an on-demand `render_page(&self, document, page_number) -> Result<RenderedPage, DomainError>` so a caller renders one page, sends it, and drops it before the next page is rendered, keeping retained image memory bounded independently of document length. `ScriptImportWorker<Q, C, E>` and `ScheduleImportWorker<Q, C, E>` SHALL parameterize `extractor: E` over `E: DocumentStructureExtractor` (wired at the composition root via a `Clone` enum `ConfiguredDocumentExtractor` in `WorkerDeps` without `Arc<dyn ...>` or double-`Arc` wrapping) rather than hardwiring a single concrete `pdftotext` struct.

#### Scenario: Digital PDF yields pages with spatial block coordinates
- **WHEN** a multi-page digital PDF is passed to `SpatialPdfExtractor::extract`
- **THEN** the returned `StructuredDocument` contains one `StructuredPage` per PDF page in ascending order
- **AND** each `DocumentBlock` carries normalized `x0, y0, x1, y1` coordinates preserving horizontal indentation and top-band running headers

#### Scenario: Page rendering obeys timeout and byte bounds
- **WHEN** `render_page` is called for one page of a `K`-page schedule PDF
- **THEN** the returned `RenderedPage.png_bytes` is produced within the configured DPI and per-page byte ceiling
- **AND** a timed-out or failed child renderer process is killed and reaped without leaking OS processes

#### Scenario: Rendered pages are not accumulated across the page loop
- **WHEN** `ScheduleImportWorker` walks pages `1..=K` of a multimodal schedule
- **THEN** each page image is obtained by its own `render_page` call and dropped before the next page is rendered
- **AND** the job aborts with a validation error once cumulative rendered bytes for the document exceed the configured document-wide rendered-byte ceiling, rather than retaining all `K` images

### Requirement: Parser fingerprint and accepted structural plan participate in chunk-store resume invalidation
Every `DocumentStructureExtractor` implementation SHALL return a non-empty static identifier from `parser_fingerprint(&self) -> &str`, and the durable `#871` chunk-store fingerprint (`fingerprint_key`) SHALL incorporate both `CHUNKER_VERSION` and `parser_fingerprint()`. Because the optional VLM/LLM structural-index pass is non-deterministic, the accepted anchor plan (per-page zone labels and the ordered anchor block IDs that derive chunk boundaries) SHALL be persisted with the chunk set and its canonical digest (`structural_plan_digest`) SHALL also enter `fingerprint_key`.

#### Scenario: Switching structure extractors invalidates cached chunks
- **WHEN** a script import job stored partial chunks under `parser_fingerprint = "legacy-pdftotext-v1"`
- **AND** the job is retried by a worker configured with `parser_fingerprint = "poppler-spatial-v1"`
- **THEN** `open_chunk_set` detects the fingerprint mismatch, deletes the stale partial chunks, and restarts extraction cleanly at chunk `0`

#### Scenario: A changed structural anchor plan restarts extraction instead of splicing plans
- **WHEN** a partially extracted script import stored chunks `0..=2` under a structural anchor plan whose `structural_plan_digest` was `A`
- **AND** the retry re-runs the structural pass and accepts a plan with different zone boundaries or anchor block IDs (digest `B`)
- **THEN** `open_chunk_set` reports the fingerprint mismatch, deletes the partial chunks cut under plan `A`, and restarts at chunk `0`
- **AND** no chunk produced under plan `A` is ever combined with chunks produced under plan `B` in one `ScriptContext`

#### Scenario: An unchanged re-run of the structural plan resumes the stored prefix
- **WHEN** the retry's structural pass accepts the same zone boundaries and anchor block IDs it accepted before
- **THEN** `structural_plan_digest` is unchanged and the stored chunk prefix is reused without re-extraction

### Requirement: OSI-open local extraction and GDPR Zero-Data-Retention multimodal vision routing
All bundled document-structure adapters and recommended model profiles SHALL use OSI-approved open licenses (`MIT`, `Apache-2.0`, or `AGPL-3.0`-compatible) without revenue caps or territory restrictions. `LlmClient` SHALL expose a schema-constrained multimodal vision method (`chat_vision_constrained`) supporting base64 PNG page inputs alongside spatial text hints across both OpenAI-compatible vision endpoints (including `EURouter` and EU Zero-Data-Retention providers) and local `Ollama` multimodal models.
Production multimodal egress of screenplay or schedule page images to an OpenAI-compatible endpoint SHALL require that endpoint's provider policy to declare Zero Data Retention, no training on customer inputs, and EU data residency. The pre-egress policy check SHALL run before any page image is sent and SHALL reject a non-compliant endpoint with a validation error; a provider set that carries no such declaration is treated as non-compliant (fail-closed), while local `Ollama` needs no such gate because no bytes leave the host.

#### Scenario: Multimodal request routes to OpenAI-compatible EU provider with circuit-breaker accounting
- **WHEN** `chat_vision_constrained` executes against an OpenAI-compatible `LlmProvider` with one rendered page PNG and a JSON response schema
- **THEN** the client sends `image_url` (`data:image/png;base64,...`) and text content parts with the configured descriptive `User-Agent`
- **AND** token usage and provider health outcomes are recorded identically to `chat_constrained`

#### Scenario: Non-compliant vision endpoint is rejected before egress
- **WHEN** `chat_vision_constrained` targets a production OpenAI-compatible endpoint whose provider policy does not declare Zero Data Retention, no training on customer inputs, and EU data residency
- **THEN** the client returns a validation error before serializing any image part
- **AND** no page PNG is sent to that endpoint

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
