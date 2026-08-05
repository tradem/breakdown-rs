## 1. Workspace setup & dependencies

- [x] 1.1 Add `schemars` workspace dependency (coexists with `utoipa`)
- [x] 1.2 Add `pdftotext` CLI to the dev/prod Docker image (ADR-013)
- [x] 1.3 Add `csv` crate (schedule native parse path)
- [x] 1.4 Extend architecture tests to forbid `core` depending on `schemars`-runtime or `reqwest`
- [x] 1.5 Add `AI_IMPORT_ENABLED` feature flag (env-gated; default off)

## 2. Core `ai` bounded context — types & ports

- [x] 2.1 Create `crates/core/src/ai/mod.rs` module skeleton (namespaces: aggregate, commands, events, ports, views, preview, bounds)
- [x] 2.2 Define `LlmProvider` enum (`#[non_exhaustive]`; OpenAI, OpenRouterEU, Ollama) with curated-base-url accessor contract
- [x] 2.3 Define `AiConfig` aggregate: state (id, user_id, provider, assistant_model, image_model, prompts map, vault_key_id, version) + `CreateAiConfig`/`UpdateAiConfig`/`RevokeAiConfig` commands + events
- [x] 2.4 Define `AiConfigError` (EmptyProvider, ProviderMismatch, NotFound, VersionMismatch, …) following existing `*Error` pattern
- [x] 2.5 Define `AiConfigView` read-model DTO (no secrets)
- [x] 2.6 Define `LlmModelCatalog` port (`list(provider, vaulted_key) -> Vec<ModelInfo>`) and `LlmClient` port (`chat_constrained(req) -> ScriptContext` shaped output)
- [x] 2.7 Define static preview DTOs: `ScriptContext`, `DraftScene`, `Uncertainty` (with `suggested_value: Option<String>`), `ShootingSchedule`, merged preview + `unmatched_schedule_rows`/`unmatched_script_scenes`
- [x] 2.8 Define `AiImportJob` operational types: `AiImportJobId`, `DocumentKind` (Script/Schedule), `JobStatus` (Pending/Running/Succeeded/Failed/DeadLetter), `AiImportJob` row struct (excluding secrets)
- [x] 2.9 Define `AiImportBounds` config struct (mirrors `RenderBounds`: max_chunks_per_script, max_tokens_per_req, max_concurrent_jobs_global, …) + compile-time invariant assertion
- [x] 2.10 Define telemetry types: `provider, model, doc_kind, chunk_count, tokens_in/out, latency_total, accept_as_is, edit_distance`
- [x] 2.11 Define `AiImportQueue` port (enqueue/dedup/get/status) mirroring `ReportArchivalQueue` shape
- [x] 2.12 Define `AiImportMappingRepository` port (find/insert/list-by-preview)

## 3. Core `ai` preview/merge/apply deterministic logic

- [x] 3.1 Implement `SceneChunk::extract_scenes` fuzzy INT./EXT. chunker (regex, in core, no infra)
- [x] 3.2 Implement `merge_schedule_to_scenes` pure function: deterministic join of `ShootingSchedule` rows → applied `SceneView` list by scene_number → `MergedPreview` + unmatched lists
- [x] 3.3 Implement apply dispatch planner: given a preview + `AiImportMapping` decisions, produce the ordered list of existing commands (`CreateScene`/`UpdateSceneDetails`/…) to dispatch
- [x] 3.4 Implement uncertainty-apply-gate check: preview open uncertainties present → reject apply
- [x] 3.5 Implement merge-apply-gate check: `unmatched_*_rows` present → reject schedule apply
- [x] 3.6 Unit tests: chunker (deterministic, multiple formats), merge (matched + unmatched), planner idempotency on crash-retry, both apply gates

## 4. Infra — provider transport & catalog

- [x] 4.1 Create `crates/infra/src/ai/` module skeleton
- [x] 4.2 Implement `OpenAiCompatibleChatClient` (chat completions + `response_format` JSON-schema constrained decoding) against curated base URLs
- [x] 4.3 Implement model-catalog adapter: `GET /v1/models` with curated allowlist filter
- [x] 4.4 Implement Ollama adapter: `{format:"json"}` fallback + bounded parse-or-retry when schema mode unsupported
- [x] 4.5 Classify LLM HTTP errors: 429/5xx/timeout → `ServiceUnavailable` (retry in-loop); 4xx → permanent `Failed`; wire into existing `retry_transient`
- [x] 4.6 Reuse `CredentialVault`/`VaultClient` for AI keys: store/fetch via new `vault_key_id` bindings (no new secret store)
- [x] 4.7 Add `pdftotext` CLI wrapper adapter (subprocess; bounded output; error → ValidationError)
- [x] 4.8 Add CSV schedule parser adapter (flat row → `ShootingSchedule`)
- [x] 4.9 Add default prompt-template seed config (per `DocumentKind`) — TOML in `config/`, parsed in infra (pattern: `default_costume_categories.toml`)

## 5. Infra — job queue, mapping projection, workers

