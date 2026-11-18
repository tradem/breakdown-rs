<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 768 — Tasks

## 1. Core: the cost data model carries two components and an explicit total

- [x] 1.1 `core/ai/views.rs`: `DecisionCostBreakdown` (provider, model, status,
      the component's own usage counts, its own `currency` / `price_as_of` /
      `pricing_source` snapshot, its own rates, and the priced
      `token_cost_nano` / `energy_cost_nano`).
- [x] 1.2 `core/ai/views.rs`: `CostTotal` + `CostTotalStatus`
      (`known`, `incomplete`, `mixed_currency`, `unknown`); `unknown` is the
      `serde(default)` value so a pre-#768 snapshot never claims a total.
- [x] 1.3 `core/ai/views.rs`: `CostBreakdown` gains `decision: Option<…>`
      (skip-serializing when `None`) and `total: CostTotal`
      (`serde(default)`); `unknown()`/`not_applicable()` stay total-free.
- [x] 1.4 `core/ai/views.rs`: `token_cost` / `energy_cost` documented as the
      **extraction** component (field names unchanged, meaning now exact).
- [x] 1.5 `core/ai/mod.rs`: re-export the three new types.

## 2. Core: pure pricing of a second component and the total fold

- [x] 2.1 `core/ai/cost.rs`: `decision_cost_breakdown(provider, model, usage,
      pricing)` — prices the component from its **own** row; a `None` row
      degrades the component to `unknown` with its usage counts kept.
- [x] 2.2 `core/ai/cost.rs`: `cost_breakdown(…, pricing, decision)` folds the
      components into `CostTotal` — `known` only for one currency, `incomplete`
      when a recorded component is unpriced, `mixed_currency` when the rate
      cards disagree, `unknown` when nothing is priced.
- [x] 2.3 `core/ai/cost_tests.rs`: two-rate-card case asserting that the
      extraction component holds **only** extraction usage; missing
      decision-pricing case asserting an honest `unknown` component plus an
      `incomplete` total; `mixed_currency` case; saturation/`LlmCallUsage` split
      stays element-wise.

## 3. Infra: two accumulators, two pricing lookups

- [x] 3.1 `infra/ai/workers.rs`: `total_usage` → `extraction_usage` and a new
      `decision_usage` accumulator. The decision passes take
      `&mut UsageAccumulator` (usage counters **plus** a call count) so a 2xx
      answer that reports no usage is still a recorded Decision-Model call
      (review follow-up); the extraction side keeps the plain `LlmCallUsage`.
- [x] 3.2 `infra/ai/workers.rs`: script worker — chunk scoring and Pass-2
      continuity feed `decision_usage`; telemetry carries extraction counts.
- [x] 3.3 `infra/ai/workers.rs`: schedule worker — `score_schedule_rows` feeds
      `decision_usage`; native CSV keeps zero usage on both sides.
- [x] 3.4 `infra/ai/workers.rs`: `compute_cost_snapshot` takes the resolved
      decision identity + usage and looks the second pricing row up
      independently (an outage degrades only the decision component).
- [x] 3.5 No migration: the snapshot is JSONB, the fields are additive.
- [x] 3.6 `infra/ai` tests: the completion snapshot of a mixed-provider job
      carries two components and the summed total.

## 4. API + contract

- [x] 4.1 `api` fixtures updated for the additive fields.
- [x] 4.2 `backend/openapi.yaml` regenerated
      (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`).
- [x] 4.3 `vendor/breakdown_api/` regenerated via `scripts/regen-client.sh`
      (additive only; no widget change — the card layout is #761).

## 5. Docs, versions, changelog

- [x] 5.1 `backend/CHANGELOG.md` `[Unreleased]` entry naming the version bumps
      (`core 0.51.0 → 0.52.0`, `infra 0.60.0 → 0.61.0`, `api 0.50.0 → 0.51.0`).
- [x] 5.2 OpenSpec delta for `ai-import` (MODIFIED: the per-import immutable
      cost snapshot requirement).

## 6. Verification

- [x] 6.1 `cargo test -p core ai::cost` / `cargo test -p core`
- [x] 6.2 `cargo test -p infra`
- [x] 6.3 `cargo test -p api`
- [x] 6.4 `cargo clippy --workspace --all-targets -- -D warnings`
- [x] 6.5 `cargo fmt --all -- --check`
- [x] 6.6 Flutter: `flutter analyze`, `flutter test`

## 7. Review follow-ups (CodeRabbit, PR #792)

- [x] 7.1 An unpriced **extraction** with a priced decision component degrades
      the total to `incomplete` (`total_nano = null`) instead of presenting the
      decision figure as "the total" — `cost_breakdown_unpriced` records the
      extraction as present-but-unpriced; a job with no decision component keeps
      `unknown` (the Ollama scenario).
- [x] 7.2 The decision component is keyed on the **call count**, not on the
      usage counters (`UsageAccumulator`), so a call that reports no usage no
      longer disappears from the snapshot.
- [x] 7.3 Per-request energy cap (the Neuralwatt cap applies per request, not to
      the job aggregate) — **done in issue #794** / change
      `794-per-request-energy-cap`: `UsageAccumulator::per_call` retains the
      ledger and both components price energy as
      `Σ_calls min(raw_i, token_i)`.
