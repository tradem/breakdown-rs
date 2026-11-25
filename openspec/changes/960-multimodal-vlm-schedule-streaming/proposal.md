<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (opencode-go) -->

# Proposal — P4 Multimodal VLM vision seam, page-streaming PDF schedule extractor & additive cast legend (issue #960)

Part 4 of 4 (`[P4]`) of `ai-import-vlm-document-structure` / ADR-041 (`tasks.md` §4.1–4.6 + deferred §1.4 document-wide rendered-byte ceiling). Depends on #958 (`[P1]`), #959 (`[P2]`), and #961 (`[P3]`), all merged on `main` (`5ae975db`).

## Discovery evidence

- Index: project `breakdown-rs`; `scripts/check-graph-freshness.sh` → fresh (`5ae975db`, 2026-11-24T05:21:06Z).
- Graph (meaning): `search_code("LlmVisionRequest|chat_vision_constrained|extract_schedule_page|ScheduleLegendEntry|ScheduleCastMember|ScheduleRoleModifier|ScheduleCarryOver|VisionEgressPolicy", regex=true)` → 0 code definitions (only ADR-041 and `openspec/changes/ai-import-vlm-document-structure/*`). `get_code_snippet(LlmClient)` → `chat_constrained` + `extract_schedule`; `get_code_snippet(DocumentStructureExtractor)` → `parser_fingerprint`, `extract`, `render_page`; `trace_path(parse_schedule_scene_ref, inbound)` → 4 callers (`ShootingScheduleSchema.into_core`, `preview_tests`, `OpenAiCompatibleChatClient.extract_schedule`, `retry_schedule`); `trace_path(ScheduleImportWorker.process, inbound, include_tests=true)` → 9 callers (8 tests in `infra/src/ai/tests.rs` + `workers.rs`).
- Text (occurrence): `search_code("ShootingSchedule(Row)? \\{", regex=true)` → 20 sites across `core/src/ai/preview.rs`, `core/src/ai/preview_tests.rs`, `infra/src/ai/{csv_schedule,client,decision_scoring,tests,worker_mutation_tests}.rs`.
- Coverage: `check_index_coverage(paths=[core/src/ai/ports.rs, core/src/ai/preview.rs, core/src/ai/document.rs, core/src/ai/bounds.rs, infra/src/ai/client.rs, infra/src/ai/ollama.rs, infra/src/ai/workers.rs, infra/src/ai/csv_schedule.rs, infra/src/ai/schedule_apply.rs, infra/src/ai/spatial_pdf.rs, infra/src/ai/document_extractor.rs, infra/src/ai/provider_registry.rs, infra/tests/ai_document_eval_corpus.rs])` → all `no_recorded_issue` / `metadata_match`.
- Not the graph (and why): `config/default_ai_prompts.toml` and `config/ai_eval_corpus.tsv` are TOML/TSV configuration files read directly with `read`; `~/Downloads/drive-download/Drehplan_1.pdf` out-of-tree Golden Corpus layout was inspected via `pdftotext -layout` to verify real multi-row grid cells, `"ROLLEN"` legend entries, `"Drehfrei"` banners, `"300.37N"`, `"SB7.2"`, `"T3"`, and trailing page-break shooting-day headers (`"11. Drehtag"` at the bottom of page 5).

## Plan

1. **Core — Vision Seam & Pre-Egress Provider Policy Gate (`crates/core/src/ai/ports.rs`):**
   - Add `LlmVisionPageInput { pub page_number: u32, pub png_bytes: Vec<u8>, pub spatial_text_hint: Option<String> }` and `LlmVisionRequest { pub provider: LlmProvider, pub model: String, pub prompt: String, pub user_context: String, pub page: LlmVisionPageInput, pub max_tokens: u32, pub response_schema: Option<serde_json::Value>, pub reasoning_effort: Option<String> }`.
   - Add `VisionEgressPolicy { pub zero_data_retention: bool, pub no_training_on_inputs: bool, pub eu_data_residency: bool }`, pure `vision_egress_policy(provider: LlmProvider) -> VisionEgressPolicy`, and `vision_egress_compliant(policy: VisionEgressPolicy) -> bool` (fail-closed by default; `LlmProvider::EURouter` declares all three guarantees; `LlmProvider::Ollama` is local and has zero external egress).
   - Extend `LlmClient` with `chat_vision_constrained(&self, req: LlmVisionRequest) -> Result<LlmCallOutcome<SchedulePageExtraction>, DomainError>` (and `extract_schedule_page` delegating to `chat_vision_constrained` by default), with a safe default returning a validation error for pure text test doubles.
