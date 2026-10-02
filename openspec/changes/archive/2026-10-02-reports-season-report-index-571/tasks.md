<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

## 1. Navigation context (season id)

- [x] 1.1 Add a required named `seasonId` parameter to
      `ShootingDaysScreen` (`lib/features/shooting_days/shooting_days_screen.dart`),
      documented as nav context only — no projection lookup, no active-season read
- [x] 1.2 Pass `block.seasonId` into `ShootingDaysScreen` at the single call
      site in `lib/features/episodes/episodes_screen.dart` (the same field
      `ScenesScreen` already receives on the adjacent push)
- [x] 1.3 Verify the compiler enumerates no other call site; a silently
      defaulted season id is a failure of this task, not a convenience

## 2. Localization

- [x] 2.1 Add the new copy keys to `lib/l10n/app_de.arb` and `lib/l10n/app_en.arb`:
      `shootingDaysReportsLabel` (`Berichte`), `reportsIndexTitle`
      (`Berichte – {episode}`), `reportsIndexDayFinal` (`Abschließend`),
      `reportsIndexDayOpen` (`Offen`), `reportsIndexEmpty` (names the Soll/Ist
      report as what becomes available once a shooting day is planned)
- [x] 2.2 Regenerate the localizations (`flutter gen-l10n`); the generated
      output is rebuild-only, never hand-edited
- [x] 2.3 Confirm no key collides with the existing `reportsFinal`
      (`Abschließend – dieser Tag ist abgeschlossen.`) — the index chip is a
      short state, the report banner is a full sentence, and they stay
      distinct keys

## 3. Index controller and state

- [x] 3.1 Add `reports_index_state.dart`: an `ReportsIndexRow` carrying the
      `ShootingDayView` plus its derived per-day finality, and a
      `ReportsIndexScreenState` carrying the rows, the stale flag and the
      gate `ProblemError?`
- [x] 3.2 Derive per-day finality from `ShootingDayView.wrapped_at` in one
      place (present → `abschließend`, `null` → `offen`); no client-side
      recomputation and no aggregate verdict anywhere in the state shape
- [x] 3.3 Add `reports_index_controller.dart`: a `@riverpod` family provider
      that **watches** `shootingDaysControllerProvider(episodeId)` and
      projects its `ProjectedShootingDayRow`s into index rows — zero HTTP
      requests, no new Drift table, no new repository
- [x] 3.4 Exclude `OptimisticShootingDayRow`s from the index (an unprojected
      day carries no server-derived `wrapped_at`) and surface the day list's
      stale/pending indicator instead
- [x] 3.5 Carry the episode- and season-scoped scope through the provider
      family (episode id for the day list, season id for the gate) so the
      index never needs a second read to fill in context

## 4. Index screen

- [x] 4.1 Add `reports_index_screen.dart` as a `ConsumerWidget` container
      rendering `asyncValue.when`, following the seasons reference pattern
- [x] 4.2 Render one row per day in the day list's server order
      (`order_key ASC`, never re-sorted client-side) with label, date and
      the per-day finality chip
- [x] 4.3 Make each row a single tap target pushing the existing
      `ReportsScreen` with `ReportDayScope(dayId, seasonId)` — no report
      content rendered on the index, no new report fetch
- [x] 4.4 Add pure presentation widgets under
      `lib/features/reports/widgets/` (no Riverpod imports) for the row and
      the finality chip, taking plain data and callbacks
- [x] 4.5 Render the empty state (`reportsIndexEmpty`) when the projected
      day list is empty and no fetch is failing; offer no report affordance
      for a day-less scope
- [x] 4.6 Render the error state keyed on the stable problem `code`, keeping
      cached rows visible and stale-indicated on a failed refresh, with
      pull-to-refresh delegating to the shared day-list controller

## 5. Authz pre-check

- [x] 5.1 Evaluate the existing gate (`currentMembershipProvider(seasonId)` →
      `canViewReports`) on the index and render the localized 403 narrative
      with **zero** requests on denial (`report.forbidden`; `membership.pending`
      / `membership.unavailable` while unresolved)
- [x] 5.2 Follow the backend-computed `has_active_costume_role_in_season`
      flag only — an unknown capability string never enables the gate
- [x] 5.3 Add a test asserting a denied membership issues no day-list
      refresh and no report fetch from the index

## 6. Entry in the spine

- [x] 6.1 Add the labelled reports action to `ShootingDaysScreen`'s app bar,
      carrying the Gherkin contract key `reportsIndexOpen` on its tap target
- [x] 6.2 Follow #549's adaptive pattern: `TextButton.icon` with the visible
      label `Berichte`, collapsing into a **labelled** overflow-menu item at
      narrow widths, never a bare icon, with the width decision taken from a
      `LayoutBuilder` breakpoint (not a platform check)
- [x] 6.3 Keep `ShootingDayTile`'s action set unchanged — no tap target added
      to a row that already carries rename, reschedule, unschedule, archive
      and move
- [x] 6.4 Wire the action to push `ReportsIndexScreen` with the episode and
      the threaded season id

## 7. Tests

- [x] 7.1 Widget tests for the index: rows render from state in server order;
      a row tap pushes `ReportsScreen` with the right `ReportDayScope`; no
      report content appears on the index
- [x] 7.2 Widget tests for the per-day finality chip (wrapped → `abschließend`,
      open → `offen`) and for the absence of any aggregate verdict on a
      mixed wrapped/open list
- [x] 7.3 Widget tests for the empty state and for the pending (optimistic)
      day being absent from the index
- [x] 7.4 Golden tests for the index across the established
      `{light,dark} × {android,macos}` matrix: idle, loaded, denied — the
      same matrix #549 extended for the report screen
- [x] 7.5 Widget tests for the app-bar entry at both widths: the labelled
      `TextButton.icon` and the labelled overflow item, with
      `reportsIndexOpen` resolving as the tap target in both

## 8. Gherkin (tier 3)

- [x] 8.1 Add a scenario to `features-spec/soll_ist_report.feature` covering
      season → block → episode → reports index → per-day report
- [x] 8.2 Reinstate the step #549 deleted (`whenOpenSollIstReport()`, tapping
      `Key('open-soll-ist-report-$seasonId')`) against a key that now exists,
      and re-register it in `integration_test/gherkin/configuration.dart`
- [x] 8.3 Add the index step (tapping `reportsIndexOpen`) and register it;
      keep the existing `whenOpenReports()` (`reports-open`) untouched
- [x] 8.4 Match the surrounding `@pending` tag treatment and the designated
      critical-flow framing of the file — removing `@pending` is a separate
      decision about the seeded on-device backend flow, not part of this change

## 9. Docs and guards

- [x] 9.1 Update `docs/design/screens/navigation-shell.md` (the D8 note at
      line 84) to describe the episode-level index alongside the day-board anchor
- [x] 9.2 Add a `docs/design/glossary.md` row for the new entry, using the
      real copy key — no duplicate rows, per #549's fix
- [x] 9.3 Run `flutter analyze` and the client lint runner; no `discard-result`
      suppression without a justification comment
- [x] 9.4 Confirm the diff touches no backend file, no `openapi.yaml`, and no
      `vendor/breakdown_api/` file — the contract-drift job must stay green
