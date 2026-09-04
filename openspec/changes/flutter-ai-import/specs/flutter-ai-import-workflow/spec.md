<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-ai-import-workflow Specification (delta)

## ADDED Requirements

### Requirement: Raw-Document Job Submission
The workflow SHALL submit schedules (CSV file, PDF file, or pasted
plain text) and scripts (PDF) as RAW-body uploads with the matching
declared `Content-Type` (never multipart), after the season
membership AUTHZ-GATE (capability check before the network call,
`// AUTHZ-GATE:` annotated). A 202 SHALL navigate to the job status
screen; a 200 duplicate SHALL navigate with an explicit "already
imported (duplicate)" callout; 413/415/404 SHALL render copy keyed on
the problem `code`.

#### Scenario: Schedule upload accepted
- **WHEN** the user submits a CSV and the backend returns 202 with a
  job id.
- **THEN** the job status screen pushes with the returned id; the
  submission screen surfaces in-flight progress and never blocks the
  frame on the upload.

#### Scenario: Duplicate document
- **WHEN** the upload returns 200 (digest-duplicate).
- **THEN** the UI navigates to the existing job with the duplicate
  callout; nothing implies a second import was created.

#### Scenario: Membership denial short-circuits
- **WHEN** a user without the costume-dept capability submits.
- **THEN** the client denies before the network call with the 403
  narrative (fake-repository call count of zero in tests).

### Requirement: Job Status With Terminal Error States
The job status screen SHALL watch the job with bounded, foreground-
only refetching (no background polling/wake-ups) and render every
status honestly: pending/running with indeterminate progress (no
fabricated percentages), retryable `failed` with `retries/max_retries`,
and terminal `dead_letter`/`payload_unavailable` as error cards whose
primary copy is keyed on the status with `last_error` as secondary
text only. A "cancel" affordance SHALL NOT exist (no server route);
the user may only close/leave, and the copy SHALL say so.

#### Scenario: Processing latency
- **WHEN** a job stays in pending/running across watch ticks.
- **THEN** the screen shows the indeterminate progress affordance and
  remains interactive (no UI-thread block); leaving the screen stops
  the watch and returning re-arms it.

#### Scenario: Terminal processing error
- **WHEN** the job reaches `dead_letter` or `payload_unavailable`.
- **THEN** the terminal error card renders with status-keyed primary
  copy and the `last_error` string as secondary detail; the watch ends.

### Requirement: Tolerant Preview Rendering and Explicit Apply
The preview screen SHALL render the typed `AiImportPreviewResponse` / `AiPreviewPayload` (`kind`/`data`: `script` → `ScriptContext`, `schedule` → `ShootingSchedule`, `merged` → `MergedPreview`; backend issue #337, PR #357) from the generated client: recognized payloads as cards, an unknown future `kind` as an explicit degraded card with a stable code — never silently coerced data, never retyped DTOs. The apply action SHALL submit `ApplyAiImportRequest`
with `draft_ref`s taken verbatim from the preview rows the user acted
on, per-row decisions (Create / Update with the picked aggregate id +
version from the read DTO / skip), the episode context from the
navigation stack, and the `accept_as_is` + `edit_distance` values from
the actual selection state. The 200 response SHALL render the outcome
summary (`applied_count`, `created_days`, `planned_scene_shoots`).

#### Scenario: Partial preview results
- **WHEN** the preview contains a mix of recognized rows and an
  unknown future `kind`.
- **THEN** recognized rows are actionable; the unknown payload renders as
  a degraded card excluded from one-tap accept-all; apply proceeds only
  with explicit user decisions.

#### Scenario: Unknown preview kind strict-rejects
- **WHEN** the preview carries a `kind` string the client does not know.
- **THEN** the screen renders the standard error state keyed on the
  stable code instead of guessing a meaning (no guessed rendering).

#### Scenario: Apply with mixed decisions
- **WHEN** the user marks one row Create, one Update (existing
  aggregate picked), and skips the rest.
- **THEN** the request carries exactly those mappings; the summary
  card reflects the server's outcome counts; deep navigation to the
  affected episode is offered.

#### Scenario: Apply reconciles after an ambiguous timeout
- **WHEN** an apply dispatch times out with an unknown outcome.
- **THEN** the controller re-reads the job/outcome first and reconciles
  (bounded retry, server-side idempotency per backend issue #338) —
  never blind re-dispatch, never a duplicate import implied.

#### Scenario: Empty preview
- **WHEN** a succeeded job's preview returns 404.
- **THEN** an explicit "no preview available" state renders with the
  option to view the job's terminal status; no fabricated rows.
