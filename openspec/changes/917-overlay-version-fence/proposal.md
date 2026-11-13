<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Version-fence the overlay branch of the shared reconciliation runner

## Why

Issue #917 — the sibling gap of #916, on the **overlay** branch of
`ReconciliationCoordinator._runPass`:

```dart
final rows = await _refetchProjection();
if (rows != null) {
  _dropProjectedIds(rows.map((row) => row.id).toSet());
}
if (!_hasOverlays()) return;
```

For a **create** overlay this is correct: the id appears in the projection only
once the create reached the read model, so id presence is a real completion
signal. For an **update** overlay it is not: the row is projected from the
start, so id presence is true *before* the fetch and says nothing about whether
the command reached the read model. The overlay was therefore dropped on attempt
0 and the screen fell back to the stale projected row — old value **and** old
`version`, which then becomes the echo of the next command.

Three aggregates already worked around this locally (`pieces`,
`scene_shoots`, `outfits`, each pruning with a typed, version-fenced helper
inside its own refetch seam), and `scenes` carried a mutable
`_lastProjectedVersions` field in the controller to feed its beat/details
drop. The **shared contract** knew nothing about it: `ReconciliationOverlay`
exposed only `id`, so a new aggregate — or a new overlay on an existing one —
regressed to the id-presence drop silently. That is the defect this change
closes.

## What

- **The contract carries the version.** `ReconciliationOverlay` gains
  `int? get acknowledgedVersion`. `null` explicitly means *"id presence IS the
  completion signal"* (a create overlay: its optimistic fields are display-only
  form values, not an aggregate version); a version means *"the fetched row must
  reach this version"* (an update overlay). Every implementation states which of
  the two it is, with the reason at the declaration.
- **One generic, version-aware drop.** `overlayDropProjectedRows(state, rows)`
  replaces `overlayDropProjectedIds(state, ids)` (rows are `ProjectedRow`, so
  the seam that already carried `id` + `version` since #916 is reused — no new
  type, no new callback). `OverlayStore.dropProjectedRows` and every
  per-aggregate store delegate to it, so no aggregate can implement the fence
  differently.
- **The runner hands over the rows.** The coordinator's `dropProjectedIds:
  (Set<String>)` seam becomes `dropProjectedRows: (List<ProjectedRow>)`. The
  runner stays aggregate-agnostic (it still never reads a DTO and still never
  decides for a store), but it can no longer reduce the fetched rows to ids
  before anyone gets to compare versions.
- **The local workarounds collapse into it.** `pieces` and `scene_shoots` drop
  their typed `pruneWithProjection` (called inside the refetch seam) and
  `outfits` its typed variant, in favour of the shared drop; `scenes` drops the
  `_lastProjectedVersions` field and the `Map`-based `dropProjected` on its beat
  and details stores. Their version-fenced helpers
  (`shouldClearPieceOverlay`, `shouldClearSceneShootOverlay`,
  `shouldClearOutfitOverlay`) stay where they are still needed — in the
  *rendering* merge, which decides which row is shown until the fence passes.
- **Every overlay type answers the question** (issue criteria 3): the six
  create-only types return `null` with the documented reason (and name the
  overlay-less commands that reconcile on the #916 path instead); the four
  row-level types (`SceneBeatOverlay`, `SceneDetailsOverlay`,
  `PieceRowOverlay`, `SceneShootRowOverlay`, `OutfitRowOverlay`) record their
  acknowledged version as before and now satisfy the contract.

## Out of scope

- The retry budget, the overlay-less #916 path, and the `AsyncValue` shape are
  unchanged.
- No wire change (`backend/openapi.yaml` untouched, no client regeneration), no
  Drift schema change, no user-visible copy change — the fix restores the
  optimistic value the user already saw after a 2xx.

## Tests (deterministic, no wall clock)

`test/domain/reconciliation_coordinator_test.dart`: the harness now drives the
**real** generic drop through a real `ReconciliationOverlay`, so the contract and
the runner are exercised together. New group for issue #917: a lagging update
overlay keeps the overlay through the whole `kMaxReconcileAttempts` budget and is
retained `stale` (never discarded); an in-budget freshening drops it; a row
already at the acknowledged version drops on the first fetch; a create overlay
still completes on id presence; a row the projection does not carry keeps the
overlay.
