<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# 638-shell-top-bar-redesign — implementation tasks

## 1. Design documentation (before implementation)

- [x] 1.1 Update `docs/design/screens/navigation-shell.md`: two-row top
  bar, Salt wireframes for all three morphologies, component/semantics
  table (pill visibility + per-level colors), status-bar inset
- [x] 1.2 Update `docs/design/glossary.md`: scope-pill rows (unset labels +
  per-level highlight) and the new ARB identifiers in the implemented
  inventory
- [x] 1.3 `scripts/check-design-diagrams.sh` passes

## 2. Localization

- [x] 2.1 Add de/en keys `scopeChipSeasonUnset`, `scopeChipBlockUnset`,
  `scopeChipBlockUnsetTooltip`, `episodeChipUnset`,
  `episodeChipUnsetTooltip`
- [x] 2.2 `flutter gen-l10n`; ARB parity + untranslated report clean

## 3. Scope pills

- [x] 3.1 Add `lib/features/shell/scope_pill.dart`: shared rounded
  `ActionChip` styling (`StadiumBorder`, neutral vs. selected container
  fill, 48dp tap target)
- [x] 3.2 `SeasonScopeChip`: always visible; neutral unset arm
- [x] 3.3 `ActiveScopeChip`: visible when a season is active or a block
  scope is set; neutral unset arm opening the active season's block picker
- [x] 3.4 `ActiveEpisodeChip`: visible when a block scope is set or an
  episode scope is set; neutral unset arm opening the active block's
  episode picker
- [x] 3.5 Per-level selected colors (primary/secondary/tertiary container)

## 4. Shell top bar

- [x] 4.1 Add `lib/features/shell/shell_top_bar.dart`: `SafeArea`-wrapped
  two-row bar; row 1 = profile + pills, row 2 = title + `LocationStrip` +
  search; keys `shell-context-bar`, `shell-scope-bar`, `shell-view-bar`,
  `shell-view-title`
- [x] 4.2 Expose the destination label for the view title from
  `ShellDestinations`
- [x] 4.3 Wire `ShellTopBar` into `AppShell.build` (all three morphologies)
- [x] 4.4 `ShellSearchAction` / `ProfileMenuButton`: optional
  destination-navigator seam; shell passes the active tab's navigator key

## 5. Destination roots lose their app bars

- [x] 5.1 `CastTabScreen`: own toolbar row (switch + categories + fundus),
  no `AppBar`
- [x] 5.2 `ScriptTabScreen` / `ScheduleTabScreen`: no `AppBar`
- [x] 5.3 Update the placement doc comments on the search/profile widgets

## 6. Tests

- [x] 6.1 Widget test: top bar clears the simulated status bar in all
  three morphologies
- [x] 6.2 Widget tests: pill prerequisite visibility arms + per-level
  selected color + unset picker entry
- [x] 6.3 Widget tests: view title + breadcrumb + search row
- [x] 6.4 Update the `shell-context-bar` visibility assertions in
  `app_shell_test.dart` (the bar is never hidden now)
- [x] 6.5 Regenerate the shell goldens (3 morphologies × light/dark)

## 7. Verification

- [x] 7.1 `dart format --set-exit-if-changed .`, `flutter analyze`,
  `flutter test` clean
- [x] 7.2 `tool/breakdown_lints_runner`, `tool/check_inline_copy.sh`,
  `tool/check_glossary_catalog.py` clean
- [x] 7.3 `openspec validate 638-shell-top-bar-redesign --strict` passes
