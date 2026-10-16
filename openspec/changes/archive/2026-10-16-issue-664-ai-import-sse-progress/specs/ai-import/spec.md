<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# ai-import Delta (issue-664-ai-import-sse-progress)

## ADDED Requirements

### Requirement: Owner-fenced job progress with stage and episode visibility
The operational `AiImportJob` record SHALL carry an optional `progress`
payload (`AiImportProgress`: `stage`, `chunk`, `chunks_total`,
`episodes_seen`) persisted in `ai_import.ai_import_job.progress` (`JSONB`)
and exposed on `GET /v1/ai-import/jobs/{id}`, `GET /v1/ai-import/jobs`, and
`GET /v1/ai-import/jobs/{id}/events`. Progress writes SHALL be executed via
an owner-fenced `AiImportQueue::mark_progress` method
(`WHERE id = $1 AND status = 'running' AND claimed_by = $2`) and SHALL be
throttled to stage transitions (`extracting_text`, `extracting`, `merging`,
`storing_preview`) and completed chunks (`1..=chunks_total`), NEVER per
generated LLM token. The `episodes_seen` list SHALL be populated at zero
extra LLM token cost from the deterministic `Ep.:` marker scan and extracted
per-chunk `DraftEpisode` metadata in first-seen order, deduplicated. Re-claiming
a job after a retryable failure SHALL reset `progress` to `null` so stale
progress from an earlier attempt is never served.

#### Scenario: Script worker publishes throttled per-chunk progress and episodes seen
- **WHEN** a script import job with 12 scene chunks processes chunks 1 through 4
  spanning markers `Ep.: 3` and `Ep.: 4`
- **THEN** the worker calls `mark_progress` once after chunking and once after
  each completed chunk (never per LLM token)
- **AND** after chunk 4 the persisted `job.progress` carries
  `stage = "extracting"`, `chunk = 4`, `chunks_total = 12`, and
  `episodes_seen = ["Ep. 3", "Ep. 4"]`

#### Scenario: Displaced worker cannot overwrite progress
- **WHEN** a worker whose claim lease expired calls `mark_progress` after
  another worker has reclaimed the job
- **THEN** `mark_progress` affects zero rows and returns `DomainError::Conflict`
- **AND** the new owner's `progress` state remains intact

#### Scenario: Retry reclaim clears stale progress from a prior attempt
- **WHEN** a retryable `failed` job with non-null `progress` from attempt 1 is
  claimed for attempt 2
- **THEN** the claim transition resets `progress` to `null` before attempt 2
  begins processing

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
  membership in the job's block requests `GET /v1/ai-import/jobs/{id}/events`
- **THEN** the handler rejects the request with `403 ai-import.forbidden`
  (`application/problem+json`) before opening an SSE stream
