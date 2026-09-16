<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Why

The app has no shell: after login the user lands on `SeasonsScreen`
and navigates via a deep `Navigator.push()` stack — every screen its
own `Scaffold`, no bottom/rail navigation, no way to switch between
"planning" and "costuming" without popping the whole stack. The
UI/UX research report identified this — together with icon-only
entries — as the app's primary information-design problem (worse than
its visual polish). Team decision 1 fixed the target: **four tabs —
Season, Planen, Kleidung, Mehr** — with Material 3 adaptive navigation
(NavigationBar → NavigationRail → NavigationDrawer by window size
class).

## What Changes

- Introduce an app shell below `AuthGate`: an adaptive
  `NavigationShell` widget replacing `SeasonsScreen` as the
  post-login root, hosting four destinations:
  **Season** (home: current seasons overview), **Planen**
  (hierarchy Season→Block→Episode→Scene), **Kleidung**
  (costume domains scoped to the active season), **Mehr**
  (reports, AI import, costume categories, settings, sign-out).
- Adaptive navigation per M3 window size classes: compact
  (<600dp) `NavigationBar`, medium (600–839dp) `NavigationRail`,
  expanded (≥840dp) permanent `NavigationDrawer`; implemented with
  Flutter primitives and window-size breakpoints (no new routing
  package — decision documented in design.md; go_router stays
  forbidden).
- Every destination renders **visible labels** (no icon-only
  navigation: glossary rule from `establish-design-doc-workflow`).
- Season-tile trailing icon buttons (`checkroom`, `person`, `style`)
  are **removed**; their targets become first-class tabs/detail
  routes (M1 migration list in design.md).
- Per-tab nested `Navigator` (or IndexedStack — decided in design.md)
  preserves each tab's position/filters when switching tabs; system
  back never hops tabs, it pops within the tab first, then exits
  (Android predictive-back compatible).
- AUTHZ-GATE discipline and login-gate behavior (`AuthGate`, splash,
  login rules) remain unchanged — the shell renders only for a
  resolved authenticated session.

## Capabilities

### New Capabilities
- `flutter-navigation-shell`: adaptive four-tab app shell, label
  rules, per-tab navigation state, and the migration of existing
  push flows into it.

### Modified Capabilities
- `flutter-hierarchy-navigation`: the Hierarchy Navigation Spine
  requirement changes context — hierarchy pushes now happen inside
  the Planen tab hosted by the shell (still plain `Navigator.push`,
  still no new routing package), and system back/parent-return
  behavior contracts to the shell.

## Impact

- **Code:** `lib/app.dart` (AuthGate renders shell instead of
  SeasonsScreen), new `lib/features/shell/` (or `lib/shell/` — per
  design.md) with shell controller + navigation suite widgets;
  `lib/features/seasons/seasons_screen.dart` (icon buttons removed,
  becomes home tab content); screens currently reachable only via
  those icons get new entry points (Kleidung tab, Mehr tab,
  season detail).
- **Tests:** existing widget tests touching season-tile icon keys
  (e.g. `open-costume-assignment-<id>`, `season-characters-<id>`) are
  updated/rewired to the new tab entry points; goldens re-baselined.
- **Runtime deps:** none added (Material adaptive widgets +
  MediaQuery breakpoints only).
- **Sequence:** depends on `add-dtcg-design-tokens` (shell consumes
  tokens from day one) and benefits from
  `establish-design-doc-workflow` (screen specs for the shell).
