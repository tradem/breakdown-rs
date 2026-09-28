# flutter-ai-import-workflow Specification

## Purpose
Defines the AI document import workflow of the Flutter client: the
user-facing pipeline that submits raw schedule/script documents (paste,
CSV, PDF) to the backend import routes, observes job processing through
a bounded watch state machine (pending/running → succeeded/failed/
dead_letter/payload_unavailable, no cancel affordance — the backend
owns cancellation), renders typed previews with strict rejection of
unknown future payload kinds, and applies mapping decisions into an
episode (verbatim draft_refs, edit_distance from real selections,
missing-context picker requirement). Every dispatch is AUTHZ-gated
client-side — a denial issues zero network requests — and duplicate
uploads are surfaced honestly, never as a fresh import.

## Requirements
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
version from the read DTO / skip), the job's PERSISTED episode context
(`episode_id` + `series_id`, stamped onto the cached job row at submit
time — never read from the navigation stack; a missing context requires
the explicit episode picker before the apply dispatch), and the
`accept_as_is` + `edit_distance` values from the actual selection state. The 200 response SHALL render the outcome
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

### Requirement: Point-of-interaction AI disclosure

The AI-import submit screen SHALL render a persistent disclosure card ABOVE
the submit action, visible before any submission, stating that the picked
document is processed by a server-side AI configured by the deployment, that
the results are AI-generated, and that they must be verified in the preview
before apply. The copy SHALL be localized ARB catalog copy keyed by the
glossary; the card SHALL be visibly distinct (icon + icon surface) so the
disclosure is not skippable content.

#### Scenario: Disclosure precedes submit
- **WHEN** the submit screen renders (any kind selection).
- **THEN** the disclosure card renders before the submit button in the
  scroll order and remains persistent while the file picker and kind picker
  render.

#### Scenario: No submission before disclosure
- **WHEN** a test asserts the screen's scroll order.
- **THEN** the disclosure card's scroll offset precedes the submit button's
  (the card is never moved below the fold as an afterthought).

### Requirement: Preview AI-extracted banner

The preview screen SHALL render an "AI-extracted content — review carefully"
banner above the typed payload body whenever a successfully typed payload
renders. The banner copy SHALL state that the rows are machine-extracted
drafts and that the payload carries no machine-verified confidence values
(the wire preview has none; `confidence` exists only on the recorded
provenance after apply). The client SHALL NOT render fabricated per-row
confidence chips.

#### Scenario: Typed payload shows the banner
- **WHEN** a script / schedule / merged payload renders.
- **THEN** the banner renders above the payload header.

#### Scenario: No fabricated confidence chips
- **WHEN** the payload renders.
- **THEN** no per-row chip asserts a confidence value; the honest review
  note is the banner's only safety framing (the wire carries none).

### Requirement: Apply review acknowledgement

The apply section SHALL gate the apply dispatch behind an explicit review
checkbox ("I have reviewed the AI-extracted content"). The submit button
SHALL stay disabled until the checkbox is checked (together with the
existing context gate); the selection summary
(create/update/skip counts + edit distance) SHALL render adjacent to the
acknowledgement.

#### Scenario: Unchecked apply is disabled
- **WHEN** the apply section renders with a valid context and the checkbox
  is unchecked.
- **THEN** the submit button is disabled.

#### Scenario: Acknowledged apply dispatches once
- **WHEN** the user checks the acknowledgement and taps submit.
- **THEN** the existing single apply dispatch runs unchanged (context,
  rows, decisions, versions) — the acknowledgement adds no second dispatch.

### Requirement: Provenance badge on AI-derived read rows

Every read surface that renders AI-derived rows SHALL render a persistent
provenance badge whenever the row's `source` is `Some(AiExtracted)`:
the shooting-days day list, the scene-detail shooting-days section and its
schedule picker, and the Soll/Ist day surface. Rows with `Manual` or `null`
source SHALL NOT carry the badge (legacy-proof). The badge copy SHALL be
localized and the badge SHALL be a semantic visible element (test key per
row id), not an arrow decoration.

#### Scenario: AI-derived day row is recognizable
- **WHEN** a `ShootingDayView` with `source = Some(AiExtracted)` renders.
- **THEN** the row carries one visible badge keyed
  `shooting-day-ai-badge-<id>`.

#### Scenario: Manual row carries no badge
- **WHEN** a row's `source` is `Manual` or `null`.
- **THEN** no badge renders for that row (no false attribution in either
  direction).
