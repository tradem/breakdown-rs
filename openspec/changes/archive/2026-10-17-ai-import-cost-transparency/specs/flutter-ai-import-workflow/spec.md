<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## ADDED Requirements

### Requirement: Per-Import Cost Display in Jobs List and Job Detail
The Flutter AI import jobs list and job status/detail screens SHALL display
per-import cost information from `AiImportJob.cost` and `AiImportJob` telemetry
(including updates arriving via the terminal `succeeded` SSE frame on
`GET /v1/ai-import/jobs/{id}/events`):
- When `cost.status == "known"`:
  - **Compact view (jobs list):** renders the primary formatted total cost in
    `cost.currency`. If the user's `AiConfig.cost_display_preference` is
    `"energy"` and `cost.energy_cost` is present, the primary badge SHALL show
    `cost.energy_cost.effective_capped_nano`; otherwise it SHALL show
    `cost.token_cost.total_nano`.
  - **Detailed view (job status / detail screen):** renders the full breakdown:
    provider and model, `tokens_in` / `tokens_out` (and `cached_tokens_in` when
    non-zero), the snapshot rates and `price_as_of` timestamp, `token_cost`
    total, and — when `cost.energy_cost` is present — the energy consumption
    (`energy_millijoules` / Wh) and energy cost alongside the token cost, with
    the user's preferred metric highlighted as primary.
- When `cost.status == "unknown"`: both compact and detailed views SHALL render
  localized `"Unbekannt"` / `"Unknown"` copy (while still displaying recorded
  token counts in the detail view) and SHALL NEVER display `0` or `$0.00`.
- When `cost.status == "not_applicable"` (e.g. native CSV schedule import):
  the UI SHALL indicate that no AI model was billed (or omit the LLM cost badge)
  rather than displaying an unknown or zero LLM price.

#### Scenario: Jobs list and detail switch primary cost according to user preference
- **WHEN** a completed Neuralwatt job carries both `token_cost` (`$0.0235`) and `energy_cost` (`$0.00005`) and the user's `AiConfig.cost_display_preference` is `"energy"`
- **THEN** the jobs list compact badge displays the energy cost as the primary figure
- **AND** the job detail card displays both the energy breakdown and the token breakdown

#### Scenario: Unknown model price displays Unknown and never zero
- **WHEN** a completed job carries `cost.status == "unknown"` (e.g. an Ollama import)
- **THEN** both the jobs list and the job detail screen display localized `"Unbekannt"` / `"Unknown"` for the cost and never `0` or `$0.00`

#### Scenario: Final SSE frame populates cost breakdown on job completion
- **WHEN** the job status screen is watching a running job over SSE and receives the terminal `succeeded` frame containing `job.cost`
- **THEN** the screen immediately renders the completed job's cost breakdown without requiring an extra manual refresh
