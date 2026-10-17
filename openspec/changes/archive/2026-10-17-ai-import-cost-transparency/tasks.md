<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## 1. Core Domain Types, Provider Enum, and Integer Cost Math (`crates/core`)

- [x] 1.1 Add `LlmProvider::Gemini` (`#[serde(rename = "gemini", alias = "google")]`, `as_str() == "gemini"`) to `crates/core/src/ai/ports.rs` and expand `CURATED_PROVIDERS` to 8 variants with unit tests.
- [x] 1.2 Add `CostDisplayPreference` (`Token` default | `Energy`) to `crates/core/src/ai` and thread it through `AiConfig`, `CreateAiConfig`, `UpdateAiConfig`, `AiConfigEvent::Created` / `Updated` (`#[serde(default)]` for replay compatibility), and `AiConfigView`, plus aggregate unit tests.
- [x] 1.3 Define `Currency` (`USD` | `EUR`), `PricingSource` (`CuratedSeed` | `ProviderLive` | `ModelsDev`), `ModelPricing` (and `pricing: Option<ModelPricing>` on `ModelInfo`), `CostStatus` (`Known` | `Unknown` | `NotApplicable`), `TokenCostBreakdown`, `EnergyCostBreakdown`, `ImageCostBreakdown`, and `CostBreakdown` in `crates/core/src/ai/views.rs` with `ToSchema` derives.
- [x] 1.4 Implement pure integer nano-currency calculation helpers (`i64` with `i128` intermediate math, zero floats) for token cost, cached input token cost, energy cost (millijoules × nano-rate per kWh / $3.6 \times 10^9$), and Neuralwatt surge-protection capping (`min(raw_energy_nano, token_total_nano)`), covered by deterministic unit and boundary tests.
- [x] 1.5 Extend `LlmClient` / `Telemetry` and `AiImportJob` in `crates/core/src/ai` with `LlmCallUsage` (`tokens_in`, `tokens_out`, `cached_tokens_in`, `energy_millijoules`), `AiModelPricingRepository` port trait, and additive `telemetry` / `cost: Option<CostBreakdown>` fields on `AiImportJob`.

## 2. Database Migration, Provider Registry, and Pricing Read Model (`crates/infra`)

- [x] 2.1 Add reversible SQL migration creating `ai_import.ai_model_pricing` (seeded with `curated_seed` baseline rates for all curated assistant and image models across the 8 providers), adding `cost_display_preference TEXT NOT NULL DEFAULT 'token'` to `ai_import.projection_ai_config`, and adding `cached_tokens_in BIGINT NOT NULL DEFAULT 0`, `energy_millijoules BIGINT`, and `cost JSONB` to `ai_import.ai_import_job`.
- [x] 2.2 Update `crates/infra/src/projectors/ai_config.rs` and `crates/infra/src/queries/ai_config.rs` to project and query `cost_display_preference`.
- [x] 2.3 Update `CuratedProviderUrls` (`https://generativelanguage.googleapis.com/v1beta/openai` for `LlmProvider::Gemini`), `PROVIDER_REGISTRY` (`key: "gemini", aliases: &["google"]`), `curated_model_ids`, `curated_image_model_ids`, `recommended_model`, and `default_allowlist()` (retaining legacy model IDs) in `crates/infra/src/ai/provider_registry.rs` and `catalog.rs`.
- [x] 2.4 Implement `PgAiModelPricingRepository` (`find_for_model`, `list_for_provider`, `upsert_batch`) in `crates/infra/src/ai/`.
- [x] 2.5 Implement `AiPricingRefreshWorker` in `crates/infra/src/ai/` using `pg_try_advisory_lock`, ADR-024 hardened `build_hosted_client_with_user_agent` transport, and isolated parsers for `api.neuralwatt.com/v1/models`, `openrouter.ai/api/v1/models`, `api.eurouter.ai/api/v1/models`, and `models.dev/api.json` (`openai`, `google`, `opencode`, `opencode-go`, `neuralwatt`, `openrouter`), with wiremock unit tests.

## 3. LLM Usage/Energy Extraction and Worker Cost Snapshots (`crates/infra`)

- [x] 3.1 Update `OpenAiCompatibleChatClient` (`crates/infra/src/ai/client.rs`) and `OllamaChatClient` (`crates/infra/src/ai/ollama.rs`) to parse `usage` (`prompt_tokens`, `completion_tokens`, `prompt_tokens_details.cached_tokens` / `prompt_eval_count`, `eval_count`) and Neuralwatt `energy` (`energy_joules` / `energy_kwh`) and accumulate usage across truncation/parse retries.
- [x] 3.2 Update `ScriptImportWorker`, `ScheduleImportWorker`, and `QueueMergeWorker` (`crates/infra/src/ai/workers.rs` and `merge_worker.rs`) to accumulate `LlmCallUsage` across all chunks, look up `(provider, model)` in `AiModelPricingRepository`, compute the `CostBreakdown` snapshot (`Known`, `Unknown` for Ollama/unpriced models, or `NotApplicable` for native CSV/merge), and persist it via `record_worker_telemetry` before `mark_succeeded`.
- [x] 3.3 Update `PgAiImportQueue` (`crates/infra/src/ai/queue.rs`) to persist `cached_tokens_in`, `energy_millijoules`, and `cost` in `record_worker_telemetry` / `record_telemetry` and select telemetry + `cost` into `AiImportJob` in `get` and `list_for_user`.

## 4. API Routes, Composition Root, and OpenAPI Contract (`crates/api`)

- [x] 4.1 Wire `PgAiModelPricingRepository` into `Ports` / `AppState` and spawn `AiPricingRefreshWorker` in `crates/api/src/main.rs` when `AI_IMPORT_ENABLED` is true.
- [x] 4.2 Update `list_ai_models` (`GET /v1/ai-import/providers/{provider}/models`) to enrich `ModelInfo` items with `pricing` from `AiModelPricingRepository`, and update `create_ai_config` / `update_ai_config` (`POST`/`PATCH /v1/ai-import/config`) to accept and return `cost_display_preference`.
- [x] 4.3 Add handler and SSE tests (`crates/api/tests/handlers_ai.rs`, `handler_ai_import_sse.rs`) verifying model pricing enrichment, `google`/`gemini` alias routing, `cost_display_preference` round-trip, and `job.cost` presence on `GET /v1/ai-import/jobs*` and the terminal `succeeded` SSE frame.
- [x] 4.4 Regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`) and bump crate versions/changelogs in lockstep (`core → infra → api`).

## 5. Flutter AI Config and Import Workflow Cost Surfaces (`frontend-flutter/`)

- [x] 5.1 Regenerate Flutter API DTOs/models for `LlmProvider` (`gemini`), `ModelInfo.pricing`, `AiConfigView.costDisplayPreference`, and `AiImportJob.cost` / telemetry.
- [x] 5.2 Update the Flutter AI configuration screen (`flutter-ai-config`) to display formatted token and energy price signals next to each model in the picker (rendering localized `"Unbekannt"` / `"Unknown"` when `pricing == null`, never `0`) and add the `cost_display_preference` (`token` vs `energy`) selector.
- [x] 5.3 Update the Flutter AI import jobs list and job status/detail screen (`flutter-ai-import-workflow`) to render compact and detailed cost breakdowns (switching primary display according to `cost_display_preference`, showing both token and energy breakdowns when present, and rendering `"Unbekannt"` / `"Unknown"` for `status == "unknown"`), including widget and golden tests.
