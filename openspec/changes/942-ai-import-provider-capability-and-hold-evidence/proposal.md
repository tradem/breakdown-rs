<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 942 — A provider outage is diagnosed before it is paid for again

## Why

A first real AI-import run against `eurouter` / `mistral-large-3` never completed
a single chunk. Every cycle was `3 × 120 s` of `AI_IMPORT_REQUEST_TIMEOUT_SECS`
(no HTTP response ever arrived), the job was held with
`last_error = ai-import.llm-provider-unavailable`, `retries = 0` and **zero**
attempt rows, and the app told the user *"EURouter ist nicht erreichbar"*. The
live analysis in issue #942 shows the diagnosis was wrong on every layer:

| Finding | Evidence | Root cause |
|---|---|---|
| F1 a hold has no reason | 35 min of looping → 0 attempt rows; `last_error` is a code | `retry_bounded` replaces the real failure with `breaker_open_error()` (`workers.rs`), `hold_job` took no error, `mark_held` persisted `reason_code` |
| F2 the probe is blind | `GET /models` answers `200` for a **bogus** token; `GET /key` `200` while `POST /chat/completions` stalls | the probe measured reachability of a public endpoint, and a `200` closed the breaker directly |
| F3 the chunk spends 6 min on timeouts | `363–365 s` per cycle is the analytic fingerprint | `1 + max_attempt_retries` attempts × 120 s, even for a `half_open` probe |
| F4 quota looks like an outage | `402` → `RetryClass::Rejected` → `domain.validation`; the quota variant renders the outage code | no account-scoped code, no Fluent copy |
| F5 the copy asserts an unknowable fact | `aiJobProviderHoldTitle` = "… ist nicht erreichbar" | the hold carries no reason to render (F1) |

## What changes

**W1 — capability-accurate two-stage probe (core + infra, this PR).**
A curated `const` capability table over all eight `LlmProvider` variants
(`/key` for `eurouter`+`openrouter`, `/api/tags` for `ollama`, no preflight for
the other five). A passing preflight moves `open → half_open` and grants
**one** trial token (`provider_health.trial_job_id`); the claim predicate admits
exactly that job; the trial runs **one** request (0 in-attempt retries); a
retryable trial failure re-opens immediately with `flap_count + 1`; only a real
paid call closes.

**W2 — a hold carries its reason (core + infra, this PR).**
`CallFailure { error, evidence }` carries the bounded narrative of the failure
that fired the sentinel into `hold_job`; `mark_held` appends **one**
`ai_import_job_attempt` row per hold *series* (`error_summary` + `error_code`,
`retryable = TRUE`). `retries` stays untouched; a re-hold appends nothing.

**W3 — quota is its own taxonomy entry (core + infra + api locales, this PR).**
`ai-import.provider-quota-exhausted` (402) in `problem_codes!` with `de`/`en`
Fluent texts; `402 Payment Required` classified as a terminal quota verdict in
`classify_http_status_rich` (both the extraction and the decision client).
Supersedes `#822 D-X1` / `#927`'s reuse of the outage code for this case.

**W4/W5 — deferred to a follow-up PR under this same change.**
Per-provider health/budget read (`GET /v1/ai-import/providers/{provider}/health`,
`(provider, model)` snapshots, strictly `current_user.sub` Vault scope, TTL cache
keyed `(user_id, provider, vault_key_id)`, `AUTHORIZE_CREDENTIAL_ROLE` gate) and
the Flutter surface (`aiProviderHealth` provider, `#816` capability pre-tap gate,
de/en ARB parity, goldens) plus the design-doc updates of
`frontend-flutter/AGENTS.md` §11. They are not in this PR because they add a
second contract change and a second subsystem to one diff.

## Locked decisions

