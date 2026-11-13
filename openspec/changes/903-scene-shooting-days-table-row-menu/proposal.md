<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Scene detail — shooting days as a table, with a labelled row menu and a real date chooser

## Why

Issue #903 is the second half of the same scene-detail review that produced
#902 (the cast table). Five findings on the shooting-days section (German UI):

1. **Three affordances, one picker, no distinction.** The script-day chip, the
   section button "Auf Drehtag planen" and the row icon `swap_horiz` all open
   the SAME sheet (`_pickDayAndSchedule`), and the sheet's title repeated the
   button's copy — so all three *look* like "plan the scene on a day". Two of
   them were byte-identical calls with the same icon.
2. **The label states an intent the backend does not have.** `scheduleScene`
   APPENDS to `SceneView.shootingDayIds`; it never "plans on *the* day".
   Meanwhile "Drehtag anlegen" creates the day aggregate itself. Two different
   aggregate operations, two words apart.
3. **The row's only payload is unformatted and silently absent.** The subtitle
   rendered `shootingDayDate('${day.date}')`, i.e. Dart's ISO `toString()`
   ("Datum: 2026-09-14") under the very copy key that
   `shooting_days_widgets.dart` renders LOCALIZED. And a script-imported day
   carries no date, so the row often rendered a title and nothing else — no
   signal, no hint, and `shootingDayNoDate` ("Noch kein Datum") existed and was
   unused here. The fix (a date chooser) already existed, but only on the
   shooting-days screen: the user had to leave the scene, find the day and come
   back.
4. **Three inline `IconButton`s ate the payload width.** 3 × 48 dp of a
   320–360 dp row before the `ListTile` inset — the "actions squeeze the
   information column" finding #902 documents for the cast row, and icon-only,
   which the visible-label norm tolerates only as reinforcement.
5. **No table chrome, and dark mode made it worse.** No column header, no row
   band, no column axis: "Datum" was a subtitle only some rows had. In dark
   mode the card surface is nearly the page surface, so the section read as
   floating text. The section was also collapsed by default, hiding the first
   operational fact of a planned scene.

## What changes (frontend only)

**1. The button's copy says what it does.** `sceneDetailScheduleOnDay` →
`sceneDetailAddShootingDay` ("Drehtag hinzufügen" / "Add shooting day"). The
picker's title becomes NEUTRAL over its three entry points —
`sceneDetailScheduleTitle` → `sceneDetailPickShootingDay` ("Drehtag wählen" /
"Pick shooting day") — and drops its inline `TextStyle` for a theme role.
`sceneDetailCreateFirstDay` ("Drehtag anlegen") stays untouched and distinct.

