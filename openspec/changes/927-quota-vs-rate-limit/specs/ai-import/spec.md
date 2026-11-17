<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import

## ADDED Requirements

### Requirement: A quota-exhausted `429` is terminal, a rate-limited one is not

A provider `429` SHALL be classified on **response-body evidence**, not on the
status alone: an account-level quota exhaustion (OpenAI `insufficient_quota` /
`credit_balance_exhausted`, Gemini's per-day quota id, OpenRouter's
`free-models-per-day`) SHALL be a **non-retryable** failure, while a per-minute
rate limit SHALL stay retryable.

The classification SHALL use a curated, non-user-configurable per-provider marker
table in the transport layer and SHALL default to **retryable** whenever the
evidence is missing or unreadable — an unparsable body, an empty body, an HTML
gateway page or an unknown code.

#### Scenario: Quota exhaustion dead-letters on the first attempt

- **WHEN** a provider answers `429` with a body naming an exhausted quota
- **THEN** the failure SHALL be non-retryable and the job SHALL be recorded as
  `dead_letter` without consuming another paid call
- **AND** the attempt row SHALL carry the registered
  `ai-import.llm-provider-unavailable` code and a narrative naming the status and
  the **matched** quota code — independent of where that code sits in the
  provider's prose, so the evidence cannot be truncated out of the history
- **AND** the terminal verdict SHALL NOT move the provider breaker counter, so a
  dead-letter can never be converted into a hold.

#### Scenario: A rate limit keeps today's behaviour

- **WHEN** a provider answers `429` with a rate-limit code, or with a body that
  cannot be parsed
- **THEN** the failure SHALL remain the retryable
  `ai-import.llm-provider-unavailable`, with the #926 hint scheduling unchanged
- **AND** a `5xx` carrying a quota-looking body SHALL stay retryable, because the
  evidence table only applies to `429`.

#### Scenario: The error body read is bounded in bytes and in time

- **WHEN** a non-2xx response carries a large or slowly-streamed body
- **THEN** at most 1 KiB SHALL be read, streamed chunk by chunk, **and** the
  whole read SHALL end within a fixed deadline (5 s) that is shorter than any
  configured request timeout — the two bounds together are what keep the read
  from holding the job's concurrency permit
- **AND** an IO error or the deadline SHALL keep the bytes collected so far and
  SHALL NOT replace the provider's real failure with a parsing error of our own
- **AND** an **incomplete** read SHALL NOT be treated as evidence: it keeps the
  conservative retryable default even when the bytes that arrived contain a
  quota code, because a stream cut by a proxy may have lost the part that
  changes the meaning.

#### Scenario: `402`/`403` stay distinct from `429`

- **WHEN** EURouter answers `402` for a budget cap, or a gateway answers `403`
  for an entitlement
- **THEN** the classification SHALL remain the existing non-retryable rejection
  and SHALL NOT be reported as a quota-exhausted `429`.
