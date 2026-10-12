<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# Tasks: Deja-vu Cat + per-egg Easter-egg configuration (issue #615)

## 1. Design & copy artifacts

- [x] 1.1 `design.md` — cat silhouette + walk-cycle sketch (Salt), October
      gate, flat-key persistence decision, déjà-vu beat (done in this change).
- [x] 1.2 `docs/design/screens/settings.md` — per-egg switch rows in the
      layout, components table, states, interactions, tests.
- [x] 1.3 `docs/design/glossary.md` — per-egg settings rows + the cat
      section entry.
- [x] 1.4 `lib/l10n/app_de.arb` + `app_en.arb` — per-egg name/subtitle
      keys; run `flutter gen-l10n`; de/en parity clean.
- [x] 1.5 `openspec validate 615-dejavu-cat-easter-egg --strict` +
      `scripts/check-design-diagrams.sh`.

## 2. Per-egg persistence (Tier-1, `data/`)

- [x] 2.1 `easter_eggs_store.dart`: `EasterEggId` enum with flat wire keys
      (`easter_eggs.karl_klammer`, `easter_eggs.dejavu_cat`); `read(id)` /
      `write(id, value)`; `readAll()` returning per-egg values + migration
      result; legacy `easter_eggs` seeding (null-only) + removal.
- [x] 2.2 Replace the single notifier with
      `NotifierProvider.family<EasterEggs, bool, EasterEggId>` +
      `HydratedEasterEggs` carrying the bootstrap value + `readFailed`.
- [x] 2.3 `app.dart` `bootstrap()`: `readAll()` → log + default-ON
      fallback on Err → override the whole family via `overrideWith2`.
- [x] 2.4 `easter_eggs_store_test.dart`: per-egg round-trip, legacy
      migration (seeds both, drops legacy, preserves explicit per-egg
      values), missing-key default, Ok/Err branches, notifier toggle +
      read-failure seeding.

## 3. October gate + walk math (Tier-1, pure)

- [x] 3.1 `lib/features/easter_eggs/dejavu_cat_gate.dart`:
      `dejaVuCatActive(enabled:, now:)`, `dejaVuCatTravel(phase)`,
      `dejaVuCatGlance(phase)` — no Flutter imports.
- [x] 3.2 `dejavu_cat_gate_test.dart`: on-October/off-September/off-November,
      disabled-off-even-in-October, travel monotonic + pause plateau, glance
      peaks mid-pause and is 0 outside.

## 4. Splash cat (CustomPainter + overlay)

- [x] 4.1 `lib/features/easter_eggs/dejavu_cat.dart`: `DejaVuCatFigure`
      (`CustomPainter`, `onSurface` silhouette, static pose when
      `animate: false`) + `DejaVuCatOverlay` (watches `dejavu_cat` + the
      injectable `dejaVuCatClockProvider`, `IgnorePointer`, `LayoutBuilder`
      placement in the lower band).
- [x] 4.2 `app.dart` `SplashView`: wrap the splash body in
      `DejaVuCatOverlay`; brand icon/wordmark/spinner unchanged.
- [x] 4.3 `dejavu_cat_test.dart`: renders only with both splash visibility
      and the egg flag; hidden in September; remove-animations static pose
      (no ticker); walk repaint proof; goldens.

## 5. Consumers rewire

- [x] 5.1 `karl_klammer_overlay.dart`: watch
      `easterEggProvider(EasterEggId.karlKlammer)`; behaviour unchanged when
      its flag is on.
- [x] 5.2 `settings_screen.dart`: section header + explanatory line + one
      `SwitchListTile` per egg (localized name/subtitle, visible error
      state per row, write-failure snackbar).
- [x] 5.3 Update `karl_klammer_overlay_test.dart` +
      `settings_screen_test.dart` to the family provider / per-egg rows.
- [x] 5.4 `app_gate_test.dart`: pin `dejaVuCatClockProvider` to a
      non-October date so the pre-existing splash assertions/goldens stay
      deterministic year-round.

## 6. Validation & CI gates

- [x] 6.1 `dart format --set-exit-if-changed .`; `flutter analyze`;
      `breakdown_lints` runner clean.
- [x] 6.2 `flutter test --coverage`; Err-branch assertions present.
- [x] 6.3 No `backend/openapi.yaml` change → no client regen; no
      `*.g.dart`/`*.freezed.dart` hand-edits.
