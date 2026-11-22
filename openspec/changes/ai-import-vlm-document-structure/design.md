<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-carbon (google) -->

# Design — Pluggable Document Structure Extraction, Zone-Aware Script Segmentation, and Multimodal Schedule Parsing

Companion to `proposal.md` and `ADR-041`. Locked decisions `D1…D8` live in `proposal.md`; this document specifies the hexagonal ports, domain IR, deterministic algorithms, multimodal wire shapes, and migration stages.

---

## Context

`ScriptImportWorker` and `ScheduleImportWorker` (`backend/crates/infra/src/ai/workers.rs`) currently invoke a concrete `PdfTextExtractor` (`pdftotext -q -layout - -`) returning a single `String`. Downstream, `extract_scenes(&str)` (`backend/crates/core/src/ai/preview.rs`) iterates line-by-line without page or section awareness, discarding pre-scene cast lists, gluing multi-page `"SYNOPSIS"` / `"MEDIZINISCHE FÄLLE"` prose onto the trailing entry of `"SCRIPT REPORT"`, missing `"A+I/T"` / `"I+A/T"` headings, absorbing `"CONTINUED:"` page headers into dialogue, and leaving Ghostscript kerning-split names (`"Mik k o"`) unnormalized. Meanwhile, non-CSV shooting schedules send all flattened pages in one `8192`-token text request, losing multi-row visual cell alignment and two-column `"ROLLEN"` number legends.

Deployment targets a cost-efficient CPU vServer (Netcup RS series, no dedicated vGPU) paired with GDPR / Zero-Data-Retention (ZDR) European pay-as-you-go VLM endpoints (`EURouter`, Scaleway, OVHcloud, Nebius EU) in production and `Ollama` on a 4 GB VRAM Turing GPU (`GTX 1650`, Compute Capability 7.5, `fp16`/GGUF `Q4_K_M`) in local development.

---

## Goals / Non-Goals

**Goals:**
- Decouple AI workers from `pdftotext` via a hexagonal `DocumentStructureExtractor` port in `crates/core::ai::ports` returning a rich `StructuredDocument` IR (`D1`).
- Use 100% OSI-open parser/model stacks (`MIT` / `Apache-2.0`, compatible with `AGPL-3.0`) that run locally on CPU/4 GB VRAM and via GDPR/ZDR European pay-as-you-go VLM endpoints (`D2`).
- Achieve deterministic, contamination-free screenplay scene counts by classifying document zones (`TitlePage`, `CastList`, `SceneIndex`, `FrontMatter`, `ScriptBody`) before slicing verbatim `ScriptBody` text (`D3`, `D4`).
- Raise `main_cast` / `guest` / `extra` accuracy via `CastDirectory` + corpus dialogue signals resolved deterministically in `crates/core` with zero `(OT)` false-positive promotions (`D5`).
- Extract multi-page tabular PDF shooting schedules page-by-page via multimodal VLM with carry-over day state and additive, non-mutating `"ROLLEN"` cast legends (`D6`).
- Protect `#871` chunk-resume integrity via `parser_fingerprint()` (`D7`) and enforce regression safety via an out-of-tree Golden Corpus harness (`D8`).

**Non-Goals:**
- Full-document optical OCR of degraded historical paper scans on the CPU vServer (born-digital broadcast PDFs are the primary target; scanned pages route selectively through multimodal VLM or an optional `Docling` sidecar).
- Automatic mutation or creation of `Character` aggregates from shooting-schedule cast numbers (`D6`).
- Adopting weight-restricted models (`HunyuanOCR-1.5`, `chandra-ocr-2`, `dots.mocr`).

---

## Decisions & Architecture

### 1. Hexagonal Port, Canonical `StructuredDocument` IR & Poor Man's DI (`D1`, `D7`)

