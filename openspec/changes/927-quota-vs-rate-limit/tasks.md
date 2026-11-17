<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — a quota-exhausted `429` is terminal (issue #927)

## 1. Bounded body read (transport layer, `infra/src/ai/client.rs`)

- [x] 1.1 `MAX_ERROR_BODY_BYTES = 1024` — the bound `decision_client` already
      used locally, now one owner.
- [x] 1.2 `read_error_body(&mut reqwest::Response) -> String`: streams with
      `Response::chunk()`, stops at the bound, never fails (a read error keeps the
      bytes collected so far + a `debug` line). `.text()`/`.bytes()` are banned
      here — they buffer whatever the provider sends while a concurrency permit
      is held. **It lives in `ai/client.rs`, not `retry.rs`**: the #925 core is
      documented as pure, stateless and IO-free, and this is IO. The decision
      adapter's local copy of the same loop is deleted (one owner).

## 2. Provider verdict + curated table (`infra/src/ai/client.rs`)

- [x] 2.1 `RateLimitVerdict { RateLimited, QuotaExhausted }` with
      `is_retryable()`; `Copy`, no payload, no `Arc<T>`.
- [x] 2.2 `classify_provider_body(provider, body) -> RateLimitVerdict`: parses the
      JSON, collects its string values, matches the provider's curated markers
      case-insensitively. Unparsable/empty body ⇒ `RateLimited` + `debug` (the
      conservative default).
- [x] 2.3 Curated `const` marker table next to `CuratedProviderUrls`
      (`OPENAI_QUOTA_MARKERS`, `GEMINI_QUOTA_MARKERS`,
      `OPENROUTER_QUOTA_MARKERS`, empty for `eurouter`/`ollama`). Static data, not
      user-configurable.
- [x] 2.4 `classify_http_status_rich(status, detail, retry_after, verdict)`: the
      quota arm maps to `DomainError::llm_provider_quota_exhausted` **only** for
      `429` (a `5xx` with a copied body stays retryable). `classify_http_status`
      and `classify_http_status_with_detail` keep their signatures and pass
      `RateLimited`.

## 3. Error taxonomy (`core/src/error.rs`)

- [x] 3.1 `DomainError::LlmProviderQuotaExhausted { reason }` — non-retryable by
      construction (`is_retryable()` matches only `ServiceUnavailable`), renders
      the **existing** registered `ai-import.llm-provider-unavailable` code
      (#822 D-X1), carries no `retry_after` (a terminal job has nothing to
      schedule).
- [x] 3.2 Constructor `DomainError::llm_provider_quota_exhausted(reason)`.
- [x] 3.3 Unit tests: code/§display, `is_retryable() == false`,
      `retry_after() == None`.

## 4. Call sites

- [x] 4.1 Hosted chat (`client.rs::request_decoded`): capture the hint, read the
      bounded body on any non-2xx, classify, forward the body as the narrative
      detail (the #767 lesson — a status alone cannot be acted on).
- [x] 4.2 Decision adapter (`decision_client.rs`): replace the local bounded
      read with `retry::read_error_body`, classify, pass the verdict.
- [x] 4.3 Ollama (`ollama.rs`): pass `RateLimitVerdict::RateLimited` explicitly
      (self-hosted, no account quota) — the default, documented at the site.

## 5. Worker wiring (`infra/src/ai/workers.rs`)

- [x] 5.1 `AiImportRuntime::fail` marks the job with `error.is_retryable()`
      instead of `matches!(…, ServiceUnavailable)` — one source of truth for
      retryability, so the terminal verdict dead-letters on the first attempt.
- [x] 5.2 `retry_bounded` records a breaker failure **only** for a retryable
      provider failure: three terminal quota verdicts must not open the breaker
      and turn a dead-letter into a hold that waits for nothing.

## 6. Tests

- [x] 6.1 `client_tests.rs`: verdict matrix per provider × {rate-limit code,
      quota code, `5xx` with a quota body, empty body, malformed JSON, HTML page},
      the conservative default, and `classify_http_status_rich` + verdict
      (variant, unchanged code, `is_retryable()`, narrative carries the code).
- [x] 6.2 `decision_client_tests.rs` (wiremock, the only adapter with an
      injectable endpoint): `429` + `insufficient_quota` → terminal, one request,
      narrative names the code; existing `429` + `slow down` test stays the
      retryable regression pin.
- [x] 6.3 `provider_gate_tests.rs` (paused clock): a quota verdict costs exactly
      one call and records no breaker outcome.
- [x] 6.4 Timing-safe throughout: attempt counts and state, never wall clock.

## 7. Docs, versions, changelogs

- [x] 7.1 `backend/.github/instructions/ai-import.instructions.md`: the
      quota-vs-rate-limit split, the curated table, the conservative default.
- [x] 7.2 `core` MINOR (new public variant + constructor), `infra` MINOR (new
      transport surface), `api` unchanged (same code, same status, no Fluent key).
- [x] 7.3 CHANGELOG entries for both bumped crates; `Cargo.lock` staged.

## 8. CodeRabbit review (PR #931)

- [x] 8.1 The read outcome is separate from the text: `ErrorBody { text, complete }`,
      and an incomplete read (IO error or deadline) is never evidence — a stream
      cut after a quota-looking prefix keeps the conservative retryable verdict.
- [x] 8.2 The byte bound got a **time** bound: `ERROR_BODY_DEADLINE` (5 s) bounds
      the whole read, so a provider that writes half a body and stalls cannot hold
      the permit for `AI_IMPORT_REQUEST_TIMEOUT_SECS`. Spec, code docs and the
      instruction register state the same two bounds.
- [x] 8.3 `RateLimitVerdict::QuotaExhausted { marker }` carries the matched table
      entry and the narrative always names it, so the classified code survives the
      400-character detail truncation. Regression tests: a >400-character
      `error.message` before the code, and a stalled body read (raw TCP mock,
      50 ms deadline vs a 30 s stall).
