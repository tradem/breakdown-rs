<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 794 — The energy cap applies per provider request, not to the job aggregate

## Why

Issue #794 (reported by CodeRabbit on PR #792): the Neuralwatt surge-protection
cap `energy_cost = min(raw_energy_cost, token_cost)` was applied **once** to the
job's accumulated figures, for both cost components:

- `core/ai/cost.rs::cost_breakdown` priced
  `cap_energy_by_token(raw_energy_nano(Σ mJ), token_cost_breakdown(Σ tokens))` — the
  extraction component;
- `core/ai/cost.rs::decision_cost_breakdown` did the same for the Decision-Model
  component (#768).

Neuralwatt caps each **request** on its own, so the billed figure is
`Σ_calls min(raw_energy_nano(mJ_i), token_cost_nano(tokens_i))`. Because
`Σ min(a_i, b_i) <= min(Σ a_i, Σ b_i)`, the aggregate cap can only ever
**overstate** the energy component — and with it `CostBreakdown::total`, the
figure the user is shown for an immutable, "exact" snapshot (#675).

The impact today is small (energy ≈ $10/kWh against token rates ≈ $1.45/1M, so
the cap practically never binds), but a cap that claims not to engage while the
provider did engage it is exactly the kind of quiet inaccuracy the snapshot
exists to prevent.

Why this was not a one-line fix: the cap needs each call's **token** cost, and
only the summed counters were retained. The job's usage is accumulated into one
`LlmCallUsage` per component, so the per-call figures were already gone by the
time the pricing row is resolved at job completion.

## What changes

1. **`UsageAccumulator` keeps the per-call ledger** (`core/ai/ports.rs`). A new
   `per_call: Vec<LlmCallUsage>` is written only by `record()`, so the ledger and
   the summed counters cannot drift; `priced_calls()` returns the ledger, falling
   back to the aggregate as a single request for an accumulator that never kept
   one (a hand-built value or a pre-#794 payload) — the pre-#794 figure, never a
   zero. The accumulator loses `Copy` (a `Vec` is not `Copy`); nothing relied on
   copying it silently.
2. **The extraction component uses the same accumulator** as the Decision-Model
   component, so both sides of a job carry a ledger.
3. **Both components are priced per request** (`core/ai/cost.rs`):
   `cost_breakdown` and `decision_cost_breakdown` take the per-call slice instead
   of four scalars, and a private `capped_energy` helper sums
   `min(raw_i, token_i)` per request. `raw_energy_nano` is that same sum of
   per-request raw figures, so `effective <= raw` keeps holding.
4. **The token figure stays aggregate on purpose.** `token_cost.total_nano` is
   still priced once over the summed tokens: only the energy cap needs the
   per-request split, and moving the token rounding per call would change a
   persisted wire figure for every multi-call job with nothing gained. (The
   per-request sum could exceed the aggregate token figure by at most half a nano
   per request, i.e. rounding noise below 1e-9 currency units.)
5. **Docs, spec and tests** state the per-request semantics, and a multi-call
   test pins the acceptance case: one call capped, one not, and the snapshot
   records the sum of the caps rather than the cap of the sums.

The wire shape does not change (`EnergyCostBreakdown` and
`DecisionCostBreakdown` keep their fields); only their descriptions do, so
`backend/openapi.yaml` is regenerated.

## Non-goals

- Retaining the usage of **failed** retries (a truncation retry that billed tokens
  but returned no answer). That is a separate gap: `retry_chat`/`retry_schedule`
  only see the usage of the successful answer.
- Changing the token pricing model (per-call token rounding) or re-pricing
  already-persisted snapshots — the snapshot is immutable by contract.
