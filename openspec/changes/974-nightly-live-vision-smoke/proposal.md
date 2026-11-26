<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 974 — Nightly live vision smoke across the ADR-041 `D2` providers

## Why

#968 declared three EU pay-as-you-go vision endpoints (`scaleway`, `ovhcloud`, `nebius`) plus the
client-side ZDR attestation, and #960 built the page-streaming loop (pre-egress gate, strict JSON
schema, inner format fallback, per-page billing). Both are **static data and unit tests**: nothing in
CI ever opened a socket to any of those endpoints, so a rotated model ID, a retired host or an
API-contract change would surface first in a customer's failed schedule import.

The existing `AI Import Nightly` smoke covers only the **text** path and the Decision Model, and it
had no notion of *required vs advisory*, so one flaky reseller turns the board red for a reason
nobody can act on.

## What changes

| # | Change | File |
|---|---|---|
| 1 | `vision_smoke_catalog_preflight` — zero-token catalogue reads (`ovhcloud` anonymous `/v1/models`, keyed `/models` otherwise) plus the free EURouter `GET {base}/key` read | `crates/integration-tests/tests/ai_llm_smoke_test.rs` |
| 2 | `vision_smoke_reads_a_schedule_page` — one real page of `Drehplan_1.pdf` through the production extractor → `LlmVisionRequest` → `chat_vision_constrained`, per matrix provider | same |
| 3 | Hermetic guards: the unattested-Nebius gate refusal (in process, zero egress), the capability registry behind the `/key` preflight, the credential-variable convention, the page resolver, the rate-card/curated-model drift guard, `cost_usd=unknown` | same |
| 4 | Two nightly steps (preflight, then paid), `env:`-only register, own timeouts, no new action | `.github/workflows/ai-import-nightly.yml` |
| 5 | Canary decision, `AI_VISION_*` register, rotation recipe | `docs/operations/runbooks.md` §18, `.github/instructions/ai-import.instructions.md`, ADR-041 §`D2.1` |

## Binding decisions (from the issue)

- **D1** the canary is the *most stable cheapest* endpoint (`ovhcloud` / `qwen3-vl-30b-a3b`), not the
  production one — production fidelity stays the text pass's job (`AI_LLM_*`, untouched).
- **D2** `eurouter` gets the zero-token `/key` read (`ProbeCapability::KeyEndpoint`), **never** a paid
  vision call.
- **D3** `required` (red) vs `advisory` (one greppable `vision-smoke advisory-degraded …` WARN); a
  missing credential is SKIP + WARN naming the variable; a gate verdict contradicting
  `vision_egress_policy_for_config` is always red.
- **D4** zero-cost preflight before every paid call, on the curated base URLs only.
- Severity, cost (`VISION_RATE_CARDS`, verified 2026-11-25, `cost_usd=unknown` instead of `0.0`) and
  the `AI_VISION_KEY_<PROVIDER>` naming convention (`AI_IMPORT_USER_AGENT_<PROVIDER>` precedent) are
  as specified in the issue.

## Deliberate deviations (reviewed)

1. **`reqwest` as a dev-dependency of `integration-tests`.** The anonymous `ovhcloud` catalogue read
   cannot go through `OpenAiCompatibleModelCatalog::list` (it refuses an empty key and always sends
   `bearer_auth`). The raw read still uses the production transport policy
   (`infra::ai::transport::build_hosted_client`: HTTPS-only, same-origin redirects, DNS pinning, no
   proxy) and `CuratedProviderUrls::base_url`. No production code changed, no crate version moved.
2. **The preflight is gated on the matrix being DECLARED** (`AI_VISION_REQUIRED_PROVIDERS` /
   `AI_VISION_ADVISORY_PROVIDERS` set, which the nightly always does). It needs no credential by
   design, but it does need the network, and a pull-request run of `ai_llm_smoke_test` must stay
   hermetic.

## Verification

- `cargo test -p integration-tests --test ai_llm_smoke_test` — 18 tests, every live test skips without
  secrets (measured 0.00 s).
- Live preflight verified locally on 2026-11-26: `ovhcloud live_models=33 curated=2 status=ok`; a bogus
  `AI_VISION_KEY_SCALEWAY` produced exactly one `advisory-degraded … code=smoke-catalogue-unreachable`
  WARN with a green run; a bogus `AI_VISION_KEY_EUROUTER` produced the required-red
  `smoke-eurouter-key-refused` verdict.
- `cargo clippy -p integration-tests --all-targets -- -D warnings`, `cargo fmt --all --check`.
- `openapi.yaml`, the Dart client, `CLIENT_VERSION` and every crate version unchanged.

## Out of scope (recorded, not lost)

- Correcting the EURouter `curated_seed` pricing rows (own migration).
- Switching the text pass to a cheaper provider (product decision).
- Persisting the nightly cost/latency trend (needs a table + `cqrs-boundary` review).
