<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-navigation-shell Delta — issue #825

## ADDED Requirements

### Requirement: Season Label Always Leads With the Number

Every season label the shell composes SHALL lead with the season **number**,
mirroring the episode pill's rule (issue #709). A season WITH a name SHALL
render as `{number} · {name}` (ARB `seasonNumberName`); a season WITHOUT a
name — `null`, empty or whitespace-only title — SHALL render as
`Season {number}` (ARB `seasonsDefaultTitle`). The season title SHALL NOT be
composed with a `?? ` fallback alone, because a blank title is a legal wire
value that would render an empty label. The `Season: ` wrapper
(`scopeChipSeason`) SHALL NOT be applied: the season and episode pills share
one shape.

#### Scenario: Named season
- **WHEN** the active season is number 1 with title „Dreharbeiten 2026".
- **THEN** the pill reads „1 · Dreharbeiten 2026" and the number is visible.

#### Scenario: Season without a title
- **WHEN** the active season is number 1 with a `null` title.
- **THEN** the pill reads „Season 1" (the term is not doubled).

#### Scenario: Season with an empty title
- **WHEN** the active season is number 1 whose title is `''` or whitespace
  only.
- **THEN** the pill reads „Season 1" — never a bare prefix and never an empty
  pill.

#### Scenario: Picker rows agree with the pill
- **WHEN** the season scope picker opens from the pill.
- **THEN** every season row uses the same composition as the pill, so a row one
  tap away cannot disagree with the label that opened it.

### Requirement: One Season Label Composition

The season label SHALL be composed in exactly one place
(`seasonDisplayLabel`), used by the season pill and the season picker rows.
A new season label SHALL NOT be built by inlining
`title ?? seasonsDefaultTitle(number)` at a call site.

#### Scenario: A new surface needs a season label
- **WHEN** a surface renders a season's label.
- **THEN** it calls the shared helper instead of re-deriving the fallback, and
  the label keeps the number-first shape.

### Requirement: One Season Wording Per Surface

The shell surface SHALL keep the „Season" wording this change inherits; the
German „Staffel" usage elsewhere SHALL NOT be extended into the shell, and
app-wide unification SHALL be a separate copy decision recorded in
`docs/design/glossary.md`.

#### Scenario: Pill inside the German shell
- **WHEN** the German UI renders the season pill beside „Season wählen".
- **THEN** the pill does not switch to „Staffel", so the row carries one
  wording for the level.
