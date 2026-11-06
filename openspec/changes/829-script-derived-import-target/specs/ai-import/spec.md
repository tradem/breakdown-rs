<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import Delta (829-script-derived-import-target)

Extends the `771-explicit-ai-import-target` delta (a job snapshots its
dispatched target) and consumes the `827-script-block-visibility` delta (the
block the script states). Both are open changes at the time of writing.

## ADDED Requirements

### Requirement: An upload may omit its target block by declaring its season
Both upload routes (`POST /v1/ai-import/scripts`,
`POST /v1/ai-import/schedules`) SHALL accept an **absent** `X-Active-Block`
header. When it is absent, `X-Declared-Season` SHALL be required and SHALL be
the upload's authorization scope: the handler SHALL evaluate
`AuthorizationPolicy::authorize_season_result` with `Action::Write` on the
declared season — the same predicate the block path evaluates on the block's
owning season — and SHALL carry a `// AUTHZ-GATE:` comment.

A block-less upload SHALL store the job with `block_id = NULL` and a target
snapshot naming the season but no block number. When `X-Active-Block` is
present, the established behaviour SHALL be unchanged (block scope, #771
declared-season agreement, `409 ai-import.scope-mismatch` on contradiction).

An unknown declared season SHALL answer with the established season-not-found
surface; a season the caller holds no active costume-dept role in SHALL answer
`403 ai-import.forbidden`. No new problem code is introduced for either case,
because both are already derivable from the unfiltered, `Authenticated`-only
season list — the block-less path discloses no new existence information.

#### Scenario: A declared-season upload creates a block-less job
- **WHEN** an authorized caller uploads a script with `X-Declared-Season: S`
  and no `X-Active-Block`
- **THEN** the job is enqueued (`202`) with `block_id = null` and
  `target = {season_id: S, season_number: <S's number>, block_number: null}`

#### Scenario: Neither header is a client bug
- **WHEN** the request carries neither `X-Active-Block` nor `X-Declared-Season`
- **THEN** the response is `400` and no document is stored and no job exists

#### Scenario: A season the caller has no role in is refused before storage
- **WHEN** the caller declares a season in which they hold no active
  costume-dept role
- **THEN** the response is `403 ai-import.forbidden`, no source document is
  stored and no job row is created

#### Scenario: The block path is untouched
- **WHEN** an authorized caller uploads with `X-Active-Block` naming a block of
  season S and `X-Declared-Season: S`
- **THEN** the job is enqueued with that block and its full target snapshot,
  exactly as before this change

#### Scenario: A contradictory pair is still refused
- **WHEN** the caller uploads with `X-Active-Block` naming a block of season A
  and `X-Declared-Season: B`
- **THEN** the response is `409 ai-import.scope-mismatch` and nothing is stored

### Requirement: The import target is attached by one job-scoped write
The system SHALL expose `PUT /v1/ai-import/jobs/{id}/target` taking
`{block_id}` and answering the updated `AiImportJob` view, which attaches the
write target to a job that has none.

The write SHALL be **set-once** and idempotent: repeating the already attached
block SHALL answer `200` and write nothing; a different block SHALL answer
`409 ai-import.target-immutable` carrying the S1 extension
`existing_block_id`. The block id and the target snapshot's block number SHALL
be written in one statement so the guard value and the displayed target cannot
drift.

The handler SHALL be gated by `authorize_ai_job(Action::Write)` — ownership plus
an active costume-dept role in the **attached** block's season — and SHALL
refuse:

