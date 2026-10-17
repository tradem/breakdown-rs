<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Proposal: Per-import AI cost transparency — model pricing read model, dual token/energy tracking, and Google Gemini curation (issue #675)

## Why

Users currently have no cost visibility when configuring an AI provider/model or after running a script or schedule import: model pickers omit pricing signals, LLM adapters discard token and energy usage fields from provider responses (persisting `tokens_in = 0, tokens_out = 0`), and `AiImportJob` does not expose cost breakdowns or telemetry on the wire. Adding end-to-end cost transparency — before the first import (at model selection) and per import (as an immutable completion snapshot over REST and SSE #664) — lets operators and costume-department users make informed provider/model choices (including energy-based billing on Neuralwatt and multimodal/image pricing for #673).

## What Changes

- **Add Google Gemini (`LlmProvider::Gemini`, key `"gemini"`, alias `"google"`)** as the 8th curated provider (`https://generativelanguage.googleapis.com/v1beta/openai`), refresh the curated assistant model lists (`curated_model_ids`) across all providers against live catalogs while keeping legacy model IDs in the validation allowlist, and introduce curated image-generation model lists (`curated_image_model_ids`) preparing for #673.
- **Introduce the `ai_import.ai_model_pricing` PostgreSQL read model and `AiPricingRefreshWorker`**: seeded by SQL migration (`pricing_source = 'curated_seed'`) for offline/deterministic startup and periodically refreshed in the background (at boot and on a configurable interval, guarded by a Postgres advisory lock) via `UPSERT` from public provider catalogs (`api.neuralwatt.com/v1/models`, `openrouter.ai/api/v1/models`, `api.eurouter.ai/api/v1/models`, and `models.dev/api.json` for OpenAI, Google Gemini, OpenCode, OpenCode-Go, and rotated-model fallbacks).
- **Enrich `ModelInfo` on `GET /v1/ai-import/providers/{provider}/models`** with optional `pricing: Option<ModelPricing>` carrying integer nano-currency rates per 1M tokens (`input_nano_per_million`, `output_nano_per_million`, `cached_input_nano_per_million`), optional energy rates (`energy_nano_per_kwh`, `energy_capped_by_token`), optional image rates (`image_output_nano_per_million`, `image_nano_per_unit`), `currency` (`USD` | `EUR`), `pricing_source`, and `price_as_of`.
- **Persist user cost-display preference (`CostDisplayPreference`: `token` | `energy`) on the `AiConfig` aggregate** (commands `CreateAiConfig` / `UpdateAiConfig`, `AiConfigEvent` with `#[serde(default)]` replay compatibility, `ai_import.projection_ai_config`, and `AiConfigView`).
- **Capture real token and energy telemetry from LLM calls**: extend `OpenAiCompatibleChatClient` and `OllamaChatClient` to parse token usage (`prompt_tokens`, `completion_tokens`, `cached_tokens` / `prompt_eval_count`, `eval_count`) and hardware energy telemetry (`energy.energy_joules`, `energy.energy_kwh` on Neuralwatt), accumulating usage across all chunks and bounded truncation/parse retries and persisting them via `record_worker_telemetry`.
- **Compute and persist an immutable `CostBreakdown` snapshot (`cost jsonb`) on `ai_import.ai_import_job` at job completion**: using integer nano-units ($10^{-9}$ of the currency unit, `i64` with `i128` intermediate math, zero floats), tracking **both** `token_cost` and `energy_cost` (including Neuralwatt's surge-protection cap `min(raw_energy_nano, token_total_nano)`) plus an extensible `image_cost` slot for #673, and distinguishing `CostStatus::Known`, `CostStatus::Unknown` (e.g. Ollama or unpriced custom models — never rendered as `0`), and `CostStatus::NotApplicable` (native CSV schedule imports).
- **Expose job telemetry and `cost: Option<CostBreakdown>` on `AiImportJob`** across `GET /v1/ai-import/jobs`, `GET /v1/ai-import/jobs/{id}`, and the terminal `succeeded` snapshot frame of `GET /v1/ai-import/jobs/{id}/events` (SSE #664).
- **Update Flutter AI configuration and import workflow surfaces**: render token/energy/image price signals next to models in the AI config picker, add the `cost_display_preference` selector on AI config, and render compact and detailed cost breakdowns (honoring the user's `cost_display_preference` when both token and energy costs are present, and showing localized `"Unbekannt"` / `"Unknown"` when `status == "unknown"`) in the jobs list and job status/detail screens.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `ai-import`: Add `LlmProvider::Gemini` and refreshed curated model catalogs; add `ai_import.ai_model_pricing` read model and periodic `AiPricingRefreshWorker`; add `CostDisplayPreference` to `AiConfig`; capture real LLM token and energy usage across chunks/retries; persist immutable `CostBreakdown` snapshots in integer nano-units on `ai_import_job`; expose `pricing` on `ModelInfo` and `telemetry`/`cost` on `AiImportJob` (REST + SSE).
- `flutter-ai-config`: Display model pricing signals (input/output token price, energy kWh price where offered, and `"Unknown"` for unpriced/local models) in the model picker and manage `cost_display_preference` (`token` vs `energy`) on the AI configuration form.
- `flutter-ai-import-workflow`: Display per-import cost in the jobs list (compact) and job detail/status screen (full breakdown of tokens in/out, energy consumption, model, price snapshot timestamp, and total), switching primary display between token and energy cost according to the user's `AiConfig.cost_display_preference` and never displaying `0` for `unknown` pricing.

## Impact

- **Backend Core (`crates/core/src/ai`)**: `LlmProvider::Gemini`, `CURATED_PROVIDERS`, `CostDisplayPreference` on `AiConfig` / commands / events / `AiConfigView`, `ModelPricing` on `ModelInfo`, `LlmCallUsage` / `EnergyTelemetry` on `LlmClient` responses, `CostBreakdown` / `CostStatus` / `TokenCostBreakdown` / `EnergyCostBreakdown` / `ImageCostBreakdown` on `AiImportJob` and `Telemetry`.
- **Backend Infra (`crates/infra/src/ai`, migrations, projectors)**: new migration seeding `ai_import.ai_model_pricing`, adding `cost_display_preference` to `ai_import.projection_ai_config`, and adding `cost jsonb` (plus energy telemetry) to `ai_import.ai_import_job`; new `AiPricingRefreshWorker` and `PgAiModelPricingRepository`; updated `provider_registry.rs`, `client.rs`, `ollama.rs`, `workers.rs`, and `queue.rs`.
- **Backend API (`crates/api`) & Contract (`backend/openapi.yaml`)**: `GET /v1/ai-import/providers/{provider}/models` enriches `ModelInfo` from `AiModelPricingRepository`; `POST/PATCH/GET /v1/ai-import/config` round-trip `cost_display_preference`; `GET /v1/ai-import/jobs*` and SSE `/events` serialize `cost` and telemetry on `AiImportJob`; regenerated `openapi.yaml`.
- **Flutter Client (`frontend-flutter/`)**: generated API client/DTO regeneration, AI config screen model-picker price labels and `cost_display_preference` toggle, AI import job list and job detail/status cost cards and localization keys (`app_de.arb` / `app_en.arb`).
