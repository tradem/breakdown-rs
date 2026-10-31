<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 768 — Decision-Model token usage is priced with the Decision Model's own rate card

## Why

Issue #768: when a Decision Model **is** used, its tokens and energy are folded
into the extraction usage and costed at the **extraction** model's rates.

Verified in the tree before the fix:

- `ScriptImportWorker::process_text` accumulates **every** LLM call of a job into
  one `LlmCallUsage` (`crates/infra/src/ai/workers.rs`, `total_usage`): the
  extraction chunks, the per-chunk Decision-Model scoring
  (`decision_scoring::score_script_chunk(…, &mut total_usage)`) and the Pass-2
  outfit-continuity calls (`outfit_continuity::run_outfit_continuity_pass(…,
  &mut total_usage, …)`). The schedule worker does the same with
  `score_schedule_rows`.
- The completion snapshot is then built once, with the **extraction** identity
  only: `compute_cost_snapshot(self.pricing, self.provider, &self.model,
  &total_usage)` — and `cost_breakdown` looks `(provider, model)` up in
  `ai_import.ai_model_pricing`.
- The Decision Model is explicitly allowed to be a **different** provider/model
  than the extraction model (split billing, #722/#723 — e.g. extraction at
  provider A, scoring `clef-flash` at provider B). Those calls were therefore
  priced with the wrong rate card.

Consequence: with mixed providers the token **total** was right, the currency
total was **wrong** (too high or too low depending on the two rate cards), and
because the per-import cost card (#675) is sold as an exact, immutable
per-import snapshot, the wrong figure was frozen forever. There was no way to
split it after the fact either — the snapshot is immutable by design.

## What changes

1. **Decision usage is tracked separately.** The scoring pass and the Pass-2
   continuity pass accumulate into their own `decision_usage: LlmCallUsage`
   (`decision_scoring`/`outfit_continuity` keep their signature — the *caller*
   decides which accumulator a decision call feeds). The job's
   `Telemetry.tokens_in` / `tokens_out` / `cached_tokens_in` /
   `energy_millijoules` therefore describe the **extraction** component only.

2. **Both components are priced with their own rate card.** `CostBreakdown`
   gains an additive `decision: Option<DecisionCostBreakdown>` carrying the
   Decision Model's `provider`/`model`, its own usage counts, its own snapshot
   rates, `currency`, `price_as_of` and `pricing_source`, and the two priced
   figures (`token_cost_nano`, `energy_cost_nano`). The existing `token_cost`
   and `energy_cost` keep their field names and now mean exactly what they say:
   the extraction component.

3. **The hero figure becomes explicit.** Additive `total: CostTotal` with
   `status: known | incomplete | mixed_currency | unknown` and `total_nano`. The
   sum is only ever published when it is honest:
   - `known` — every recorded component is priced in **one** currency;
   - `incomplete` — a component is present but unpriced (no rate substitution,
     no partial sum presented as a total; the priced parts still render);
   - `mixed_currency` — the components are priced in different currencies, and
     design D2 forbids a conversion, so no sum is offered;
   - `unknown` — nothing was priced (also the `serde(default)` value for every
     snapshot recorded before this change, so an old row never *claims* a total
     it does not carry).

4. **Honest unknown, per component.** A missing pricing row for the decision
   model degrades **that component** to `status = unknown` with its usage counts
   intact — never `0`, never the extraction rate. The extraction component and
   the `CostStatus` of the snapshot are unaffected.

5. **No schema migration.** The snapshot is already persisted as JSONB
   (`ai_import.ai_import_job.cost`), so the additive fields ride along; old rows
   deserialize with `decision = null`, `total.status = "unknown"`.

6. **Deliberate non-changes (drift findings).** `Telemetry`/`JobTelemetrySummary`
   are **not** extended with a second `decision_provider`/`decision_model` pair,
   because issue #767 already ships them on the job
   (`AiImportJob.decision_telemetry: Option<DecisionTelemetry>` with `provider`,
   `model`, `outcome`, `failed_rows`, persisted in the `decision_telemetry`
   JSONB column). Duplicating the pair on the telemetry summary would create two
   sources of truth for one fact. The card *rendering* of the split belongs to
   #761 (roadmap PR-12, "reine Darstellung auf Basis von #768"); this change
   ships the data shape only — the Dart client is regenerated so #761 can build
   on it.

## Impact

- **Specs:** `ai-import` (MODIFIED: the per-import immutable cost snapshot
  requirement — the decision component, the per-component rate card, the
  explicit total statuses).
- **Backend:** `core` (`cost.rs`: `decision_cost_breakdown`, the total fold;
  `views.rs`: `DecisionCostBreakdown`, `CostTotal`, `CostTotalStatus`,
  `CostBreakdown.decision`/`.total`), `infra` (`workers.rs`: two accumulators,
  a second pricing lookup, both workers). Versions `core 0.51.0 → 0.52.0`,
  `infra 0.60.0 → 0.61.0`, `api 0.50.0 → 0.51.0`; `openapi.yaml` regenerated.
- **Frontend:** `vendor/breakdown_api/` regenerated (`CostBreakdown.decision`,
  `CostBreakdown.total`, new `DecisionCostBreakdown`/`CostTotal`/
  `CostTotalStatus` models). No widget change (#761).
- **Not changed:** the pricing read model and its refresh worker, the
  immutability contract of the snapshot, `CostStatus`, the extraction path's own
  behaviour, and the Decision Model configuration UI.
