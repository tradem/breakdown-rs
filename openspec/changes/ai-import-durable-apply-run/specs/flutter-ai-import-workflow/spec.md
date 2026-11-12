<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-ai-import-workflow Delta (live test 2026-11-11 — resume instead of restart)

## ADDED Requirements

### Requirement: An interrupted apply is resumed, not restarted
The client SHALL treat a dispatched apply as a server-side run it observes, not
as a request it owns:

- a `202 ApplyRunAccepted` answer SHALL be followed by opening
  `GET /v1/ai-import/jobs/{id}/apply-events` and rendering the run's counters and
  estimate from its frames;
- a **dropped dispatch** — `connectionError`, a timeout, a socket closed by an
  Android suspend — SHALL be classified as an **unknown outcome** (the same class
  as the pre-existing ambiguous-timeout reconciliation), never as a definitive
  failure; the client SHALL re-read the job and then attach to the run it finds;
- a `409 ai-import.apply-in-flight` SHALL be a **wait**: the client attaches to
  the run the refusal names and renders its progress, instead of surfacing an
  apply error;
- on re-entering the apply screen after a process death or suspend, the client
  SHALL decide from `GET /v1/ai-import/jobs/{id}` alone: no run → offer Apply, a
  live run → attach, a finished run → render the persisted result (counters,
  `unapplied_outfits`, `applied_episodes`) without a new dispatch.

The remaining-time display SHALL keep following the run's own frames
(`progress.updated_at`), so it keeps advancing while the run advances and shows
the honest stalled narrative only when the server itself stopped publishing.

#### Scenario: Suspended app re-attaches
- **WHEN** the app is suspended mid-apply and resumed later
- **THEN** the apply screen renders the run's current progress from its stream
- **AND** no second apply is dispatched

#### Scenario: A dropped dispatch is not a failure
- **WHEN** the dispatch fails with `transport.connectionError` (the socket died)
- **THEN** the client re-reads the job and attaches to the live run
- **AND** it does not render the apply-error narrative and does not re-dispatch

#### Scenario: Taking over an abandoned run is explicit
- **WHEN** the refusal reports an owner silence that has reached the server's own
  staleness window
- **THEN** the client offers the takeover, and performs it as a fresh dispatch
  that the server accepts by its own window

### Requirement: The client never mirrors the server's staleness window
The takeover affordance SHALL be gated on the values the `409` carries
(`apply_run_age_seconds` and `stale_after_seconds`), never on a client-side
constant. A server that predates the extension fields SHALL be rendered with the
pre-existing bounded-wait copy; the client SHALL NOT invent a window.

#### Scenario: No invented policy on an older server
- **WHEN** a `409 ai-import.apply-in-flight` arrives without the staleness
  extension fields
- **THEN** the client shows the bounded-wait narrative and offers no takeover
  based on a guessed duration
