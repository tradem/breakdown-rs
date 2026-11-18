<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — one retry core for the provider-HTTP call sites (issue #925)

## 1. The core (`crates/infra/src/retry.rs`)

- [x] 1.1 `RetryClass` + `RetryClass::of(StatusCode)`: `429` and every 5xx
      retryable, every other 4xx rejected, 1xx/3xx/non-standard unexpected.
      `classify_http_status_with_detail` now classifies through it, keeping the
      exact `DomainError` variants and message texts at the call boundary.
- [x] 1.2 `RetryHint { class, wait, limit_remaining, limit_reset }` — owned and
      `Copy`, no lifetime on the response.
- [x] 1.3 `parse_retry_hint(&HeaderMap, StatusCode) -> RetryHint` (`#[must_use]`,
      `pub(crate)`): `Retry-After` (delta or HTTP-date), `X-RateLimit-Remaining`,
      `X-RateLimit-Reset` (delta or epoch, normalised). Absent/unreadable/
      unparsable ⇒ `None` + `tracing::debug!`; absurd ⇒ capped at
      `MAX_SERVER_HINT` (24 h).
- [x] 1.4 `Backoff { Fixed, EqualJitter, FullJitter }` with `delay(attempt)` —
      the one jitter implementation. `BACKOFF_BASE` (500 ms) plus the exponent
      clamp keeps every attempt finite (the pre-#925 equal-jitter copy could
      overflow a debug build at a saturated exponent).
- [x] 1.5 `log_hint(site, &RetryHint)`: the hint is *read* everywhere and acted
      on nowhere yet (the follow-ups change the scheduling, not the plumbing).

## 2. Migrating the five sites — no policy change

- [x] 2.1 `ai/workers.rs::retry_bounded` sleeps
      `Backoff::EqualJitter { BACKOFF_BASE, MAX_ATTEMPT_BACKOFF_SECS }`
      (still 1-based, so the first retry waits ~1 s).
- [x] 2.2 `ai/client.rs::request_decoded` — hint captured before `.json()`;
      the loop keeps its bounded re-requests (no pause, no `Backoff`), with the
      reason written down.
- [x] 2.3 `ai/decision_scoring.rs::decide_with_quick_retry` — one fixed
      `DECISION_RETRY_BACKOFF` pause via `Backoff::Fixed`.
- [x] 2.4 `ai/pricing_refresh.rs::fetch_json_with` — hint captured; the cadence
      stays the interval ticker (a failing catalog is never hammered in a loop).
- [x] 2.5 `ai/ollama.rs::request_once` — hint captured before `.json()`; the
      parse-retry budget is unchanged.
- [x] 2.6 `ai/decision_client.rs::decide` — hint captured before the body is
      read in chunks (the sixth classification site, same core).
- [x] 2.7 `projectors/supervisor.rs` and `reporting/backup.rs` delegate their
      `compute_backoff` to the core; `BACKOFF_BASE_MS` is pinned to
      `retry::BACKOFF_BASE` by a const assertion.

## 3. Tests

- [x] 3.1 `retry_tests.rs` — header matrix, classification matrix, both jitter
      formulas' bounds, `usize::MAX` attempt.
- [x] 3.2 `decision_scoring` — paused-clock pin of the implicit policy (one
      retry, exactly `DECISION_RETRY_BACKOFF` of virtual time; a permanent
      failure costs one call and no pause).
- [x] 3.3 Wiremock regressions where an injectable endpoint exists (decision
      adapter, catalog fetch): a `429` with hints keeps its pre-#925 error and
      its single request; a `2xx` with hints still decodes.
- [x] 3.4 Existing suites stay green (`provider_gate_tests`,
      `infra/tests/supervisor.rs`, `reporting_backup.rs`, the full `infra` lib
      suite: 600 passed, 1 ignored).

## 4. Validation

- [x] 4.1 `cargo fmt --check`
- [x] 4.2 `cargo clippy --workspace --all-targets -- -D warnings`
- [x] 4.3 `cargo deny check bans`
- [x] 4.4 `cargo test -p architecture_tests`
- [x] 4.5 ast-grep guardrails over the touched files (error hygiene, CQRS
      boundary, test-shim leak) + `scripts/add-spdx-headers.sh --check`
