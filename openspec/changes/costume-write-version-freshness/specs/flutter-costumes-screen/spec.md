<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# flutter-costumes-screen Delta (issue #473 — costume write version freshness)

## ADDED Requirements

### Requirement: Costume writes echo the freshest known aggregate version
Every `CostumesController` write command (`updateNotes`, `addDetail`,
`assign`, `unassign`, and both legs of the `_reassign` sequence) SHALL resolve
the `AggregateVersion` it submits from the freshest known state at dispatch
time — a held overlay's ack version first, else the reconciled projection
row, else the screen-passed fallback — and MUST NOT trust the screen-captured
`CostumeView` snapshot's `version` when fresher state is known. Consecutive
writes to the same costume therefore advance `version` with each ack; the
result of one command is echoed by the next. The resolution SHALL be
performed by `CostumeController._resolveVersion` for every write.

#### Scenario: Second save to the same costume succeeds
- **WHEN** a user saves costume notes (version N acked, aggregate → N+1) and
  then saves notes again on the same screen.
- **THEN** the second request carries version N+1 (the first ack) and the
  backend answers 200 — never a `422 domain.validation` version-mismatch loop.

#### Scenario: A stale screen snapshot cannot regress the echoed version
- **WHEN** a write is dispatched with a `CostumeView` snapshot whose version
  is behind the acknowledged version (re-opened cached state, or a reconcile
  refetch that never fed back into the view object the editor holds).
- **THEN** the wire request still carries the freshest known version (the
  held overlay's ack), not the snapshot's stale version.

#### Scenario: Projection fresher than the snapshot wins
- **WHEN** the reconciled projection row reports a version higher than the
  screen-passed snapshot (another client advanced the aggregate).
- **THEN** the write echoes the projection's higher version.

### Requirement: Version-mismatch errors surface a pull-to-refresh narrative
A costume command failing with the optimistic-concurrency problem codes
(`concurrency.version-mismatch`, `costume.version_conflict`) SHALL render a
distinct, actionable "pull to refresh and try again" narrative via
`costumeErrorCopy` — not the generic conflict copy. The generic
`domain.validation` 422 SHALL NOT be blanket-mapped to this narrative,
because it also covers non-concurrency validation failures.

#### Scenario: 409 version-mismatch renders distinct copy
- **WHEN** a costume command returns 409 `concurrency.version-mismatch`.
- **THEN** the screen shows "Changed elsewhere — pull to refresh and try
  again." instead of the generic conflict copy.
