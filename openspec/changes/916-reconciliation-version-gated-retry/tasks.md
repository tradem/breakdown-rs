<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — retry the projection pass on the acknowledged version (issue #916)

## 1. The seam carries the version (`lib/domain/reconciliation/reconcile_coordinator.dart`)

- [x] 1.1 Add `ProjectedRow` (`id` + aggregate `version`) and switch the refetch
      seam from `refetchProjectedIds: Future<List<String>?>` to
      `refetchProjection: Future<List<ProjectedRow>?>` (mandatory — the compiler
      forces every wiring site to state the version). The overlay branch keeps
      dropping by id (`rows.map((row) => row.id)`).
- [x] 1.2 Extend `ackReceived({String? id, int? version})`: an overlay-less
      command records the acted-on row + acknowledged version; overlay-creating
      commands keep calling it with no arguments.
- [x] 1.3 `_runOverlaylessPass`: version comparison + retries inside the
      existing `kMaxReconcileAttempts` budget via the injected scheduler; a
      missing row (archive/delete) ends the pass; a fetch `Err` spends the
      attempt; exhaustion retains the last fetched row and consumes the ack.
- [x] 1.4 `_consumeAck` clears only the acknowledgement the pass started with, so
      a newer ack keeps ownership; `_runWithFollowUp` also chains a follow-up for
      an overlay-less ack (nothing left to poll for).
- [x] 1.5 Update the class/`reconcile()` docs to state the overlay-less rule.

## 2. Wiring sites (`lib/features/**/*_controller.dart`)

- [x] 2.1 Map every refetch closure to `ProjectedRow(id: x.id, version:
      x.version)` (`seasons`, `blocks`, `episodes`, `scenes`, `characters`,
      `costume_categories`, `scene_shoots`, `pieces`, `shooting_days`).
- [x] 2.2 Supply the acknowledgement version where an overlay-less command
      echoes its own row's version: `shooting_days` (`_intent` →
      reschedule/rename/reorder/unschedule, plus `archive`), `seasons` (archive),
      `characters` (contact / measurements / category), `costume_categories`
      (rename, archive), `scene_shoots` (link/unlink continuity photo).
- [x] 2.3 Document why each remaining site cannot lag: `blocks` + `episodes`
      (create-only), `scenes` (every write re-acks an overlay), `pieces` (row
      commands re-ack overlays; photo upload/delete echo no piece version),
      `scene_shoots.wrap` (day aggregate version, not the shoot row's),
      `shooting_days.linkInto` (two aggregates, no echoed version).
- [x] 2.4 `reschedule` semantics unchanged: no overlay, no extra command, version
      echo from the acted-on DTO.
- [x] 2.5 `scenes` drops its `List<SceneView> _lastProjectedRows` capture in
      favour of the version map the seam now already provides
      (`_lastProjectedVersions`).

## 3. Tests

- [x] 3.1 `test/domain/reconciliation_coordinator_test.dart`: rewrite the harness
      onto `ProjectedRow` + a scripted snapshot sequence; add the overlay-less
      group (in-budget freshening, budget-spent retention, no slow-down for later
      refreshes, missing row, fetch `Err`, late ack follow-up, ack without a
      version).
- [x] 3.2 `test/features/shooting_days/shooting_days_flows_test.dart`: a
      controller-level `reschedule` test — budget spent while the stub keeps
      serving version 1 (stale date + version retained), then one fetch swaps
      date and version once the projection catches up.
- [x] 3.3 Fix the fixtures that modelled a projection which never advances its
      version (`costume_categories` controller + screen archive flows now carry
      version 2; `scene_shoots` link/unlink start from an already-acked version
      and drain the manual scheduler where the pass legitimately parks).

## 4. Verification

- [x] 4.1 `dart format --set-exit-if-changed .`
- [x] 4.2 `flutter analyze` — clean
- [x] 4.3 `flutter test` — full suite green
- [x] 4.4 No generated artefact touched (no `vendor/breakdown_api/**`, no
      `*.g.dart`): the change is hand-written Dart only.
