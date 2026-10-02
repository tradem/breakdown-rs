<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Proposal: add-karl-klammer-easter-egg

Implements issue #516.

## Why

The app currently has no general app settings and no Easter-egg
infrastructure: settings live in a `SettingsDialog` that mixes the
dev-only backend-URI override flow into a dialog with English copy that
pre-dates the glossary workflow. Issue #516 bundles two tightly related
features: a full-screen Settings that cleanly separates general settings
from dev settings, and a foundational "Easter eggs" toggle consumed by
the first Easter egg — a Karl Klammer assistant (a clothes-hanger
re-imagining of Clippy) in the AI Import view.

## What Changes

- **Settings screen replaces the dialog** (**BREAKING for the settings
  surface**): the "Einstellungen" tile in the Mehr tab pushes a full
  screen (`SettingsScreen`) with AppBar back navigation instead of
  `showSettingsDialog`. The `SettingsDialog` and `showSettingsDialog`
  are removed — no dual entry point. `info_dialog.dart` stays untouched.
- **Two separated sections** on the settings screen:
  1. *General app settings* — visible in every flavor; contains the
     Easter-eggs switch; structured so future general settings join it.
  2. *Entwicklung (dev)* — visible only in the `dev` flavor; migration
     target of the current dialog dev content: editable backend URI with
     inline validation (`validateApiBase`), save
     (`SessionReset.switchBackend`), reset-to-default
     (`SessionReset.resetBackendToDefault`), progress surfacing. In
     `prod` the read-only server address + flavor display remain (with
     explanatory copy), as before.
- **Easter-eggs toggle** (`SwitchListTile`, German copy): default
  **enabled** on first launch, persisted on-device via a new
  `shared_preferences`-backed store (Decision D1), globally reactive
  immediately via a `@riverpod` notifier — no restart.
- **Karl Klammer Easter egg**: a self-drawn (CustomPainter) clothes
  hanger character in the AI Import screens, styled after the app icon's
  `checkroom` glyph. Context-dependent tips/poses per import-flow state
  (no config / running / error / success / idle), non-modal, tap
  dismissible, deterministic triggers (injectable clock, no
  wall-clock/random), respect `MediaQuery.disableAnimations`, visible
  only while Easter eggs are enabled (immediate removal, no residue).
- **UI copy migration**: the settings screen copy is German and
  glossary-conformant (`settings.*` keys re-mapped in
  `docs/design/glossary.md`, new `aiImport.clippy.*` prefix); the
  English copy of the old dialog is retired with it.
- **Screen spec**: `docs/design/screens/settings.md` (template +
  PlantUML Salt wireframe) authored in this change before the
  implementation tasks; glossary entries added in the same change.
- New dependency: `shared_preferences` (Decision D1 — see design.md).

## Capabilities

### New Capabilities
- `flutter-settings-screen`: full-screen settings with back navigation,
  always-visible general section (Easter-eggs switch) and dev-only
  development section; migration of the dialog dev flow without feature
  loss; prod read-only display.
- `flutter-easter-eggs`: the global Easter-eggs toggle (default ON,
  persistent, immediately effective) and the single Karl Klammer Easter
  egg in the AI Import view with its hard requirements (non-modal,
  deterministic, fully hideable, accessibility).

### Modified Capabilities
- `flutter-app-dialogs`: the "Settings Dialog with Dev-Only
  Backend-URI Override" and "Runtime Override Applies at Next Bootstrap"
  requirements move from the dialog to the settings screen — the dialog
  requirement is removed (its runtime-override behavior is preserved
  verbatim as a settings-screen requirement); the Info dialog
  requirements are unchanged.

## Impact

- `frontend-flutter/lib/features/app_info/settings_dialog.dart` —
  removed; new `lib/features/settings/settings_screen.dart` +
  controller/state.
- `frontend-flutter/lib/features/shell/more_tab_screen.dart` — tile
  pushes the screen instead of the dialog.
- `frontend-flutter/lib/data/settings/` — new `easter_eggs_store.dart`
  (`shared_preferences`, Result-typed); `api_base_override_store.dart`
  unchanged.
- `frontend-flutter/lib/features/ai_import/` — Karl Klammer overlay
  widget + trigger logic; consumed by the AI config/jobs screens.
- `frontend-flutter/lib/l10n/app_{de,en}.arb` — new/migrated
  `settings.*` + `aiImport.clippy.*` keys; `flutter gen-l10n`.
- `docs/design/glossary.md` + new `docs/design/screens/settings.md`.
- `frontend-flutter/pubspec.yaml` — `shared_preferences` dependency.
- Tests: unit (store, trigger logic), widget (screen, flavor
  visibility, switch), goldens (settings screen; AI import with/without
  Karl Klammer). Old settings-dialog tests replaced.
