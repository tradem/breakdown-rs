<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — 942

`[W1–W3]` shipped in the first PR; `[W4/W5]` shipped in the follow-up PR under
this same change (route + Dart client + design docs + Flutter surface). No task
gates on wall-clock timing (AGENTS.md §4).

## 1. [W1–W3] Backend — shipped

- [x] 1.1 `ProbeCapability` + `probe_capability` `const` table over all eight
      `LlmProvider` variants, no catch-all arm (D1).
- [x] 1.2 `ProbeOutcome` renamed `Usable`/`NotUsable` so the verdict names what
      it measured (account usability, not endpoint existence).
- [x] 1.3 `/key` preflight (`key_probe_url`, verdict table in
      `probe_key_endpoint`) with the curated-tier HTTP client; the public
      `/models` read is gone from the probe path.
- [x] 1.4 `on_probe_success` → `half_open` + `trial_due` (never `closed`, D2);
      `BreakerDecision::trial_due` added.
- [x] 1.5 Migration `20261119000001_provider_trial_token` (`trial_job_id` +
      partial index) and `trial_job_id` cleared on every non-`half_open` CAS.
- [x] 1.6 `ProviderHealth::begin_provider_trial` (single statement; guarded
      against concurrent sweepers) + `run_probes` grants the trial after a
      passing preflight and re-grants when a window elapses without a holder.
- [x] 1.7 Claim fence on all four claim paths (`ph.trial_job_id = job.id`, with
      the `IS NOT NULL` guard).
- [x] 1.8 `admits_paid_call()` vs `admits_claim()` split; in-process gates use
      the former.
- [x] 1.9 `ProviderGate.trial` + `ProviderGate::attempt_retries` → a trial runs
      one request (D4).
- [x] 1.10 A retryable trial failure escalates (`flap_count + 1`, D5) and
      re-materializes the holds.
- [x] 1.11 `CallFailure { error, evidence }` + `hold_evidence` (bounded) +
      `retry_chat`/`retry_schedule` propagation (D6).
- [x] 1.12 `HoldEvidence` on the `mark_held` port; one attempt row per hold
      *series*, `retries` untouched, re-holds append nothing.
- [x] 1.13 `ai-import.provider-quota-exhausted` (402) registered + `de`/`en`
      Fluent texts + `PROBLEM_CODE_COUNT` bump.
- [x] 1.14 `402` classified as a terminal quota verdict in
      `classify_http_status_rich` (extraction + decision client).
- [x] 1.15 Tests: capability table, `/key` URL, probe-success/failed-trial state
      machine, bounded evidence, single-shot trial, trial-fence claim
      (integration), hold-series attempt row (integration).
- [x] 1.16 `UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`
      → only `x-code-registry` changed; **no** Dart client regeneration.
- [x] 1.17 Docs: `backend/.github/instructions/ai-import.instructions.md`
      (probe section rewritten, hold-attempt-row rule, quota-code note).

## 2. [W4] Backend — provider health + budget read (follow-up PR)

- [x] 2.1 `GET /v1/ai-import/providers/{provider}/health?model=` returning
      `(provider, model)` breaker snapshots (`credential_configured`,
      `probe_status`, `budget`).
- [x] 2.2 Credential resolution strictly for `current_user.sub` (never a donor
      job); `credential_configured: false` + `budget: null` for an unbound user,
      never `404`/`500`.
- [x] 2.3 `// AUTHZ-GATE:` `authorize_credential_role` inside the handler.
- [x] 2.4 TTL cache keyed `(user_id, provider, vault_key_id)`, hard timeout,
      degradation to `unknown` — `GET /v1/ai-import/configs` stays pure Postgres.
- [x] 2.5 `UPDATE_OPENAPI=1` + `scripts/regen-client.sh` with the committed diff
      and a `CLIENT_VERSION` MINOR bump (this is where client drift is expected
      and must be committed).
- [x] 2.6 Integration tests: User A vs User B isolation, unconfigured user, no
      secret/raw-`detail` on the wire.

## 3. [W5] Flutter — provider health + budget (follow-up PR, design docs first)

- [x] 3.1 `docs/design/screens/{settings,ai-import-jobs,ai-config}.md` +
      `docs/design/glossary.md` Salt wireframes, verified with
      `scripts/check-design-diagrams.sh` **before** widget work
      (`frontend-flutter/AGENTS.md` §11).
- [x] 3.2 `@riverpod aiProviderHealth` that consults `myCapabilitiesProvider`
      first (`#816`: a resolved denial short-circuits locally, no HTTP).
- [x] 3.3 Keep `aiConfigReachabilityProvider` scoped to backend reachability
      (`#809`) — a quota-exhausted provider must never render as
      "Backend noch nicht erreichbar".
- [x] 3.4 `AiConfigScreen` states: usable + budget / usable + budget unknown /
      held-degraded / quota exhausted / unconfigured / checking / unreachable.
- [x] 3.5 `de`/`en` ARB parity + goldens in the German template locale; render
      the new quota code as "budget/quota exhausted — top up", never the backend
      `detail`.
- [x] 3.6 `dart format --set-exit-if-changed`, `flutter analyze`,
      `tool/breakdown_lints_runner`.
