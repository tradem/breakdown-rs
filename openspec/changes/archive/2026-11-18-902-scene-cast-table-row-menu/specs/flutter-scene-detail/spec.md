<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-scene-detail

## ADDED Requirements

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
