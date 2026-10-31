<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow Delta (761-cost-card-redesign)

## MODIFIED Requirements

### Requirement: Per-Import Cost Display in Jobs List and Job Detail
The Flutter AI import jobs list and job status/detail screens SHALL display
per-import cost information from `AiImportJob.cost`, `AiImportJob.telemetry` and
`AiImportJob.decision_telemetry` (including updates arriving via the terminal
`succeeded` SSE frame on `GET /v1/ai-import/jobs/{id}/events`), using the
integer nano-currency formatting of `cost_format.dart` only (no floating-point
math, and a non-zero amount SHALL NEVER render as `0`):

- **Detailed view (job status / detail screen)** SHALL render a card with a
  visible hierarchy rather than a flat list:
  - a **hero figure**, rendered large and with an ALWAYS-VISIBLE label that
    names what the figure is. The figure SHALL be the money the user pays:
    `cost.total.total_nano` when `cost.total.status == "known"`, otherwise
    `cost.token_cost.total_nano`. When the user's
    `AiConfig.cost_display_preference` is `"energy"` and `cost.energy_cost` is
    present, the hero SHALL instead show
    `cost.energy_cost.effective_capped_nano` (the capped value, never the raw
    one) under an energy label. The label SHALL change with the figure, so a
    component is never presented as the total.
  - the **effective model** (`telemetry.model`) and the **provider**
    (`telemetry.provider`) as two prominent, individually LABELLED elements that
    wrap in narrow layouts, ellipsize past two lines and expose the full value
    in a tooltip.
  - the remaining figures as icon-prefixed, visually subordinate detail rows:
    `tokens_in` / `tokens_out` (and `cached_tokens_in` when non-zero), the
    snapshot rates and `price_as_of` timestamp, the token cost, and — when
    `cost.energy_cost` is present — the energy consumption
    (`energy_millijoules` / Wh) and the energy cost, with the user's preferred
    component emphasised. No figure the detailed view rendered before MAY be
    dropped.
  - when `cost.decision` is present, that component's OWN `provider` / `model`,
    its own usage counts and its own priced figures (`token_cost_nano`,
    `energy_cost_nano` in the component's own `currency`), visually grouped
    apart from the extraction component; when it is present but not `"known"`,
    its usage counts SHALL still render and its price SHALL be stated as not
    priced — the extraction rate SHALL NEVER be substituted. When
    `cost.image_cost` is present, its total SHALL render, so a displayed total
    stays explainable by the rows around it.
- **A refused total** SHALL be rendered honestly: `cost.total.status`
  `"incomplete"` or `"mixed_currency"` SHALL render the priced component plus a
  localized note stating why no sum is shown (no rate substitution, and no
  currency conversion — design D2). `"unknown"`, or a snapshot that carries no
  total at all (every pre-#768 row), SHALL claim no total and SHALL render no
  note.
- **Compact view (jobs list):** SHALL render the primary formatted total in
  `cost.currency`, chosen exactly like the detailed hero (`energy_cost
  .effective_capped_nano` under the `"energy"` preference when present, the
  token total otherwise), with a metric icon that mirrors the same choice. The
  icon is reinforcement only: the visible `"Kosten: …"` text SHALL always be
  present, and the line SHALL NOT trigger any additional request (a cached row
  carries no cost and renders no line).
- When `cost.status == "unknown"`: both views SHALL render localized
  `"Unbekannt"` / `"Unknown"` copy (the detailed view as the hero VALUE, while
  still displaying the recorded token counts) and SHALL NEVER display `0` or
  `$0.00`.
- When `cost.status == "not_applicable"` (e.g. native CSV schedule import):
  the UI SHALL indicate that no AI model was billed (or omit the LLM cost badge)
  rather than displaying an unknown or zero LLM price.

#### Scenario: Jobs list and detail switch primary cost according to user preference
- **WHEN** a completed Neuralwatt job carries both `token_cost` (`$0.0235`) and `energy_cost` (`$0.00005`) and the user's `AiConfig.cost_display_preference` is `"energy"`
- **THEN** the jobs list compact line displays the energy cost as the primary figure and carries the energy metric icon
- **AND** the job detail card displays the energy figure as its labelled hero
- **AND** the job detail card displays both the energy breakdown and the token breakdown below it

#### Scenario: The detail card names the model and the provider
- **WHEN** a completed job carries `telemetry.model = "gpt-5.6-luna"` and `telemetry.provider = "neuralwatt"`
- **THEN** the detail card renders both as labelled identity elements next to the hero figure

#### Scenario: A published total is the hero figure
- **WHEN** a #768 job carries `cost.total.status = "known"` with `total_nano` and the preference is `"token"`
- **THEN** the hero figure is the formatted total, under a total label
- **AND** the token and energy component rows still render below it

#### Scenario: A total the server refuses is not invented client-side
- **WHEN** a job carries `cost.total.status = "incomplete"` (a recorded component is unpriced) or `"mixed_currency"`
- **THEN** the hero figure is the priced component under a component label
- **AND** a localized note states why no total is shown
- **AND** no rate is substituted and no currency is converted

#### Scenario: A pre-#768 snapshot claims no total
- **WHEN** a job's cost snapshot carries no `total` at all
- **THEN** the hero figure is the token component under a component label
- **AND** no "total unavailable" note is rendered (an absence is not an error)

#### Scenario: The Decision Model's own component is shown separately
- **WHEN** a job's `cost.decision` carries a different `provider` / `model` than the extraction telemetry
- **THEN** the card renders that pair with its own usage counts and its own priced figures in its own currency
- **AND** the extraction component's figures are unchanged

#### Scenario: An unpriced Decision component is never priced with the extraction rate
- **WHEN** `cost.decision.status` is `"unknown"` (no pricing row for that model)
- **THEN** its usage counts still render
- **AND** its price line states that the component is not priced
- **AND** neither `0` nor the extraction rate is rendered for it

#### Scenario: Unknown model price displays Unknown and never zero
- **WHEN** a completed job carries `cost.status == "unknown"` (e.g. an Ollama import)
- **THEN** both the jobs list and the job detail screen display localized `"Unbekannt"` / `"Unknown"` for the cost and never `0` or `$0.00`
- **AND** the detail card still renders the recorded token counts

#### Scenario: Nothing was billed
- **WHEN** a completed job carries `cost.status == "not_applicable"` (native CSV import)
- **THEN** the detail card states that no AI model was billed
- **AND** the jobs list renders no cost line

#### Scenario: A long model id holds in the compact layout
- **WHEN** the detail card renders a model id that does not fit the available width
- **THEN** its identity element wraps to at most two lines and ellipsizes, with the full value available in a tooltip
- **AND** the card does not overflow horizontally at the compact window width

#### Scenario: Final SSE frame populates cost breakdown on job completion
- **WHEN** the job status screen is watching a running job over SSE and receives the terminal `succeeded` frame containing `job.cost`
- **THEN** the screen immediately renders the completed job's cost breakdown without requiring an extra manual refresh
