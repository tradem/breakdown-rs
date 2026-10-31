<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import Delta (794-per-request-energy-cap)

## MODIFIED Requirements

### Requirement: Per-import immutable cost breakdown snapshot in integer nano-units

At job completion (immediately before `mark_succeeded`), the import worker
SHALL compute an immutable `CostBreakdown` snapshot from the job's accumulated
telemetry and the current `ai_import.ai_model_pricing` rows and persist it in
`ai_import.ai_import_job.cost` (`JSONB`). All cost math SHALL use integer
arithmetic (`i64` / `i128`, no floats).

Usage SHALL be accumulated **per component and per request**: each component
keeps the individual `LlmCallUsage` of every billable provider request (bounded
by the job's request budget) alongside the summed counters, because a provider
may price or cap a request on its own. The summed counters remain the telemetry
figures.

Energy SHALL be capped **per request**, never on the component's or the job's
sums: when the pricing row sets `energy_capped_by_token`, a component's
`energy` figure SHALL be `Σ_calls min(raw_energy_nano_i, token_cost_nano_i)`,
where request *i*'s token cost is priced from the same rate card. Capping the
sums instead (`min(Σ raw_i, Σ token_i)`) is only an upper bound
(`Σ min(a_i, b_i) <= min(Σ a_i, Σ b_i)`) and SHALL NOT be reported. The reported
`raw_energy_nano` SHALL be the matching sum of the per-request uncapped figures,
so `effective_capped_nano <= raw_energy_nano` holds, and `capped_by_token_cost`
SHALL be true iff at least one request was reduced.

Token cost SHALL be priced **once over the component's summed tokens** (not per
request): the per-request split is confined to the energy cap, so a job's token
figure does not change with how its requests were divided.

