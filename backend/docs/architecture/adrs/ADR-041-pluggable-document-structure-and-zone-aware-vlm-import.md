<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-carbon (google) -->

# ADR-041: Pluggable Document Structure Extraction, Zone-Aware Script Segmentation, and Multimodal Schedule Parsing

**Status**: Accepted (implemented across #963 `[P1]`, `#964` `[P2]`, #965 `[P3]`, and the `[P4]` multimodal schedule PR)
**Date**: 2026-11-22
**Author**: Tobias Rademacher (@tradem); gemini-4-carbon (google); deepseek-v4.1-flash (opencode-go)
**Related**: ADR-001 (Hexagonal Architecture), ADR-006 (utoipa OpenAPI), ADR-013 (Hybrid LLM Script Parsing — amends §1 Fuzzy Chunking), ADR-024 (TLS & Curated Outbound HTTP), ADR-027 (Secrets Vault), ADR-030 (AI Import Bounded Context), ADR-031 (HTTP Error Surface), ADR-038 (AI Import SSE Progress)
**Source change**: `openspec/changes/ai-import-vlm-document-structure/` (tracked in GitHub issues #958 `[P1]`, #959 `[P2]`, #961 `[P3]`, #960 `[P4]`)

---

## Context

`ADR-013` established a hybrid architecture for AI script parsing: deterministic Rust chunking over `pdftotext -layout` output followed by schema-constrained LLM scene extraction. `ADR-013` §1 explicitly wagered that *"perfect chunking is unnecessary; the LLM understands context across boundaries."*

Testing against real multi-episode German broadcast screenplays (~95–105 pages, digital PDF exports via Ghostscript/PDF24) and production shooting schedules (8+ pages, iText multi-row tabular PDFs without accompanying CSV exports) demonstrated that flat `pdftotext -layout` extraction plus line-by-line heading regexes is structurally fragile:

1. **Front-matter cast directories are lost:** Everything preceding the first scene heading is discarded. Broadcast scripts place their authoritative cast classification (`"PERSONEN/ HAUPTCAST"`, `"CROSS"`, `"EPISODENHAUPTROLLEN"`, `"KOMPARSEN"`) on page 2. Dropping page 2 blinds per-scene extraction to guest leads and named background performers, collapsing unlabelled characters onto `main_cast`.
2. **Unzoned front-matter contaminates scenes:** Broadcast scripts include a 2-page `"SCRIPT REPORT"` scene index (pages 3–4) followed by 5–6 pages of prose `"SYNOPSIS"` and medical/storyline bios (pages 5–10) before the actual script body starts on page 11. Because `extract_scenes` scans from line 1 without page-zone awareness, all 6 pages of synopsis prose glue onto the final heading of the `"SCRIPT REPORT"` and are then merged into the last real scene by `merge_duplicate_scene_numbers`.
3. **Regex boundary & typography brittleness:** Combined interior/exterior prefixes (`"A+I/T"`, `"I+A/T"`), wrapped two-column headings, ~50 `"CONTINUED:"` page-break headers per script, and Ghostscript kerning artifacts (`"Mik k o"`, `"Le yla"`) cause scene-count drift and split character identities.
4. **Shooting-schedule tables cannot be reliably recovered from flat text:** Production schedules use multi-row visual cells without text delimiters (episode.scene `"300.33"` on line 1, script day `"2"` stacked underneath on line 2, wrapped set names in the center, numeric cast IDs `"2, 4, 50"` on the right referencing a two-column `"ROLLEN"` legend on page 1, interspersed with full-width shooting-day banners and `"Drehfrei"` rows). Sending `pdftotext` output of an entire schedule in a single `8192`-token LLM call scrambles row alignment and hits output-token ceilings on longer blocks.
5. **Infrastructure, licensing, and privacy constraints:**
   - The target production server is a cost-effective CPU vServer (e.g. Netcup RS series, no dedicated vGPU); local developer machines may only have modest GPUs (e.g. 4 GB VRAM Turing GTX 1650 without native `bf16`).
   - Breakdown RS is licensed under **AGPL-3.0**: parser code and model weights must maintain genuine OSI openness (**MIT / Apache-2.0** or AGPL-compatible), excluding proprietary community licenses or revenue-capped weights.
   - Unpublished screenplays and schedules are strictly confidential IP subject to NDAs and GDPR: external pay-as-you-go inference must guarantee **Zero Data Retention (ZDR)**, **no training on customer inputs**, and **EU data residency / GDPR compliance**.

## Decision

We amend `ADR-013` §1 by replacing flat-string PDF extraction and unzoned line-regex splitting with **pluggable document-structure extraction behind hexagonal ports**, **zone-aware screenplay segmentation**, **deterministic cast-role precedence**, and **page-streaming multimodal schedule parsing**.

### D1 — Hexagonal `DocumentStructureExtractor` port & `StructuredDocument` IR

`ScriptImportWorker` and `ScheduleImportWorker` no longer depend on a concrete `infra::ai::PdfTextExtractor`. Instead, `crates/core::ai::ports` defines `DocumentStructureExtractor`:

- Returns a pure domain IR `StructuredDocument` containing ordered `StructuredPage` entries, reading-order `DocumentBlock`s with normalized bounding boxes (`x0, y0, x1, y1` — preserving screenplay indentation columns), structural block kinds (`PageHeader`, `PageFooter`, `Heading`, `Paragraph`, `Table`, `ListItem`), and optional HTML `<table>` markup preserving `colspan`/`rowspan`.
- Carries **no** rendered page images: a companion on-demand `render_page(&self, document, page_number) -> RenderedPage` returns the PNG for exactly one page, so a page-streaming caller renders, sends, and drops one image at a time (aggregate retention `O(1)` pages, not `O(K)`), bounded per page and document-wide.
- Exposes `fn parser_fingerprint(&self) -> &'static str`, which MUST be folded into `#871` `chunk_store::fingerprint_key` alongside `CHUNKER_VERSION`, provider, model, and prompt so cached chunk prefixes never resume across different structure extractors. Because the optional VLM/LLM structural index pass is non-deterministic, the accepted anchor plan (zone labels + anchor block IDs) is persisted with the chunk set and its canonical digest (`structural_plan_digest`) enters `fingerprint_key` too: an unchanged re-run resumes the stored prefix, a changed plan restarts extraction at chunk `0` instead of splicing two plans.
- Uses **idiomatic static dispatch (`E: DocumentStructureExtractor`) and Poor Man's DI** rather than `Arc<dyn DocumentStructureExtractor>` or `#[async_trait]` heap boxing: `ScriptImportWorker<Q, C, E = LegacyPdfToTextAdapter>` and `ScheduleImportWorker<Q, C, E = LegacyPdfToTextAdapter>` hold `extractor: E` by value, and `WorkerDeps` holds a `Clone` enum `ConfiguredDocumentExtractor` wired once at the composition root (`crates/api/src/main.rs`) with zero redundant `Arc` wrapping.

### D2 — Open-source licensing & hybrid CPU + EU ZDR VLM topology

We evaluate and select technologies strictly on **OSI openness** and **deployment fit**:

- **Accepted open components (MIT / Apache-2.0):**
  1. **On-host CPU extraction & rendering (0 € marginal cost, 0 bytes egress):** Because production screenplays and schedules are born-digital PDFs (not scans), local spatial extraction + targeted page-to-PNG rendering runs in milliseconds per page on a CPU vServer (`SpatialPdfExtractor` / `LegacyPdfToTextAdapter` fallback), with an optional `DoclingHttpAdapter` (`docling-serve`, MIT / Apache-2.0 under LF AI & Data, including TableFormer and `Granite-Docling-258M`) for self-hosted layout/table enrichment on CPU or small GPUs.
  2. **Multimodal VLM reasoning & table extraction (`LlmClient::chat_vision_constrained`):** Targets **Apache-2.0 / MIT open-weight VLMs** — primarily **`Qwen3-VL`** (Apache-2.0), **`GLM-OCR`** (MIT), and **`PaddleOCR-VL`** (Apache-2.0).
     - **Production (Pay-as-you-go, GDPR / ZDR / No-Training):** Routed through curated OpenAI-compatible vision endpoints with EU data residency and policy-declared or account-attested Zero Data Retention (`EURouter`, Scaleway Generative APIs Paris, OVHcloud AI Endpoints EU, Nebius Token Factory EU — ~€0.005–€0.02 per 8-page schedule, ~€0.01–€0.03 for screenplay structural zoning; the two documented caveats — Scaleway's error-path retention and Nebius's Global processing region — are accepted and scoped in `D2.1` → "Accepted exceptions under D2"). `chat_vision_constrained` SHALL reject (fail-closed) any production OpenAI-compatible endpoint whose provider policy does not declare Zero Data Retention, no training on customer inputs, and EU data residency, and the check SHALL run **before** any page image is serialized, because publishing an unpublished screenplay page to a non-compliant endpoint is an NDA/GDPR breach that cannot be undone server-side.
     - **Local development (4 GB VRAM / CPU):** Executed locally via `Ollama` (`Qwen3-VL:2b/4b` Q4 or `GLM-OCR` 0.9B) with zero external network traffic.
#### D2.1 — Declared EU vision endpoints (issue #968)

The fail-closed table above is only a guarantee if an operator can *reach* a compliant endpoint when one flaps. Production ran with exactly one declared vision endpoint (`EURouter`), whose recurring instability held schedule imports for the whole `AI_IMPORT_MAX_PROVIDER_HOLD_SECS` window, so #968 declared the three researched alternatives in code. Re-verified **2026-11-25** against each provider's own documentation (and, for OVHcloud, against the live anonymous `GET /v1/models` response):

| Provider (`LlmProvider`) | Base URL | ZDR | No training | EU residency | Declared in code |
|---|---|---|---|---|---|
| `EURouter` | `https://api.eurouter.ai/api/v1` | ✅ | ✅ | ✅ | compliant |
| `Scaleway` | `https://api.scaleway.ai/v1` | ✅ default, **one accepted exception** (below) | ✅ | ✅ Paris, France | compliant |
| `Ovhcloud` | `https://oai.endpoints.kepler.ai.cloud.ovh.net/v1` | ✅ billing/ops metadata only | ✅ | ✅ EU-only infrastructure | compliant |
| `Nebius` | `https://api.tokenfactory.nebius.com/v1` | ⚠️ **account-level switch** | ✅ | ⚠️ EU **data** residency; processing region Global (below) | **fail-closed** until attested |
| `OpenAI`, `Gemini`, `OpenRouter`, `Neuralwatt`, `OpenCode`, `OpenCodeGo` | — | ✗ | ✗ | ✗ | rejected |
| `Ollama` | local | ✅ | ✅ | ✅ (no egress) | compliant |

Sources: Scaleway, "Data privacy" — *"By default we apply a Zero Data Retention Policy"*, inputs are *"not used for training, retraining, or improving the base models"*, data stored in *"Paris, France"* (`scaleway.com/en/docs/generative-apis/reference-content/data-privacy/`, reviewed 2025-10-03; the Batch API — which this workspace never uses — retains inputs up to 24 h). OVHcloud, "AI Endpoints" — *"Zero data retention: We keep only the data required for billing purposes"*, *"Service hosted at OVHcloud in the European Union"*, *"Your data is never used to train our models"* (`ovhcloud.com/en/public-cloud/ai-endpoints/`). Nebius, Token Factory, "Legal Quick Guide" — no training on prompts/inputs/outputs, while ZDR is the organization-level `ZDR Mode` switch (admin-only, off by default) and public endpoints carry **no region commitment** (`docs.tokenfactory.nebius.com/legal/legal-quick-guide`).

**Accepted exceptions under D2 (owner decision, 2026-11-25).** Two documented caveats are accepted for the vision path rather than treated as disqualifying. Without them the fail-closed table would have exactly one reachable hosted endpoint (`OVHcloud`) plus `EURouter`, which is the single-endpoint fragility #968 exists to remove. Both are narrow, written down here, and re-verified with the rest of this table:

1. **Scaleway — error-path retention.** The ZDR policy is not unqualified: *"For Serverless, it is only in the event of misuse harming the service functionality (such as specific customer requests generating unexpected errors or carrying out malicious activity) that we may store temporarily and access the full content of HTTP requests … As a concrete example, this analysis happens when a request triggers a 500 HTTP error, occurring very rarely (1 out of a million requests). Data is stored for up to two weeks … This temporary data storage does not apply to Dedicated Deployments."* **Scope of the acceptance:** serverless (our tier — a synchronous call does **not** escape the exception; an earlier revision of the code comment wrongly claimed it did), the misuse path only (the provider's own example is a request triggering an `HTTP 500`, quoted as `~1 out of a million requests`; the policy does **not** enumerate a closed list of triggers, so this ADR claims no exemption for a successful request either), retention ≤ 2 weeks, triage-only, no training and no onward sharing. `zero_data_retention` therefore stays `true` for Scaleway **as accepted-with-scope**, not as an unqualified guarantee; the code comment in `crates/core/src/ai/ports.rs` states the same scope and the two must change together.
2. **Nebius — residency is a data guarantee, not a processing-region guarantee.** The legal guide states that for public endpoints "the Region field shows **Global**. The processing location is decided dynamically, is not tied to any single data center, and can change at any time without prior notice", and that only a Dedicated Endpoint fixes a region. `eu_data_residency: true` therefore asserts what the provider *does* commit to: any **retained copy** lives in Finland (EU), processing runs under the DPA/Standard Contractual Clauses, and with `ZDR Mode` on there is no retained copy at all. **Scope of the acceptance:** per-request processing may occur outside the EU; nothing is stored there, and the attestation (`AiConfig.zdr_attested`) is what makes the no-retained-copy half true. Read this flag as `EU data residency`, never as `processing stays in the EU`; an operator who needs a guaranteed processing region must use a Dedicated Endpoint (not wired: the base URL is curated and static).

**Nebius is therefore declared with `zero_data_retention: false`.** A boolean the code cannot observe must never be asserted `true`; a `false` gate is a *correct* state, not a TODO. The operator attests the account setting per AI configuration (`AiConfig.zdr_attested`, collected by the Flutter client and persisted with the config — the vault holds only key material), and `vision_egress_policy_for_config(provider, zdr_attested)` is the **only** place that turns that attestation into an effective policy. The attestation lifts exactly one flag: `no_training_on_inputs` and `eu_data_residency` always come from the provider declaration, so an attestation can never open an undeclared provider. **The attestation is bound to the credential it was given for:** it describes one organization's `ZDR Mode`, so an update that replaces `vault_key_id` (or the provider, which always requires a fresh key) does not inherit it — the stored attestation is cleared unless the same request re-asserts `zdr_attested: true`. A prompt-only edit keeps it. The deployment prerequisite is the runbook section "AI import vision egress" in `docs/operations/runbooks.md`.

**Model curation** follows the same verify-first rule: `curated_model_ids` lists only open-weight (Apache-2.0/MIT) vision models confirmed in the provider's own catalogue — Scaleway `qwen3.5-397b-a17b` / `mistral-small-3.2-24b-instruct-2506`, OVHcloud `qwen3-vl-30b-a3b` / `Mistral-Small-3.2-24B-Instruct-2506`, Nebius `Qwen/Qwen3.8-27B` / `deepseek-ai/DeepSeek-V4.1-Flash-1017`. OVHcloud's `Qwen2.5-VL-72B-Instruct` is **not** curated (the catalogue marks it "Being retired"), and NVIDIA's Nemotron VL is not curated because its weights are not OSI-licensed. Rotated-out IDs survive in `default_allowlist` and the `ai_model_pricing` seed, so persisted configurations keep working.

**Re-verification duty:** the provider policy and the model catalogue are live data. Any future change to this table MUST carry a new verification date plus the source link, and a model may only be curated after it appears in the provider's `/models` answer. Nebius `/v1/models` needs a paid key, so that one check is a deployment task recorded in the same runbook.

- **Explicitly rejected on openness/licensing grounds:**
  - `HunyuanOCR-1.5` (*Tencent Hunyuan Community License* — territory/commercial clauses, non-OSI).
  - `chandra-ocr-2` (*Custom OpenRAIL-M* — revenue cap and competing-service prohibition).
  - `dots.mocr` (auxiliary commercial API delivery restrictions and chart-to-SVG specialization unsuited to text/tabular scripts).

### D3 — Zone-aware screenplay segmentation & verbatim span slicing

Screenplay parsing introduces **Pass 0 (Document Zoning & Structural Indexing)** ahead of per-scene LLM extraction:

1. **Page Zoning:** Pages are classified into `TitlePage`, `CastList`, `SceneIndex` (e.g. `"SCRIPT REPORT"`), `FrontMatter` (e.g. `"SYNOPSIS"`, `"MEDIZINISCHE FÄLLE"`), and `ScriptBody`.
2. **Strict `ScriptBody` Chunking:** Only `ScriptBody` emits `SceneChunk`s. `FrontMatter` prose is never appended to scenes. `PageHeader`, `PageFooter`, and `"CONTINUED:"` markers are stripped cleanly before chunk assembly. Combined headings (`"A+I/T"`, `"I+A/T"`, `"A/I/T"`) are first-class heading tokens.
3. **Verbatim Slicing (Zero Prose Re-Transcription):** Structural analysis identifies scene start/end block anchors; Rust slices the verbatim text directly from `StructuredDocument` blocks rather than asking a VLM to re-emit scene dialogue/action. This keeps token cost minimal and preserves `verify_draft_outfits` verbatim `source_quote` verification without false rejections. Kerning-split character tokens (`"Mik k o"`) are normalized deterministically only when matching a known entry in `CastDirectory`.
4. **`SceneIndex` Reconciliation:** When a `SceneIndex` zone is present, its scene number sequence serves as a built-in manifest check against `ScriptBody` chunks; discrepancies are recorded on `ScriptContext` diagnostics/uncertainties rather than silently masked by cross-zone merging.

### D4 — Deterministic cast-category precedence ladder & neighbor context

To improve `main_cast` / `guest` / `extra` assignment without inducing LLM hedging or false positives (such as promoting `(OT)` extras to `guest`):

- **Models extract facts; Rust resolves categories:** `CastList` zones yield a structured `CastDirectory` mapping normalized names to their stated section (`main_cast` for `"HAUPTCAST"`, `guest` for `"EPISODENHAUPTROLLEN"` / `"GASTROLLEN"` / `"CROSS"`, `extra` for `"KOMPARSEN"` / `"STATISTEN"`). Scene extraction records appearance, dialogue presence, and explicit inline markers (`(OT)`).
- **Precedence in `crates/core`:**
  1. Explicit `CastDirectory` entry wins (so a silent episodic lead listed under `"EPISODENHAUPTROLLEN"` as `"JONAS (8, OT)"` resolves deterministically to `guest`, while named background performers under `"KOMPARSEN"` resolve to `extra` even without inline `(OT)`).
  2. For unlisted characters: existing season `Character` projection category (passed in from the read edge at job start, respecting the CQRS boundary) → explicit inline `(OT)`/background marker (strictly `extra`) → zero-dialogue generic role designator across the script (`extra`) → `main_cast` default.
- **Neighbor-Scene Continuity Bracket:** Each Pass 1 chunk and Pass 2 continuity gap receives compact metadata for the immediately preceding and succeeding `ScriptBody` scenes (number, location, mood, script day, shared characters) alongside `CastDirectory`.

**Shipped by issue #960 (P4):** `LlmVisionPageInput` / `LlmVisionRequest` / `LlmClient::chat_vision_constrained` (core `ports`) with the fail-closed `VisionEgressPolicy` table (`vision_egress_policy` / `vision_egress_compliant` — every provider undeclared until it asserts ZDR + no-training + EU residency; `EURouter` declares, local `Ollama` is exempt because no bytes leave the host), the hosted transport whose pre-egress gate runs before any base64 encoding (ONE bounded plain-JSON fallback for providers rejecting `image_url` + `json_schema`), the Ollama `images` transport, and the page-streaming `ScheduleImportWorker::extract_pdf_pages` loop (render-on-demand per page, `<carry-over>` + `<spatial-text-hint>` context, `ScheduleCarryOver` merge, per-page `#664` progress frames, the deferred document-wide `AI_IMPORT_MAX_RENDERED_TOTAL_BYTES` ceiling, usage accumulated across ALL page calls). Additive wire metadata: `ShootingSchedule.cast_legend`, `ShootingScheduleRow.shot_suffix` / `cast_refs` (`ScheduleRoleModifier`: `none`/`dummy`/`voice_only`/`extra_ot`), all `#[serde(default)]`. `parse_schedule_scene_ref` now returns the pick-up suffix (`"300.37N"`); `"SB7.2"`/`"T3"` stay honestly unmatched. Schedule apply still dispatches zero `CharacterCommands` (`D6`). The legacy-pdftotext rollback keeps the pre-#960 flat-text request via the `parser_fingerprint` guard. The Golden Corpus harness asserts the schedule through the same deterministic extraction (`sched=` expectations: 129 rows, 16 day labels, day-1 date, `300.37N`, legend modifiers, zero `"Drehfrei"`) — plus the deterministic spatial extractor itself now reads the real `Drehplan_1.pdf` page grid (including bottom-band rows, which schedule pages legitimately carry in the footer band).

**Shipped by issue #961 (P3):** `document::parse_cast_directory` / `CastDirectory` (static section table, comma-list and parenthetical parsing), `document::normalize_kerning` (dictionary-gated Ghostscript repairs only), `preview::resolve_character_category` (the ladder above, with one `characters` uncertainty only for conflicting sections), `preview::neighbor_brackets` / `render_document_context` for Pass 1, and `continuity::continuity_state` `previous_scene` / `next_scene` fields for Pass 2. The resolver runs in `core` AFTER the model answers; the season cast slice is loaded once in `infra::ai::worker_loop` at the read boundary and passed by borrow, never through an `Arc` or a write-side repository call. Grounding accepts a quote against both the raw and the normalized view, so a kerning repair cannot drop a real outfit.

### D5 — Page-streaming multimodal schedule extraction & additive cast legend

Non-CSV shooting schedules are processed **page-by-page** rather than as a single flattened text blob:

- Page 1 / legend tables (`"ROLLEN"`) are extracted into an optional `cast_legend` map (`number -> { name, modifier: VoiceOnly | Dummy | ExtraOt | None }`).
- Schedule table pages are extracted sequentially via multimodal VLM (`page PNG + spatial text blocks + carry_over { active_shooting_day, date }`), eliminating the single-request `8192` output-token bottleneck and preserving visual multi-row cell grouping (`"300.33"` above script day `"2"`).
- `"Drehfrei"` banners are ignored; shot suffixes (`"300.37N"`) parse cleanly to `(episode: 300, scene: 37)` with additive shot metadata; non-episode units (`"SB7.2"`, `"T3"`) remain honest `unmatched_schedule_rows`.
- Cast numbers on schedule rows are resolved strictly against `cast_legend` as **additive, read-only preview metadata** — schedule apply never creates or mutates `Character` aggregates.

### D6 — Out-of-tree Golden Evaluation Harness

An env-gated test/CLI harness (`AI_EVAL_CORPUS_DIR`) evaluates adapters and zoning rules against real production PDFs stored outside the Git repository using `omni_parse_bench`-style deterministic assertions (exact scene count, zero synopsis contamination, cast-category precision/recall, schedule row & day alignment). Synthetic layout-equivalent fixtures live in-tree for CI.

---

## Consequences

### Positive
- **Eliminates structural scene-count drift:** Separating `CastList`, `SceneIndex`, `FrontMatter`, and `ScriptBody` removes the synopsis Franken-chunk defect and turns `"SCRIPT REPORT"` pages from a bug trigger into a self-checking manifest.
- **High cast-classification accuracy with zero `(OT)` false positives:** Page-2 cast tables and silent-vs-speaking corpus signals classify `main_cast`, `guest` (`"EPISODENHAUPTROLLEN"` / `"CROSS"`), and named `extra` (`"KOMPARSEN"`) deterministically.
- **Reliable PDF schedule import without CSVs:** Multimodal page-streaming resolves stacked multi-row cells, full-width day banners, and numeric cast legends within bounded per-page token budgets.
- **Sovereign, low-cost operations:** Runs cleanly on a ~€20/mo CPU vServer paired with €0.01–€0.05/doc GDPR/ZDR European VLM calls, or 100% offline on a 4 GB VRAM developer GPU via `Ollama`.
- **Clean swap seam:** Future open document VLMs (e.g. `MinerU 2.5-Pro` Apache-2.0 sidecar or `Docling`) plug into `DocumentStructureExtractor` without touching worker orchestration, merge logic, or apply sagas.

### Negative
- **Additional Pass 0 & per-page schedule requests:** Screenplay imports add a lightweight zoning/cast-list step, and an 8-page PDF schedule makes up to 8 bounded page calls instead of 1 text call (mitigated by per-page progress frames and low ~12k–15k total vision input tokens).
- **PDF rendering dependency in `infra`:** Rendering page PNGs for multimodal VLM calls requires `pdftoppm` (Poppler, already installed alongside `pdftotext` in the runtime image) or `pdfium` in `crates/infra`, bounded by strict timeouts, DPI caps, and child-process reaping (`pdf.rs` pattern).

## Alternatives Considered

1. **Patching more regexes onto `pdftotext -layout` (`ADR-013` status quo):** Rejected. Cannot separate prose `"SYNOPSIS"` pages from trailing `"SCRIPT REPORT"` headings reliably across arbitrary broadcast templates, and cannot reconstruct borderless multi-row shooting-schedule grids.
2. **Full end-to-end VLM transcription of all 95 screenplay pages:** Rejected. High latency and output-token cost (~50k+ output tokens), and minor VLM wording changes break `verify_draft_outfits` verbatim `source_quote` checks.
3. **Self-hosting a mandatory vGPU server (`vLLM` + `MinerU 2.5` / `HunyuanOCR-1.5`):** Rejected as baseline requirement because Netcup vGPU instances violate fixed-cost targets and `HunyuanOCR-1.5` fails OSI license requirements; kept optional behind `DocumentStructureExtractor` for high-volume on-prem deployments.

## Notes

- **CQRS Boundary (`AGENTS.md` §1):** Any existing season `Character` list used as a fallback hint for `CastDirectory` MUST be read at job preparation in the worker/read-side orchestration and passed into pure `core` functions as an immutable value slice — write-side command adapters and aggregates remain completely untouched.
- **Chunk Resume (`#871`):** Bump `CHUNKER_VERSION` and include `extractor.parser_fingerprint()` **and** the accepted anchor plan's `structural_plan_digest` in `chunk_store::fingerprint_key` when landing Package 1/2.
