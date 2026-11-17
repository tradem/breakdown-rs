<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Honour provider retry hints in retry and hold scheduling

## Why

Issue #926. Every hosted provider we integrate answers a rate limit with `429`
plus `Retry-After` / `X-RateLimit-*`, and #925 taught the transport to *parse*
those headers — `retry::parse_retry_hint` reads them at all four provider call
sites — but nothing acts on them: `classify_http_status` flattens every `429`
into the generic retryable `ServiceUnavailable`, and three schedulers keep
guessing:

| Scheduler | Today |
|---|---|
| `ai/workers.rs::retry_bounded` (in-attempt chunk retry) | `Backoff::EqualJitter` 500 ms × 2^attempt, 30 s cap, ≤25 % jitter |
| `queue.rs::mark_failed` (job-level retry) | SQL ladder `1 min × 2^retries`, capped at 6 h |
| `provider_health` / `provider_probe` (breaker probe) | `retry_at = open window`, hint-blind |

A provider that says "wait 5 s" is therefore retried after ~1 s, and a provider
that says "wait 10 min" is probed again after the open window has elapsed.

**The design constraint is the anti-pattern #871 removed:** no in-request
sleeping on the hint. Sleeping inside a provider call holds an
`ai_import.concurrency_permit` for the hint's whole duration (25 paid calls /
19–25 min permit-hold per chunk). The hint must therefore propagate **up** as
data into the schedulers that already exist, and it must be **bounded** in each
of them so the analytic worst case stays computable.

## What

### 1. The hint crosses the error boundary by value

`DomainError::ServiceUnavailable` gains a sibling field
`retry_after: Option<Duration>` (no new variant: a variant is an ADR-031
problem-code story, and a `429` is already the registered
`ai-import.llm-provider-unavailable`). It stays `Clone + Send + 'static`
(`Duration` is `Copy`) and every non-provider `service_unavailable(…)` call site
passes `None`, so the taxonomy is unchanged.

A core helper `llm_provider_unavailable_with_hint(reason, Option<Duration>)`
plus the accessor `DomainError::retry_after()` are the only new surface. The
**narrative** (the attempt row's `error_summary`) is composed at the
classification site in `infra` from the same single input, so structure and text
cannot disagree — and `core` gains no `format!` (ADR-031).

### 2. In-attempt retry: the hint is a floor, bounded at 120 s

`retry_bounded` sleeps `max(computed_backoff, min(hint, 120 s))`. The new
constant is `core::ai::MAX_IN_ATTEMPT_HINT_SECS = 120` and it is deliberately
**the** permit-hold bound: the sleep happens while a concurrency permit is held,
so this number is what `AiImportBounds::attempt_worst_case_secs` multiplies.

The recomputed worst cases (defaults: `max_attempt_retries = 2`,
`request_timeout_secs = 120`, `MAX_ATTEMPT_BACKOFF_SECS = 30`):

```text
(1 + max_attempt_retries) × (1 + inner_retries) × request_timeout_secs
  + max_attempt_retries × max(MAX_ATTEMPT_BACKOFF_SECS, MAX_IN_ATTEMPT_HINT_SECS)
```

| Provider | inner_retries | Before #926 | After #926 |
|---|---|---|---|
| hosted | 2 | 19 min | **22 min** |
| Ollama | 3 | 25 min | **28 min** |

The selection itself is a pure function
(`retry::effective_in_attempt_delay`), so the matrix — hint above, below, absent,
at the clamp — is asserted analytically instead of slept through.

### 3. Job-level retry: the hint beats the ladder, clamped to 6 h

`mark_failed` gains a `retry_after: Option<Duration>` argument and its SQL takes
`GREATEST(ladder, LEAST(hint, 6 h))` for `next_attempt_at`. The 6 h ceiling is
the ladder's own literal cap (and the default
`AI_IMPORT_MAX_PROVIDER_HOLD_SECS`), so a provider claiming
`Retry-After: 86400` cannot freeze the queue for a day; the clamp is logged at
`warn` with both values. `$7 = NULL` (no hint, or a non-provider failure) leaves
the ladder exactly as it was — `GREATEST` ignores `NULL`.

### 4. Hold series and probe: the hint moves the probe schedule

`core::ai::provider_health::on_retryable_failure` takes the hint and sets
`retry_at = now + max(open_window(flap_count), clamped_hint)`. That single
number is:

- the **probe schedule** — `provider_probe` selects `state <> 'closed' AND
  retry_at <= now()`, so a probe is skipped while the hint is unexpired, with no
  new column and no migration;
- the **hold's `until`** — `ProviderHold.until` is built from `retry_at`, so a
  held job's `next_attempt_at` honours the hint too (layer 3 of the issue);
- the **narrative trigger** — the hold keeps #822's registered
  `ai-import.llm-provider-unavailable` code (D-X1, no new code) and logs the
  rate-limit hint alongside it.

The probe picks its **own** clamp, `MAX_PROBE_DEFER_SECS` (= `MAX_OPEN_SECS`,
30 min), and deliberately does **not** reuse `MAX_IN_ATTEMPT_HINT_SECS`: a probe
holds no concurrency permit, so the permit-driven 120 s cap would make the hint
pointless here. A 10-minute hint therefore defers the probe by 10 minutes. The
ceiling is the breaker's own maximum open window, so a remote party still cannot
defer a probe indefinitely, and the hold-series deadline
(`AI_IMPORT_MAX_PROVIDER_HOLD_SECS`) bounds the whole series independently.

A later failure that carries **no** hint must not shorten a deadline an earlier
hint earned: `retry_at` is written unconditionally, so `BreakerCounters` carries
the stored deadline and `probe_at` keeps the later of it (while unexpired) and
the newly computed probe time. An expired stored deadline is discarded.

## Non-goals (issue #926, unchanged)

- Quota-exhaustion differentiation (non-retryable `429`s) — follow-up.
- Adaptive per-`(provider, model)` throttling, breaker-semantics cleanup,
  cross-provider fallback — parked.
- Honouring the hint in the decision-scoring pass
  (`decision_scoring::decide_with_quick_retry`) or the pricing ticker: the
  decision pass carries the hint but keeps its single fixed pause, because its
  policy is a *bounded two-call* pass rather than a scheduling loop. Recorded
  here so the omission is a decision, not an oversight.
