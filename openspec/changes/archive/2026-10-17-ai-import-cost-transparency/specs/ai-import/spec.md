<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## MODIFIED Requirements

### Requirement: Curated LLM provider enum
The system SHALL expose a `LlmProvider` enum (`#[non_exhaustive]`) curating the
set of supported providers (OpenAI, Gemini, OpenRouter, EURouter, Neuralwatt, OpenCodeGo, OpenCode, Ollama). OpenRouter
and EURouter SHALL be modeled as separate providers with separate curated URLs
and credential bindings. Google Gemini (`LlmProvider::Gemini`, canonical key
`"gemini"`, alias `"google"`) SHALL use Google's official OpenAI-compatible
endpoint (`https://generativelanguage.googleapis.com/v1beta/openai`).
Each provider's `base_url` SHALL be hardcoded in infra; the API SHALL NOT
accept a user-supplied base URL for model-list or chat calls. Adding a
provider SHALL be an additive, non-breaking change. The provider registry SHALL
maintain curated assistant model lists (`curated_model_ids`) and curated image
generation model lists (`curated_image_model_ids`, preparing for #673), while
preserving previously curated legacy model IDs in the validation allowlist so
existing persisted `AiConfig` records remain valid across catalog refreshes.

#### Scenario: User selects a provider from a curated list
- **WHEN** the user configures an AI provider
- **THEN** the system presents only the curated `LlmProvider` variants (including `gemini`)
- **AND** rejects any user-supplied base URL

#### Scenario: Google alias resolves to Gemini provider
- **WHEN** a client requests `/v1/ai-import/providers/google/models` or `/v1/ai-import/providers/gemini/models`
- **THEN** both resolve to `LlmProvider::Gemini` and return the curated Gemini models

#### Scenario: Model catalog is curated per provider
- **WHEN** the system lists models for a selected provider
- **THEN** it returns the curated models for that provider (with `recommended: true` on the provider's default model)
- **AND** applies the curated allowlist (including legacy allowlisted model IDs) when validating configurations

### Requirement: Per-user AI configuration
Each user MAY persist an `AiConfig` selecting a curated provider, an assistant
model, an image model, one editable prompt template per document kind
(Script, Schedule), and a `cost_display_preference` (`CostDisplayPreference`:
`token` default or `energy`). Creating or mutating an AI config SHALL be gated by the
existing `has_active_credential_role` membership check. Prompt template text is
the ONLY user-editable schema-affecting input; the output structure is static.
Pre-existing `AiConfigCreated` and `AiConfigUpdated` events persisted before
`cost_display_preference` was introduced SHALL deserialize with
`CostDisplayPreference::Token` (`#[serde(default)]`).

#### Scenario: Only credential-role members may configure AI
- **WHEN** a user without an active credential role attempts to create an
  `AiConfig`
- **THEN** the system returns 403

#### Scenario: Prompt text is editable; output schema is not
- **WHEN** a user edits their script-import prompt template
- **THEN** the system persists the new prompt text
- **AND** the target `ScriptContext` struct shape is unchanged and
  compile-time-derived from Rust types

#### Scenario: Cost display preference round-trips and replays safely
- **WHEN** a user creates or updates an `AiConfig` with `cost_display_preference = "energy"`
- **THEN** `GET /v1/ai-import/config` and `GET /v1/ai-import/config/{id}` return `cost_display_preference = "energy"`
- **AND** historic `AiConfig` events without `cost_display_preference` replay as `"token"`

### Requirement: Telemetry is captured from day one
Every import job SHALL record `provider`, `model`, `doc_kind`, `chunk_count`,
`tokens_in`, `tokens_out`, `cached_tokens_in`, `energy_millijoules` (when
reported by the provider, e.g. Neuralwatt), `latency_total` and an apply state.
The LLM chat adapters (`OpenAiCompatibleChatClient` and `OllamaChatClient`)
SHALL extract token counts (`prompt_tokens`, `completion_tokens`,
`cached_tokens` / `prompt_eval_count`, `eval_count`) and hardware energy
telemetry (`energy.energy_joules` / `energy.energy_kwh`) from every provider
response and accumulate them across all chunks and bounded truncation or parse
retries of a job. Jobs that never
reach apply SHALL be recorded as `NotApplied` (`accept_as_is` NULL,
`edit_distance` NULL); jobs that
are applied SHALL record `accept_as_is: bool` (applied with zero edits) and
`edit_distance: u32` (content-free count of user resolutions/edits; never
script text — NDA). `accept_as_is` and `edit_distance` SHALL be captured at
apply time (the only moment they are observable) and SHALL NOT be backfillable.
Acceptance-rate and edit-rate calculations SHALL exclude `NotApplied` jobs.
Auto-apply is out of scope for v1.

#### Scenario: LLM worker accumulates real token and energy usage across chunks and retries
- **WHEN** a script import job runs two chunks where chunk 1 succeeds on the first call (`1000` in, `400` out, `5.0 J`) and chunk 2 truncates once (`800` in, `500` out, `4.0 J`) before succeeding on retry (`800` in, `900` out, `6.0 J`)
- **THEN** the worker records `tokens_in = 2600`, `tokens_out = 1800`, and `energy_millijoules = 15000` via `record_worker_telemetry`
- **AND** `GET /v1/ai-import/jobs/{id}` and `GET /v1/ai-import/jobs` expose the recorded telemetry on the `AiImportJob` view

#### Scenario: Apply records accept signal
- **WHEN** a user applies a preview without any edits or uncertainty resolutions
- **THEN** the job's `accept_as_is` is recorded as true and `edit_distance` as 0
- **AND** an applied zero-edit outcome is distinguishable from a never-applied
  job (which SHALL have `edit_distance` NULL)

#### Scenario: Never-applied job has no edit distance
- **WHEN** a job reaches preview but is never applied
- **THEN** its apply state is `NotApplied`
- **AND** its `edit_distance` is NULL

#### Scenario: Telemetry contains no script content
- **WHEN** the system records `edit_distance`
- **THEN** the recorded value is a count only
- **AND** no script text, costume description, or NDA-protected content is
  persisted in telemetry

## ADDED Requirements

### Requirement: Seeded model pricing read model and periodic background refresh
The system SHALL maintain model pricing in a PostgreSQL read-model table
`ai_import.ai_model_pricing` keyed by `(provider, model)`. All monetary rates
SHALL be stored as non-negative 64-bit integers (`BIGINT` / `i64`) in
**nano-currency units** ($10^{-9}$ of the currency unit: `1_000_000_000 = 1.00`
`USD` or `EUR`), carrying:
- `currency` (`"USD"` or `"EUR"`),
- `input_nano_per_million` and `output_nano_per_million` (nano-units per 1,000,000 tokens),
- optional `cached_input_nano_per_million`,
- optional `energy_nano_per_kwh` and `energy_capped_by_token` (for providers offering energy billing such as Neuralwatt at `$10.00 / kWh`),
- optional `image_output_nano_per_million` and `image_nano_per_unit` (for image generation models such as Google Gemini *Nano Banana* and OpenAI `gpt-image-*`),
- `pricing_source` (`"curated_seed"`, `"provider_live"`, or `"models_dev"`), and
- `price_as_of` (`TIMESTAMPTZ`).

A database migration SHALL seed `ai_import.ai_model_pricing` with baseline
rates (`pricing_source = 'curated_seed'`) for all curated hosted models so
offline and freshly booted deployments have deterministic pricing immediately.
When `AI_IMPORT_ENABLED` and `AI_PRICING_REFRESH_ENABLED` (default `true`) are
active, a background task (`AiPricingRefreshWorker`) SHALL run an initial
non-blocking refresh after startup and periodically every
`AI_PRICING_REFRESH_INTERVAL_SECS` (default `21600` = 6 hours, clamped to
`300..=604800`), coordinated across instances via `pg_try_advisory_lock`.
The refresh worker SHALL fetch public catalogs over the ADR-024 hardened
hosted HTTP client (`api.neuralwatt.com/v1/models`, `openrouter.ai/api/v1/models`,
`api.eurouter.ai/api/v1/models`, and `models.dev/api.json`) and `UPSERT` rows
without deleting pre-existing rows that were rotated out of a live feed.

#### Scenario: Fresh deployment has seeded pricing before any network refresh
- **WHEN** the backend starts with all external catalog endpoints unreachable
- **THEN** `ai_import.ai_model_pricing` still contains the migration-seeded rates with `pricing_source = "curated_seed"`
- **AND** `GET /v1/ai-import/providers/{provider}/models` returns those rates with their `price_as_of` timestamp

#### Scenario: Background refresh upserts live pricing and preserves rotated models
- **WHEN** `AiPricingRefreshWorker` completes a refresh cycle against a provider feed that updated `glm-5.3` pricing and omitted legacy `glm-5.2`
- **THEN** the `glm-5.3` row is updated with the new nano-rates, `pricing_source = "provider_live"`, and a fresh `price_as_of`
- **AND** the existing `glm-5.2` row remains in `ai_import.ai_model_pricing` untouched

#### Scenario: Partial upstream failure does not abort other pricing sources
- **WHEN** one upstream catalog endpoint returns HTTP 503 or times out during a refresh cycle
- **THEN** `AiPricingRefreshWorker` logs a warning for that source and still commits updates from the remaining healthy sources

### Requirement: Model catalog exposes pricing metadata and unknown-price honesty
`GET /v1/ai-import/providers/{provider}/models` SHALL enrich each returned
`ModelInfo` with `pricing: Option<ModelPricing>` read from
`ai_import.ai_model_pricing`. For providers or models without known pricing
(such as local `LlmProvider::Ollama` models), `pricing` SHALL be `null` (`None`)
— NEVER a fabricated zero-price object. Genuine free-tier hosted models (e.g.
`nvidia/nemotron-3.5-lightning:free` where the provider explicitly reports `0`
input and `0` output cost) SHALL carry `Some(ModelPricing)` with
`input_nano_per_million = 0` and `output_nano_per_million = 0`.

#### Scenario: Hosted model returns token and energy pricing metadata
- **WHEN** an authorized caller requests `GET /v1/ai-import/providers/neuralwatt/models`
- **THEN** each curated model carries `pricing` with `currency = "USD"`, `input_nano_per_million`, `output_nano_per_million`, `energy_nano_per_kwh = 10000000000`, `energy_capped_by_token = true`, and `price_as_of`

#### Scenario: Local Ollama model returns null pricing
- **WHEN** an authorized caller requests `GET /v1/ai-import/providers/ollama/models`
- **THEN** every returned `ModelInfo` has `pricing = null`

### Requirement: Per-import immutable cost breakdown snapshot in integer nano-units
At job completion (immediately before `mark_succeeded`), the import worker
SHALL compute an immutable `CostBreakdown` snapshot from the job's accumulated
telemetry and the current `ai_import.ai_model_pricing` row for `(provider, model)`
and persist it in `ai_import.ai_import_job.cost` (`JSONB`). All cost math SHALL
use integer arithmetic (`i64` / `i128`, no floats).

`CostBreakdown` SHALL carry:
- `status: CostStatus` (`"known"`, `"unknown"`, or `"not_applicable"`),
- `currency: Option<Currency>` (`"USD"` or `"EUR"` when `status == "known"`),
- `price_as_of: Option<DateTime<Utc>>`,
- `pricing_source: Option<PricingSource>`,
- `token_cost: Option<TokenCostBreakdown>` (`tokens_in`, `tokens_out`, `cached_tokens_in`, `input_rate_nano_per_million`, `output_rate_nano_per_million`, `cached_input_rate_nano_per_million`, `total_nano`),
- `energy_cost: Option<EnergyCostBreakdown>` (populated when both hardware energy telemetry and `energy_nano_per_kwh` exist: `energy_millijoules`, `rate_nano_per_kwh`, `raw_energy_nano`, `effective_capped_nano`, `capped_by_token_cost`), and
- `image_cost: Option<ImageCostBreakdown>` (kind-tagged extensibility slot for #673 per-image / image-token costs).

The snapshot SHALL be exposed on `AiImportJob` in `GET /v1/ai-import/jobs`,
`GET /v1/ai-import/jobs/{id}`, and the SSE `event: job` frames of
`GET /v1/ai-import/jobs/{id}/events`. Subsequent changes to
`ai_import.ai_model_pricing` SHALL NOT mutate the persisted `cost` snapshot of
already-completed jobs.

#### Scenario: Neuralwatt import records both token and energy cost snapshots
- **WHEN** a Neuralwatt script import completes with `tokens_in = 10000`, `tokens_out = 2000`, `energy_millijoules = 18000` (5 µkWh), and model pricing of `$1.45 / 1M` in, `$4.50 / 1M` out, `$10.00 / kWh` energy
- **THEN** the persisted `job.cost` has `status = "known"`, `token_cost.total_nano = 23500000` (`$0.0235`), and `energy_cost.raw_energy_nano = 50000` (`$0.00005`) with `effective_capped_nano = 50000` and `capped_by_token_cost = false`
- **AND** the terminal `succeeded` SSE frame on `GET /v1/ai-import/jobs/{id}/events` includes `job.cost`

#### Scenario: Ollama import records unknown cost status and never zero
- **WHEN** an Ollama script import completes with `tokens_in = 8000` and `tokens_out = 1500`
- **THEN** the persisted `job.cost` has `status = "unknown"`, `token_cost = null`, and `energy_cost = null`
- **AND** the job still records `tokens_in = 8000` and `tokens_out = 1500` in its telemetry

#### Scenario: Native CSV schedule import records not_applicable cost status
- **WHEN** a CSV schedule import completes via the native parser without invoking an LLM
- **THEN** the persisted `job.cost` has `status = "not_applicable"`
