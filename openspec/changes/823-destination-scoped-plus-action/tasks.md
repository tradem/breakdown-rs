<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — issue #823

## 1. Shared affordance

- [x] 1.1 `lib/design/components/plus_action_fab.dart` — the extended FAB with
      the explicit BUTTON semantics role, caller-supplied test key and visible
      label; `kPlusActionFabBottomClearance` (the 80 dp band) moves here from
      `app_shell.dart`, because two surfaces now need it.
- [x] 1.2 `lib/features/shell/quick_create_sheet.dart` — `aiImportQuickCreateAction`
      (the shared Import row) + `aiImportJobsQuickCreateActions` (the one-entry
      list); `shellQuickCreateActions` builds its Import row from the same
      helper.

## 2. Shell: destination scoping

- [x] 2.1 `app_shell.dart` — `showsPlusAction = canCreate && selectedIndex ==
      kScriptTabIndex`; the FAB renders through `PlusActionFab`; Cast/Schedule
      get `null`.
- [x] 2.2 `app_shell.dart` — `bottomClearance: showsPlusAction ? … : 0`, plus a
      keyed `shell-plus-fab-clearance` band so the dead-band presence is
      assertable (the M3 NavigationBar has its own 80 dp `SizedBox`).
- [x] 2.3 AUTHZ-GATE comment restated for the destination scope (session gate
      unchanged: pending/erroring/signed-out renders nothing).

## 3. AI-import jobs screen

- [x] 3.1 `jobs_screen.dart` — its own plus action (`ai-jobs-plus-fab`, label
      `navAiImport`), one-entry sheet, push on the root navigator, with its own
      AUTHZ-GATE comment.
- [x] 3.2 `jobs_screen.dart` — reserve the 80 dp band below the content in every
      list state (one `Padding` at the body seam, all four states).
- [x] 3.3 `jobs_screen.dart` — drop the empty-state CTA (`ai-jobs-empty-cta`) and
      the now-unused `AiImportSubmitScreen` import; the FAB is the screen's
      single create path.
- [x] 3.4 `lib/l10n/app_{de,en}.arb` — remove `aiJobsEmptyCta` (no new copy
      keys: the FAB label and entry copy already exist) + `flutter gen-l10n`.

## 4. Tests

- [x] 4.1 `app_shell_test.dart` 5.4 — role/label, morphologies, "no action on
      Cast/Schedule", sheet-opens, entry routing, session gate and the
      foreign-scope guard all select the Script destination explicitly.
- [x] 4.2 `app_shell_test.dart` — new dead-band test (`shell-plus-fab-clearance`
      present on Script only).
- [x] 4.3 `jobs_screen_test.dart` — Import action (label + button role), the
      one-entry sheet, the root-navigator push, and the session gate; the
      empty-state test now asserts the narrative and the ABSENCE of the CTA.
- [x] 4.4 `quick_create_sheet_test.dart` — the jobs list has one entry, it IS the
      shell's Import row (key/icon/copy/target), and its sheet renders only that
      row.
- [x] 4.5 Re-baseline the 15 affected goldens (7 shell + 8 jobs) and inspect
      them: no FAB and no dead band on Cast/Schedule; the Import FAB renders
      bottom-trailing above the reserved band.

## 5. Docs

- [x] 5.1 `docs/design/screens/navigation-shell.md` — the plus action as a
      destination-scoped affordance (component row, interactions, test list,
      layout note).
- [x] 5.2 `docs/design/screens/ai-import-jobs.md` — the Import action (navigation,
      wireframes with and without rows, component row, states, interactions,
      tests), and the dropped empty-state CTA.
- [x] 5.3 `docs/design/screens/script-view.md` — the plus action as this
      destination's create entry.
- [x] 5.4 `docs/design/glossary.md` — the `add` row split into the two surfaces
      („Erstellen\" / „Import\"), the shared Import entry row, and
      `aiJobsEmptyCta` removed from the key list.
- [x] 5.5 `scripts/check-design-diagrams.sh` passes.

## 6. Verification

- [x] 6.1 `dart format --set-exit-if-changed .` clean.
- [x] 6.2 `flutter analyze` clean.
- [x] 6.3 `dart run bin/run_lints.dart` (breakdown_lints_runner) — no violations.
- [x] 6.4 `bash tool/check_inline_copy.sh` — no new user-facing literals.
- [x] 6.5 `flutter gen-l10n` re-run; de/en ARB parity holds.
- [x] 6.6 `flutter test` — full suite green.

## Follow-ups (not this change)

- [ ] Decide whether a pushed detail screen inside the Script destination should
      hide the destination-level plus action (navigation design question, #638
      territory; it can no longer leak into Cast/Schedule).