**2. The row's per-row action is the DATE, re-using what exists.** A menu item
opens the same `showDatePicker` the shooting-days screen uses (`initialDate` =
the day's date, else today; `firstDate` 2000, `lastDate` 2100) and dispatches
the existing `ShootingDaysController.reschedule` with the day's own `version`.
No new endpoint, provider, controller method or wire change.

**3. The date cell renders a localized date — or says it is missing.** With a
date: `formatMediumDate(context, date.toDateTime())` under the existing
`shootingDayDate` key, exactly like the shooting-days screen. Without one:
`shootingDayNoDate` in `onSurfaceVariant` plus an `event_busy` glyph, so the
row STATES that the assignment is missing and the menu item next to it is the
fix. A day that did not resolve renders the fallback label and NO date cell
(its date is unknown, not "none yet") and disables the date item.

**4. All three actions move into a labelled row menu.** Tap (or long-press) the
row → `showModalBottomSheet` with labelled `ListTile`s, in this order:
**Day-Board öffnen** (`view_agenda_outlined`, disabled without a day),
**Datum festlegen / Datum ändern** (`edit_calendar`, disabled without a day),
**Auf anderen Drehtag umhängen** (`swap_horiz`, disabled when no candidate
exists), **Termin entfernen** (`event_busy`, the unchanged `_unschedule`). The
row is ONE tap target of at least 48 dp with `Semantics(button: true, hint: …)`
and a trailing `chevron_right` — a menu with no cue is a hidden affordance.

**5. The section reads as a table, in both schemes, from theme roles only.**
The same treatment #902 prescribes for the cast table, so both tables share one
look: a label band (`Drehtag` / `Datum`) on `surfaceContainerHighest` with
`onSurfaceVariant` labels and the body's 4/3 flex plus the chevron spacer;
zebra rows alternating `surface` / `surfaceContainerLow` with an
`outlineVariant` hairline drawn as a `DecoratedBox` border — never a `Divider`
widget; the day label wraps to a second line instead of ellipsizing. No
hardcoded colour, no new DTCG token.

**6. The section is visible by default.** `Drehtage (n)` is the first
operational fact of the scene (#834 orders it first), so the `SectionCard`
wrapper and its expand step are dropped: plain section header + table, matching
the #902 cast section. `SectionCard` itself is NOT deleted — it stays the
component for sections that legitimately collapse.

## Reconciling with the #834 "no divider chrome" rule

Restated, not broken: #834 rejected the `ExpansionTile`'s own **section** chrome.
An intra-table row separator is **table** chrome, and it is a `DecoratedBox`
border, never a `Divider` widget — so the existing
`find.byType(Divider) == findsNothing` assertion stays green and still means what
it meant. `docs/design/screens/scenes.md` gains the days section's
non-collapsing exception next to the cast one.

## Stable keys, so the delta stays small

- **Unchanged**: `scene-shooting-days-<sceneId>` (section),
  `scene-shooting-day-<dayId>` (row identity, now on the label cell),
  `scene-shooting-day-schedule-<sceneId>` (button — identity unchanged, only the
  label), `scene-shooting-day-no-candidates-<sceneId>`,
  `scene-shooting-day-create-<sceneId>`, `scene-shooting-days-empty`,
  `schedule-day-<dayId>` (picker), `scene-script-day-assign-<sceneId>`.
- **Retired** (now menu items): `open-day-board-<dayId>`,
  `scene-shooting-day-move-<dayId>`, `scene-shooting-day-unschedule-<dayId>`.
- **New**: `scene-shooting-days-title`, `scene-shooting-day-table`,
  `scene-shooting-day-header-band`, `scene-shooting-day-column-day`,
  `scene-shooting-day-column-date`, `scene-shooting-day-row-<dayId>` (tap
  target), `scene-shooting-day-menu-<dayId>` (sheet), the items
  `scene-shooting-day-menu-board-<dayId>`,
  `scene-shooting-day-menu-date-<dayId>`,
  `scene-shooting-day-menu-move-<dayId>`,
  `scene-shooting-day-menu-remove-<dayId>`, and the date cell
  `scene-shooting-day-date-<dayId>` / `scene-shooting-day-date-missing-<dayId>`.

## The one Gherkin step that touches the retired key

The issue assumed no Gherkin step reaches this section; that is not true at
HEAD. `integration_test/gherkin/steps/common_steps.dart::whenOpenDayBoard` taps
`open-day-board-<day>` and backs nine steps in
`continuity_photo_capture.feature`, `soll_ist_execution.feature` and
`soll_ist_report.feature` (all `@pending`). It now opens the row menu first and
taps the board item — and, because the section no longer collapses, needs no
expand step.

## Deviation from the issue text (one)

The issue asks the date chooser to "then refresh the scene projection". The row's
date cell is fed by the DAYS projection, and `ShootingDaysController._intent`
already refreshes it on every ack; a scene refresh would dispatch a request whose
result this row does not read. So the date path refreshes nothing extra, and a
failure surfaces as the localized `shootingDayErrorCopy` in a SnackBar — the same
shape `_unschedule` uses on this screen.

## Non-goals

- No backend, contract or `backend/openapi.yaml` change; no
  `vendor/breakdown_api/` regeneration.
- No change to which commands are dispatched, their version echo, their
  AUTHZ-GATE or their error copy.
- Not the cast section (#902), not the synopsis, not the scene list, not the
  shooting-days screen — the date picker body is re-used, not moved.
- No new Riverpod provider: the menu is local widget state, the commands keep
  their controllers, the day projection keeps coming from
  `shootingDaysViewProvider`.
- No new design tokens; `ColorScheme` roles only.

## Impact

Frontend only: `lib/features/scenes/scene_detail_screen.dart` (the days section,
the table header, the row, the row menu, the re-used date-chooser helper),
`lib/design/components/section_card.dart` (one doc-comment sentence),
`lib/l10n/app_de.arb` + `app_en.arb` (two renames, five new keys) with
regenerated `lib/l10n/generated/`, `pubspec.yaml` + `CHANGELOG.md`, the widget
tests and both scene-detail goldens (light and dark), the one Gherkin step, and
`docs/design/screens/scenes.md`.

## Related

- **#902** — the cast half of the same review; it settled the per-row contract
  this section follows (tap → labelled menu, long-press as the same trigger) and
  the table chrome the two tables now share.
- **#834** — merged the scene detail sections, ordered shooting days first,
  introduced `SectionCard` and the "no divider chrome" rule.
- **#669** — "Auf Drehtag planen" permanently disabled; source of the
  empty-candidate explanation.
- **#549** — the visible-label norm the menu items satisfy better than the icon
  row.
- **#374 / #372** — the reschedule/unschedule wire bodies the date chooser
  re-uses.