2. **Core — Shot-Suffix Parsing, Additive Cast Legend DTOs & Page Carry-Over (`crates/core/src/ai/preview.rs`, `document.rs`):**
   - Extend `parse_schedule_scene_ref(raw: &str) -> (Option<i32>, Option<u32>, Option<String>)`:
     - `"294.10"` → `(Some(294), Some(10), None)`
     - `"300.37N"` → `(Some(300), Some(37), Some("N"))`
     - `"12A"` → `(None, Some(12), Some("A"))`
     - `"SB7.2"`, `"T3"` → `(None, None, None)` (preserved in `row_ref`, landing in `unmatched_schedule_rows`).
   - Add `#[derive(ToSchema)]` additive types:
     - `ScheduleRoleModifier` (`#[serde(rename_all = "snake_case")]`: `None`, `Dummy`, `VoiceOnly`, `ExtraOt`)
     - `ScheduleLegendEntry { pub code: String, pub character_name: String, #[serde(default)] pub modifier: ScheduleRoleModifier }`
     - `ScheduleCastMember { pub code: String, pub character_name: String, #[serde(default)] pub modifier: ScheduleRoleModifier }`
     - On `ShootingSchedule`: `#[serde(default)] pub cast_legend: BTreeMap<String, ScheduleLegendEntry>`
     - On `ShootingScheduleRow`: `#[serde(default)] pub shot_suffix: Option<String>`, `#[serde(default)] pub cast_refs: Vec<ScheduleCastMember>`
   - Add `SchedulePageExtraction`, `SchedulePageRow`, `ScheduleCarryOver`, deterministic `"Drehfrei"` banner filtering, `"ROLLEN"` legend normalization & code resolution (dropping unknown codes silently), carry-over day/date inheritance across page breaks, and deterministic spatial schedule page extraction (`extract_schedule_page_from_structured`) for spatial hints and Golden Corpus verification.
   - Add `AI_IMPORT_MAX_RENDERED_TOTAL_BYTES_ENV` / `DEFAULT_MAX_RENDERED_TOTAL_BYTES` (`64 MiB`, coupled via `const _: () = assert!(DEFAULT_MAX_RENDERED_TOTAL_BYTES >= DEFAULT_MAX_RENDER_BYTES)`) in `document.rs`.
3. **Infra — Multimodal Transports & Page-Streaming Schedule Worker (`crates/infra/src/ai/client.rs`, `ollama.rs`, `workers.rs`):**
   - Implement `chat_vision_constrained` / `extract_schedule_page` on `OpenAiCompatibleChatClient`: enforce `vision_egress_compliant(vision_egress_policy(self.provider))` **before** any base64 image serialization or HTTP call (fail-closed validation error on non-compliant endpoints); serialize user content as `[{ "type": "image_url", "image_url": { "url": "data:image/png;base64,..." } }, { "type": "text", "text": ... }]`; preserve `#871`/`#925`/`#927` circuit-breaker, retry-hint, truncation-retry, and inner JSON-mode fallback if a provider rejects `image_url` + strict `json_schema`.
   - Implement `chat_vision_constrained` / `extract_schedule_page` on `OllamaChatClient`: serialize `"images": ["<base64>"]` on the user message with structured JSON formatting, breaker checks, and zero Vault lookup.
   - Refactor `ScheduleImportWorker::process` for `SourceFormat::Pdf`: extract `StructuredDocument` via `self.extractor`, stream pages `1..=K` via `self.extractor.render_page` + `retry_schedule_page` (`chat_vision_constrained`) with `ScheduleCarryOver`, enforce the document-wide rendered-byte ceiling (`AI_IMPORT_MAX_RENDERED_TOTAL_BYTES`), drop each page's `RenderedPage` before rendering the next, accumulate `UsageAccumulator` across all page calls, hold cleanly on breaker open, and publish per-page progress frames (`chunk = Some(page_idx)`, `chunks_total = Some(page_count)`). Keep `LegacyPdfToTextAdapter` (`AI_DOCUMENT_PARSER=legacy-pdftotext`) as the flat-text rollback path.
   - Ensure `ScheduleApplyWorker` (`crates/infra/src/ai/schedule_apply.rs`) dispatches **zero** `CharacterCommands`.