- [x] 5.1 New PG migration: `ai_import` schema with `ai_import_job` table + `projection_ai_import_mapping` table (dedup_key, status enum, telemetry columns; mirroring report-archival layout)
- [x] 5.2 Implement `AiImportQueue` adapter (PG; enqueue dedup by doc hash + user; claim/status transitions; `DeadLetter`)
- [x] 5.3 Implement `AiImportMappingRepository` adapter (PG; `WHERE` version-guard-style idempotent insert)
- [x] 5.4 Implement `ScriptImportWorker`: dequeue → pdftotext → chunk → per-chunk `LlmClient` (bounded by `max_chunks_per_script`) → assemble `ScriptContext` preview blob → store + project preview + telemetry
- [x] 5.5 Implement `ScheduleImportWorker`: dequeue → CSV parse or LLM → `ShootingSchedule` preview blob → telemetry
- [x] 5.6 Implement `MergeWorker`: dequeue → load schedule preview + Scene read-model projection by block → `merge_schedule_to_scenes` → block until block has applied scenes → store merged preview + unmatched lists
- [x] 5.7 Implement `ApplyWorker`: reviewed rows → planner → dispatch existing commands (source: `AiExtracted`); per-row mapping check before Create; `series_id` resolved at the API edge (no write-side projection lookup)
- [x] 5.8 Per-user in-flight concurrency cap (advisory lock / PG counter); global concurrency cap from `AiImportBounds`
- [x] 5.9 Graceful shutdown: drain in-flight jobs to terminal state before `run()` returns `Ok(())`
- [x] 5.10 Telemetry write at apply time: `accept_as_is` + content-free `edit_distance` (no script text)

## 6. API handlers & authorization

- [x] 6.1 Add `/v1/ai-import/providers` (GET curated enum) and `/v1/ai-import/providers/{provider}/models` (GET curated catalog) — read-only, requires `has_active_credential_role`
- [x] 6.2 Add `AiConfig` CRUD handlers under `/v1/ai-import/config` — gated `has_active_credential_role`, `// AUTHZ-GATE:` comments
- [x] 6.3 Add `POST /v1/ai-import/scripts` (upload PDF → enqueue ScriptImportJob; dedup) and `POST /v1/ai-import/schedules` (upload CSV/DOC → enqueue ScheduleImportJob) — active costume-dept membership, `// AUTHZ-GATE:`
- [x] 6.4 Add `GET /v1/ai-import/jobs/{id}` and `GET /v1/ai-import/jobs/{id}/preview` (ScriptContext / ShootingSchedule / merged) — membership gate
- [x] 6.5 Add `POST /v1/ai-import/jobs/{id}/apply` (reviewed rows + per-row mapping decision → ApplyWorker dispatch) — membership gate, resolve `series_id` at edge, `// AUTHZ-GATE:`
- [x] 6.6 Register all routes on the production router + `ApiDoc` (utoipa) OpenAPI surface
- [ ] 6.7 Handler tests: dedup on re-upload, 403 for non-members, apply-gate rejections, crash-retry idempotency

## 7. Integration tests (crates/integration-tests)

- [ ] 7.1 Round-trip: script PDF upload → job Succeeded → ScriptContext preview with uncertainties → resolve → apply → Scene created with `source: AiExtracted`
- [ ] 7.2 Round-trip: schedule upload → merge (after script apply) → unmatched adjudication → schedule apply → ShootingDays/SceneShoots created
- [ ] 7.3 Idempotency: re-apply same preview → no duplicate aggregates (mapping hit)
- [ ] 7.4 Resilience: simulate 5xx → `retry_transient` retries → success; 4xx → `Failed`
- [ ] 7.5 Cost cap: oversized script → job `Failed` at `max_chunks_per_script`
- [x] 7.6 Ordering: schedule import before script apply → merge blocked
- [ ] 7.7 Telemetry: `accept_as_is` recorded true on no-edit apply; `edit_distance` recorded on correction; no script text persisted

## 8. Guardrails, docs, security

- [x] 8.1 Verify the `cqrs-boundary` ast-grep rule covers `crates/infra/src/ai/` (add path if needed); ApplyWorker resolves `series_id` at edge only
- [x] 8.2 Add `discard-result` rule coverage for new ai infra (no `let _ = <fallible>`)
- [x] 8.3 Add `test-helper-gate` coverage for any `*_for_test` AI helpers
- [x] 8.4 gitleaks scan: no provider keys, no prompt secrets in repo
- [x] 8.5 Confirm all AI handlers carry `// AUTHZ-GATE:` comments (grep audit)
- [x] 8.6 Timing-safe test for `AiImportBounds` worst-case cost (derive max backoff from constants; no sleep)
- [x] 8.7 Update ADR-013 status Proposed→Accepted with reference to this change; add ADR-030 (AI bounded context) capturing decisions A–I
- [x] 8.8 Document env vars (`AI_IMPORT_ENABLED`, bounds, default prompt config path) in AGENTS.md §6
