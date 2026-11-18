<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-scene-detail

## ADDED Requirements

### Requirement: The shooting-days table is always visible

The scene detail SHALL render the scheduled shooting days as page CONTENT: a
plain section header that keeps the count (`sceneDetailShootingDaysTitle`,
„Drehtage ({count})") followed by the table, with **no** expand step and no
`SectionCard` wrapper — matching the cast table (issue #902). `SectionCard`
SHALL remain the shared component for sections that legitimately collapse.

#### Scenario: A cold open shows the days

- **WHEN** the scene detail renders for a scene scheduled on one day
- **THEN** the day row is in the tree without any tap
- **AND** the section header still carries the count
- **AND** the days section has no `ExpansionTile`

### Requirement: The shooting-day table draws its chrome from ColorScheme roles

The table SHALL draw its structure only from `ColorScheme` roles — no
`Color(...)` literal and no new design token: a label band on
`surfaceContainerHighest` with `onSurfaceVariant` labels („Drehtag" / „Datum"),
zebra rows alternating `surface` / `surfaceContainerLow`, and a row separator as
a `DecoratedBox` border in `outlineVariant`. The separator SHALL NOT be a
`Divider` widget (issue #834's no-divider rule governs *section* chrome). Body
and label band SHALL share one column flex (4/3) plus the chevron spacer, so the
date column starts at the same x as its label. A day label that does not fit
SHALL wrap instead of ellipsizing.

#### Scenario: The table reads as a table in both brightnesses

- **WHEN** the day table renders under the light OR the dark `ThemeData`
- **THEN** the label band's colour is the scheme's `surfaceContainerHighest`
- **AND** the first row is banded `surface` and the second `surfaceContainerLow`
- **AND** each row carries an `outlineVariant` bottom border
- **AND** the widget tree contains no `Divider`

### Requirement: A shooting-day row states its date honestly

The row's date cell SHALL render the day's date LOCALIZED
(`formatMediumDate`, under the existing `shootingDayDate` key) — never Dart's ISO
`toString()`. When the day carries no date, the cell SHALL SAY so with
`shootingDayNoDate` in `onSurfaceVariant` plus an `event_busy` glyph. A day the
episode projection did not resolve SHALL render the fallback label and NO date
cell (its date is unknown, not "none yet").

#### Scenario: A date renders in the active locale

- **WHEN** a scheduled day carries the date 2026-09-14
- **THEN** the date cell shows the German medium date
- **AND** it does not show the raw ISO string

#### Scenario: A date-less day says so

- **WHEN** a scheduled day carries no date
- **THEN** the date cell shows „Noch kein Datum"
- **AND** the date menu item is enabled (the fix sits next to the state)

#### Scenario: An unresolved day invents no date

- **WHEN** the row's day is not in the episode projection
- **THEN** the day cell shows the fallback label
- **AND** no date cell is rendered
- **AND** the board and date menu items are DISABLED, never absent

### Requirement: A shooting-day row is one accessible tap target opening a labelled menu

A row SHALL be ONE tap target of at least 48 dp that opens the row's context menu
on tap **and** on long-press. It SHALL announce `Semantics(button: true, hint:
<row actions>)` and carry a decorative trailing `chevron_right`. Nothing in the
table SHALL be icon-only: every action is a `ListTile` with a visible label. The
sheet SHALL close before the action's picker or navigation opens.

#### Scenario: The row is a button with a cue

- **WHEN** the day row renders
- **THEN** its height is at least 48 dp
- **AND** its semantics node is a button with the localized row-action hint
- **AND** it contains no `IconButton`

#### Scenario: Tap and long-press open the same menu

- **WHEN** the user taps OR long-presses the row
- **THEN** the same labelled action sheet opens

### Requirement: The menu offers the four day actions with real availability

The row menu SHALL render labelled items in this order: **Day-Board öffnen**
(`view_agenda_outlined`), **Datum festlegen** / **Datum ändern**
(`edit_calendar`), **Auf anderen Drehtag umhängen** (`swap_horiz`), **Termin
entfernen** (`event_busy`). Board and date SHALL be rendered DISABLED (never
absent) when the day did not resolve; the move item DISABLED when no other
eligible day exists; the remove item always available.

#### Scenario: No other day to move to

- **WHEN** every other day is archived or already scheduled on this scene
- **THEN** the move item is present and disabled
- **AND** the empty-candidate explanation still renders below the table

#### Scenario: The date item labels what it does

- **WHEN** the day carries no date
- **THEN** the item reads „Datum festlegen"
- **WHEN** the day carries a date
- **THEN** the item reads „Datum ändern"

### Requirement: The date item re-uses the existing reschedule command

The menu's date item SHALL open `showDatePicker` seeded with the day's date
(else today, bounds 2000–2100) and dispatch
`ShootingDaysController.reschedule` with the day's own `version`. It SHALL add no
endpoint, provider, controller method or wire field. A failure SHALL surface the
localized `shootingDayErrorCopy` in a SnackBar, never a silent discard.

#### Scenario: Picking a date dispatches one reschedule

- **WHEN** the user opens the date item and picks 2026-09-14
- **THEN** exactly one `reschedule` is dispatched
- **AND** it echoes the day's current `version`

### Requirement: The rename says the button adds a day

The section's schedule button SHALL read „Drehtag hinzufügen" /
`sceneDetailAddShootingDay` (the command APPENDS the scene to a day), and the day
picker's title SHALL be neutral over its three entry points —
`sceneDetailPickShootingDay` („Drehtag wählen"), rendered as a theme role rather
than an inline `TextStyle`. `sceneDetailCreateFirstDay` („Drehtag anlegen")
SHALL stay distinct and untouched.

#### Scenario: The picker is not one of its entry points

- **WHEN** the day picker opens from the section button, a row's move item or the
  script-day chip
- **THEN** its title reads „Drehtag wählen"
- **AND** the button that opened it reads „Drehtag hinzufügen"
