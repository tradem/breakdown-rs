<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Design: Per-import AI cost transparency (issue #675)

## Context

Issue #675 introduces end-to-end AI import cost transparency:
1. **Before an import (at AI configuration / model selection time):** operators see the input/output token rates, optional energy-consumption pricing (Neuralwatt kWh billing), and image generation rates (#673 preparation) next to each curated model, and can persist their preferred primary cost display mode (`token` vs `energy`) on `AiConfig`.
2. **Per import (in the jobs list, job detail/status screen, and SSE stream #664):** users see what each import job actually cost, computed from recorded token/energy telemetry and the price snapshot active at completion time.

During the explore phase, live inspection of the codebase and the public catalogs of all curated providers surfaced three foundational facts:
- **Telemetry gap in current LLM adapters:** `ai_import.ai_import_job` already has `provider`, `model`, `tokens_in`, `tokens_out`, and `latency_total_ms` columns, and `AiImportQueue::record_worker_telemetry` writes them. However, `OpenAiCompatibleChatClient` and `OllamaChatClient` currently discard `usage` (`prompt_tokens`, `completion_tokens`) and `energy` (`energy_joules`, `energy_kwh`) from provider responses, and `ScriptImportWorker` / `ScheduleImportWorker` hardcode `tokens_in: 0, tokens_out: 0`. Furthermore, `PgAiImportQueue::get` / `list_for_user` do not project those columns onto the wire `AiImportJob` DTO.
- **Provider pricing catalog landscape:**
  - `Neuralwatt` (`https://api.neuralwatt.com/v1/models`), `OpenRouter` (`https://openrouter.ai/api/v1/models`), and `EURouter` (`https://api.eurouter.ai/api/v1/models`) expose live pricing directly on their public (unauthenticated) `/models` endpoints.
  - `OpenAI`, `OpenCode`, `OpenCodeGo`, and `Google Gemini` do **not** return pricing on their `/v1/models` endpoints, but all four are covered with structured per-1M-token and multimodal pricing in the public **`https://models.dev/api.json`** catalog (`openai`, `google`, `opencode`, `opencode-go`, plus `neuralwatt` and `openrouter` fallback entries).
- **Google Gemini & Image Diffusion (#673):** Google provides an official OpenAI-compatible endpoint (`https://generativelanguage.googleapis.com/v1beta/openai`) supporting both text/extraction (`gemini-3.6-flash`, `gemini-3.5-flash-lite`, `gemini-3.1-pro-preview`, `gemini-2.5-flash`, `gemini-2.5-pro`) and image generation (*Nano Banana*: `gemini-3.1-flash-image`, `gemini-3.1-flash-lite-image`, `gemini-3-pro-image`, `gemini-2.5-flash-image`), where 1 standard 1024×1024 image consumes 1,290 image-output tokens.

## Goals / Non-Goals

**Goals:**
- Add `LlmProvider::Gemini` (`"gemini"`, alias `"google"`) as the 8th curated provider and update curated assistant and image model registries across all providers while keeping legacy model IDs in the validation allowlist.
- Maintain fresh model pricing in a PostgreSQL read model (`ai_import.ai_model_pricing`) seeded by SQL migration and periodically updated via `UPSERT` by a background worker (`AiPricingRefreshWorker`).
- Use exact integer money math in **nano-currency units** ($10^{-9}$ of the currency unit, `i64` with `i128` intermediate products) with explicit currency (`USD` | `EUR`) — zero floating-point arithmetic in cost calculations.
- Always track and persist **both** token cost and energy cost (when the provider supplies hardware energy telemetry, e.g. Neuralwatt) in an immutable `CostBreakdown` snapshot on `ai_import.ai_import_job` at completion time.
- Persist the user's primary display preference (`CostDisplayPreference`: `token` | `energy`) on the event-sourced `AiConfig` aggregate.
- Explicitly represent unknown prices (`CostStatus::Unknown`, e.g. Ollama) and non-LLM imports (`CostStatus::NotApplicable`, native CSV schedules) so the UI never displays a misleading `0` for unpriced models.

**Non-Goals:**
- Multi-user or period-based cost aggregation dashboards and budget hard-caps/alerts (explicitly deferred per issue #675).
- Executing image-generation jobs (#673) — this change only establishes the curated provider/model entries, pricing read-model columns (`image_output_nano_per_million`, `image_nano_per_unit`), and `ImageCostBreakdown` schema variant so #673 slots in without a schema migration.
- Currency conversion between `USD` and `EUR` — costs and rates are stored and displayed in the native currency reported by the provider catalog for that model.

## Decisions

### D1: Hybrid Price Data Source — Seeded PostgreSQL Read Model (`ai_import.ai_model_pricing`) + Periodic `AiPricingRefreshWorker`

**Decision:** Store model pricing in `ai_import.ai_model_pricing`, seeded in the migration with baseline prices (`pricing_source = 'curated_seed'`) for all curated models, and refreshed in the background by `AiPricingRefreshWorker` (once after startup without blocking boot, then every `AI_PRICING_REFRESH_INTERVAL_SECS`, default `21600` = 6 hours, guarded by a Postgres session advisory lock).

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│  [SQL Migration: seeds curated baseline prices (`pricing_source = 'curated_seed'`)]│
│                         │                                                          │
│                         ▼                                                          │
│  [AiPricingRefreshWorker] (boot + 6h interval, pg_try_advisory_lock)               │
│     ├── GET https://api.neuralwatt.com/v1/models   (primary for Neuralwatt)        │
│     ├── GET https://openrouter.ai/api/v1/models    (primary for OpenRouter)        │
│     ├── GET https://api.eurouter.ai/api/v1/models  (primary for EURouter)          │
│     └── GET https://models.dev/api.json            (primary for OpenAI, Gemini,    │
│                                                     OpenCode, OpenCodeGo;          │
│                                                     fallback for rotated models)   │
│                         │                                                          │
│                         ▼  UPSERT (never deletes rows missing from live feed)      │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │ Postgres ReadModel: `ai_import.ai_model_pricing`                             │  │
│  └──────────────────────┬───────────────────────────────────────┬───────────────┘  │
│                         │ (< 1 ms local query)                  │ (< 1 ms)         │
│                         ▼                                       ▼                  │
│        GET /v1/ai-import/providers/{p}/models          Script/ScheduleWorker       │
│        (enriches `ModelInfo.pricing`)                  computes `CostBreakdown`    │
│                                                        snapshot before succeeded   │
└────────────────────────────────────────────────────────────────────────────────────┘
```

**Rationale & Alternatives Considered:**
- *Alternative rejected — Ad-hoc live fetch per request/job:* `models.dev/api.json` is ~1.6 MB and `openrouter.ai/api/v1/models` is ~800 KB. Fetching them synchronously on `GET /v1/ai-import/providers/{provider}/models` or inside `ScriptImportWorker` at job completion adds multi-second latency, couples job completion to third-party catalog uptime, and fails in offline/air-gapped dev or integration test environments.
- *Alternative rejected — Static compile-time table only:* Provider prices and model slugs evolve between releases.
- *Why UPSERT-only (never delete on refresh):* Live checks showed providers rotate models out of `/v1/models` (e.g. Neuralwatt rotating `glm-5.2*` while existing `AiConfig`s may still reference them). Keeping seeded/prior rows via `ON CONFLICT (provider, model) DO UPDATE` preserves the last known price and its `price_as_of` timestamp.
- *Transport security (ADR-024 / issue #170 / issue #521):* All four public HTTPS catalog endpoints are fetched through `build_hosted_client_with_user_agent` (HTTPS-only, public-IP DNS resolution + pinning, no cross-host redirects, descriptive `User-Agent`, bounded response body size, no credentials sent).

### D2: Integer Money Math in Nano-Currency Units ($10^{-9}$)

**Decision:** Represent all monetary rates and computed costs as signed 64-bit integers (`i64`) in **nano-units** ($10^{-9}$ of the currency major unit: `1_000_000_000 = $1.00 USD` or `€1.00 EUR`), with `Currency` (`USD` | `EUR`).
- Token rates in `ai_model_pricing` and `ModelPricing` are stored as **nano-units per 1,000,000 tokens** (`input_nano_per_million`, `output_nano_per_million`, `cached_input_nano_per_million`, `image_output_nano_per_million`).
  - Example: `$1.45 / 1M tokens` = `1_450_000_000` nano-USD per million tokens (`1_450` nano-USD per single token).
  - Example: `$0.2925 / 1M tokens` (Neuralwatt flex) = `292_500_000` nano-USD per million tokens (`292.5` nano-USD per token).
  - Example: `$0.003625 / 1M tokens` (`mimo-v2.6-pro` cache read) = `3_625_000` nano-USD per million tokens.
- Per-job token cost is computed using `i128` intermediate integer arithmetic with half-up rounding to the nearest nano-unit:
  $$\text{cost\_nano} = \left\lfloor \frac{\text{tokens} \times \text{rate\_nano\_per\_million} + 500\,000}{1\,000\,000} \right\rfloor$$
- Catalog parser conversion from JSON decimal strings/numbers (e.g. `"0.0000002925"` per token or `0.2925` per 1M tokens) parses the decimal representation deterministically without floating-point drift.

**Rationale:** Standard cents ($10^{-2}$) round typical single-import costs (`$0.0005` – `$0.008`) down to `0`, violating the requirement that non-free imports never display `0`. Nano-units ($10^{-9}$) give 7 sub-cent decimal places while fitting up to $\approx \$9.22 \times 10^9$ in a standard Postgres `BIGINT` (`i64`).

### D3: Dual Tracking of Token and Energy Costs + `CostDisplayPreference` on `AiConfig`

**Decision:**
1. **Worker & LLM Clients:** Whenever an LLM response includes token usage (`usage`) and/or energy telemetry (`energy` on Neuralwatt), the client returns both in a structured `LlmCallOutcome<T>` (`output: T, usage: LlmCallUsage`), and the worker accumulates `tokens_in`, `tokens_out`, `cached_tokens_in`, and `energy_millijoules` across all chunks and bounded truncation/parse retries.
2. **Dual Snapshot on `AiImportJob`:** At job completion, if pricing is known for `(provider, model)`, `CostBreakdown` records:
   - `token_cost: Option<TokenCostBreakdown>` (computed from uncached/cached input tokens and output tokens).
   - `energy_cost: Option<EnergyCostBreakdown>` (computed when `energy_millijoules > 0` and `energy_nano_per_kwh` is present: $\text{raw\_energy\_nano} = \lfloor (\text{energy\_millijoules} \times \text{rate\_nano\_per\_kwh} + 1.8 \times 10^9) / (3.6 \times 10^9) \rfloor$ since $1\text{ kWh} = 3.6 \times 10^9\text{ mJ}$, plus `effective_capped_nano = min(raw_energy_nano, token_cost.total_nano)` and `capped_by_token_cost: bool` per Neuralwatt's surge-protection cap).
   - `image_cost: Option<ImageCostBreakdown>` (extensible slot for #673, `None` for script/schedule text imports).
3. **Display Preference on `AiConfig`:** `AiConfig` carries `cost_display_preference: CostDisplayPreference` (`Token` default | `Energy`). Because both `token_cost` and `energy_cost` are persisted on every Neuralwatt job, toggling `cost_display_preference` in `AiConfig` immediately switches the primary cost badge across both historical and future jobs without recalculation.

### D4: Honest Unknown and Not-Applicable Semantics

**Decision:** `CostBreakdown` carries an explicit discriminator `status: CostStatus`:
- `known`: pricing was found in `ai_model_pricing` (or reported by the provider); `currency`, `price_as_of`, and cost breakdown structs are populated.
- `unknown`: the job invoked an LLM whose `(provider, model)` has no pricing entry (e.g. `LlmProvider::Ollama` or an unpriced custom model). Rate and total fields are `None` — never `0` — and the UI renders localized `"Unbekannt"` / `"Unknown"`.
- `not_applicable`: the job did not invoke an LLM at all (e.g. native CSV schedule import or deterministic schedule merge).

### D5: Curated Provider & Model Refresh + Google Gemini (`LlmProvider::Gemini`)

**Decision:**
- Add `LlmProvider::Gemini` (`as_str() == "gemini"`, alias `"google"`, curated base URL `"https://generativelanguage.googleapis.com/v1beta/openai"`) to `CURATED_PROVIDERS` (now 8 providers).
- Refresh `curated_model_ids(provider)` across all 8 providers to include current live models (`deepseek-v4.1-flash`, `glm-5.3-flash`, `mimo-v2.6-pro`, `gemini-3.6-flash`, `nvidia/nemotron-3.5-lightning:free`, `mistral-small-4`, etc.) while keeping legacy model IDs (`glm-5.2*`, `kimi-k2.7-code*`, `mistral-small-3.1`, `nvidia/nemotron-3-nano:free`) in `OpenAiCompatibleModelCatalog::default_allowlist()` and the pricing seed migration so existing persisted `AiConfig` records remain valid.
- Add `curated_image_model_ids(provider)` in `provider_registry.rs` (including Google Gemini *Nano Banana* `gemini-3.1-flash-image`, `gemini-3.1-flash-lite-image`, `gemini-3-pro-image`, `gemini-2.5-flash-image` and OpenAI `gpt-image-2`, `gpt-image-1`) and seed their pricing in `ai_model_pricing` so #673 can consume them directly.

### D6: Wire Contract on `ModelInfo` and `AiImportJob` (REST + SSE #664)

**Decision:**
- `GET /v1/ai-import/providers/{provider}/models` queries `AiModelPricingRepository::list_for_provider(provider)` and attaches `pricing: Option<ModelPricing>` to each `ModelInfo` (`None` when unknown, e.g. Ollama).
- `AiImportJob` exposes additive `#[serde(default)]` fields:
  - `telemetry: Option<JobTelemetrySummary>` (or flattened `provider`, `model`, `tokens_in`, `tokens_out`, `cached_tokens_in`, `energy_millijoules`, `latency_total_ms`) populated once the worker records telemetry.
  - `cost: Option<CostBreakdown>` populated alongside `record_worker_telemetry` before `mark_succeeded`.
- Because `record_worker_telemetry` (with `cost`) runs immediately before `mark_succeeded`, the terminal `succeeded` SSE frame emitted by `GET /v1/ai-import/jobs/{id}/events` (#664) automatically carries the complete `telemetry` and `cost` snapshot with zero extra SSE event types or round-trips.

## Risks / Trade-offs

- **[Risk] Upstream catalog schema drift or outage on `models.dev` / provider `/models` endpoints** → **Mitigation:** Each source is fetched and parsed independently with tolerant serde structs; a failure on one source logs a `tracing::warn!` without aborting sibling sources, and the migration-seeded rows in `ai_import.ai_model_pricing` remain intact with their `price_as_of` timestamps.
- **[Risk] Existing `AiConfig` events in SierraDB predate `cost_display_preference`** → **Mitigation:** `#[serde(default)]` on `AiConfigEvent::Created` and `AiConfigEvent::Updated` defaults to `CostDisplayPreference::Token` on replay; `AiConfigProjector` does not write to `projection_audit`, so event-key hashes are unaffected.
- **[Risk] Existing `AiConfig` rows reference rotated model IDs (e.g. `glm-5.2`)** → **Mitigation:** `default_allowlist()` and the `ai_model_pricing` seed migration retain all previously curated model IDs alongside the newly added live IDs.

## Migration Plan

1. Add a reversible SQL migration creating `ai_import.ai_model_pricing` (with seeded baseline rows for all curated assistant and image models), adding `cost_display_preference TEXT NOT NULL DEFAULT 'token'` to `ai_import.projection_ai_config`, and adding `cached_tokens_in BIGINT NOT NULL DEFAULT 0`, `energy_millijoules BIGINT`, and `cost JSONB` to `ai_import.ai_import_job`.
2. Deploy backend and regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`).
3. Regenerate Flutter API client DTOs and ship the AI config and job cost UI surfaces.

## Open Questions

None — all open questions from issue #675 were resolved during the explore session.
