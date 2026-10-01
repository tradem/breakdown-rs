<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks — `PlanningLocation` + context strip + scope chip (issue #548)

## 1. Value object (`lib/features/shell/planning_location.dart`)

- [x] **1.1 Sealed ladder** — `SeasonLocation` / `BlockLocation` /
      `EpisodeLocation` / `SceneLocation` with the `const` factory
      redirecting constructors; each step requires the previous DTO, so a
      non-contiguous chain is not representable.
- [x] **1.2 Label getters** — per-level labels + `segments(l10n)` +
      `semanticsLabel(l10n)`; season-title fallback
      `season.title ?? seasonsDefaultTitle(number)`; `==`/`hashCode`;
      typed deepening (`withBlock` / `withEpisode` / `withScene`).
- [x] **1.3 Route plumbing** — `LocationRouteObserver` (per-tab stack
      bookkeeping) and `locationOf(NavigatorState)` pure function.
- [x] **1.4 Unit tests** — every level, label fallbacks, equality,
      deepening, observer stack (push/pop/remove/replace), empty stack.

## 2. Scope label (`ActiveScope` + store)

- [x] **2.1 `ActiveScope.blockNumber`** — `int?`, from the acted-on
      `BlockView`; `==`/`hashCode` updated; every `set` call site passes it.
- [x] **2.2 Store v2 document** — `{seasonId: {blockId, number}}` values;
      read accepts old bare-string values AND the new object shape;
      `saveScope` writes the new shape.
- [x] **2.3 Gate restore** — `blockScopeResolution` restore/pick/single
      paths carry the block number from the fetched rows.
- [x] **2.4 Unit tests** — old-shape read, new-shape round-trip,
      degradation, gate comparisons re-tested.

## 3. Shell surfaces

- [x] **3.1 `LocationStrip`** — icon + visible text per segment, compact
      max 3 / medium+ max 4 segments, full-path merged semantics node,
      ARB copy only.
- [x] **3.2 `ActiveScopeChip`** — hidden without scope; labelled with a
      scope; foreign-season arm; cache-only backfill of a missing number;
      tap opens the block picker (scope becomes changeable).
- [x] **3.3 `app_shell.dart`** — `ShellContextBar` above the tab content in
      all three morphologies; strip hidden when the topmost route carries
      no location.
- [x] **3.4 Widget tests + goldens** — strip at each level, overflow
      collapse, chip arms, chip tap opens picker, pop updates the strip in
      the same frame, tab switch shows the active tab's location; new
      strip/chip goldens.

## 4. Push-site wiring

- [x] **4.1** `planning_tab_screen.dart:_openSeason` → `season` level.
- [x] **4.2** `blocks_screen.dart` → `block` level.
- [x] **4.3** `episodes_screen.dart` → `episode` level (Scenes + ShootingDays).
- [x] **4.4** `scenes_screen.dart` → `scene` level (SceneDetail).
- [x] **4.5** `scene_detail_screen.dart` → scene level (SceneShoots day board).
- [x] **4.6** Season-direct entries (`CostumesScreen`, `CharactersScreen`,
      `CharacterDetailScreen`, `CostumeCategoriesScreen`) → season level only.

## 5. Design docs & spec

- [x] **5.1** `docs/design/screens/README.md`: `## Location & Context`
      section after `## Navigation`, worked example updated.
- [x] **5.2** `docs/design/glossary.md`: strip segments, `Location strip`,
      `Scope chip`, `Scope chip unknown`; `categories.icon` rule extended
      to context segments.
- [x] **5.3** Spec delta `MODIFIED` on
      `flutter-hierarchy-navigation` → `Requirement: Hierarchy Navigation
      Spine` (incl. extended Back-navigation scenario).

## 6. Validation

- [x] **6.1** `flutter gen-l10n`, de/en ARB parity, glossary catalog check.
- [x] **6.2** `dart format`, `flutter analyze`, `flutter test` green;
      goldens regenerated only where affected.
