<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Retry the projection pass when the fetched row lags the acknowledged version

## Why

Issue #916. The shared `ReconciliationCoordinator._runPass` treated an
**overlay-less** refresh as one projection fetch:

```dart
if (!_hasOverlays()) {
  await _refetchProjectedIds();
  return;                       // one fetch, no version check, no retry
}
```

The overlay branch retries within `kMaxReconcileAttempts` because it has a
completion signal — "the projection now carries this id". An overlay-less
command has none: the row is *already* projected, so id presence is true before
the fetch and says nothing about whether the command reached the read model.

`ShootingDaysController._intent` deliberately inserts no overlay (single-intent
day mutations only refresh), so every `reschedule` / `rename` / `reorder` /
`unschedule` took the unretried path. After a successful `reschedule` a lagging
projector therefore left the day on its OLD date **and old `version`**, and the
next command built from that row failed with
`409 concurrency.version-mismatch` although nothing conflicted.

Surfaced by the CodeRabbit review of #915 (the scene detail's date affordance);
pre-existing on the shooting-days screen as well.

## What

- **The seam carries the version.** The refetch callback
  (`refetchProjectedIds`) becomes `refetchProjection` returning
  `List<ProjectedRow>` (`id` + aggregate `version`) instead of a bare id list.
  The runner stays aggregate-agnostic — it still never reads a DTO — but it can
  now ask "does the projection carry this row at this version". Making the
  parameter mandatory (rather than an optional extra callback) lets the
  compiler force every wiring site to state the version its rows carry.
- **`ackReceived({id, version})`.** Overlay-creating commands keep calling it
  with no arguments (unchanged). An overlay-less command passes the acted-on
  row and the aggregate version its 2xx body returned, which records the pending
  acknowledgement.
- **The overlay-less pass is version-gated** (`_runOverlaylessPass`): plan a
  fetch, compare the fetched row's version with the acknowledged one, and
  re-fetch within the SAME `kMaxReconcileAttempts` budget — never a new budget,
  never a wall-clock loop (the injectable `ReconciliationScheduler` drives every
  tick). A row at/after the acknowledged version ends the pass, and so does a
  row the projection no longer carries (archive/delete). A fetch `Err` is not
  evidence of freshness and spends the attempt. On exhaustion the older row the
  last fetch wrote stays in place (Drift keeps it — nothing silently discarded,
  D3) and the acknowledgement is consumed so one lag cannot slow every later
  refresh; the 409 re-read added with #903 stays as the last resort.
- **Late acknowledgements still get a follow-up pass**, now also when no overlay
  exists (an overlay-less ack leaves nothing to poll for). A newer ack that
  arrives mid-pass keeps ownership of the next pass (`_consumeAck` only clears
  the ack it started with).
- **Every wiring site decides** (AC #2):
  - **supply** the version: `shooting_days` (`reschedule`/`rename`/`reorder`/
    `unschedule` + `archive`), `seasons` (archive), `characters` (contact /
    measurements / category corrections), `costume_categories` (rename,
    archive), `scene_shoots` (continuity photo link/unlink);
  - **documented as not lag-capable**: `blocks` and `episodes` (create-only
    command sets → the overlay branch reconciles), `scenes` (every write re-acks
    an overlay), `pieces` (row commands re-ack overlays; the overlay-less photo
    upload/delete belong to the photo aggregate and echo no piece version),
    `scene_shoots.wrap` and `shooting_days.linkInto` (the acknowledged version
    belongs to the DAY aggregate / to two aggregates, so no fetched row of this
    projection could ever match it).
- **Command semantics unchanged** (AC #3): `reschedule` still adds no overlay,
  dispatches no extra command, and echoes the version from the acted-on DTO.

## Out of scope (follow-up)

Update commands that DO insert an overlay (`scenes.updateDetails`,
`pieces.updateNotes`, …) have a sibling gap in the overlay branch: an update
overlay drops on id presence, which is already true, so it is dropped after the
first fetch. Fixing that needs the overlay entries to expose their acknowledged
version to the drop decision. Tracked separately — this change is the
overlay-less half the issue reports.

## Tests (deterministic, no wall clock)

Unit (`test/domain/reconciliation_coordinator_test.dart`): in-budget freshening
swaps the row and its version; a lagging projection spends the whole budget and
retains the stale row; an exhausted ack does not slow later refreshes; a
missing row (archive/delete) ends the pass; a fetch `Err` is not freshness; a
late overlay-less ack gets its own pass; an ack without a version keeps the
single-fetch pass.

Controller (`test/features/shooting_days/shooting_days_flows_test.dart`):
`reschedule` against a stub that keeps serving version 1 spends the budget and
retains the stale row, then a single fetch swaps date **and** version once the
projection catches up.
