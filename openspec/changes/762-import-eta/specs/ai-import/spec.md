<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import Delta (762-import-eta)

## MODIFIED Requirements

### Requirement: Live extraction progress of a running AI import job

`AiImportProgress` SHALL describe *where* a running import is, and SHALL carry
the data a client needs to derive a remaining-time estimate without keeping its
own history:

- `stage` — the pipeline stage (`extracting_text`, `extracting`, `merging`,
  `storing_preview`);
- `chunk` / `chunks_total` — the completed-chunk counter and the document's
  chunk count (unchanged);
- `episodes_seen` — labels discovered so far, first-seen order (unchanged);
- `started_at` — the claim timestamp of the **current attempt**, identical on
  every frame of that attempt. The claim statement that flips the job to
  `running` also clears the stale counters, so the anchor and the counters can
  never describe different attempts and a retry restarts the estimate instead of
  inheriting the previous attempt's rate;
- `done_bytes` / `total_bytes` — source-text bytes already extracted and the
  document's total budget, both derived from the deterministic chunk scan and
  measured over exactly the bytes the model receives (`heading` + `\n` + `text`
  per chunk). `done_bytes` SHALL saturate and SHALL never exceed `total_bytes`;
- `written_at` — the server timestamp of **this frame**. It is the end of the
  measured interval (`written_at - started_at` = extraction time), so a client
  never counts the time its screen was closed, backgrounded or offline as work.
  It is also what a stall watchdog must measure — the job row's `updated_at` is
  refreshed by heartbeats and therefore hides a stopped progress stream.

All four new fields SHALL be additive on the wire (`serde(default)`), so a frame
written before them deserializes as `None` and a client shows no estimate rather
than a fabricated one. `None` is honest absence — a job with no byte budget (a
schedule is a single extraction unit) SHALL publish no pair instead of a zeroed
one.

#### Scenario: A retry restarts the anchor and the budget

- **WHEN** a script job fails retryably and a later attempt claims it
- **THEN** the claim clears `progress` and the first frame of the new attempt
  carries that attempt's `started_at` with `done_bytes = 0`, so no client
  carries the previous attempt's rate into the new one

#### Scenario: A pre-#762 frame is still readable

- **WHEN** a client built after this change reads a frame written before it
- **THEN** `started_at`, `done_bytes` and `total_bytes` deserialize as `None`
  and the client renders the "estimating" state, never a number

## ADDED Requirements

### Requirement: Honest ETA presentation for the extraction phase

The client SHALL render a coarse remaining-time estimate for a `running` import
from the job's own progress frames, and SHALL withhold it whenever it is not
defensible:

- no estimate before **two completed chunks**, independent of the basis the
  rate is measured in — a byte-basis frame whose first chunk finished has one
  sample, not two, and the client renders "estimating …" instead;
- bytes SHALL be preferred whenever `total_bytes > 0`; the chunk counters are
  the documented fallback;
- the estimate SHALL be re-derived on every frame from a smoothed (EMA)
  per-unit cost whose newest sample is clamped to a bounded step, so the
  rendered figure cannot jump backwards on one slow chunk;
- units SHALL be coarse (whole minutes, then whole hours) and a single figure
  SHALL be shown only for a steady cadence — an unsteady one renders as a range,
  and the uncertainty is smoothed like the rate, so one slow chunk cannot flip a
  figure into a full-width range;
- the elapsed interval SHALL end at the frame's own `written_at`, never at the
  client clock, and the stall window SHALL be derived from the observed
  **chunk** cadence (a per-byte cost cannot express how long a chunk takes);
- a `pending` job SHALL show no estimate at all (queueing is not extraction
  time), and a job without counters SHALL render exactly as before this change;
- when no frame arrived within 3× the observed cadence (clamped to 2–30 min) the
  estimate SHALL be dropped and the client SHALL say the job is delayed;
- the estimator SHALL be a pure function of (progress, now, previous estimate)
  so it is unit-testable without timers or clock injection into widgets;
- recomputation SHALL NOT introduce new network traffic: the SSE stream stays
  the only source of job state and any local ticker only rebuilds the widget.

#### Scenario: Two chunks done, six to go

- **WHEN** a running job publishes `chunk = 2`, `chunks_total = 8` and
  `started_at` two minutes ago
- **THEN** the job-status screen renders "about 6 min left" (coarse minutes)

#### Scenario: Frames stop arriving

- **WHEN** the last frame is older than 3× the observed per-chunk cadence
- **THEN** the screen drops the number and renders the delayed copy

#### Scenario: A queued job

- **WHEN** the job is `pending`
- **THEN** no ETA line renders at all, even if a stale progress record is
  attached