- a job whose status is not `succeeded` (`409 domain.conflict`, matching the
  apply handler's precedent);
- a job that has already been applied (`409 ai-import.target-immutable` with the
  S1 extension `applied: true`);
- a block belonging to another season than the job's target season (`409
  ai-import.scope-mismatch`, the #771 comparison).

#### Scenario: A blind upload receives its target
- **WHEN** the owner of a `succeeded` block-less job attaches a block of the
  declared season
- **THEN** the response is `200` with the job view carrying that `block_id` and
  the matching `target.block_number`

#### Scenario: The same attach is idempotent
- **WHEN** the same block is attached a second time
- **THEN** the response is `200`, the job is unchanged and no write occurs

#### Scenario: A second, different block is refused
- **WHEN** a different block is attached after one is already set
- **THEN** the response is `409 ai-import.target-immutable` with
  `existing_block_id` naming the block that won, and the job is unchanged

#### Scenario: An applied job cannot be re-targeted
- **WHEN** an attach is attempted on a job whose apply already recorded rows
- **THEN** the response is `409 ai-import.target-immutable` with `applied: true`

#### Scenario: A block of another season is refused
- **WHEN** the caller attaches a block whose season differs from the job's
  target season
- **THEN** the response is `409 ai-import.scope-mismatch`

#### Scenario: The attach is season-authorized, not owner-authorized
- **WHEN** the owner attaches a block of a season in which they hold no active
  costume-dept role
- **THEN** the response is `403 ai-import.forbidden` and the job is unchanged

### Requirement: A job's authorization scope is its target season
`authorize_ai_job` SHALL evaluate the season policy on the job's target season
whenever one is known, so no job-scoped operation (status, preview, delete,
apply, attach) degrades to an ownership-only check. The block, when present,
SHALL additionally constrain the write: a target episode or group episode outside
`job.block_id` SHALL keep answering `403 ai-import.forbidden` (the CWE-639
guard, unchanged).

#### Scenario: A block-less job is not owner-only
- **WHEN** the owner of a block-less job (target season S) requests the job's
  preview and holds no active costume-dept role in S any more
- **THEN** the response is `403 ai-import.forbidden`

#### Scenario: A block-scoped job keeps its season scope
- **WHEN** a job was uploaded with a block of season S
- **THEN** every job-scoped operation is gated on the caller's role in S, as
  before this change

### Requirement: An apply requires an attached target block
`POST /v1/ai-import/jobs/{id}/apply` SHALL refuse a job whose `block_id` is
`null` with the registered `409 ai-import.target-missing`, carrying the S1
extension `season_id`. The CWE-639 cross-block guard SHALL keep exactly one
meaning — a target episode or group episode outside `job.block_id` is refused —
with no "block-less means unguarded" branch.

#### Scenario: A blind upload cannot be applied without a target
- **WHEN** an apply is requested for a `succeeded` job that never received a
  block
- **THEN** the response is `409 ai-import.target-missing` with `season_id`, and
  no scene, episode or shooting day is written

#### Scenario: The attach unlocks the apply
- **WHEN** the target has been attached and the reviewer picks an episode inside
  that block
- **THEN** the apply proceeds exactly as for a block-scoped upload

### Requirement: The target snapshot may name a season without a block
`AiImportTarget.block_number` SHALL be optional; `season_id` and
`season_number` SHALL remain required. `None` SHALL mean "the target block is
not chosen yet" — never `0` and never a placeholder value. The season pair SHALL
be written together, and the block number SHALL be written in the same statement
that sets `block_id`.

No schema migration SHALL be required: the persisted `target_*` columns are
already nullable.

#### Scenario: A block-less job renders an honest target
- **WHEN** a job's target is read before the attach
- **THEN** it carries `season_id`, `season_number` and `block_number = null`

#### Scenario: The attach fills the block number
- **WHEN** the target is read after a successful attach
- **THEN** `block_number` names the attached block and no second read is needed

#### Scenario: A block-scoped upload is unchanged
- **WHEN** a job was uploaded with a block
- **THEN** its target carries all three values, as before this change

## MODIFIED Requirements

### Requirement: Authorization gates on import endpoints
All AI import and configuration endpoints SHALL be gated by active costume-dept
membership. Privileged handlers under `Authenticated`-only routes SHALL call the
relevant `AuthorizationPolicy` method inside the handler body and return 403 on
denial, and SHALL carry a `// AUTHZ-GATE:` comment (mirrors the photo-handler
rule). AI config create/mutate SHALL additionally gate on
`has_active_credential_role`.

The scope SHALL be:

- **at upload** — the season owning the `X-Active-Block` block when that header
  is present, and the `X-Declared-Season` season when it is absent
  (`authorize_season_result` with `Action::Write` on that season in both cases,
  since the predicate is season-scoped either way);
- **on every job-scoped operation** (status, list frame, preview, event streams,
  apply, target attach, delete) — the job's **target season**, plus the attached
  block as the write target whenever one is attached. No job-scoped operation
  SHALL degrade to an ownership-only check while the job's target season is
  known.

#### Scenario: Non-member cannot import
- **WHEN** a user without an active costume-dept role in the target block — or,
  for a block-less upload, in the declared target season — attempts to upload a
  script
- **THEN** the system returns 403

#### Scenario: Non-member cannot read a block-less job
- **WHEN** the owner of a block-less job requests its preview after losing the
  costume-dept role in the job's target season
- **THEN** the system returns `403 ai-import.forbidden` and the preview payload
  is never read

#### Scenario: The write target still constrains the apply
- **WHEN** an authorized caller applies a job whose attached block is A while the
  request names an episode of block B
- **THEN** the system returns `403 ai-import.forbidden` (the CWE-639 guard)

### Requirement: Push-based job progress stream via Server-Sent Events (SSE)
The system SHALL expose `GET /v1/ai-import/jobs/{id}/events` returning a
`text/event-stream` (`Cache-Control: no-store, no-transform`,
`X-Accel-Buffering: no`)
stream of `AiImportJobResponse` frames (`event: job`). The handler SHALL
enforce authentication and the handler-internal `// AUTHZ-GATE:`
`authorize_ai_job` check (`Action::Read`) before opening the stream,
returning `404 ai-import.disabled` when AI import is disabled,
`404 ai-import.not-found` when the job does not exist, and
`403 ai-import.forbidden` when the caller is not authorized.