4. **Prompt, OpenAPI, Flutter Client & Golden Corpus (`config/default_ai_prompts.toml`, `backend/openapi.yaml`, `frontend-flutter/`):**
   - Update `[schedule]` in `backend/config/default_ai_prompts.toml` for multimodal page-level extraction (`"ROLLEN"` legend, stacked multi-row cells, `"300.37N"` shot suffixes, `"SB7.2"`/`"T3"` verbatim preservation, `"Drehfrei"` skipping, and `<carry-over>` inheritance).
   - Extend `crates/infra/tests/ai_document_eval_corpus.rs` and `config/ai_eval_corpus.tsv` to verify `Drehplan_1.pdf` (8 pages, `"ROLLEN"` legend with `Dummy`/`VoiceOnly`/`ExtraOt`, `"300.33"` stacked cell, `"300.37N"` shot suffix, `"SB7.2"`/`"T3"` unmatched preservation, `"Drehfrei"` exclusion, and page-break day carry-over).
   - Regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`), run `../scripts/regen-client.sh` + bump `CLIENT_VERSION` minor version, and attach contract tests in an existing `crates/api` test harness (`AGENTS.md` §8).

## Guardrails

- Zero `Arc<T>` on domain data, extractors, page PNG buffers, or `ScheduleCarryOver` (`png_bytes: Vec<u8>` moved directly into `LlmVisionPageInput`, dropped at end of each page iteration).
- `jiff::civil::Date` exclusively (`ADR-040`).
- `#[serde(default)]` on every new `ShootingSchedule` and `ShootingScheduleRow` field for Garage S3 backward compatibility.
- Zero `CharacterCommands` in `ScheduleApplyWorker` (`ADR-041` D6).
- Zero new `[[test]]` binaries in `crates/api/Cargo.toml` (`AGENTS.md` §8).

## Version Bumps

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.78.0 | 0.79.0 | MINOR | New public multimodal vision port types, pre-egress policy gate, shot-suffix parser, and additive schedule cast-legend DTOs |
| `infra` | 0.89.0 | 0.90.0 | MINOR | Multimodal vision transport in `OpenAiCompatibleChatClient` & `OllamaChatClient` and page-streaming PDF loop in `ScheduleImportWorker` |
| `api` | 0.71.3 | 0.72.0 | MINOR | Additive `ShootingSchedule` / `ShootingScheduleRow` OpenAPI schema fields (`cast_legend`, `shot_suffix`, `cast_refs`) |

## Verification (shipped)

- `cargo test -p breakdown_core` → 811 passed (incl. new `parse_schedule_scene_ref` suffix table, `ScheduleCarryOver` page-break/`"Drehfrei"` tests, `300.37N` merge, `"ROLLEN"` modifier resolution, stacked-cell spatial extraction, `#[serde(default)]` pre-`[P4]` preview regression, and the fail-closed `VisionEgressPolicy` table).
- `cargo test -p infra` → 843 passed (incl. `chat_vision` pre-egress gate tests, the page-streaming worker test with a recording vision client, the legacy-pdftotext rollback test, and the Ollama non-Ollama refusal).
- `AI_EVAL_CORPUS_DIR=~/Downloads/drive-download cargo test -p infra --test ai_document_eval_corpus -- --nocapture` → pass: 5/5 scripts at their expected scene counts (20/20 cast assertions) and `Drehplan_1.pdf` schedule assertions via the deterministic `extract_schedule_from_structured`: 129 rows, 16 distinct day labels, day-1 date `2021-10-18`, `300.37N` → `(300, 37, "N")` on day 6, `SB7.2`/`T3` non-episode, legend modifiers (`1015`/`1040` `voice_only`, `130`/`150` `dummy`, `33` `extra_ot`), zero `"Drehfrei"` rows.
- `cargo clippy --workspace --all-targets -- -D warnings` → clean; `cargo test -p architecture_tests` → pass; `flutter analyze` → clean.
- `UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift` → regenerated `backend/openapi.yaml` (+68 lines, additive only); `frontend-flutter/scripts/regen-client.sh` → clean diff with `breakdown_api` 1.10.0; SPDX check → the 4 reported files are pre-existing regenerated artifacts (identical on a clean `main`).

### Version bumps (final)

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.78.0 | 0.79.0 | MINOR | Multimodal vision port + policy gate, shot-suffix parser, additive schedule cast-legend DTOs, rendered-byte ceiling |
| `infra` | 0.89.0 | 0.90.0 | MINOR | Vision transports (hosted + Ollama), page-streaming `extract_pdf_pages` loop, corpus `sched=` assertions |
| `api` | 0.71.3 | 0.72.0 | MINOR | Additive `ShootingSchedule` / `ShootingScheduleRow` schema fields (wire-additive; Dart client 1.9.0 → 1.10.0) |
