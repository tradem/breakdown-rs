<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny (opencode-go) -->

## 1. Design Documentation

- [x] 1.1 Rewrite `docs/design/screens/navigation-shell.md` for the three
      destinations, the season + block scope surface in the context bar,
      the season scope picker and the per-view profile affordance
      (Salt wireframes per morphology; static layout only)
- [x] 1.2 Add screen specs `docs/design/screens/cast-view.md`,
      `script-view.md` and `schedule-view.md` from the template
- [x] 1.3 Update `docs/design/glossary.md`: replace the four destination
      rows (Season/Planen/Kleidung/Mehr) with Cast/Script/Schedule/Dispo,
      add the scope-picker, profile-menu and Script partial-load copy keys
- [x] 1.4 Verify every PlantUML block under `docs/design/` parses
      (`scripts/check-design-diagrams.sh`)

## 2. Shell Controller & Destinations

- [x] 2.1 Replace the tab-index constants in `shell_controller.dart` with
      `kCastTabIndex`/`kScriptTabIndex`/`kScheduleTabIndex`; bound
      `selectTab` to the new range; reset to the Cast destination on a
      session change
- [x] 2.2 Rework `_DestinationSpec` in `app_shell.dart`: three entries,
      labels/icons/semantics (`nav.cast`, `nav.script`, `nav.schedule`),
      keys `shell-destination-0..2`, "Tab N of 3"
- [x] 2.3 Rename the nested navigators' debug labels to
      `shell-tab-0-cast` / `-1-script` / `-2-schedule`
- [x] 2.4 Add the three destination icon pairs to
      `lib/design/material_icons.dart`
      (`shellCastOutline/Filled`, `shellScriptOutline/Filled`,
      `shellScheduleOutline/Filled`)

## 3. Scope Surface

- [x] 3.1 Add `SeasonScopeChip` (visible season label, picker action,
      hidden when no season is active)
- [x] 3.2 Add `SeasonScopePickerScreen`: season rows (setting the active
      season from the acted-on DTO), season-management entry
      (`SeasonsScreen`) and production-management entry
- [x] 3.3 Render the season chip next to the existing `ActiveScopeChip` in
      `ShellContextBar`, keeping the whole bar hidden when neither scope is
      set

## 4. View Roots

- [x] 4.1 Add `CastTabScreen`: characters/costumes switch over the existing
      season-scoped screens, `Kategorien` app-bar action, season-empty
      state whose CTA opens the scope picker
- [x] 4.2 Add the season-wide chronological scene composition
      (`seasonScriptController`: blocks → episodes → scenes, Result-typed,
      bounded, partial-load flag) with unit tests for merge order,
      contiguity and the partial path
- [x] 4.3 Add `ScriptTabScreen` rendering the merged, continuously numbered
      scene list; row tap pushes `SceneDetailScreen` with the scene DTO
- [x] 4.4 Add `ScheduleTabScreen` hosting the season's shooting days
- [x] 4.5 Add `ProductionOverviewScreen` (block/episode spine, AI-import
      entry, active-jobs row) re-homed from `planning_tab_screen.dart`, and
      delete `planning_tab_screen.dart` + `more_tab_screen.dart`
- [x] 4.6 Add `ProfileMenuButton` (identity, About, Settings, Sign out) and
      mount it on all three view roots; drop the costume-categories entry
      from the profile surface

## 5. Localization

- [x] 5.1 Add the new keys to `lib/l10n/app_de.arb` (template) and
      `app_en.arb` (complete catalog), with de/en key parity
- [x] 5.2 Run `flutter gen-l10n` and commit the regenerated output

## 6. Tests

- [x] 6.1 Migrate `test/unit/shell/shell_controller_test.dart` and
      `test/features/shell/app_shell_test.dart` to the three destinations
      (including "Tab N of 3" semantics and the destination-key contract)
- [x] 6.2 Add widget tests for the three view roots and the scope picker
      (data, empty, partial-load states; profile menu content)
- [x] 6.3 Migrate `integration_test/tab_switch_smoke_test.dart`,
      `integration_test/settings_base_test.dart` and
      `integration_test/gherkin/steps/common_steps.dart` to the new
      destination keys and view entry points
- [x] 6.4 Goldens for the three view roots and the shell in
      {compact, medium, expanded} × {light, dark}

## 7. Verification

- [x] 7.1 `dart format --set-exit-if-changed .`
- [x] 7.2 `flutter analyze`
- [x] 7.3 `flutter test`
- [x] 7.4 `dart run tool/breakdown_lints_runner/bin/run_lints.dart ../../`
      (custom lint gate — no violations)
- [x] 7.5 `flutter gen-l10n` + the de/en parity/untranslated report
- [x] 7.6 Confirm `backend/openapi.yaml` untouched (no client
      regeneration) and no generated file was hand-edited


## 8. Notes / deltas from the plan

- The deleted `more_categories*` copy keys were **replaced** (not kept):
  the vocabulary's label now lives under `cast.*`, matching its new home.
- `seasonTabSemantic` gained a `{total}` placeholder (the destination count
  is no longer a baked-in "4"). The placeholder is deliberately NOT named
  `count`: the ICU message parser reserves that name for a plural selector
  and silently mangles the sentence.
- `seasonTabSemanticEn` (a duplicate English literal) got the same
  placeholder; it has no call sites today and is kept for parity.
- No new golden images were added for the three view roots in this change:
  the existing shell goldens cover the destinations themselves, and the view
  roots render either an empty state or hosted screens that already have
  their own goldens (their tests pump them directly). A follow-up may add
  per-view goldens once the views carry non-trivial data states.