The first message on every initial connect and every `Last-Event-ID`
reconnect SHALL be a full snapshot of the current `AiImportJobResponse`,
so clients need no separate catch-up polling. Subsequent messages SHALL be
pushed without database polling whenever an owner-fenced status or progress
write commits, distributed through a storage-agnostic port subscription
(`AiImportQueue::subscribe`) backed by an in-process broadcast hub
(`AiJobEventHub`). In the PostgreSQL operating mode, fenced writes SHALL
additionally emit `pg_notify('ai_import_job_events', ...)` in the same SQL
statement, bridged into the local hub by a single shared `PgListener` per
API instance; single-node test and future SQLite operating modes SHALL
publish directly to the in-process hub without requiring `LISTEN/NOTIFY`.
The stream SHALL emit keep-alive comment frames (~30 s) and SHALL close
automatically immediately after emitting a frame whose `job.status` is
terminal (`succeeded`, `dead_letter`, `payload_unavailable`).

#### Scenario: Initial connect receives an immediate full snapshot
- **WHEN** an authorized user opens `GET /v1/ai-import/jobs/{id}/events` for a
  running job
- **THEN** the server responds with `200 OK` and `Content-Type: text/event-stream`
- **AND** the first SSE event (`event: job`) carries the full current
  `AiImportJobResponse` snapshot (including `progress`) and an `id` field

#### Scenario: Reconnect with Last-Event-ID converges via fresh snapshot
- **WHEN** a client reconnects to `GET /v1/ai-import/jobs/{id}/events` with a
  `Last-Event-ID` header after missing intermediate chunk updates
- **THEN** the server immediately emits the latest authoritative
  `AiImportJobResponse` snapshot as the first SSE event without requiring
  catch-up polling

#### Scenario: Fenced progress and status updates push over the stream and terminal status closes it
- **WHEN** a worker commits `mark_progress` and then `mark_succeeded` for a
  watched job
- **THEN** the SSE stream pushes an `event: job` frame for the progress update
  and an `event: job` frame with `status = "succeeded"`
- **AND** the server closes the SSE stream immediately after the terminal
  `succeeded` frame

#### Scenario: Already-terminal job emits one snapshot and closes
- **WHEN** an authorized user connects to `GET /v1/ai-import/jobs/{id}/events`
  for a job that is already in `succeeded`, `dead_letter`, or
  `payload_unavailable`
- **THEN** the server emits the single snapshot `event: job` frame and closes
  the stream immediately

#### Scenario: Unauthorized caller is rejected before streaming
- **WHEN** a user who does not own the job or lacks active costume-department
  membership in the job's target season requests
  `GET /v1/ai-import/jobs/{id}/events`
- **THEN** the handler rejects the request with `403 ai-import.forbidden`
  (`application/problem+json`) before opening an SSE stream

#### Scenario: The attach pushes the new target to a watching client
- **WHEN** a client is streaming a job's events and the job's target block is
  attached by another request
- **THEN** the stream pushes an `event: job` frame whose snapshot carries the
  attached `block_id` and the filled `target.block_number`, with no reconnect
  required

### Requirement: Import is an operational job queue
AI imports SHALL be modelled as operational jobs (`AiImportJob`), NOT as
event-sourced aggregates or sagas. The queue SHALL live in a dedicated
Postgres schema, mirror the `ReportArchivalQueue` pattern (dedup key,
`Pending|Running|Succeeded|Failed|DeadLetter` status, idempotent enqueue),
and emit NO business events. The job family consists of three kinds:
`ScriptImport` (LLM), `ScheduleImport` (CSV native OR LLM) and `Merge`
(deterministic, no LLM). The dedup key SHALL NOT include the import target, so
an upload that names no target block and a re-upload that names one are the same
document for duplicate detection.

#### Scenario: Re-uploading the same document is deduplicated
- **WHEN** a user uploads a document whose hash + user id matches an existing
  job
- **THEN** the system returns the existing job id without enqueuing a new job

#### Scenario: A deduplicated re-upload does not re-target the existing job
- **WHEN** a user re-uploads a document that already has a job, this time with a
  block the existing job does not carry
- **THEN** the system returns the existing job id, that job's stored target stays
  unchanged, and the response never implies the new block was adopted — the
  client offers the target attach for the existing job instead

#### Scenario: Import failures are classified
- **WHEN** an LLM call returns 429/5xx/timeout
- **THEN** the job is retried in-loop via `retry_transient` and mapped to
  `ServiceUnavailable`
- **WHEN** an LLM call returns 4xx (bad key / bad model)
- **THEN** the job transitions to `Failed` (permanent) without retry