`CostBreakdown` SHALL carry:
- `status: CostStatus` (`"known"`, `"unknown"`, or `"not_applicable"`),
- `currency: Option<Currency>` (`"USD"` or `"EUR"` when `status == "known"`),
- `price_as_of: Option<DateTime<Utc>>`,
- `pricing_source: Option<PricingSource>`,
- `token_cost: Option<TokenCostBreakdown>` (`tokens_in`, `tokens_out`, `cached_tokens_in`, `input_rate_nano_per_million`, `output_rate_nano_per_million`, `cached_input_rate_nano_per_million`, `total_nano`) — the **extraction** component,
- `energy_cost: Option<EnergyCostBreakdown>` (populated when both hardware energy telemetry and `energy_nano_per_kwh` exist: `energy_millijoules`, `rate_nano_per_kwh`, `raw_energy_nano`, `effective_capped_nano`, `capped_by_token_cost`, the last three summed over the requests as described above) — the **extraction** component,
- `image_cost: Option<ImageCostBreakdown>` (kind-tagged extensibility slot for #673 per-image / image-token costs),
- `decision: Option<DecisionCostBreakdown>` — the **decision** component, present
  iff the job issued at least one Decision-Model call, carrying `provider`,
  `model`, `status` (`"known"` or `"unknown"`), that component's own
  `tokens_in` / `tokens_out` / `cached_tokens_in` / `energy_millijoules`, its own
  `currency` / `price_as_of` / `pricing_source` snapshot, its own
  `input_rate_nano_per_million` / `output_rate_nano_per_million` /
  `cached_input_rate_nano_per_million` / `energy_rate_nano_per_kwh`, and the
  priced `token_cost_nano` / `energy_cost_nano` (the latter capped per request,
  like the extraction component); and
- `total: CostTotal` (`status: CostTotalStatus`, `currency`, `total_nano`) — the
  figure the user pays, which SHALL only be a number when it is honest:
  `"known"` (every recorded component priced in one currency, `total_nano` is
  their sum), `"incomplete"` (a recorded component has no pricing row, so
  `total_nano` is `null` and the priced parts stay visible), `"mixed_currency"`
  (the components are priced in different currencies; no conversion exists per
  design D2, so `total_nano` is `null`), or `"unknown"` (nothing priced, and the
  `serde(default)` value for snapshots recorded before this field existed).

A missing pricing row for a component SHALL degrade **only that component** to
an explicit unknown — never `0`, never a substituted rate. The snapshot SHALL
be exposed on `AiImportJob` in `GET /v1/ai-import/jobs`,
`GET /v1/ai-import/jobs/{id}`, and the SSE `event: job` frames of
`GET /v1/ai-import/jobs/{id}/events`. Subsequent changes to
`ai_import.ai_model_pricing` SHALL NOT mutate the persisted `cost` snapshot of
already-completed jobs.

#### Scenario: Neuralwatt import records both token and energy cost snapshots
- **WHEN** a Neuralwatt script import completes with `tokens_in = 10000`, `tokens_out = 2000`, `energy_millijoules = 18000` (5 µkWh), and model pricing of `$1.45 / 1M` in, `$4.50 / 1M` out, `$10.00 / kWh` energy
- **THEN** the persisted `job.cost` has `status = "known"`, `token_cost.total_nano = 23500000` (`$0.0235`), `energy_cost.raw_energy_nano = 50000` (`$0.00005`) with `effective_capped_nano = 50000` and `capped_by_token_cost = false`
- **AND** the terminal `succeeded` SSE frame on `GET /v1/ai-import/jobs/{id}/events` includes `job.cost`

#### Scenario: A multi-request job sums the per-request caps, not the cap of the sums
- **WHEN** a Neuralwatt script import runs two extraction requests with `$10.00 / kWh` energy and `$1.45 / 1M` input tokens, where request 1 reports `10000` input tokens and `18000` mJ (`raw = 50000` nano, `token = 14500000` nano) and request 2 reports `1` input token and `18000` mJ (`raw = 50000` nano, `token = 1450` nano)
- **THEN** `job.cost.token_cost` holds the summed usage (`tokens_in = 10001`) and `total_nano = 14501450`, priced once over the sum
- **AND** `job.cost.energy_cost.raw_energy_nano = 100000` (the sum of both requests' uncapped figures)
- **AND** `job.cost.energy_cost.effective_capped_nano = 51450` — request 1 uncapped (`50000`), request 2 capped at its own token cost (`1450`)
- **AND** `job.cost.energy_cost.capped_by_token_cost` is `true`, even though capping the sums would have produced `min(100000, 14501450) = 100000` and claimed no cap at all

#### Scenario: The Decision-Model component is capped per request as well
- **WHEN** a job's Decision Model scores two chunks in two requests whose per-request energy exceeds the per-request token cost in one of them
- **THEN** `job.cost.decision.energy_cost_nano` is the sum of the two per-request caps
- **AND** `job.cost.decision.token_cost_nano` stays the figure of the component's summed tokens

#### Scenario: Ollama import records unknown cost status and never zero
- **WHEN** an Ollama script import completes with `tokens_in = 8000` and `tokens_out = 1500`
- **THEN** the persisted `job.cost` has `status = "unknown"`, `token_cost = null`, and `energy_cost = null`
- **AND** `total.status = "unknown"` and `total.total_nano = null`
- **AND** the job still records `tokens_in = 8000` and `tokens_out = 1500` in its telemetry

#### Scenario: Native CSV schedule import records not_applicable cost status
- **WHEN** a CSV schedule import completes via the native parser without invoking an LLM
- **THEN** the persisted `job.cost` has `status = "not_applicable"`
- **AND** `job.cost.decision = null`

#### Scenario: A Decision Model on its own rate card is priced with its own rates
- **WHEN** a script import extracts 10000 in / 2000 out tokens with model `a` at `$1.45 / 1M` in and `$4.50 / 1M` out, and its Decision Model `b` consumes 3000 in / 500 out tokens at `$0.2925 / 1M` in and `$1.17 / 1M` out
- **THEN** `job.cost.token_cost` carries **only** the extraction usage (`tokens_in = 10000`, `tokens_out = 2000`, `total_nano = 23500000`)
- **AND** `job.cost.decision` carries `provider`/`model` of `b` with `tokens_in = 3000`, `tokens_out = 500`, `status = "known"`, `input_rate_nano_per_million = 292500000`, and `token_cost_nano = 1462500`
- **AND** `job.cost.total.status = "known"` with `total_nano = 24962500` (the sum of both components, what the user pays)

#### Scenario: Unknown decision pricing degrades only the decision component
- **WHEN** a script import completes successfully with a priced extraction model and a Decision Model whose `(provider, model)` has no `ai_model_pricing` row
- **THEN** `job.cost.token_cost` and the snapshot `status` are unchanged (the extraction component is priced)
- **AND** `job.cost.decision.status = "unknown"` with `token_cost_nano = null`, `energy_cost_nano = null`, `currency = null`, and its recorded `tokens_in`/`tokens_out` still present
- **AND** `job.cost.total.status = "incomplete"` and `total.total_nano = null` — no partial sum is presented as the total and no extraction rate is substituted

#### Scenario: Components priced in different currencies are never summed
- **WHEN** a job's extraction model is priced in `USD` and its Decision Model in `EUR`
- **THEN** `job.cost.total.status = "mixed_currency"` and `total.total_nano = null`
- **AND** both components still carry their own `currency` and priced figures

#### Scenario: An old snapshot does not claim a total it does not carry
- **WHEN** a job whose `cost` JSONB was recorded before the `decision`/`total` fields existed is read
- **THEN** it deserializes with `decision = null` and `total.status = "unknown"`, `total.total_nano = null`
- **AND** the pre-existing `status`, `token_cost` and `energy_cost` fields keep their recorded values
