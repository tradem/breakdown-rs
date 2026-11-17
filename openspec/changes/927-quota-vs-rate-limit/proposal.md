<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# A quota-exhausted `429` is terminal, not a burst

## Why

Issue #927. `429 Too Many Requests` carries two very different conditions, and
`classify_http_status` (`infra/src/ai/client.rs`) maps both to the retryable
`ServiceUnavailable`:

| Condition | Retrying helps? | Examples |
|---|---|---|
| Rate limit (RPM/TPM) | yes — waiting solves it | OpenAI `rate_limit_exceeded`, OpenRouter platform RPM |
| Quota exhaustion | **no** — the account is empty | OpenAI `insufficient_quota` / `credit_balance_exhausted`, Gemini free-tier RPD quota id, OpenRouter `free-models-per-day` |

Retrying the second kind burns paid calls — each holding an
`ai_import.concurrency_permit` for up to `AI_IMPORT_REQUEST_TIMEOUT_SECS` — and
then consumes the whole job retry budget before dead-lettering, while the first
response already said the account cannot pay. It is the same waste pattern #871
removed for dead providers, and #925/#926 left exactly this hole open: the retry
core reads the *headers* for a wait hint but never looks at the *body*.

## What

- **A body-aware verdict in the transport layer.**
  `client::classify_provider_body(provider, body) -> RateLimitVerdict`
  (`RateLimited` | `QuotaExhausted`) decides on evidence — the provider's own
  error `code`, not the status alone (#521's *verify before attributing*). The
  curated per-provider marker table is a `const` next to `CuratedProviderUrls`:
  `static`/const data, no `Arc<T>`, not user-configurable (the curated-URL trust
  rule), and **not** in `core`.
- **A bounded body read, with the read outcome kept separate from the text.**
  `client::read_error_body(&mut Response)` streams with `Response::chunk()`,
  stops at `MAX_ERROR_BODY_BYTES` (1 KiB) **and** at
  `error_body_budget(request_timeout)` — at most `ERROR_BODY_DEADLINE` (5 s), and
  never longer than the request timeout that already bounds the response
  (`AI_IMPORT_REQUEST_TIMEOUT_SECS` is configurable down to 1 s):
  `.text()`/`.bytes()` buffer whatever the provider sends, and a byte bound alone
  is no time bound — a provider can send half a body and stall while the caller
  holds a permit. It never fails; it returns
  `ErrorBody { text, complete }`, and an **incomplete** read is never evidence
  (the verdict stays retryable) while the arrived bytes still reach the
  narrative.
- **An honest, non-retryable error variant.**
  `DomainError::LlmProviderQuotaExhausted` renders the **existing** registered
  `ai-import.llm-provider-unavailable` code (#822 D-X1 decided against a new
  code, so the client keeps aggregating it and no Fluent/registry entry changes).
  The only difference to `ServiceUnavailable` is retryability, which is exactly
  the fact we now know. The narrative names the status and the **matched** quota
  code from the curated table (plus the bounded body), so the attempt row
  (`ai_import.ai_import_job_attempt.error_summary` + `error_code`) says *why* it
  was terminal even when the provider hides its code behind a long message and
  the raw detail is truncated.
- **Wiring, not a new channel.** `AiImportRuntime::fail` marks the job with
  `error.is_retryable()`, so a quota verdict dead-letters on the first attempt
  (`mark_failed(…, retryable = false)` → `status = dead_letter`), and
  `retry_bounded` refuses to feed the terminal verdict into the provider breaker
  — counting it would let three terminal failures open the breaker and turn a
  dead-letter into a hold that waits for nothing.
- **Conservative default, per #521's lesson:** an unparseable body, an HTML
  gateway page, an empty body or an unknown code stays `RateLimited` (today's
  behaviour, logged at `debug`). A wrong "non-retryable" verdict dead-letters a
  job a retry would have saved; a wrong "retryable" verdict costs one wasted
  attempt.
- **402/403 stay untouched.** EURouter's budget/spend caps are `402` (not
  `429`), and `opencode` entitlement is `403`; both keep their existing
  `Rejected` classification, so the quota arm can never misfile them.

## Per-provider evidence table

The table is curated `const` data in the transport layer. Markers are lowercased
substrings of the provider's own error strings (matched case-insensitively
against the JSON string values of the body).

| Provider | Quota markers (terminal) | Everything else on `429` |
|---|---|---|
| `openai`, `neuralwatt`, `opencode`, `opencode-go` | `insufficient_quota`, `credit_balance_exhausted`, `billing_hard_limit_reached` | retryable |
| `gemini` | `perdayperproject`, `per_day_per_project` (the RPD quota id inside `error.details[].metadata.quota_limit`) | retryable |
| `openrouter` | `free-models-per-day`, `free_models_per_day` | retryable |
| `eurouter` | *(none — plan RPM is retryable, budget caps are `402`)* | retryable |
| `ollama` | *(none — self-hosted, no account quota)* | retryable |

`X-RateLimit-Remaining: 0` is deliberately **not** evidence: an RPM window also
reaches zero, so header-only turnstiles stay retryable (the hint still schedules
the retry, per #926).

## Non-goals

- `Retry-After` / hint honouring → #926 (already shipped; unchanged here).
- A new problem code for "quota exhausted" — #822 D-X1: the client aggregates
  `ai-import.llm-provider-unavailable`, and the attempt row's `retryable` flag is
  what distinguishes terminal from degraded.
- Adaptive throttling, cross-provider fallback.
- Ollama and the model-catalog/pricing endpoints: no quota concept, no evidence
  to read.

## Validation

- Unit matrix: per provider × {rate-limit code, quota code, empty body,
  malformed JSON, HTML error page, oversized body} → verdict, plus the
  conservative default.
- `classify_http_status_rich(…, QuotaExhausted)` → new variant, unchanged code,
  `is_retryable() == false`; a `503` carrying a quota body stays retryable.
- wiremock (decision adapter — the only provider adapter with an injectable
  endpoint): `429` + `insufficient_quota` → terminal error, one request, zero
  retries, narrative contains the provider code; `429` + `slow down` → today's
  retryable behaviour (regression pin).
- Paused-clock `retry_bounded` test: a quota verdict costs exactly one call and
  records **no** breaker outcome.