```
                    crates/core::ai::ports
         ┌───────────────────────────────────────────┐
         │ trait DocumentStructureExtractor          │
         │  • parser_fingerprint(&self) -> &'static str
         │  • extract(&self, bytes, opts)            │
         │      -> impl Future<Output = Result<      │
         │           StructuredDocument, ...>> + Send│
         └─────────────────────┬─────────────────────┘
                               │ (static dispatch `E`, enum `ConfiguredDocumentExtractor` in `WorkerDeps` — NO `Arc<dyn ...>`)
       ┌───────────────────────┼───────────────────────┐
       ▼                       ▼                       ▼
SpatialPdfExtractor    DoclingHttpAdapter     LegacyPdfToTextAdapter
(Copy config struct:   (Clone struct holding  (Copy config struct
 Poppler XML bbox +     already-Arc internal   wrapping existing
 PNG page renderer)     `reqwest::Client`)     `pdftotext -layout`)
```

**Poor Man's DI & `Arc<T>` Discipline (binding for all packages):**
- **`DocumentStructureExtractor` uses static dispatch (`E: DocumentStructureExtractor`), NOT `Arc<dyn DocumentStructureExtractor>` and NOT `#[async_trait]`:** Mirrors `LlmClient` (`crates/core/src/ai/ports.rs:313`). `ScriptImportWorker<Q, C, E = LegacyPdfToTextAdapter>` and `ScheduleImportWorker<Q, C, E = LegacyPdfToTextAdapter>` own `pub extractor: E` by value.
- **Runtime adapter selection without heap/vtable indirection:** `crates/infra::ai` defines `#[derive(Clone)] pub enum ConfiguredDocumentExtractor { Spatial(SpatialPdfExtractor), Docling(DoclingHttpAdapter), Legacy(LegacyPdfToTextAdapter) }` implementing `DocumentStructureExtractor` and constructed **once** in the composition root (`crates/api/src/main.rs`) from `AI_DOCUMENT_PARSER`. `WorkerDeps` stores `pub extractor: ConfiguredDocumentExtractor` by value — **never** `Arc<ConfiguredDocumentExtractor>`, `Arc<SpatialPdfExtractor>`, or `Arc<reqwest::Client>` (`Spatial`/`Legacy` are `Copy` stack configs; `reqwest::Client` and `sqlx::PgPool` are already internal-`Arc` handles).
- **Pure domain logic borrows slices:** Every function in `crates/core::ai::{document, preview}` (`classify_document_zones`, `parse_cast_directory`, `resolve_character_category`, `reconcile_scene_index`, `extract_scenes_from_structured`) takes borrowed references (`&StructuredDocument`, `&[StructuredPage]`, `&CastDirectory`, `&[ExistingSeasonCharacter]`, `&str`) and returns plain owned domain values — zero `Arc<T>`, zero `Mutex`, zero interior mutability.

In `crates/core::ai::document`:

```rust
pub struct StructuredDocument {
    pub parser_fingerprint: String,
    pub pages: Vec<StructuredPage>,
}

pub struct StructuredPage {
    pub page_number: u32, // 1-based
    pub width_pt: f32,
    pub height_pt: f32,
    pub blocks: Vec<DocumentBlock>,
    /// Populated on demand (e.g. schedule pages or ambiguous layout pages)
    /// bounded by DPI and max-byte ceilings.
    pub rendered_png: Option<Vec<u8>>,
}

pub struct DocumentBlock {
    pub id: BlockAnchor,      // (page_number, block_ordinal) -> e.g. P04.B03
    pub kind: BlockKind,      // PageHeader | PageFooter | Heading | Paragraph | Table | ListItem
    pub bbox: NormalizedBBox, // x0, y0, x1, y1 in 0.0..=1.0 (indentation signal!)
    pub text: String,         // Verbatim UTF-8 text of the block
    pub html_table: Option<String>, // Preserves colspan/rowspan when kind == Table
}
```

