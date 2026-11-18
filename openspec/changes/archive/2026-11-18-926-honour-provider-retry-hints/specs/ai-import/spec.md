<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import

## ADDED Requirements

### Requirement: A provider's retry hint bounds every scheduler that already exists

A `429`/`5xx` response that carries `Retry-After` (or `X-RateLimit-Reset`) SHALL
propagate that wait **as data** out of the provider call and into the schedulers
that already exist — the in-attempt retry, the job-level `next_attempt_at`, the
breaker probe schedule and the provider hold — as a **minimum** delay. The hint
SHALL NOT be slept through inside the provider call, because that call holds an
`ai_import.concurrency_permit` for the whole sleep.

Every scheduler SHALL clamp the hint to a documented bound, so the analytic
worst case of one attempt stays a computed number and no provider can order an
unbounded permit-hold or an unbounded queue freeze.

#### Scenario: The hint lifts the in-attempt backoff, bounded at 120 s

- **WHEN** a provider answers `429` with `Retry-After: 5` and the computed
  exponential backoff for that attempt is smaller
- **THEN** the in-attempt retry SHALL wait 5 s instead of the computed delay
- **AND** the jitter SHALL stay on the computed backoff, so the hint is a floor
  and not a target
- **AND** a hint above `MAX_IN_ATTEMPT_HINT_SECS` (120 s) SHALL be clamped to
  it, with the computed backoff unchanged when it is already larger.

#### Scenario: The hint beats the job-level ladder, clamped to 6 h

- **WHEN** a retryable attempt fails with a hint and the job keeps its retry
  budget
- **THEN** `next_attempt_at` SHALL be `now + max(ladder, min(hint, 6 h))`
- **AND** a hint larger than the ceiling SHALL be clamped and logged, so a
  `Retry-After: 86400` cannot freeze the queue for a day
- **AND** a failure without a hint SHALL leave the `1 min × 2^retries` ladder
  byte-identical to the pre-hint behaviour.

#### Scenario: A known hint defers the probe instead of being rediscovered

- **WHEN** a provider failure carrying a hint is recorded for a `(provider,
  model)` pair
- **THEN** the breaker's `retry_at` SHALL be the later of the open window and
  the clamped hint
- **AND** the probe task SHALL therefore not probe that pair before the hint
  expires
- **AND** a job held while the breaker is open SHALL carry the same instant as
  its `ProviderHold.until`, keeping #822's registered
  `ai-import.llm-provider-unavailable` code rather than adding a problem code
  for rate limiting.

#### Scenario: The attempt narrative names the rate limit

- **WHEN** an attempt fails because the provider rate-limited it
- **THEN** the persisted attempt row's narrative SHALL name the rate limit (and
  the wait the provider asked for)
- **AND** the text SHALL be produced at the `infra` classification boundary
  from the same value as the typed hint, never re-derived from it (ADR-031: no
  string building in `core`).

#### Scenario: A hint never changes the classification

- **WHEN** any response carries a hint
- **THEN** its `DomainError` variant, problem code, HTTP status and retryability
  SHALL be identical to the same response without a hint
- **AND** a malformed or absurd header SHALL degrade to "no hint", never to an
  error or a panic.

#### Scenario: The documented worst case matches the code

- **WHEN** `AiImportBounds::attempt_worst_case_secs` renders the window one
  attempt may occupy a permit
- **THEN** its backoff term SHALL use
  `max(MAX_ATTEMPT_BACKOFF_SECS, MAX_IN_ATTEMPT_HINT_SECS)`
- **AND** the defaults SHALL render 22 min for a hosted provider and 28 min for
  Ollama, asserted in `bounds_tests` and mirrored in
  `.github/instructions/ai-import.instructions.md`.