| # | Decision | Rejected alternative and why |
|---|---|---|
| D1 | `KeyEndpoint` for `eurouter`/`openrouter`, `LocalTags` for `ollama`, `NoPreflight` for the rest | Probing every hosted provider live: no verified zero-token endpoint exists for `openai`/`gemini`/`neuralwatt`/`opencode*`, and the #521 "verify before attributing" rule forbids curating a guess. A public `/models` read is never proof (it answers `200` for an invalid key). |
| D2 | A passing preflight grants a trial; it never closes | The measured flap loop: `GET /key` `200` in 0.2 s while the model stalls at 120 s. Closing there released the fleet into another `3 × 120 s` round. |
| D3 | The claim predicate names the single trial holder (`trial_job_id`) | Admitting every held job in `half_open` would turn one probe window into a fleet-wide (`0..n` jobs) paid burst instead of one call. The in-process gates cannot see a job id, so the fence has to live in SQL. |
| D4 | A trial runs 0 in-attempt retries | `1 + AI_IMPORT_MAX_ATTEMPT_RETRIES` answers "is the chat path back?" no better than one request, and costs 6 min of a held permit per window (F3). |
| D5 | A failed trial escalates (`flap_count + 1`) | Re-arming the base 60 s window forever oscillates. A paid call failing right after a passing preflight is a *new* incident by definition. |
| D6 | W2 reuses `ai_import_job_attempt` (one row per hold series) | A new nullable `last_provider_detail` column would need a DTO field → an OpenAPI change → a Flutter client regeneration, for data the attempt pipeline (#822/#637) already reads and renders. |
| D7 | `402` is terminal and account-scoped | Keeping `#927`'s `domain.validation` mapping hides a top-up behind "your request was wrong"; opening the deployment-wide breaker would punish every other user of the endpoint. |
| D8 (W4) | The health read resolves **the caller's own** Vault binding; the donor-job credential stays confined to the background probe | A donor key is another user's. Publishing a verdict derived from it would leak that account's key validity and balance — and make the route an existence oracle for foreign bindings. |
| D9 (W4) | The response is `(provider, model)`-shaped (`breakers[]`), not one provider verdict | `ai_import.provider_health` is keyed by the pair; a single verdict would have to pick one model and hide the rest — exactly the blindness F2 recorded. |
| D10 (W4) | `trial_job_id` becomes `trial_granted: bool` on the wire | The token names a job that may belong to another user. The client only needs to know a trial is in flight. |
| D11 (W4) | Budget is three-valued: absent / `remaining: null` / a number | Collapsing "no limit configured" and "no budget endpoint" into one null forces the client to invent a `0` or a `—`. A measured `0` is still reported as `0`. |
| D12 (W4) | The cache key is `(user_id, provider, vault_key_id)`, TTL 60 s | Keyed by provider alone the first caller's balance would be served to everyone on that provider — the tenant leak the credential rule exists to prevent. The Vault reference makes a rotation a miss. |
| D13 (W5) | A second Riverpod provider (`aiProviderHealth`) instead of extending `aiConfigReachabilityProvider` | The reachability probe answers "did the BACKEND answer". Merging the two is what rendered a stalled provider as "Backend noch nicht erreichbar" (F5). |
| D14 (W5) | The card renders on the AI-configuration screen, not in Settings | The question ("can my import run at all") belongs where the configuration is; the Settings tile keeps its single reachability/capability claim. |
| D15 (W5) | Hold copy names the *observed* fact (no timely answer) and the open cost question | F3 measured three 120 s client timeouts; "ist nicht erreichbar" was a cause nobody measured, and "kein Versuch verbraucht" is not "keine Kosten". |

## Contract impact

- `backend/openapi.yaml`: **only** the `x-code-registry` root extension gains one
  entry (W3). Verified against the generator: the Dart client is unchanged (root
  `x-*` keys are not consumed, and no problem-code string appears in
  `frontend-flutter/vendor/breakdown_api/`), so `scripts/regen-client.sh` output
  is byte-identical and **no client regeneration is required**.
- W1/W2 add no wire field at all: the trial token is internal and the attempt row
  reused existing columns.
- `frontend-flutter/lib/l10n/*.arb`: untouched in the W1–W3 PR. The follow-up PR
  (W4/W5) adds the provider-health keys plus the honest hold copy in `de` + `en`.

### Follow-up PR (W4/W5) contract impact

- `backend/openapi.yaml`: **one new path**
  (`GET /v1/ai-import/providers/{provider}/health`) plus three schemas
  (`AiProviderHealthView`, `AiProviderBreakerView`, `AiProviderBudgetView`) and
  the re-exported `AccountProbeStatus` enum. `scripts/regen-client.sh` output is
  committed (`CLIENT_VERSION` 1.8.0 → 1.9.0; new models + one `HandlersApi`
  operation).
- No new problem code: the route reuses `ai-config.forbidden`,
  `ai-import.disabled` and `ai-config.validation`.
- `frontend-flutter/lib/l10n/*.arb`: 16 new keys per catalog (de/en) plus the
  reworded hold copy.

## Non-goals (unchanged from the issue)

No SSE/apply-progress change, no new `*_in_season` predicate (ADR-035 B2), no
client-side cost estimation, no timeout re-tuning (the 120 s budget is kept; only
the trial's *number of calls* changes).