**Why `NormalizedBBox` matters for screenplays:** Screenplay formatting encodes semantics in horizontal indentation (`x0`): scene headings and action sit at the left margin (`x0 ≈ 0.10–0.15`), character cues sit centered (`x0 ≈ 0.35–0.45`), dialogue sits indented (`x0 ≈ 0.25–0.32`), and running headers (`"Block 098"`, `"Ep.: 292/1"`) sit in the top band (`y0 < 0.09`). Preserving `bbox` lets `SpatialPdfExtractor` (built on Poppler `pdftotext -bbox-layout` + `pdftoppm -png -r 150`, both already in the Poppler toolchain alongside `pdftotext`!) extract exact spatial coordinates on a Netcup CPU vServer in `< 300 ms` per 95-page script with zero C++ build-time linking hazards.

**Chunk-store invalidation (`#871`):** `chunk_store::fingerprint_key` incorporates `extractor.parser_fingerprint()` and bumped `CHUNKER_VERSION`. Any switch between `legacy-pdftotext-v1`, `poppler-spatial-v1`, or `docling-http-v1` invalidates stale stored chunks cleanly at `open_chunk_set`.

---

### 2. Multimodal Vision Seam on `LlmClient` (`D2`)

`crates/core::ai::ports::LlmClient` gains a bounded multimodal method (defaulting or implemented alongside `chat_constrained`):

```rust
pub struct LlmVisionPageInput {
    pub page_number: u32,
    pub png_bytes: Vec<u8>,
    /// Optional spatial text hint from the digital PDF layer so the VLM
    /// grounds exact character/number spellings while reading visual grid lines.
    pub spatial_text_hint: Option<String>,
}

pub struct LlmVisionRequest {
    pub provider: LlmProvider,
    pub model: String,
    pub system_prompt: String,
    pub user_text: String,
    pub pages: Vec<LlmVisionPageInput>,
    pub max_tokens: u32,
    pub response_schema: Option<serde_json::Value>,
    pub reasoning_effort: Option<String>,
}
```

- **OpenAI-compatible providers (`EURouter`, `OpenRouter`, `OpenAI`, `Gemini`, `Neuralwatt`, `OpenCode*`):** Serializes `pages` as `content: [{ "type": "image_url", "image_url": { "url": "data:image/png;base64,..." } }, { "type": "text", ... }]` with existing TLS/DNS-pinning, descriptive `User-Agent` (`#521`), and `#871`/`#942` circuit-breaker & hold accounting.
- **Local `Ollama`:** Serializes `images: ["<base64>"]` on `/api/chat` with `format: <json_schema>`, running `qwen3-vl:4b` or `glm-ocr` within 4 GB VRAM.

---

### 3. Pass 0: Zone-Aware Screenplay Segmentation & Verbatim Slicing (`D3`, `D4`)

```
StructuredDocument (Pages 1..N)
       │
       ▼
[1. Page Header/Footer & CONTINUED Filter]
   • Blocks in top header band (`y0 < 0.09` matching repeating title / `Block:` / `Ep.:`)
     -> harvested for `block_number` & `episode` metadata, tagged `PageHeader` (excluded from prose)
   • Leading `<N> CONTINUED:` / `FORTSETZUNG` blocks -> tagged `ContinuationMarker` (excluded from prose)
       │
       ▼
[2. Page Zone Classifier (Deterministic Layout + Optional VLM Disambiguation)]
   • `TitlePage`   : Cover metadata, episode number & quoted episode title
   • `CastList`    : Cast sections (`HAUPTCAST`, `CROSS`, `EPISODENHAUPTROLLEN`, `KOMPARSEN`)
   • `SceneIndex`  : Dense list of heading-only entries (`SCRIPT REPORT`, 0 dialogue blocks/page)
   • `FrontMatter` : Multi-paragraph narrative prose (`SYNOPSIS`, `MEDIZINISCHE FÄLLE`, no scene headings)
   • `ScriptBody`  : Pages carrying scene headings + indented character cues / dialogue / action
       │
       ├──▶ `CastList`   ──▶ `parse_cast_directory()` -> `CastDirectory`
       ├──▶ `SceneIndex` ──▶ `expected_scene_refs: Vec<SceneRef>` (Validation Manifest)
       └──▶ `ScriptBody` ──▶ [3. Verbatim Span Chunker]
                               • Splits ONLY inside `ScriptBody`
                               • Supports `I/T`, `A/N`, `A+I/T`, `I+A/T`, `A/I/T`, `INT.`, `EXT.`,
                                 and VLM/spatial fallback when a page lacks standard prefixes
                               • Slices verbatim `DocumentBlock.text` (never VLM-retyped!)
                               • Normalizes Ghostscript kerning splits (`"Mik k o"` -> `"Mikko"`)
                                 ONLY when the collapsed span matches an entry in `CastDirectory`
                               • Reconciles extracted `ScriptBody` scene numbers against `SceneIndex`
```

