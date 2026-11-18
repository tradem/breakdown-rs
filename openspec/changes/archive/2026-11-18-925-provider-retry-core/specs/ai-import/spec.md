<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import

## ADDED Requirements

### Requirement: Provider retry classification and hints are computed in one place

Every provider-HTTP call site in `infra` SHALL classify a response and read its
server-side retry hint through one shared, pure retry core
(`crates/infra/src/retry.rs`), so the follow-ups that honour `Retry-After` and
separate quota-exhausted `429`s change a scheduling decision instead of five
call sites.

The core SHALL expose:

- a status classification — `429` and every `5xx` **retryable**, every other
  `4xx` **rejected**, everything else (1xx/3xx/non-standard) **unexpected** —
  which the `DomainError` mapping consumes at the call boundary, so the error
  taxonomy stays unchanged;
- a hint type that is owned and free of any lifetime tied to the response
  (`wait`, `limit_remaining`, `limit_reset` plus the classification), because
  `reqwest::Response` is moved by the body read;
- the wait strategies the sites actually use (a fixed pause, the projector's
  equal jitter, the archival worker's full jitter) as one implementation each.

#### Scenario: The hint is read before the body is consumed

- **WHEN** a call site receives a provider response
- **THEN** it SHALL capture the hint from the response headers before it calls
  `.text()`/`.json()` (which move the response)
- **AND** reading the hint SHALL NOT change the request, its timing, its budget
  or its error classification.

#### Scenario: A malformed hint never fails a request

- **WHEN** a header the parser reads is absent, unparsable (`Retry-After:
  soon`), unreadable (non-ASCII bytes) or absurd (a wait beyond one day)
- **THEN** the corresponding hint field SHALL be `None`, or be capped at one
  day
- **AND** the request SHALL keep its ordinary outcome: a `2xx` body still
  decodes, and a non-`2xx` status still maps to the same `DomainError` variant
  as before the hint existed
- **AND** no panic and no validation error SHALL be raised for a bad header.

#### Scenario: No site's timing changes

- **WHEN** the retry core is adopted by an existing call site
- **THEN** that site's pre-existing timing, budget and error taxonomy SHALL be
  preserved: the in-attempt retry keeps its exponential pause (500 ms base,
  30 s cap, ≤25 % jitter), the decision pass keeps its single fixed pause, the
  truncation and Ollama parse loops keep re-requesting without a pause, and the
  catalog refresh keeps its interval ticker
- **AND** where a policy was implicit in a loop, a test SHALL pin it.

#### Scenario: The retry hint is observability only

- **WHEN** a provider sends `Retry-After` or `X-RateLimit-*` headers
- **THEN** the site SHALL log the hint at `debug` level and act on it in no
  other way
- **AND** honouring the hint SHALL be a separate, later change.
