<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# 549-reports-discoverability-loaded-goldens — Tasks

## 1. Labelled reports entry (Gap 1)

- [x] 1.1 Replace the `IconButton` in `scene_shoots_screen.dart` with a
      `_ReportsAppBarAction` rendering `TextButton.icon`
      (`Icons.summarize_outlined` + visible label `sceneShootsReportsLabel`);
      key `reports-open` stays on the tap target.
- [x] 1.2 Add the narrow-width collapse: below `_reportsLabelMinBarWidth` the
      action becomes a `PopupMenuButton` whose item is a **labelled**
      `ListTile` (leading icon + label) — never icon-only.
- [x] 1.3 Preserve the `RouteSettings(arguments: locationFromArguments(...))`
      location chain (#548) on the push in both branches.

## 2. Dead Gherkin step (Gap 2, Option A)

- [x] 2.1 Delete `whenOpenSollIstReport()` from `integration_test/gherkin/
      steps/common_steps.dart` (with its `TODO(screen)` comment).
- [x] 2.2 Remove its registration from `integration_test/gherkin/
      configuration.dart`; verify `whenOpenReports()` remains registered and
      unreferenced-step-free via `tool/check_gherkin.sh`.

## 3. Report-provenance empty state (Gap 5, client half)

- [x] 3.1 Add the subtitle to the `scene-shooting-days-empty` `ListTile` in
      `scene_detail_screen.dart` naming the Soll/Ist report as what becomes
      available once the scene is scheduled — no new affordance, no invented
      report, no season-level entry.
- [x] 3.2 Guard: the subtitle renders only when `scheduled.isEmpty`.

## 4. ARB + generated localizations

- [x] 4.1 Add `sceneShootsReportsLabel` and
      `sceneDetailNoShootingDaysReportHint` to `app_de.arb` and `app_en.arb`
      (German template + complete English catalog).
- [x] 4.2 Run `flutter gen-l10n`, commit the regenerated catalogs; de/en
      key-parity green.

## 5. Tests

- [x] 5.1 Widget (day board): the reports entry renders with a **visible
      label** (semantic finder on the label text, never `find.byType`
      alone); `reports-open` present.
- [x] 5.2 Widget (day board, narrow width): the overflow fallback renders and
      its item is **labelled** (still not icon-only); `reports-open` still
      resolves to a tappable target.
- [x] 5.3 Widget (scene detail): the report-provenance empty state on a 0-day
      scene, and its **absence** on a scene that has days.
- [x] 5.4 Goldens: add `loaded_*`, `loaded_final_*`, `loaded_denied_*` across
      `{light,dark} × {android,macos}` (12 files); assert the loaded states
      semantically before the golden comparison.
- [x] 5.5 Regenerate the four `scene_shoots_board_*` goldens (app-bar action
      is wider by the label) and confirm the four `reports_idle_*` goldens
      stay byte-valid.

## 6. Docs / design

- [x] 6.1 Collapse the two `summarize_outlined` rows in
      `docs/design/glossary.md` into one citing `sceneShootsReportsTooltip`
      + `sceneShootsReportsLabel`.
- [x] 6.2 Add both new ARB identifiers to the implemented-inventory table
      (`Hierarchy` row).
- [x] 6.3 `tool/check_glossary_catalog.py` + `scripts/check-design-diagrams.sh`
      green.

## 7. Spec deltas

- [x] 7.1 `flutter-reports-screen`: report-provenance empty-state requirement.
- [x] 7.2 `flutter-scene-shoots-screen`: labelled-entry requirement.

## 8. Validation

- [x] 8.1 `dart format --set-exit-if-changed .` clean
- [x] 8.2 `flutter analyze` clean (incl. the `breakdown_lints` runner)
- [x] 8.3 `flutter test` green; `coverde` threshold on changed code
- [x] 8.4 OpenAPI drift: N/A — `backend/openapi.yaml` untouched; verified
      against the base branch with the merge-base diff.
- [x] 8.5 Gherkin on device (`soll_ist_report.feature`) unchanged and green.

## 9. Follow-ups filed

- [x] 9.1 **#571** — season-/scene-scoped report surface (the deferred
      Option B): a new backend route + aggregation, its own authz decision,
      its own spec delta. Not smuggled into this discoverability fix.
- [x] 9.2 `ShootingDaysScreen` day-row dead end (no `onTap` → the day board,
      and therefore the reports surface, is unreachable from the
      episode-level schedule list) stays deferred to **#548** as the issue
      records: a navigation-graph change on the hierarchy spine, not a label
      change.
