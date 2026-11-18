<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-seasons-home Delta — issue #840

## ADDED Requirements

### Requirement: Every Season Label Uses the Shared Composition

Every surface that renders a season label SHALL compose it through
`seasonDisplayLabel(l10n, number:, title:)` — the season pill and its picker,
the production overview, the location strip, the seasons cards (projected and
optimistic), the blocks AppBar and its reports entry, the fundus chips and
repertoire rows, and the piece detail's repertoire rows and picker. A call
site SHALL NOT derive the label itself with `title ?? <number-only key>`.

The number SHALL lead on every one of those surfaces (`{number} · {name}` for a
named season), and a `null`, empty or whitespace-only title SHALL render
`Season {number}` — never an empty label. This imports issue #825's rule into
the surfaces that change left alone.

#### Scenario: Blank season title on the blocks AppBar
- **WHEN** the blocks screen opens for season 1 whose title is `''` or
  whitespace only.
- **THEN** the AppBar reads „Season 1" instead of an empty title.

#### Scenario: Blank season title in the location strip
- **WHEN** the hierarchy context strip renders a season segment for season 1
  with a blank title.
- **THEN** the segment reads „Season 1" and the merged semantics label
  announces the same string.

#### Scenario: Named season on a non-pill surface
- **WHEN** a seasons card, a fundus chip, a repertoire row or the blocks AppBar
  renders season 1 titled „Dreharbeiten 2026".
- **THEN** it reads „1 · Dreharbeiten 2026" — the same string the pill shows,
  so no two surfaces disagree about one season.

#### Scenario: Optimistic season without a number
- **WHEN** an optimistic overlay carries a name but no number (no creation
  path produces this; the field is display-only).
- **THEN** the card renders the name alone rather than a bare „Season " prefix.

### Requirement: One German Word for the Season Level

The German catalog SHALL name the level „Season" (plural „Seasons") in every
value that names it — label keys, hierarchy prose, repertoire copy, AI-import
copy and error copy. „Staffel" SHALL NOT appear in `app_de.arb`. The English
catalog SHALL keep `Season`, and both catalogs SHALL stay key-identical.

The decision, its rationale and the single composition rule SHALL be recorded
in `docs/design/glossary.md`, replacing the drift note issue #825 left there.

#### Scenario: German blocks AppBar
- **WHEN** the German UI renders the blocks AppBar for an unnamed season 1.
- **THEN** it reads „Season 1", the same word the shell's „Season wählen" and
  „Season-Setup" use.

#### Scenario: German hierarchy prose
- **WHEN** the German UI renders the deleted-season back affordance or the
  membership chip on the blocks screen.
- **THEN** the copy reads „Zurück zu den Seasons" and „Keine Rolle in dieser
  Season".

#### Scenario: Catalog parity after the rename
- **WHEN** `app_de.arb` and `app_en.arb` are compared.
- **THEN** they carry the same key set (de-only `@` metadata aside), and no
  German value contains „Staffel".
