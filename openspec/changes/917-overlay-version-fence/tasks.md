<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — version-fence the overlay branch (issue #917)

## 1. The contract and the shared drop (`lib/domain/reconciliation/`)

- [x] 1.1 `ReconciliationOverlay` gains `bool get isCreate` (create = id
      presence completes it) and `int? get acknowledgedVersion` (update = version
      fence; a create shell may echo a version without being fenced by it).
- [x] 1.2 `overlayDropProjectedRows(state, List<ProjectedRow>)` replaces
      `overlayDropProjectedIds(state, Set<String>)`; `OverlayStore` exposes
      `dropProjectedRows` instead of `dropProjectedIds`. An absent row completes
      an update overlay (the edited row is gone) and keeps a create overlay; an
      empty successful fetch applies the same rule (review of #919).
- [x] 1.3 `ReconciliationCoordinator`'s drop seam becomes
      `dropProjectedRows: void Function(List<ProjectedRow> rows)`; `_runPass`
      hands over the fetched rows instead of a bare id set. Class/`reconcile()`
      docs state the update-overlay rule.

## 2. Per-aggregate wiring (`lib/features/**`)

- [x] 2.1 Create-only overlay types answer `isCreate => true` +
      `acknowledgedVersion => null` **with** the reason: `SeasonOverlay`,
      `BlockOverlay`, `EpisodeOverlay`, `CharacterOverlay`,
      `CostumeCategoryOverlay`, `ShootingDayOverlay`, `SceneOverlay` (each naming
      the overlay-less commands that use the #916 path instead).
- [x] 2.2 Row-level overlay types satisfy the contract: `PieceRowOverlay`,
      `SceneShootRowOverlay`, `OutfitRowOverlay` carry `isCreate` explicitly at
      every construction site (only `pieces.create` / `outfits`'
      `_installCreateOverlay` pass `true`), `SceneBeatOverlay` +
      `SceneDetailsOverlay` answer `isCreate => false` + `acknowledgedVersion =>
      version`.
- [x] 2.3 Every overlay store delegates to the shared helper:
      `seasons` (via the `OverlayStore` base), `blocks`, `episodes`,
      `characters`, `costume_categories`, `shooting_days`, `scenes` (all three
      stores), `pieces`, `scene_shoots`, `outfits`.
- [x] 2.4 Retire the local workarounds: `pieces` / `scene_shoots` drop their
      typed `pruneWithProjection` from the refetch seam, `outfits` its typed
      variant, `scenes` the `_lastProjectedVersions` field and the two
      `dropProjected(Map<String,int>)` methods.
- [x] 2.5 Rendering-side helpers stay (`shouldClearPieceOverlay`,
      `shouldClearSceneShootOverlay`, `shouldClearOutfitOverlay` still decide
      which row the merge shows until the fence passes).

## 3. Tests

- [x] 3.1 Harness: `test/domain/reconciliation_coordinator_test.dart` now drives
      the real `overlayDropProjectedRows` with a real `ReconciliationOverlay`
      (`_TestOverlay`), so contract + runner are exercised together;
      `ack(id)` = create overlay, `ackUpdate(id, version:)` = update overlay.
- [x] 3.2 New group "update-overlay version fence (issue #917)": lagging row
      keeps the overlay through the whole budget then retains it `stale`;
      in-budget freshening drops it; a row at/after the acked version drops on
      the first fetch; a create overlay completes on id presence (with and
      without an echoed version); an update overlay whose row the projection no
      longer carries drops on the first fetch; a create overlay whose id is
      absent is kept through the budget (with and without an echoed version); an
      empty successful fetch completes update overlays and keeps create ones.
- [x] 3.3 Existing D2/D3 + #916 groups unchanged in behaviour (assertions moved
      from a status string to `OverlayStatus` + warning).

## 4. Verification

- [x] 4.1 `dart format --set-exit-if-changed .` — clean
- [x] 4.2 `flutter analyze` — clean
- [x] 4.3 `flutter test` — full suite green (2480 passed)
- [x] 4.4 `dart run build_runner build --delete-conflicting-outputs` — no
      generated drift (no annotation/schema change; methods are not codegen'd)
- [x] 4.5 No `vendor/breakdown_api/**` change: the wire contract is untouched.