**Why hybrid zoning (deterministic first, VLM fallback for non-standard formats)?**
For standard German/English scripts, spatial Signals (`SCRIPT REPORT` banner or `>= 8` consecutive body-less scene headings on one page = `SceneIndex`; `"PERSONEN"`/`"HAUPTCAST"`/`"DARSTELLER"`/`"CAST"` = `CastList`; `"SYNOPSIS"`/`"EXPOSÉ"`/`"MEDIZINISCHE FÄLLE"` = `FrontMatter`) classify zones in `< 5 ms` at **zero token cost**. When a script uses an unfamiliar layout (e.g., zero recognized headings in `ScriptBody` or ambiguous zone transitions), a single compact VLM/LLM structural index pass over page summaries classifies the zones and identifies scene heading block anchors (`P11.B02`), while Rust still performs the verbatim text slice.

---

### 4. Deterministic Cast-Role Precedence & Continuity Context (`D5`)

```rust
pub struct CastDirectory {
    pub entries: Vec<CastDirectoryEntry>,
}

pub struct CastDirectoryEntry {
    pub canonical_name: String,
    pub normalized_identity: String,
    pub declared_category: CharacterCategory, // MainCast | Guest | Extra
    pub raw_section: String,                  // e.g. "EPISODENHAUPTROLLEN", "CROSS", "KOMPARSEN"
    pub inline_ot: bool,                      // e.g. "Jannis Hauser (8, OT)"
}
```

**Section mapping table (pure, `crates/core`):**
- `"PERSONEN"`, `"PERSONEN/ HAUPTCAST"`, `"HAUPTCAST"`, `"HAUPTROLLEN"`, `"DURCHGEHENDE ROLLEN"`, `"MAIN CAST"` → `CharacterCategory::MainCast`
- `"EPISODENHAUPTROLLEN"`, `"EPISODENROLLEN"`, `"GASTROLLEN"`, `"GASTDARSTELLER"`, `"CROSS"`, `"GUEST CAST"` → `CharacterCategory::Guest`
- `"KOMPARSEN"`, `"KOMPARSERIE"`, `"STATISTEN"`, `"STATISTERIE"`, `"KLEINDARSTELLER"`, `"TAGESROLLEN"`, `"EXTRAS"` → `CharacterCategory::Extra`

**Deterministic Resolution Function (`resolve_character_category` in `crates/core`):**
1. **Exact or unique given/surname token match in `CastDirectory`:** Returns `entry.declared_category` unconditionally (even when `entry.inline_ot == true`). If the same normalized identity appears under two *different* `CastDirectory` categories, emit one `Uncertainty` (`field: "characters"`).
2. **Existing Season `Character` read-model match** (loaded once by the worker before chunk processing and passed as `&[ExistingSeasonCharacter]` — never queried from write-side adapters): Returns the existing character's `CharacterCategory`.
3. **Explicit inline background marker in scene (`(OT)`, `(O.T.)`, `Off-Text`, `Statist`, `Komparse`):** Returns `CharacterCategory::Extra` unconditionally (preserving `#826` zero-hedging behavior for unlisted figures).
4. **Corpus dialogue heuristic (for scripts lacking a `CastList`):** If a character has `0` dialogue blocks across all `ScriptBody` chunks AND matches a numbered/generic role pattern (`"PFLEGER 2"`, `"PASSANT"`, `"ÄRZTIN"`), returns `CharacterCategory::Extra`.
5. **Default:** `CharacterCategory::MainCast` with zero uncertainty.

