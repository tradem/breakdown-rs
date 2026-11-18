<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# One retry core for the provider-HTTP call sites

## Why

Issue #925. Every hosted provider we integrate answers a rate limit with
`429` + `Retry-After` / `X-RateLimit-*`, and `infra` responded to that fact five
times in five different ways:

| Site | Loop | Policy before this change |
|---|---|---|
| `ai/workers.rs` `retry_bounded` | in-attempt chunk retry | base 500 ms doubling, cap 30 s, ≤25 % jitter, `max_attempt_retries` |
| `ai/client.rs` `request_decoded` | truncation re-request | `MAX_TRUNCATION_RETRIES`, own budget accounting, no pause |
| `ai/decision_scoring.rs` `decide_with_quick_retry` | decision pass | 1 retry, fixed `DECISION_RETRY_BACKOFF` |
| `ai/pricing_refresh.rs` | catalog refresh | interval ticker + warn |
| `ai/ollama.rs` `request_once` | Ollama parse retry | own inner budget, no pause |

The classification (`429`/5xx → provider-unavailable, other 4xx → rejected) was
one function, but the *jitter formula* existed twice (the projector supervisor's
equal jitter and the report-archival full jitter, each re-derived), and **no**
site read a single retry header. Two follow-ups — honouring `Retry-After` and
distinguishing quota-exhausted `429`s — each had five call sites to change
before they could change one behaviour.

## What

- **`crates/infra/src/retry.rs`, a crate-internal retry core** with three
  pieces: [`RetryClass`] (status classification), [`RetryHint`] +
  [`parse_retry_hint`] (the server's own hint) and [`Backoff`] (the wait
  strategies). Pure and stateless by construction — no `Arc<T>`, no async, no
  shared state; small values in, small values out.
  It lives at crate level rather than under `ai/` (the issue suggested
  `ai/transport.rs`) for one reason: the projector supervisor and the photo and
  report retry paths use the same formula today, and `projectors → ai` would be
  a new cross-context dependency. The core is the neutral place all of them
  share; the AI transport consumes it like any other call site.
- **`RetryHint` is owned and `Copy`** (`class`, `wait`, `limit_remaining`,
  `limit_reset`), because `reqwest::Response` is *moved* by `.text()`/`.json()`.
  Call sites therefore read the hint from the headers **before** consuming the
  body — which is exactly the plumbing a follow-up needs.
- **`parse_retry_hint(&HeaderMap, StatusCode) -> RetryHint`** reads
  `Retry-After` (delta-seconds *and* all three RFC 9110 HTTP-date shapes, via
  the already-present `httpdate` crate), `X-RateLimit-Remaining` and
  `X-RateLimit-Reset` (delta seconds or epoch seconds, normalised to "time until
  the reset"). Absent, unreadable (obs-text / non-UTF-8) or unparsable values
  degrade to `None` plus a `tracing::debug!` — never a panic and never a
  validation error, because a bad header must not fail a request that otherwise
  succeeded. Absurd values are capped at `MAX_SERVER_HINT` (one day).
- **The jitter formula is one implementation.** `Backoff::EqualJitter` is the
  projector supervisor's shape (base·2^attempt, cap, ≤25 % jitter) and
  `Backoff::FullJitter` the report-archival shape (the same doubling, then one
  uniform draw from `[0, capped]`). `projectors::supervisor::compute_backoff`,
  `reporting::backup::compute_backoff` and the worker retry loop all delegate;
  their public signatures and their numeric output are unchanged.
  `BACKOFF_BASE_MS` is kept as the millisecond view of `retry::BACKOFF_BASE`
  with a const assertion tying the two together.
- **`classify_http_status_with_detail` classifies through `RetryClass`.** The
  `DomainError` mapping stays exactly where it was — at the call boundary — so
  `core` is untouched and the error taxonomy every caller matches on is
  byte-identical (same variants, same messages).
- **Every HTTP site reads the hint and logs it at `debug`.** Nothing acts on it:
  this change is the consolidation, so honouring `Retry-After` and separating
  quota `429`s remain the follow-ups. The plumbing being in place is the point —
  they now change the *scheduling decision*, not five call sites again.

## Non-goals (unchanged by design)

- **No timing change**: `retry_bounded` still sleeps 500 ms·2^attempt (1-based,
  ≤30 s, ≤25 % jitter), the decision pass still pauses exactly
  `DECISION_RETRY_BACKOFF` once, the truncation loop and the Ollama parse loop
  still re-request with no pause, and the catalog refresh is still the interval
  ticker. The decision policy was implicit in a loop and is now pinned by a
  test.
- **No error-taxonomy change**: `DomainError` is not modified; `429`/5xx stay
  `llm_provider_unavailable` at the chat/decision adapters and the catalog keeps
  its own `service_unavailable` narrative.
- **No shared state**: adaptive per-`(provider, model)` throttling stays parked —
  it needs an owner-task + channel, not `Arc<Mutex<_>>` in an async path.
- **No `core` change**: the core is `pub(crate)` transport plumbing, not a port.

## Tests (deterministic, no wall-clock gating)

- `retry_tests.rs` (26 tests): the header matrix (`Retry-After` integer /
  HTTP-date / past date / malformed / absurd, `X-RateLimit-Reset` delta vs
  epoch, `X-RateLimit-Remaining`, obs-text value, all absent, all together), the
  classification matrix (429/5xx retryable, other 4xx rejected, 1xx/3xx
  unexpected), and both jitter formulas' bounds including a `usize::MAX`
  attempt (which the pre-#925 equal-jitter copy could overflow in debug).
- `decision_scoring` policy pin with `#[tokio::test(start_paused = true)]`: one
  transient failure ⇒ exactly two calls and exactly `DECISION_RETRY_BACKOFF` of
  *virtual* elapsed time; a permanent failure ⇒ one call, zero pause.
- Wiremock regressions for the two sites that already expose an injectable
  endpoint: a `429` carrying hints keeps its pre-#925 error and its single
  request (decision adapter, catalog fetch), and a `2xx` carrying the same hints
  still decodes.
- The untouched suites (`provider_gate_tests` for the retry loop,
  `infra/tests/supervisor.rs` + `reporting_backup.rs` for the two formulas)
  verify the migration did not move any value.
