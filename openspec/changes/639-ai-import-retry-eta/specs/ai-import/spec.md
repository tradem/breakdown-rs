<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# ai-import Delta (639-ai-import-retry-eta)

## ADDED Requirements

### Requirement: Attempt failure history carries the problem code
Each recorded AI-import attempt SHALL expose the stable registry `code`
(ADR-031 D2) of the failure that ended it, so a client can localize the
reason without parsing the free-form `error_summary`. The code SHALL be the
same entry the HTTP layer renders for the same `DomainError`, derived from
`DomainError::code()` and persisted alongside the summary at write time.
`code` SHALL be absent (`None`/`null`) when the writer recorded no typed
error, and a client SHALL treat an absent or unrecognized code as an unknown
reason rather than inventing one.

#### Scenario: A rejected Vault credential records its code
- **WHEN** a worker fails a job with `DomainError::DependencyAuthFailed`
- **THEN** the appended `AiImportAttempt` carries `code = "dependency.auth-failed"`
  and its human-readable `error_summary` as separate fields

#### Scenario: A retryable dependency outage records its code
- **WHEN** a worker fails a job with `DomainError::ServiceUnavailable`
- **THEN** the appended `AiImportAttempt` carries `code = "http.service-unavailable"`
  (the registry entry `DomainError::code()` resolves to)

#### Scenario: A code-less writer stays honest
- **WHEN** an attempt is recorded without a typed error (test seam or future
  writer)
- **THEN** `code` is `null` on the wire and the client renders the generic
  localized reason, never a fabricated code