**Neighbor-Scene Continuity Bracket:**
Both Pass 1 (`<document-context>` XML block appended alongside `<input>`) and Pass 2 (`DecisionQuestion::Choice` state payload) receive:
- `cast_directory_summary`: compact list of known characters and their locked categories so the LLM spells names consistently and emits zero bogus category uncertainties.
- `previous_scene` & `next_scene`: `{ scene_number, location, mood, script_day, same_script_day_as_current }`, enabling accurate continuity reasoning across immediate interior/exterior transitions (`"A/T VOR KLINIK"` → `"I/T FOYER KLINIK"` on `"Tag 2"`).

---

### 5. Page-Streaming Multimodal Schedule Extraction (`D6`)

```
Schedule PDF (Pages 1..K)
       │
       ▼
`DocumentStructureExtractor::extract(..., render_pages = true)`
       │
       ▼
Page Loop (p = 1..=K) with `ScheduleCarryOver { active_day_label, active_date, cast_legend }`
  • Multimodal call (`LlmClient::chat_vision_constrained`):
      Input : Page `p` PNG + spatial block table/text hint + `carry_over` JSON
      Output: `SchedulePageExtraction { legend_entries, day_banners_seen, rows, end_of_page_day }`
  • Post-processing per row in `crates/core`:
      - Ignore `"Drehfrei"` / rest-day banners (never create a shooting day)
      - Parse `<Episode>.<Scene><Suffix?>`:
          `"300.33"`  -> ep=Some(300), scene=Some(33), shot_suffix=None
          `"300.37N"` -> ep=Some(300), scene=Some(37), shot_suffix=Some("N")
          `"SB7.2"`   -> ep=None,      scene=None,     row_ref="SB7.2" (stays unmatched)
      - Validate row `cast_numbers` against `cast_legend`; attach resolved `ScheduleCastMember`
        entries (`name`, `role_modifier: None | Dummy | VoiceOnly | ExtraOt`) as read-only metadata;
        discard unknown numbers silently to prevent table-noise amplification.
```

Progress frames (`#664` / `ADR-038`) publish `(chunk = page_idx, chunks_total = page_count)` as each schedule page finishes, giving real-time progress and ETA on multi-page PDF schedules for the first time.

---

### 6. Golden Corpus Evaluation Harness (`D8`)

Located in `backend/crates/infra/tests/ai_document_eval_corpus.rs` (ignored by default unless `AI_EVAL_CORPUS_DIR` is set, plus an always-on unit suite over synthetic multi-zone fixtures in `crates/core`):

- Reads a declarative `manifest.toml` (or auto-discovers known filenames in `AI_EVAL_CORPUS_DIR`) defining ground-truth expectations:
  - Expected `ScriptBody` scene count (e.g. `40`, `42`, `43`) and `SceneIndex == ScriptBody` parity.
  - Zero `"SYNOPSIS"` or `"MEDIZINISCHE FÄLLE"` substrings inside any `SceneChunk.text`.
  - Zero `"CONTINUED:"` page-header lines inside `SceneChunk.text`.
  - Expected `CastDirectory` category assertions (`main_cast`, `guest` including `"CROSS"` and `(OT)` episodic leads, named `extra` under `"KOMPARSEN"`).
  - Schedule row count, day-banner dates, `"300.37N"` normalization, `"Drehfrei"` exclusion, and `"ROLLEN"` legend resolution.

---

## Risks / Trade-offs

