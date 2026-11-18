<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# flutter-settings-screen

## ADDED Requirements

### Requirement: Settings Screen with Back Navigation
The app SHALL present its settings as a dedicated full screen
(`SettingsScreen`) pushed from the Mehr tab's "Einstellungen" tile via
`Navigator.push` + `MaterialPageRoute` — never `showDialog`. The screen
SHALL carry an AppBar with a working back navigation (`Navigator.pop`).
The former `SettingsDialog` and `showSettingsDialog` SHALL be removed;
there SHALL be no dual entry point. The Info dialog
(`info_dialog.dart`) SHALL remain untouched. UI copy SHALL be German
and glossary-conformant (`docs/design/glossary.md`, `settings.*` keys).

#### Scenario: Tile opens the full screen
- **WHEN** the user taps the "Einstellungen" tile in the Mehr tab.
- **THEN** a full screen with an AppBar is pushed (no dialog) and the
  AppBar back button pops it.

#### Scenario: Dialog is gone
- **WHEN** the codebase is searched for `showSettingsDialog` /
  `SettingsDialog`.
- **THEN** no occurrence remains in `lib/` or `test/` — the tile and
  all tests target the screen.

### Requirement: General App Settings Section
The settings screen SHALL structure a **general app settings** section
that is visible in every flavor and independent of dev mode. Its first
member SHALL be the Easter-eggs switch (capability
`flutter-easter-eggs`). The section SHALL be a structured group so
future general settings can be added without re-layout. In the `prod`
flavor the read-only server address and flavor rows SHALL remain
visible (with the explanatory store-compliance copy), exactly as the
previous dialog displayed them.

#### Scenario: General section in prod
- **WHEN** a `prod` build opens the settings screen.
- **THEN** the general section (with the Easter-eggs switch) and the
  read-only server address + flavor rows with the prod explanatory note
  are visible; no editable backend-URI field exists.

#### Scenario: General section in dev
- **WHEN** a `dev` build opens the settings screen.
- **THEN** the general section (with the Easter-eggs switch) is visible
  in addition to the development section.

### Requirement: Development Section (dev flavor only)
The settings screen SHALL structure a **development** section, headed
"Entwicklung" and visually/semantically labeled as a dev area, visible
ONLY in the `dev` flavor. It SHALL migrate the previous dialog's dev
functionality without feature loss: an editable backend-URI field with
inline validation (absolute `http`/`https` URI via `validateApiBase`),
a save action (persist → pinned-CA Dio rebuild → fence → clear →
invalidate via `SessionReset.switchBackend`, progress surfaced), and a
reset-to-default action (`SessionReset.resetBackendToDefault`).

#### Scenario: Dev user sets a valid override
- **WHEN** a dev-flavor user saves a valid absolute URI in the
  development section.
- **THEN** it is persisted in `flutter_secure_storage`, the pinned-CA
  Dio is rebuilt against it (same pinned CA set), all read providers are
  invalidated, and the Drift read cache is emptied — subsequent screens
  fetch from the new base.

#### Scenario: Backend behind a different certificate
- **WHEN** the overridden backend's certificate does not chain to the
  dev flavor's pinned CA set.
- **THEN** requests fail with a transport-level `ProblemError` surfaced
  through the standard error copy; certificate verification is never
  disabled or relaxed.

#### Scenario: Invalid URI rejected client-side
- **WHEN** a non-absolute string or an unreachable host is saved.
- **THEN** the save action validates and either rejects malformed input
  inline (no network call) or surfaces the subsequent transport error
  keyed on `code` — never a crash and never a silent discard.
