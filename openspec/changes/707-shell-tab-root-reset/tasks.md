<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->

# 707 — Tasks

## 1. Controller

- [x] 1.1 Add `ShellTabSelection` enum (`switched` / `reTapped` /
      `rejected`) to `shell_controller.dart`.
- [x] 1.2 `selectTab()` returns the selection result: `rejected` for
      out-of-range indices (no state change), `reTapped` when the index
      equals the current selection (no state change), `switched`
      otherwise (index state update as before).
- [x] 1.3 Unit tests in `shell_controller_test.dart`: switch returns
      `switched`, immediate re-tap returns `reTapped`, out-of-range
      returns `rejected` and keeps the previous index.

## 2. Shell

- [x] 2.1 Add `AppShellState._onDestinationSelected`: reject → return;
      switch or re-tap → `popUntil((route) => route.isFirst)` on the
      TARGET tab's navigator (`tabNavigatorKeys[index]`).
- [x] 2.2 Wire `_onDestinationSelected` into all three morphologies'
      `onSelected` callbacks (bar / rail / drawer).
- [x] 2.3 Update the `AppShell` doc comment: per-tab position memory
      (former design D2) is replaced by the root-reset contract
      (issue #707); D3 back contract unchanged.

## 3. Tests (widget)

- [x] 3.1 Migrate "Script drilldown survives a Cast switch": keep the
      within-tab back-pop assertion, then assert the root reset on
      switch-away-and-back (fixture gone after returning to Script).
- [x] 3.2 Migrate "tab switch shows the ACTIVE tab location": switch to
      Script first, push the location, then assert the strip disappears
      after switching away and back (root reset popped it).
- [x] 3.3 New test: re-tap of the active destination pops its navigator
      to root (compact bar).
- [x] 3.4 New test: switch to a destination with a deep stack (pushed
      while another tab was active) shows its root — per morphology
      (compact / medium / expanded).
- [x] 3.5 Update the "destination switch resets nothing" test comment to
      the new root-reset semantics.

## 4. Validation

- [x] 4.1 `dart format --set-exit-if-changed .` clean.
- [x] 4.2 `flutter analyze` clean.
- [x] 4.3 `flutter test` green (shell unit + widget tests).
- [x] 4.4 `openspec validate 707-shell-tab-root-reset` passes.
