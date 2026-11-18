<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: Costume writes echo the freshest known aggregate version (issue #473)

## Why

Consecutive costume writes to the same aggregate fail: the first write (e.g.
`PATCH /v1/costumes/{id}/notes`) returns 200 and advances the aggregate
version N → N+1, but the **next** write to the same costume echoes the stale
pre-ack version N and is rejected with `422 domain.validation` (the server's
optimistic-concurrency guard, correct per contract — the backend is not at
fault). Live evidence (2026-09-21): a notes edit produced `200 → 422 →
422` on successive saves.

Root cause: `CostumesController.updateNotes` / `addDetail` (and the assign /
unassign family) build their wire requests with `version = costume.version`
taken verbatim from the `CostumeView` snapshot the calling screen passes in.
That snapshot can lag the acknowledged state — the editor re-opened cached
state, or the reconcile refetch result never fed back into the view object
the editor holds. The command must resolve the version from the freshest
state the controller knows at dispatch time, never from the screen-captured
snapshot.

## What Changes

- **`lib/features/costumes/costumes_controller.dart`**: new private
  `_resolveVersion(costumeId, fallback)` — resolves the freshest known
  aggregate version at command time from (1) a held overlay's version (this
  client's latest ack, above any lagging projection), (2) the reconciled
  projection row from `costumesViewProvider`, else (3) the screen-passed
  fallback. Applied to **every** costume write: `updateNotes`, `addDetail`,
  `assign`, `unassign`, and both legs of the `_reassign` sequence.
- **`costumeErrorCopy`**: `concurrency.version-mismatch` (409) and the
  `costume.version_conflict` alias now render a distinct, actionable
  pull-to-refresh narrative instead of generic copy (requirement #3, ties
  into the #467/#470 error-copy tranche).
- **Second-edit regression tests** (requirement #2): save notes → save
  notes again echoes the ack version (200, no silent 422 loop); cross-command
  variant (save then add-detail); a controller-level stale-snapshot test
  proving a captured `CostumeView` at v1 still echoes the overlay ack v2; and
  a 409 `concurrency.version-mismatch` copy test.

## Capabilities

### New Capabilities
- `flutter-costumes-screen`: captures the costume detail/screen write path
  contract — notably the core rule this change fixes: every costume write
  resolves the echoed aggregate version from freshest-known state at command
  time, never from a screen-captured snapshot.

### Modified Capabilities
<!-- none — no existing spec requirement changes -->

## Impact

- `frontend-flutter` (one package): controller behavior + tests only; no new
  dependency, no generated-file change, no `backend/openapi.yaml` change.
- Version bumped `0.3.0-alpha.14+23` → `0.3.0-alpha.15+24` (ADR-033 per-PR
  bump convention, #362).
