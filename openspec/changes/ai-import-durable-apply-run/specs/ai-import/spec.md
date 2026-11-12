<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# ai-import Delta (live test 2026-11-11 — the apply must outlive its request)

## ADDED Requirements

### Requirement: Applying a preview dispatches a durable run
`POST /v1/ai-import/jobs/{id}/apply` SHALL validate the apply request and
**dispatch** it instead of executing it inline. Validation keeps every
pre-dispatch rule the endpoint has today (job exists and is `succeeded`,
`authorize_ai_job` with `Action::Write`, target episode/project/block/season
resolution, mapping / episode-group / shooting-day / uncertainty validation
against the preview payload, unknown-aggregate checks). After validation the
handler SHALL claim the job's apply slot, persist the resolved apply request
next to the run, mark the run `requested`, and answer **`202 Accepted`** with an
`ApplyRunAccepted` descriptor carrying `run_id`, `stage` and `started_at`.

The apply's counters (`applied_count`, `created_*`, `planned_scene_shoots`,
`skipped_day_groups`, `unapplied_outfits`, `applied_episodes`) SHALL NOT be
returned by the `POST`: they describe the run's *end*, which the caller may no
longer be connected to observe. They SHALL be persisted on completion and served
by the run's terminal frame and by `GET /v1/ai-import/jobs/{id}`.

The run slot SHALL stay single-flight per preview: while a live run owns it, a
further `POST /apply` SHALL answer `409 ai-import.apply-in-flight` with the
owner's silence age and the server's staleness window (issue #805), and SHALL
NOT start a second run.

#### Scenario: A validated apply is dispatched and acknowledged, not executed
- **WHEN** an authorized reviewer posts a valid apply request for a `succeeded`
  job with 57 draft rows
- **THEN** the handler answers `202` with a `run_id`, the `applying` stage and the
  start instant, without waiting for a single aggregate to be written
- **AND** the response body carries no apply counters

#### Scenario: Invalid requests still fail synchronously
- **WHEN** the apply request maps a draft row the preview does not carry, or
  names an episode from another block
- **THEN** the handler answers the same problem code it answers today (`409` /
  `422`), and no run is requested

#### Scenario: A live run refuses a second dispatch
- **WHEN** a second `POST /apply` arrives while a run owns the slot and its owner
  has been silent for less than the staleness window
- **THEN** the answer is `409 ai-import.apply-in-flight`, carrying the run's
  silence age and the server's own staleness window
- **AND** the client's documented reaction is to attach to that run, not to retry
  blindly

### Requirement: A dropped request never cancels a run, and re-entry attaches
A dispatched run SHALL execute in a server-owned task holding the owner-fenced
apply slot, so the end of the HTTP connection (Android suspend/Doze, a
Wi-Fi→cellular handover, a closed socket, a killed app) SHALL NOT stop it. The
run's progress payload SHALL be cleared when the run **ends** — never when a
request future is dropped.

A client that re-enters SHALL be able to attach to the live run: the run's
progress frames arrive on `GET /v1/ai-import/jobs/{id}/apply-events` regardless
of which request started it, and `GET /v1/ai-import/jobs/{id}` SHALL report the
run's state (`idle` / `requested` / `running` / `done` / `failed`) so a fresh
process can decide between "offer an apply", "attach to a live run" and "render
the finished result".

An abandoned run (its owner died) SHALL remain recoverable through the existing
staleness window: after `ApplyProgress::STALE_AFTER` of owner silence the next
`POST /apply` claims the slot and re-drives the plan, converging through the
established reservation/idempotency protocol (no duplicate aggregates, no second
progress owner).

#### Scenario: Suspend in the middle of an apply
- **WHEN** the device suspends while the run is at row 12 of 57 and the socket
  dies
- **THEN** the run keeps applying rows server-side
- **AND** after the app resumes, the client attaches to the run's stream and sees
  the current row counter without re-posting the apply

#### Scenario: A run outlives a replica that started it
- **WHEN** the run's owner disappears and its silence exceeds the staleness
  window
- **THEN** the next apply claims the slot and re-drives the rows that were not
  confirmed
- **AND** already-confirmed rows are not applied twice

### Requirement: The run's outcome is durable and served after the fact
On completion the worker SHALL persist the run's outcome (`apply_state = done`
plus the `ApplyAiImportResponse` counters, `unapplied_outfits`,
`applied_episodes`, `skipped_day_groups`) before clearing the progress payload,
and SHALL serve it twice:

- as the **terminal frame** of `GET /v1/ai-import/jobs/{id}/apply-events`, after
  which the stream closes — a client that attaches *after* the run ended receives
  that frame immediately instead of waiting for frames that will never come;
- on `GET /v1/ai-import/jobs/{id}` so a screen that never watched the stream can
  still render what the import produced.

A failed run SHALL persist the registered problem `code` of its `DomainError`
(never a free-text `detail`), so the client's narrative stays code-driven as for
every other apply failure.

#### Scenario: Attaching after the run finished
- **WHEN** a client opens the apply stream for a job whose run already reached
  `done`
- **THEN** the first frame is the run's terminal frame with the persisted
  counters, and the server closes the stream

#### Scenario: A failed run reports a code
- **WHEN** the run aborts on a domain conflict
- **THEN** `apply_state` is `failed` and the job carries the registered problem
  `code` of that conflict
- **AND** the stream's terminal frame carries the same code
