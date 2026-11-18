<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# flutter-settings-screen

## MODIFIED Requirements

### Requirement: General App Settings Section
The settings screen SHALL structure a **general app settings** section
that is visible in every flavor and independent of dev mode. It SHALL
contain an "Easter eggs" section header with an explanatory line followed
by a **list of per-egg switches** (capability `flutter-easter-eggs`), one
`SwitchListTile` per registered egg, each carrying a localized egg name and
a short description. The section SHALL be a structured group so future
general settings (and future eggs) can be added without re-layout. In the
`prod` flavor the read-only server address and flavor rows SHALL remain
visible (with the explanatory store-compliance copy), exactly as the
previous dialog displayed them.

#### Scenario: General section in prod
- **WHEN** a `prod` build opens the settings screen.
- **THEN** the general section (with the per-egg Easter-eggs switches) and
  the read-only server address + flavor rows with the prod explanatory
  note are visible; no editable backend-URI field exists.

#### Scenario: General section in dev
- **WHEN** a `dev` build opens the settings screen.
- **THEN** the general section (with the per-egg Easter-eggs switches) is
  visible in addition to the development section.

#### Scenario: One switch per egg
- **WHEN** the settings screen renders the Easter-eggs section.
- **THEN** one switch per registered egg (Karl Klammer, Deja-vu Cat) is
  present, each with its own localized name and description, and flipping
  one leaves the other unchanged.

#### Scenario: Visible read-failure state per egg
- **WHEN** the persisted per-egg values could not be read at bootstrap.
- **THEN** every egg row shows the localized visible error subtitle with
  its switch falling back to default ON.
