<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — scene detail: shooting days as a table with a labelled row menu

## 1. The days section stops collapsing (`lib/features/scenes/scene_detail_screen.dart`)

- [x] 1.1 `_SceneShootingDaysSection` returns a plain `Column` keyed
      `scene-shooting-days-<sceneId>`: section header
      (`sceneDetailShootingDaysTitle`, count kept) + the table card
      (`scene-shooting-day-table`), the schedule button, then the empty-candidate
      explanation. No `SectionCard`, no expand step.
- [x] 1.2 The empty state (`scene-shooting-days-empty`), the schedule button
      (`scene-shooting-day-schedule-<sceneId>`), the empty-candidate block
      (`scene-shooting-day-no-candidates-<sceneId>`) and the quick-create button
      (`scene-shooting-day-create-<sceneId>`) keep their keys.
- [x] 1.3 `lib/design/components/section_card.dart`: the doc comment names the
      days section as the second deliberate non-collapsing exception.

## 2. Table chrome from `ColorScheme` roles only

- [x] 2.1 `_ShootingDayTableHeader` → band (`scene-shooting-day-header-band`) on
      `surfaceContainerHighest`, `onSurfaceVariant` labels
      (`sceneDetailShootingDayColumnDay` / `…ColumnDate`), the body's 4/3 flex and
      the chevron spacer, so the labels sit over their columns.
- [x] 2.2 `_ShootingDayRow` → `Semantics(button, hint)` + `Material` band
      (`surface` / `surfaceContainerLow`) + `InkWell` (row key
      `scene-shooting-day-row-<dayId>`) + `DecoratedBox` hairline in
      `outlineVariant`. Never a `Divider` widget.
- [x] 2.3 Rows are ≥ 48 dp and one tap target; the day label wraps instead of
      ellipsizing; the trailing `chevron_right` is the affordance cue.
- [x] 2.4 The date cell renders `formatMediumDate` under `shootingDayDate`
      (`scene-shooting-day-date-<dayId>`), or `shootingDayNoDate` +
      `event_busy` in `onSurfaceVariant`
      (`scene-shooting-day-date-missing-<dayId>`). An unresolved day renders the
      fallback label and NO date cell.
- [x] 2.5 No `Color(...)` literal and no new DTCG token; `design/tokens/`
      untouched.

## 3. The three actions become a labelled row menu

- [x] 3.1 `_ShootingDayRowMenu` (`showModalBottomSheet` + `ListTile`s) titled
      with the row's own day label; items
      `scene-shooting-day-menu-board-<dayId>`,
      `scene-shooting-day-menu-date-<dayId>`,
      `scene-shooting-day-menu-move-<dayId>`,
      `scene-shooting-day-menu-remove-<dayId>`.
- [x] 3.2 Availability: board and date DISABLED (never absent) without a resolved
      day, move disabled when no candidate exists; remove always available.
- [x] 3.3 Tap and long-press open the same menu; the sheet closes before the
      action's picker or navigation opens.
- [x] 3.4 The date item re-uses `showDatePicker` (`initialDate` = the day's date,
      else today; 2000–2100) + `ShootingDaysController.reschedule` with the day's
      own `version`; a failure shows `shootingDayErrorCopy` in a SnackBar.
- [x] 3.5 Command paths untouched: schedule-then-release ordering, version echo,
      optimistic overlay, bounded-retry reconciliation, AUTHZ-GATE.

## 4. Copy keys (de template + en parity)

- [x] 4.1 Rename `sceneDetailScheduleOnDay` → `sceneDetailAddShootingDay`
      ("Drehtag hinzufügen" / "Add shooting day") and
      `sceneDetailScheduleTitle` → `sceneDetailPickShootingDay` ("Drehtag
      wählen" / "Pick shooting day").
- [x] 4.2 New `sceneDetailShootingDayColumnDay`, `sceneDetailShootingDayColumnDate`,
      `sceneDetailRowActions`, `sceneDetailSetDayDate`, `sceneDetailChangeDayDate`;
      `shootingDayNoDate` is re-used, not duplicated.
- [x] 4.3 `flutter gen-l10n` + the de/en key-parity check green; the regenerated
      `lib/l10n/generated/` is committed.

## 5. Tests

- [x] 5.1 Widget (Tier 2) — `test/features/scenes/scene_detail_screen_test.dart`:
      the days render without an expand step; the button reads "Drehtag
      hinzufügen"; the picker title reads "Drehtag wählen"; the row is one ≥ 48 dp
      tap target; tap and long-press open the same menu; the retired inline keys
      are gone.
- [x] 5.2 New states: date present (formatted, German), date missing
      (`shootingDayNoDate`, never an empty cell), day unresolved (fallback label,
      no date cell, disabled date item), date-chooser happy path (`reschedule`
      called with the picked date and the row's version).
- [x] 5.3 Table chrome in both brightnesses (label band colour, `surface` /
      `surfaceContainerLow` banding, `outlineVariant` border) and
      `find.byType(Divider) == findsNothing` still holds.
- [x] 5.4 Golden (Tier 2): `goldens/scene_detail_screen.png` and
      `goldens/scene_detail_screen_dark.png` re-baselined with the day table.
- [x] 5.5 Gherkin step `whenOpenDayBoard` opens the row menu first (the retired
      `open-day-board-<day>` key); no `.feature` file changes.

## 6. Docs, versioning, verification

- [x] 6.1 `docs/design/screens/scenes.md`: wireframe (days always visible + table
      chrome), the non-collapsing exception, the component table rows and the
      interactions/tests sections.
- [x] 6.2 `pubspec.yaml` 0.4.0-beta.54+146 → 0.4.0-beta.55+147 and a CHANGELOG
      entry under `[Unreleased]`.
- [x] 6.3 `dart format --set-exit-if-changed .`, `flutter analyze`,
      `flutter test`, `openspec validate 903-scene-shooting-days-table-row-menu`,
      `scripts/check-design-diagrams.sh`, `scripts/add-spdx-headers.sh --check`.
