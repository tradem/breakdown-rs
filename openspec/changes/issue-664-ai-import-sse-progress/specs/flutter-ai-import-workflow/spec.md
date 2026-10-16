<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# flutter-ai-import-workflow Delta (issue-664-ai-import-sse-progress)

## MODIFIED Requirements

### Requirement: Job Status With Terminal Error States
The job status screen SHALL watch the job while foregrounded via the
push-based Server-Sent Events stream (`GET /v1/ai-import/jobs/{id}/events`)
with a single snapshot `GET /v1/ai-import/jobs/{id}` on app resume (no
periodic polling, no background wake-ups) and render every status honestly:
`pending`/`running` with localized extraction stage (`stage`), chunk counter
(`chunk / chunks_total` with determinate progress indicator only when
`chunks_total` is present and positive, otherwise indeterminate progress —
never fabricated percentages), and discovered episode badges/chips
(`episodes_seen`, e.g. `Ep. 3`, `Ep. 4`) when `progress` is present;
retryable `failed` with `retries/max_retries`, a live localized time until
the next planned attempt derived from `next_attempt_at`, and the reason the
prior attempt(s) failed keyed on the attempt's stable problem `code`; and
terminal `dead_letter`/`payload_unavailable` as error cards whose primary
copy is keyed on the status with the attempt's code-keyed reason and
`last_error` as secondary text only. A "cancel" affordance SHALL NOT exist
(no server route); the user may only close/leave, and the copy SHALL say
so. When `next_attempt_at` is absent the screen SHALL say a retry is
scheduled without inventing a time; copy SHALL NEVER be interpolated from
the backend `detail`/`error_summary`.

#### Scenario: Live stage, chunk, and episode visibility during processing
- **WHEN** the SSE stream delivers a `running` job carrying
  `progress = { stage: "extracting", chunk: 4, chunks_total: 12, episodes_seen: ["Ep. 3", "Ep. 4"] }`.
- **THEN** the job status screen renders the localized stage copy, the `4 / 12`
  chunk progress, and the discovered episode labels `Ep. 3` and `Ep. 4`
  without blocking the UI thread.

#### Scenario: Running job without chunk counts shows indeterminate progress
- **WHEN** a job is `pending` or `running` with `progress == null` or
  `chunks_total == null`.
- **THEN** the screen shows the indeterminate progress affordance (never a
  fabricated percentage); leaving the screen closes the SSE subscription and
  returning re-arms it.

#### Scenario: Retryable failure shows a live ETA
- **WHEN** a retryable `failed` job carries `next_attempt_at` in the
  future.
- **THEN** the retryable card renders a localized "next retry in …"
  that updates as time passes, alongside the retry budget.

#### Scenario: Retryable failure without an ETA degrades honestly
- **WHEN** a retryable `failed` job has no `next_attempt_at`.
- **THEN** the card says a retry is scheduled and shows no countdown —
  no fabricated time.

#### Scenario: Retryable failure explains the prior attempt
- **WHEN** a retryable `failed` job carries attempt history.
- **THEN** the reason of the newest attempt is rendered on the retryable
  card, localized from the ARB catalog keyed on the attempt's problem
  `code`; an absent or unrecognized `code` renders the generic localized
  reason, never the raw backend summary as identity.

#### Scenario: Terminal processing error
- **WHEN** the job reaches `dead_letter` or `payload_unavailable`.
- **THEN** the terminal error card renders with status-keyed primary
  copy and the `last_error` string as secondary detail; the SSE watch ends.

## ADDED Requirements

### Requirement: Foreground-Only SSE Subscription and Battery Contract
The Flutter client SHALL consume `GET /v1/ai-import/jobs/{id}/events`
exclusively over the existing ADR-024 / ADR-032 pinned-CA `Dio` transport
(`SecurityContext(withTrustedRoots: false)` with `ResponseType.stream`),
never via an unpinned `HttpClient`. Only `AiJobStatusScreen` SHALL open an
SSE subscription, and only while the screen is mounted and the application
is foregrounded.

When `AiJobStatusScreen` is disposed or the application transitions to the
background (`paused` / `hidden` / `detached`), the client SHALL cancel the
SSE stream immediately so zero background network wake-ups occur. When the
application resumes to the foreground while `AiJobStatusScreen` is mounted,
the controller SHALL perform ONE snapshot read (`GET /v1/ai-import/jobs/{id}`)
and re-subscribe to the SSE stream only if the job status is non-terminal.
On a transient stream disconnect or a read-idle watchdog timeout (`receiveTimeout`
exceeding 2× the server's 30 s `: keep-alive` interval, detecting silent
middlebox/NAT drops) while foregrounded, the client SHALL
reconnect with bounded backoff passing the last received SSE `id` in the
`Last-Event-ID` header. The jobs overview list (`AiImportJobsScreen`) SHALL
NOT open SSE streams (zero watches); it SHALL render each row's `progress`
summary (stage and `episodes_seen`) from its one-shot `GET /v1/ai-import/jobs`
fetch and manual pull-to-refresh.

#### Scenario: Stream closes on background and refreshes once on resume
- **WHEN** `AiJobStatusScreen` is watching a running job and the app is
  backgrounded.
- **THEN** the active SSE stream subscription is cancelled immediately.
- **WHEN** the app returns to the foreground (`resumed`).
- **THEN** the controller performs one `GET /v1/ai-import/jobs/{id}` snapshot
  read and re-opens the SSE stream only if the job is still non-terminal.

#### Scenario: Transient disconnect reconnects with Last-Event-ID over pinned TLS
- **WHEN** an active SSE stream on `AiJobStatusScreen` drops transiently after
  receiving event `id: 42`.
- **THEN** the repository reconnects via the pinned-CA `Dio` client with header
  `Last-Event-ID: 42` and updates the UI from the server's initial snapshot
  event.

#### Scenario: Jobs overview list renders progress without opening SSE streams
- **WHEN** `AiImportJobsScreen` renders a list of jobs fetched from
  `GET /v1/ai-import/jobs` containing a running job with `progress`.
- **THEN** the row displays the localized stage/episode progress summary
- **AND** the repository `watch` call count from `AiImportJobsScreen` remains
  zero.