- **[Risk] Poppler `pdftoppm` memory/CPU spike on malformed or huge PDFs on a small Netcup vServer** → **Mitigation:** Render pages lazily one page (or bounded batch) at a time at capped `150 DPI` grayscale/RGB, enforce `AI_IMPORT_MAX_DOCUMENT_BYTES` (`20 MiB`), cap rendered PNG bytes per page, and apply the battle-tested `tokio::time::timeout` + `reap_child` cleanup pattern from `crates/infra/src/ai/pdf.rs`.
- **[Risk] Kerning normalization (`"Mik k o"` → `"Mikko"`) accidentally collapses two real German words** → **Mitigation:** Normalization is dictionary-gated exclusively against multi-character proper names present in the same document's `CastDirectory` (never free-form spellchecking), and `verify_draft_outfits` checks both raw and kerning-normalized chunk text.
- **[Risk] Multimodal provider endpoint lacks JSON-schema `response_format` alongside image inputs** → **Mitigation:** Reuse `ai::client`'s constrained-JSON fallback + bounded inner parse retry when a provider rejects combined `image_url` + strict `json_schema`.
- **[Risk] In-flight jobs across upgrade hold pre-`ADR-041` cached chunks** → **Mitigation:** `CHUNKER_VERSION` bump + `parser_fingerprint` in `chunk_store::fingerprint_key` (`D7`) cleanly discards pre-upgrade partial chunk sets on the next worker claim and restarts extraction at chunk `0`.

---

## Migration Plan

Delivered in **4 incremental, independently reviewable PR packages** under this OpenSpec change:

1. **Package 1 (`[P1]` — Foundation & Eval Harness):** Introduce `DocumentStructureExtractor` + `StructuredDocument` IR in `core`, wire `SpatialPdfExtractor` + `LegacyPdfToTextAdapter` in `infra`, fold `parser_fingerprint` into `chunk_store::fingerprint_key`, and land the synthetic + `AI_EVAL_CORPUS_DIR` harness. No wire/OpenAPI change.
2. **Package 2 (`[P2]` — Zone-Aware Screenplay Segmentation):** Land Pass 0 page zoning (`TitlePage`, `CastList`, `SceneIndex`, `FrontMatter`, `ScriptBody`), `"CONTINUED:"` / header stripping, `"A+I/T"` / `"I+A/T"` support, and `SceneIndex` reconciliation.
3. **Package 3 (`[P3]` — `CastDirectory`, Deterministic Role Precedence & Continuity Context):** Land `CastList` parser, deterministic `resolve_character_category` ladder in `core`, kerning-split cast normalization, and `<document-context>` neighbor-scene injection for Pass 1 & Pass 2.
4. **Package 4 (`[P4]` — Multimodal Schedule Streaming & Additive Cast Legend):** Add `LlmClient::chat_vision_constrained`, page-by-page schedule extraction with carry-over day state, `"300.37N"` / `"Drehfrei"` handling, additive `cast_legend` / `cast_refs` DTO fields, `UPDATE_OPENAPI=1`, and `scripts/regen-client.sh`.

**Rollback:** Every adapter implements `DocumentStructureExtractor`; setting `AI_DOCUMENT_PARSER=legacy-pdftotext` reverts extraction to `LegacyPdfToTextAdapter` without database rollback, while `fingerprint_key` prevents cross-mode chunk mixing.

---

## Open Questions

None blocking implementation. Optional future extension: whether Flutter's schedule merge review table should display resolved `Dummy` / `Nur Stimme` badges next to matched scenes (can be layered purely on the additive DTO fields from Package 4 in a dedicated UI ticket).

---

## Appendix: File-by-File Blueprints & Idiomatic Rust Guardrails

This section is binding for implementation agents across `[P1]…[P4]`:

### A. Idiomatic Rust, Poor Man's DI & Anti-`Arc<T>` Rules

1. **NEVER wrap already-refcounted or `Copy`/`Clone` value types in `Arc<T>`:**
   - `sqlx::PgPool` and `reqwest::Client` already wrap an internal `Arc` (`Clone` is an `O(1)` atomic increment). Writing `Arc<PgPool>` or `Arc<reqwest::Client>` is a **hard review rejection**.
   - `LegacyPdfToTextAdapter` and `SpatialPdfExtractor` hold only `usize` + `Duration` bounds (`#[derive(Debug, Clone, Copy)]`). `DoclingHttpAdapter` holds `reqwest::Client` + `reqwest::Url` + bounds (`#[derive(Debug, Clone)]`).
   - `#[derive(Debug, Clone)] pub enum ConfiguredDocumentExtractor` in `crates/infra/src/ai/` wraps those three variants by value and is stored **by value** in `WorkerDeps` (`pub extractor: ConfiguredDocumentExtractor`) and **by value** in `ScriptImportWorker<Q, C, E = LegacyPdfToTextAdapter>` / `ScheduleImportWorker<Q, C, E = LegacyPdfToTextAdapter>` (`pub extractor: E`).
