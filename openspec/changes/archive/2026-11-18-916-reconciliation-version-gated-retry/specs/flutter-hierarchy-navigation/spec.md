<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-hierarchy-navigation

## ADDED Requirements

### Requirement: Overlay-less Commands Reconcile on the Acknowledged Version

A command that inserts **no** optimistic overlay (a single-intent update such as
a shooting-day `reschedule` / `rename` / `reorder` / `unschedule`, a character
contact/measurements/category correction, a costume-category rename, a
continuity-photo link/unlink, or an archive) SHALL NOT reconcile by projection
id presence: the row is already projected, so id presence is true before the
fetch and carries no information about whether the command reached the read
model.

Such a command SHALL record the acted-on row and the aggregate version its 2xx
body returned, and the shared reconciliation runner SHALL compare that
acknowledged version with the version of the freshly fetched row:

- a fetched version at or after the acknowledged one ends the pass;
- a row the projection no longer carries (archive/delete) ends the pass;
- a fetched version *older* than the acknowledged one SHALL be retried within
  the SAME `kMaxReconcileAttempts` budget, driven by the injectable
  `ReconciliationScheduler` — never a new budget, never a wall-clock loop.

On exhaustion the older row the last fetch wrote SHALL be retained as-is (no
silent discard, no fabricated row) and the acknowledgement SHALL be consumed so
a single lag cannot slow every later refresh. The command's own semantics MUST
stay unchanged: no optimistic overlay, no extra command dispatch, and the
version echo still comes from the acted-on DTO.

The refetch seam SHALL carry the version (`ProjectedRow`: id + aggregate
version) so every wiring site states which version its projection rows carry.
A wiring site whose command set cannot lag MUST say so at the wiring
(create-only command set → the overlay branch reconciles; commands whose
acknowledged version belongs to another aggregate or to two aggregates → no
fetched row of this projection could match it).

#### Scenario: The projector lags a reschedule

- **GIVEN** a shooting day projected at version 1 with date A
- **WHEN** `reschedule` is acknowledged with version 2 and the projection still
  serves the day at version 1
- **THEN** the pass refetches up to `kMaxReconcileAttempts` times, waiting on
  the injected scheduler between attempts
- **AND** the stale row (date A, version 1) stays in place — no overlay, no
  fabricated row, no dropped row
- **AND** no new retry budget and no wall-clock delay are introduced

#### Scenario: The projection catches up inside the budget

- **WHEN** an attempt returns the row at the acknowledged version (or higher)
- **THEN** the pass ends immediately, without spending the remaining attempts
- **AND** the projected row shows the new value AND its new `version`

#### Scenario: A row the command removed from the projection

- **WHEN** an archive is acknowledged and the projection no longer carries the
  row
- **THEN** the pass ends after that fetch (absence is caught up, not lag)

#### Scenario: A failed fetch is not freshness

- **WHEN** an attempt fails (`Err`, no rows)
- **THEN** the attempt is spent and the next one asks again — a failure never
  ends the pass as if the projection were current

#### Scenario: A second command is acknowledged mid-pass

- **WHEN** a later overlay-less acknowledgement arrives while a pass is in
  flight
- **THEN** a dedicated follow-up pass runs for it
- **AND** the finishing pass does not clear the newer acknowledgement
