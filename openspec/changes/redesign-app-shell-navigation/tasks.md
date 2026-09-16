<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## 1. Screen Spec & Preparation

- [x] 1.1 Create the screen spec `docs/design/screens/
      navigation-shell.md` from the template (nine sections; Salt
      wireframes compact/medium/expanded in the Layout section;
      labels from the glossary)
- [x] 1.2 Check/extend the glossary entries for the four
      destinations (Season, Planen, Kleidung, Mehr — icon, visible
      label, copy key each)

## 2. Shell Controller (Unit Tier)

- [x] 2.1 `lib/features/shell/shell_controller.dart`: `@riverpod`
      `ShellController` with `selectedIndex`, `activeSeason`
      (`SeasonView?`); unit tests for state transitions (tab
      switch, season selection, reset on sign-out) without Flutter
      imports
- [x] 2.2 `activeSeason` persistence analogous to
      `active_block_store` (Drift, TTL-compliant); unit tests for
      the store including the Err branch
- [x] 2.3 Window-size-class helper: `WindowSizeClass` resolution
      (compact/medium/expanded at 600/840dp) as a pure function +
      unit tests

## 3. Adaptive Shell Widgets (Widget Tier)

- [x] 3.1 `AppShell` (ConsumerWidget): switch over WindowSizeClass →
      `NavigationBar` / `NavigationRail` / `NavigationDrawer`; four
      destinations with visible labels + semantic labels (the
      "Season, Tab 1 of 4" pattern)
- [x] 3.2 Tab content: `IndexedStack` with a nested `Navigator` per
      tab (restorable); root screens: Season = SeasonsScreen content,
      Planen = seasons hierarchy entry, Kleidung = costumes/
      characters scope, Mehr = list (AI import, categories, settings,
      sign-out). UPDATED after review (alignment with D8/task 4.3):
      reports are NOT in the Mehr tab — `ReportsScreen` is strictly
      day-scoped and stays anchored in the day board; the Berichte
      entry was dropped during apply (see D8).
- [x] 3.3 Back behavior: inner `maybePop` first; at the tab root
      `PopScope` → app-exit intent (no tab hopping); predictive-back
      compatible
- [x] 3.4 `AuthGate` integration: the shell replaces SeasonsScreen
      as the post-login root; tab index resets on a new session;
      mid-session sign-out returns to the gate (existing listener
      pattern)

## 4. Entry-Point Migration

- [x] 4.1 Planen tab: season row → BlocksScreen → Episodes → Scenes
      pushes run on the Planen tab's navigator (the screens
      themselves unchanged; DTO context rules remain)
- [x] 4.2 Kleidung tab: costumes/characters screens with the
      `activeSeason` scope; empty state when no season is active
      (season-selection CTA); controllers/keys/AUTHZ-GATEs unchanged
- [x] 4.3 Mehr tab: AI import (the AUTHZ-GATE comment moves
      along — `grep AUTHZ-GATE` stays green), costume categories,
      settings/about, sign-out. NOTE (team decision, ask-handshake during
      apply): the planned Berichte entry is OMITTED — `ReportsScreen` is
      strictly day-scoped (`ShootingDayView` DTO) and no season-level
      report surface exists; loading a day context from Mehr would violate
      the CQRS boundary. Reports stay anchored in the day board until a
      season-level reports surface is proposed as its own change.
- [x] 4.4 Remove the season-row icon buttons (`checkroom`/`person`/
      `style`); the season detail receives the context entries
      (Kleidung, categories) as list/card actions with visible labels

## 5. Tests (Tiers 2–4)

- [x] 5.1 Widget tests: three morphologies (`tester.view.
      physicalSize` 360/700/1000dp), label visibility, semantic
      order, touch target size (48dp)
- [x] 5.2 Widget tests: tab state preservation (Planen drilldown →
      Kleidung → back), back behavior (no tab hop), app exit at
      root
- [x] 5.3 Goldens: shell in 3 morphologies × light/dark; re-baseline
      affected existing goldens (one time, in the same PR)
- [x] 5.4 Migrate existing widget tests: icon-key-based tests
      (`open-costume-assignment-*`, `season-characters-*`,
      `season-categories-*`) rewritten to the tab/detail entry
      points
- [x] 5.5 Gherkin: rewire the `costume-assignment` scenario to the
      Kleidung tab path (scenario semantics preserved)
- [x] 5.6 Integration test: tab-switch smoke on device/emulator
      (login → Season tab → Planen drilldown → Kleidung → Mehr)

## 6. Verification & Wrap-up

- [x] 6.1 `flutter analyze` + `breakdown_lints` runner green;
      `dart format --set-exit-if-changed` green
- [x] 6.2 `grep AUTHZ-GATE` verification: all protected entry points
      still carry the GATE comment + membership check
- [x] 6.3 `openspec validate redesign-app-shell-navigation` — change
      valid; update the screen spec if the implementation deviates
      from the wireframe
