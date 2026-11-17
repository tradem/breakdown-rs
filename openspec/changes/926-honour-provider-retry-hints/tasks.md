<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — honour provider retry hints (issue #926)

## 1. Carry the hint across the error boundary (`core`)

- [x] 1.1 `DomainError::ServiceUnavailable` gains
      `retry_after: Option<Duration>` — owned, `Copy`, so `Clone + Send +
'static` is preserved. No new variant (ADR-031 story), no new problem code.
- [x] 1.2 Helpers: `llm_provider_unavailable_with_hint(reason, Option<Duration>)`
      and the accessor `DomainError::retry_after()`. `service_unavailable(…)`
      and `llm_provider_unavailable(…)` keep their signatures and pass `None`.
- [x] 1.3 Every construction site passes `retry_after: None` (mechanical; the
      non-provider services — mapping DB, payload storage, pricing read model —
      never have a hint).
- [x] 1.4 The narrative is composed at the `infra` classification boundary, not
      in `core`: one input produces both the typed field and the attempt row's
      `error_summary` text.

## 2. In-attempt retry (`infra/src/ai/workers.rs`)

- [x] 2.1 `core::ai::MAX_IN_ATTEMPT_HINT_SECS = 120` (new, documented as the
      permit-hold bound).
- [x] 2.2 `retry::effective_in_attempt_delay(planned, hint)` — pure:
      `max(planned, min(hint, cap))`, hint absent ⇒ `planned`. Jitter stays on
      the computed backoff, the hint is a floor.
- [x] 2.3 `retry_bounded` sleeps that value; the hint is read from the
      `anyhow` chain via `DomainError::retry_after()` before the error is
      returned.
- [x] 2.4 Unit matrix (analytic `Duration` assertions): hint > computed,
      hint < computed, hint absent, hint exactly at the clamp, hint far beyond
      the clamp.
- [x] 2.5 Paused-clock `retry_bounded` tests: a `429` + hint error yields exactly
      one retry whose virtual delay **is** the hint, a hint below the computed
      backoff does not shorten it, an absurd hint waits the 120 s clamp and no
      longer, a hint-less failure keeps the pre-#926 window, and a hint grants no
      retry the budget forbids.
      **The permit is retained across the retry, by design** — #871 explains why
      (releasing and re-acquiring would let another job interleave between two
      calls of the same chunk). The bounded permit-hold is what the 120 s clamp
      asserts, so the omitted release/re-acquire lifecycle is not claimed here.

## 3. Job-level retry (`queue.rs::mark_failed`)

- [x] 3.1 Port: `mark_failed(…, retry_after: Option<Duration>)`.
- [x] 3.2 SQL: `next_attempt_at = now() + GREATEST(ladder, LEAST($hint, 6 h))`;
      `NULL` leaves the ladder untouched (`GREATEST` ignores `NULL`).
- [x] 3.3 The clamp is applied and logged (`warn`) in the queue impl, with the
      raw and clamped values, so an operator sees a provider trying to freeze
      the queue.
- [x] 3.4 Callers pass `error.retry_after()`; every fake queue in the tests
      accepts and records the argument (the wiring is what a fake can cover and
      a SQL test cannot).
- [x] 3.5 SQL-level assertions like #871's: hint `1 s` (ladder wins), `10 min`
      (hint wins), `24 h` (clamped to the 6 h ceiling).

## 4. Hold series and probe (`core::ai::provider_health`, `provider_probe`)

- [x] 4.1 `on_retryable_failure(counters, threshold, now, hint)` sets
      `retry_at = now + max(open_window(flap_count), clamped_hint)`.
- [x] 4.2 `ProviderHealth::record_failure(…, retry_after: Option<Duration>)`
      passes it through; table test for the hint-aware `retry_at`.
- [x] 4.3 The probe selector is already `retry_at <= now()`, so a known hint
      skips the probe — pinned by a test that a hint-unexpired `retry_at` is not
      selected.
- [x] 4.4 The hold inherits the hint through `ProviderHold.until` (built from
      `retry_at`); the hold log names the rate limit next to #822's registered
      code. No new problem code (D-X1).

## 5. Cost model and documentation

- [x] 5.1 `AiImportBounds::attempt_worst_case_secs` uses the backoff ceiling
      `max(MAX_ATTEMPT_BACKOFF_SECS, MAX_IN_ATTEMPT_HINT_SECS)`; `bounds_tests`
      pins 22 min hosted / 28 min Ollama.
- [x] 5.2 `.github/instructions/ai-import.instructions.md`: the formula, the new
      maxima (19/25 → 22/28 min), the 120 s clamp's reason, the `mark_failed`
      6 h clamp, and the hint-aware probe schedule.
- [x] 5.3 No new environment knob: the 120 s and 6 h clamps are constants and
      are named in the instructions file.
- [x] 5.4 `backend/CHANGELOG.md` `[Unreleased]` entry.

## 6. Verification

- [x] 6.1 `cargo check --workspace`, `cargo clippy --workspace --all-targets`.
- [x] 6.2 `cargo test -p breakdown_core`, `-p breakdown_infra` (retry, bounds,
      provider-health, worker retry, queue).
- [x] 6.3 `cargo deny check bans`, `cargo test -p architecture_tests`.
- [x] 6.4 ast-grep guardrail rules over the touched tree
      (`backend/rules/`, no new suppression).
- [x] 6.5 `scripts/add-spdx-headers.sh --check`.
