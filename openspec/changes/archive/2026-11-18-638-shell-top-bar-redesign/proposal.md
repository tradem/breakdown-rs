<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# 638 — Shell top bar: status-bar safe area, scope pills, profile + title/search

## Why

The three-view shell (issue #610) renders a `ShellContextBar` as the first
child of the shell `Scaffold` body, and the shell has **no `appBar`**. On
Android the body therefore starts at `y = 0` and the bar is drawn *under*
the system status bar (clock / battery / notification row) — a visible
overlap in every morphology. The scope chips are plain `ActionChip`s, not
the rounded, color-coded segmented pills the PO asked for, and the profile
affordance plus the view title/search are scattered across three
destination-root app bars (issue #613 placed them there as an interim;
#613 is closed and the final top-bar composition was still open).

Issue #638 fixes all three: a sticky, status-bar-safe top bar whose first
row carries the profile affordance and the Spotify-style scope pills, and
whose second row carries the view title, the hierarchy breadcrumb and the
search affordance.

## What Changes

- **Status-bar safe area:** the shell's top bar is inset by the
  `MediaQuery` view padding in all three morphologies (compact bottom nav,
  medium rail, expanded drawer). Nothing renders under the Android status
  bar.
- **Sticky two-row top bar owned by the shell:** row 1 = profile affordance
  (left) + Season · Block · Episode scope pills; row 2 = view title +
  hierarchy breadcrumb (`LocationStrip`) + search affordance. The
  destination roots lose their own app bars — the shell's view bar carries
  the title and the search entry (the three destination roots are no longer
  app-bar owners). The Cast view's costume-category and fundus actions move
  into the Cast view's own toolbar (they are costume-domain content and stay
  with the costume content, never with the user settings).
- **Spotify-style scope pills with prerequisite-aware visibility:** the
  three scope levels render as fully rounded pills. The season pill is
  always present (it is the only affordance that can set a season); the
  block pill appears once a season is active; the episode pill appears once
  a block is scoped. An unset level renders a neutral "… wählen" pill that
  opens its picker; a set level is filled with its own container color
  (season → primary, block → secondary, episode → tertiary) so the three
  levels are visually distinguishable. The existing tap-to-open-picker
  semantics, chip keys and the unknown-block / foreign-season narratives are
  preserved.
- **Search and profile placement:** both move from the destination-root app
  bars into the shell top bar; the search affordance still opens inside the
  active destination's nested navigator.
- **Design documentation first:** `docs/design/screens/navigation-shell.md`
  is updated (three Salt morphologies + component/semantics table) before
  the implementation, per the design-doc workflow
  (`frontend-flutter/AGENTS.md` §11).

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `flutter-navigation-shell`: the "Season and Block Scope Surface"
  requirement becomes a three-level, prerequisite-aware scope pill surface
  with per-level color highlights in the shell's first top-bar row; the
  "Per-View Profile Affordance" requirement becomes a single shell-owned
  profile action (the per-destination-root app bar is gone); the
  "Task-Oriented View Content" requirement moves the Cast view's
  costume-category action from its app bar into the Cast view's own toolbar;
  a new requirement fixes the status-bar inset and the sticky two-row
  layout. (The `flutter-navigation-shell` capability is authored by the
  still-unarchived `three-view-navigation-shell` change; this change refines
  it in place.)

## Impact

- **Code (frontend only):** new `lib/features/shell/shell_top_bar.dart` and
  `lib/features/shell/scope_pill.dart`; changes to
  `lib/features/shell/app_shell.dart` (top bar wiring),
  `season_scope_chip.dart` / `active_scope_chip.dart` /
  `active_episode_chip.dart` (pill styling + prerequisite visibility),
  `cast_tab_screen.dart` (toolbar instead of app bar),
  `script_tab_screen.dart` / `schedule_tab_screen.dart` (no app bar),
  `search_action_button.dart` / `profile_menu_button.dart` (shell placement
  + navigator seam).
- **No backend/API changes** (`backend/openapi.yaml` untouched → no Dart
  client regeneration, no drift-check run).
- **Docs:** `docs/design/screens/navigation-shell.md` (layout + components),
  `docs/design/glossary.md` (pill rows + the three new unset-pill ARB keys
  in the implemented inventory).
- **Testing:** widget tests for the status-bar inset, the pill visibility
  arms and per-level colors, the title/breadcrumb/search row; regenerated
  shell goldens for all three morphologies × light/dark.
