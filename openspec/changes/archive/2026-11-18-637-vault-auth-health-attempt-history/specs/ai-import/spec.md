<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# ai-import Delta (637-vault-auth-health-attempt-history)

## MODIFIED Requirements

### Requirement: Import is an operational job queue
AI imports SHALL be modelled as operational jobs (`AiImportJob`), NOT as
event-sourced aggregates or sagas. The queue SHALL live in a dedicated
Postgres schema, mirror the `ReportArchivalQueue` pattern (dedup key,
`Pending|Running|Succeeded|Failed|DeadLetter` status, idempotent enqueue),
and emit NO business events. The job family consists of three kinds:
`ScriptImport` (LLM), `ScheduleImport` (CSV native OR LLM) and `Merge`
(deterministic, no LLM).

#### Scenario: Re-uploading the same document is deduplicated
- **WHEN** a user uploads a document whose hash + user id matches an existing
  job
- **THEN** the system returns the existing job id without enqueuing a new job

#### Scenario: Import failures are classified
- **WHEN** an LLM call returns 429/5xx/timeout
- **THEN** the job is retried in-loop via `retry_transient` and mapped to
  `ServiceUnavailable`
- **WHEN** an LLM call returns 4xx (bad key / bad model)
- **THEN** the job transitions to `Failed` (permanent) without retry

#### Scenario: A rejected dependency credential is not retried
- **WHEN** a worker's Vault read answers `401`/`403` (invalid or expired token)
- **THEN** the failure is classified as `DomainError::DependencyAuthFailed`
  (registered code `dependency.auth-failed`) and `DomainError::is_retryable()`
  is false
- **AND** the job is dead-lettered without consuming the remaining retry budget
  against the permanent misconfiguration

#### Scenario: The wire exposes retry timing and attempt history
- **WHEN** `GET /v1/ai-import/jobs/{id}` is read for a retryable `failed` job
- **THEN** `next_attempt_at` carries the due time and `attempts` lists each
  recorded attempt (newest first) with its own status, error summary and
  retryable flag
- **AND** the per-attempt rows survive later attempts, unlike `last_error`
  which each attempt overwrites
