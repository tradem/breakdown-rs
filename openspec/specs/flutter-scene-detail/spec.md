<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-scene-detail Specification

## Purpose
TBD - created by archiving change 902-scene-cast-table-row-menu. Update Purpose after archive.
## Requirements
### Requirement: The cast table is always visible

The scene detail SHALL render the cast as page CONTENT: a plain section header
that keeps both counts (`sceneDetailCastTitle`, „Figuren {characters} · Looks
{looks}") followed by the table, with **no** expand step and no `SectionCard`
wrapper. A cold open SHALL show the figures and their looks. `SectionCard`
SHALL remain the component for the sections that legitimately collapse (the
shooting days).

#### Scenario: A cold open shows the cast

- **WHEN** the scene detail renders for a scene with one assigned figure
- **THEN** the cast row is in the tree without any tap
- **AND** the section header still carries both counts
- **AND** the cast section has no `ExpansionTile`

### Requirement: Table chrome comes from ColorScheme roles

The cast table SHALL draw its structure only from `ColorScheme` roles — no
`Color(...)` literal and no new design token: a label band on
`surfaceContainerHighest` with `onSurfaceVariant` text, zebra rows alternating
`surface` / `surfaceContainerLow`, and a row separator as a `DecoratedBox`
border in `outlineVariant`. The separator SHALL NOT be a `Divider` widget
(issue #834's no-divider rule governs *section* chrome and stays in force). The
body and the label band SHALL share one column flex and one horizontal inset,
so the look column starts at the same x as its label at every width.

#### Scenario: The table reads as a table in both brightnesses

- **WHEN** the cast table renders under the light OR the dark `ThemeData`
- **THEN** the label band's colour is the scheme's `surfaceContainerHighest`
- **AND** the first row is banded `surface` and the second `surfaceContainerLow`
- **AND** each row carries an `outlineVariant` bottom border
- **AND** the widget tree contains no `Divider`

### Requirement: A cast row is one accessible tap target opening a labelled menu

A cast row SHALL be ONE tap target of at least 48 dp that opens the row's
context menu on tap **and** on long-press. It SHALL announce
`Semantics(button: true, hint: <row actions>)` and carry a decorative trailing
`chevron_right` as the affordance cue. Nothing in the table SHALL be icon-only:
every action is a `ListTile` with a visible label. A look label that does not fit
SHALL wrap to a second line instead of ellipsizing.

#### Scenario: The row is a button with a cue

- **WHEN** the cast row renders
- **THEN** its height is at least 48 dp
- **AND** its semantics node is a button with the localized row-action hint
- **AND** it contains no `IconButton`
- **AND** it shows the chevron cue

#### Scenario: Tap and long-press open the same menu

- **WHEN** the user taps OR long-presses the row
- **THEN** the same labelled action sheet opens

### Requirement: The menu offers only the actions valid for that row

The row menu SHALL render labelled items in this order and availability:

- **Bearbeiten** (`edit_outlined`) — on the figure's FIRST row only; it SHALL be
  rendered DISABLED, never absent, when no `SeasonView` resolves. It pushes the
  Cast screen (unchanged navigation).
- **Look zuweisen** / **+ Lookwechsel** (`add`) — on every row of the figure; the
  label follows whether the figure already has a look.
- **Look entfernen** (`delete_outline`) — only on a row that carries a beat, and
  it removes THAT row's beat (through the existing confirm dialog).
- **Figur entfernen** (`person_remove_outlined`) — only on the figure's first row
  (through the existing confirm dialog).

#### Scenario: A figure without a look offers the fix, not a dead end

- **WHEN** the menu opens for a figure the scene casts without a look
- **THEN** the add-look item reads „Look zuweisen"
- **AND** no remove-look item is offered

#### Scenario: A change step offers no figure-level action

- **WHEN** the menu opens for a figure's change-step row
- **THEN** neither Bearbeiten nor Figur entfernen is offered
- **AND** Look entfernen targets that row's own beat

#### Scenario: Bearbeiten is disabled without a season row

- **WHEN** no `SeasonView` resolves for the section
- **THEN** the Bearbeiten item is present and disabled

### Requirement: The row menu changes presentation only

Moving the actions into the row menu SHALL NOT change any command path: the
confirm-first dialogs, the scene version echo, the optimistic overlay with
bounded-retry reconciliation, the client-side AUTHZ-GATE and the localized
per-`code` error mapping SHALL stay exactly as they are. The reconciling and the
exhausted (stale/cloud-off) status rows SHALL still render, below the table.

#### Scenario: A removal still confirms first

- **WHEN** the user picks „Look entfernen" or „Figur entfernen"
- **THEN** the existing confirm dialog opens before any dispatch
- **AND** the confirming action dispatches the unchanged command

#### Scenario: The status row stays below the table

- **WHEN** an optimistic beat overlay is reconciling or has gone stale
- **THEN** the status row renders below the cast table, not inside a row

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

### Requirement: The scene detail plans before it casts

The scene detail body SHALL order its sections **workflow-first**: identity
block, synopsis, then the shooting days, then the cast. The shooting days SHALL
render above the cast because a scene is planned before it is cast and the dispo
is built from the days, not from the looks.

Every day affordance SHALL be reachable from that section as an ICON on the row
it acts on (day board, move to another day, unschedule) plus the labelled
schedule action below the list. The "move to another day" action SHALL schedule
the newly picked day **first** and unschedule the current one **only after that
acknowledgement**, chained on the version the API returned — a refused schedule
SHALL leave the scene on the day it had, and a refused release SHALL leave it on
both days (two visible, individually removable rows), never on none.

#### Scenario: The days section precedes the cast

- **WHEN** the scene detail renders for a scene with one planned day and one figure
- **THEN** the shooting-days card appears above the cast card in the scroll order

#### Scenario: Moving a scene to another day releases the old one last

- **WHEN** the reviewer picks "move to another day" on a planned row and chooses a second day
- **THEN** the scene is scheduled on the second day first, and the first day is
  unscheduled only after that command was acknowledged

#### Scenario: A refused move keeps the planned day

- **WHEN** the schedule command is refused (e.g. `concurrency.version-mismatch`)
- **THEN** no unschedule is dispatched and the scene keeps the day it had

#### Scenario: A refused release leaves both days visible

- **WHEN** the schedule succeeded but the unschedule of the previous day is refused
- **THEN** the scene is shown on both days, each row removable, and the refusal is
  reported with its stable problem `code`

### Requirement: The script day binds to a real shooting day

The identity block's script-day chip SHALL carry the affordance that binds the
day the SCRIPT states (`SceneView.scriptDay`, e.g. „Tag 1") to a **real** shooting
day of the episode, opening the same day picker the section uses. The affordance
SHALL be disabled exactly when no candidate day exists (the episode has none, all
are archived, or the scene already sits on the only one), and it SHALL NOT
fabricate a day, a date or an association the server does not hold.

#### Scenario: Binding the script day

- **WHEN** the scene states "Tag 1" and the episode has a real day that is not on the scene
- **THEN** the chip's icon opens the day picker and scheduling the picked day binds it

#### Scenario: Nothing to bind

- **WHEN** every day of the episode is already planned on this scene
- **THEN** the chip's icon is disabled

### Requirement: Figure and look share one table row

The scene detail SHALL render ONE expandable cast section, titled with both
counts (`Figuren ({characters}) · Looks ({looks})`), instead of separate figures
and looks sections: the reader SHALL NOT have to join two lists by hand.

Each row SHALL show the figure and the look it wears in this scene in the **same**
row, with column labels, the look's category icon, the wardrobe cue and the
change arrow (`→`) for a figure's further looks. A figure with several looks
SHALL render one row per look so each look stays individually removable, and a
figure without a look SHALL state that in the look cell and offer the look
affordance there.

Per row the reviewer SHALL be able to remove the look, remove the figure, add a
look, or edit — where editing opens the Cast screen (the character detail, with
the season row resolved cache-first) and returning refreshes the scene so a
renamed or removed look no longer renders its old label.

The section SHALL offer one bottom action, „Figur und Look zuweisen", which picks
an unassigned figure and then opens that figure's look picker: two commands in
the aggregate's order, because a beat needs an assigned character. A cancelled
look picker SHALL leave the figure cast (a role without a costume is a real
state) and SHALL NOT roll the assignment back. When the figure has no look yet,
the flow SHALL say so instead of opening an empty picker.

#### Scenario: One row names the figure and its look

- **WHEN** a scene casts one figure wearing one look
- **THEN** a single row shows the figure's name, the look's label and the look's
  category icon, and the section header names both counts

#### Scenario: A figure with a change renders one row per look

- **WHEN** a figure wears look A and then look B in the same scene
- **THEN** the figure is named once, and each look has its own row (the second
  prefixed with `→`) with its own removal

#### Scenario: The combined assign action casts and dresses

- **WHEN** the reviewer taps „Figur und Look zuweisen" and picks an unassigned figure
- **THEN** the character is assigned to the scene and its look picker opens

#### Scenario: Editing opens the Cast screen

- **WHEN** the reviewer taps the edit icon of a cast row
- **THEN** the Cast screen for that figure is pushed, and returning refreshes the
  scene projection

### Requirement: Mood icons render for mixed location shorthands

The mood resolver SHALL resolve every location component of the set shorthand
(one location icon per component, in the shorthand's own order) plus the
time-of-day icon, so a MIXED shorthand such as `A/I/T` ("shot outside at the
street, then inside the clinic / day") renders the same icons the import preview
shows for the simple shorthands — never plain text.

A shorthand naming exactly the two distinct locations `I` and `A` in either order
(`I/A/*`, `A/I/*`) SHALL resolve to ONE threshold icon, because the scene crosses
the door — one fact, not two. The editor's canonical chip set SHALL additionally
offer the `A/I/*` forms (which the deterministic heading scan never produces but
a script states verbatim); a stored value outside the canonical set keeps
rendering as its own chip and is never destroyed.

#### Scenario: A mixed mood renders icons

- **WHEN** a scene carries the mood `A/I/T`
- **THEN** the header renders the threshold icon and the day icon next to the
  visible `A/I/T` label

#### Scenario: An unparsable mood stays text

- **WHEN** the mood is free text such as "tense"
- **THEN** no icons render and the label stays visible

