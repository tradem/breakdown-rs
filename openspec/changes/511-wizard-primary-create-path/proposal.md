<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# Guided Season Setup as the Primary Creation Path

## Why

Issue [#511](https://github.com/tradem/breakdown-rs/issues/511): season
creation has two paths — the setup wizard
(`lib/features/seasons/setup/setup_wizard_screen.dart`) and the
quick-create sheet (`create_season_sheet.dart`) — but the wizard is
only reachable from the guided empty state, so for every user who
already has a season the manual sheet is effectively the primary
path. The manual sheet additionally exposes `series_id` as an editable
text field: an internal UUID that must never be user-editable, and
whose only correct value is the env-sourced default series
(`--dart-define=DEFAULT_SERIES_ID`).

## What Changes

- The seasons-home extended FAB opens the **setup wizard** and is
  relabeled to the guided copy ("Season-Setup starten", rocket icon) so
  the primary action reads as guided — reachable whether or not seasons
  already exist.
- Manual create moves to a **secondary app-bar action** ("Manuell") that
  opens the same quick-create sheet (the inverse of today's prominence).
  The sheet loses its now-redundant "start guided setup" cross-link.
- The editable `series_id` field is **removed** from the manual form;
  the sheet derives the series from the active build config. When the
  build carries no default series, the form fails fast with the same
  actionable copy the wizard's pre-dispatch guard shows, instead of
  dispatching a request the backend can only reject blindly.
- Localization: the wizard's missing-`DEFAULT_SERIES_ID` copy is
  consolidated into one shared catalog key used by both create paths;
  the `series_id` label/required and wizard-cross-link keys are removed
  as dead entries.
- Design documentation (`seasons-home.md`, `season-setup-wizard.md`,
  glossary) and the Gherkin wizard entry step follow the new paths;
  widget tests and the seasons goldens are updated/re-baselined.

## Scope and Constraints

- No backend/OpenAPI change; `vendor/breakdown_api/` stays untouched.
- The wizard's own behavior (steps, abort semantics, dispatch sequence,
  AUTHZ-GATE) is unchanged — this change only re-ranks the entry points
  and removes one field.
- The series id is **derived**, never asked for: no second projection
  lookup is introduced on the create path (CQRS boundary).
- Both entries stay behind the same authenticated-session client gate
  (auth-only create); the wizard keeps its per-command repository gates.

## Acceptance Criteria

- [ ] The FAB opens `SetupWizardScreen` and carries the guided copy/icon;
      the empty state keeps its own setup CTA.
- [ ] Manual create is reachable from an app-bar "Manuell" action in
      both the empty and populated states, and is gone from the FAB path.
- [ ] The manual form renders no `series_id` input; the submitted command
      uses the build-config series id.
- [ ] A build without a default series id fails fast with localized copy
      and issues no network request (both create paths).
- [ ] The wizard's season → block dispatch and the CostumeAssistant
      hand-off keep working (existing wizard + integration tests green).
- [ ] Screen specs, glossary and Gherkin steps match the new entry points;
      design diagrams compile.
- [ ] Widget tests cover both entry points and the removed field; goldens
      re-baselined; `dart format`, `flutter analyze`, `flutter test` pass.

## Tasks

1. Re-point the seasons-home FAB at the wizard and add the secondary
   "Manuell" app-bar action.
2. Remove the `series_id` field and the wizard cross-link from the manual
   sheet; derive the series id and add the fail-fast guard.
3. Update the ARB catalogs (shared missing-series-id copy, guided FAB
   label, manual entry label) and regenerate `lib/l10n/generated/`.
4. Update `seasons-home.md`, `season-setup-wizard.md` and the glossary.
5. Update the Gherkin wizard entry step and the on-device integration test.
6. Update widget tests, re-baseline the seasons goldens, run the
   Flutter verification suite.
