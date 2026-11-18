<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 794 — Tasks

## 1. Core: retain the per-call usage and price energy per request

- [x] 1.1 `core/ai/ports.rs`: `UsageAccumulator` gains
      `per_call: Vec<LlmCallUsage>` (`#[serde(default)]`), written only by
      `record()` so the ledger and the summed counters cannot drift; the type
      loses `Copy`.
- [x] 1.2 `core/ai/ports.rs`: `UsageAccumulator::priced_calls()` returns the
      ledger, or the aggregate as a single request when no ledger exists
      (hand-built value / pre-#794 payload) — never an empty slice and never a
      fabricated zero.
- [x] 1.3 `core/ai/cost.rs`: `capped_energy` prices every request separately
      (`Σ_calls min(raw_i, token_i)`, plus the matching `Σ raw_i` and "any request
      capped") and `aggregate_usage` sums the same slice, so token and energy
      figures can never describe different request sets.
- [x] 1.4 `core/ai/cost.rs`: `cost_breakdown(extraction: &[LlmCallUsage], …)` and
      `decision_cost_breakdown(…, usage: &[LlmCallUsage], …)` take the per-call
      slice instead of four scalars; `token_cost.total_nano` stays the aggregate
      figure (documented decision).
- [x] 1.5 `core/ai/views.rs`: `EnergyCostBreakdown` and
      `DecisionCostBreakdown::energy_cost_nano` documented as per-request sums;
      `capped_by_token_cost` = "any request was reduced".

## 2. Infra: thread the ledgers through both workers

- [x] 2.1 `infra/ai/workers.rs`: the extraction accumulator is a
      `UsageAccumulator` (script + schedule worker) fed through `record()`;
      telemetry keeps reading the summed `.usage` counters.
- [x] 2.2 `infra/ai/workers.rs`: `DecisionUsage` carries the Decision-Model
      accumulator and `compute_cost_snapshot` prices both components from
      `priced_calls()`.

## 3. Docs, spec, versions

- [x] 3.1 OpenSpec delta for `ai-import` (MODIFIED: the per-import immutable cost
      snapshot requirement — per-request cap semantics + the multi-request
      scenario).
- [x] 3.2 `768-decision-cost-split` task 7.3 marked done (it deferred this work
      here).
- [x] 3.3 `backend/CHANGELOG.md` `[Unreleased]` entry naming the version bumps
      (`core 0.52.0 → 0.53.0`, `infra 0.61.0 → 0.62.0`, `api 0.51.0 → 0.52.0`).
- [x] 3.4 `backend/openapi.yaml` regenerated (descriptions only — the wire shape
      is unchanged).
- [x] 3.5 `frontend-flutter/vendor/breakdown_api/` regenerated via
      `scripts/regen-client.sh` (doc comments only — no Dart code, no
      `pubspec.lock` change; a second run is byte-identical, which is what the
      `openapi-client-drift` CI job asserts).

## 4. Verification

- [x] 4.1 `cargo test -p breakdown_core ai::cost` and
      `cargo test -p breakdown_core` (641 tests).
- [x] 4.2 `cargo test -p infra --lib` (479 tests), including the worker-level
      two-chunk case where the cap binds on one request only.
- [x] 4.3 `cargo test -p api --test handlers_ai` (98 tests) and
      `cargo test -p api --test contract openapi_drift`.
- [x] 4.4 `cargo clippy --workspace --all-targets -- -D warnings` and
      `cargo fmt --all -- --check`.