2. **Functions and methods take borrows (`&T`, `&[T]`, `&str`), NEVER owned `Arc<T>`:**
   - BAD: `fn extract_zones(doc: Arc<StructuredDocument>) -> ...` or `fn resolve(dir: Arc<CastDirectory>)`
   - GOOD: `pub fn classify_document_zones(doc: &StructuredDocument) -> Vec<ClassifiedPage>` and `pub fn resolve_character_category(name: &str, inline_ot: bool, has_dialogue: bool, directory: &CastDirectory, existing_season_cast: &[ExistingSeasonCharacter]) -> CharacterCategory`
3. **No `#[async_trait]` on new internal ports when static dispatch applies:**
   - `DocumentStructureExtractor` and `LlmClient::chat_vision_constrained` in `crates/core/src/ai/ports.rs` use native `async fn` / `-> impl Future<Output = ...> + Send` matching `LlmClient` (`crates/core/src/ai/ports.rs:313`).
4. **CQRS Boundary (`AGENTS.md` §1):**
   - Pre-loading existing season characters for `[P3]` fallback happens **once** in the worker/read orchestration (`crates/infra/src/ai/worker_loop.rs`) via the read-model repository and passes `&[ExistingSeasonCharacter]` into pure `crates/core` functions. Write-side command adapters (`*CommandsImpl`), sagas, and aggregates MUST NEVER query read-model projections.

### B. Backward-Compatible Serde & Persistence Touchpoints

- **`ExtractionFingerprint` (`crates/core/src/ai/ports.rs`) & `fingerprint_key` (`crates/infra/src/ai/chunk_store.rs:320`):**
  - Add `#[serde(default)] pub parser_fingerprint: String` to `ExtractionFingerprint` so existing JSON `components` rows in `ai_import` deserialize cleanly (defaulting to `""`).
  - Append `hasher.update(b"|"); hasher.update(fingerprint.parser_fingerprint.as_bytes());` at the end of `fingerprint_key` and populate `parser_fingerprint: self.extractor.parser_fingerprint().to_owned()` inside `ScriptImportWorker::open_chunk_set` (`crates/infra/src/ai/workers.rs:514`).
- **Stored Garage S3 Preview Compatibility (`crates/core/src/ai/preview.rs`):**
  - Every new field on `ScriptContext`, `ShootingSchedule` (`#[serde(default)] pub cast_legend: BTreeMap<String, ScheduleLegendEntry>`), and `ShootingScheduleRow` (`#[serde(default)] pub shot_suffix: Option<String>`, `#[serde(default)] pub cast_refs: Vec<ScheduleCastMember>`) MUST carry `#[serde(default)]` so previews persisted in Garage S3 before this change deserialize without error.
- **Poppler Spatial Parsing (`crates/infra/src/ai/spatial_pdf.rs`):**
  - Invoke `pdftotext -q -bbox-layout - -` and `pdftoppm -q -png -r 150` using the exact `tokio::join!(write, read)` + `max_output_bytes` cap + `tokio::time::timeout` + `reap_child` lifecycle from `crates/infra/src/ai/pdf.rs:46-143`.
  - Guard page dimension normalization against zero/negative dimensions (`if width_pt <= f32::EPSILON || height_pt <= f32::EPSILON`) and clamp `NormalizedBBox` coordinates to `0.0..=1.0` with zero `unwrap()`/`expect()`.
- **Pass 2 Continuity Touchpoint (`crates/core/src/ai/continuity.rs`):**
  - Extend the gap state builder in `crates/core/src/ai/continuity.rs` with `previous_scene: Option<NeighborSceneBrief>` and `next_scene: Option<NeighborSceneBrief>` derived from the ordered `ScriptContext.scenes` slice.
