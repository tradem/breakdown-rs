<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Tasks: add-karl-klammer-easter-egg (issue #516)

## 1. Design & glossary artifacts (before implementation)

- [x] 1.1 Author `docs/design/screens/settings.md` per the screen-spec
      template (Purpose, Navigation, Location & Context, Salt wireframe
      under `docs/design/` compile rules, Components & Semantics with
      `settings.*` / `aiImport.clippy.*` copy keys, States,
      Interactions, Input & Validation, Accessibility, Tests).
- [x] 1.2 Add glossary entries to `docs/design/glossary.md`: the
      "Einstellungen" destination row + new keys `settings.easterEggs`,
      `settings.general`, `settings.dev.*`, `aiImport.clippy.*`
      (prefix); migrate the existing English dialog copy keys to
      glossary-conformant German keys.
- [x] 1.3 Add the German/English ARB values for all new keys
      (`lib/l10n/app_de.arb`, `app_en.arb`); run `flutter gen-l10n`.
- [x] 1.4 Validate the change: `openspec validate
      add-karl-klammer-easter-egg` and the PlantUML design-diagram
      check (`scripts/check-design-diagrams.sh`).

## 2. Easter-eggs settings store + notifier (data/)

- [x] 2.1 Add `shared_preferences` to `pubspec.yaml`; `pub get`.
- [x] 2.2 Implement `lib/data/settings/easter_eggs_store.dart`:
      Result-typed `read()`/`write(bool)`, key `easter_eggs`,
      `ProblemError` codes `settings.easter_eggs_read_failed` /
      `easter_eggs_write_failed`, no `throw`.
- [x] 2.3 Implement `easterEggsProvider` (plain `Notifier<bool>` via
      `NotifierProvider` — deliberate codegen exception, mirroring the
      neighboring `RuntimeApiBase`; default `true`), seeded at
      `bootstrap()` via `HydratedEasterEggs`; read failure → default
      ON + visible error state flag.
- [x] 2.4 Unit tests: store Ok/Err branches, default-ON on missing
      value, persist+restore round-trip, notifier immediate flip.

## 3. Settings screen (features/settings/)

- [x] 3.1 Implement `lib/features/settings/settings_screen.dart`:
      AppBar + back, general section (all flavors) with the
      Easter-eggs `SwitchListTile`, dev-only "Entwicklung" section
      migrating the dialog's dev flow verbatim (`validateApiBase`
      inline validation, save via `SessionReset.switchBackend` with
      progress, reset via `resetBackendToDefault`), prod read-only
      base + flavor rows + prod note.
- [x] 3.2 Point the Mehr tab tile `mehr-settings` at
      `Navigator.push(SettingsScreen)`; delete
      `lib/features/app_info/settings_dialog.dart` (single commit — no
      dual entry point).
- [x] 3.3 Widget tests: back navigation, general section in both
      flavors, dev section dev-only, switch state + immediate notifier
      effect, save/reset/progress flows (ported from
      `settings_dialog_test.dart`).
- [x] 3.4 Goldens: settings screen dev + prod, light + dark (replace
      the old `settings_*.png` goldens).

## 4. Karl Klammer (features/ai_import/)

- [x] 4.1 Implement the self-drawn hanger figure: `CustomPainter`
      character based on the `checkroom` geometry, colors from
      `lib/design/` tokens; poses: swing/wobble (running), droop
      (error), proud (success), idle bob.
- [x] 4.2 Implement pure trigger logic `clippyTipFor(state, visitCount)`
      + injectable idle clock (no wall-clock/random); ARB copy set
      `aiImport.clippy.*` keyed per trigger state.
- [x] 4.3 Implement the overlay widget: non-modal (bottom-leading,
      never over primary CTAs), tap-dismissible for the session, gates
      visibility on `easterEggsEnabledProvider` (`ref.watch` —
      immediate disappearance, cancel running tips), `Semantics`
      decorative/dismissible, honors `MediaQuery.disableAnimations`
      (static pose). Wire into the AI config / jobs / submit screens
      with `// AUTHZ-GATE:` comments where a call is gated.
- [x] 4.4 Unit tests: trigger mapping per state; no network/no tracking.
- [x] 4.5 Widget tests: visible-when-enabled, hidden-when-disabled incl.
      live toggle-off, tap dismissal, CTA hit-testability, fake-clock
      idle trigger, remove-animations static pose, screen-reader
      semantics.
- [x] 4.6 Goldens: AI Import with/without Karl Klammer.

## 5. Validation & CI gates

- [x] 5.1 `dart format --set-exit-if-changed .`; `flutter analyze`;
      `breakdown_lints` runner clean.
- [x] 5.2 `flutter test --coverage` + Err-branch assertions present on
      the store tests.
- [x] 5.3 `flutter gen-l10n` untranslated report + de/en key parity
      clean; no generated-output drift.
- [x] 5.4 gitleaks clean (`.dart`/`.yaml`/`.arb`).
- [x] 5.5 Confirm no `backend/openapi.yaml` change → no client regen
      needed; no `*.g.dart`/`*.freezed.dart` hand-edits (build_runner
      only if annotations changed).
