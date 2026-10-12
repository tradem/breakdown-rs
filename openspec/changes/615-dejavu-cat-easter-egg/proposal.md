<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# Proposal: Deja-vu Cat splash egg + per-egg Easter-egg configuration (issue #615)

## Why

The launch ("build") splash currently shows only the `checkroom` brand
icon, the wordmark and a spinner. The PO wants a second Easter egg: during
**October**, an original black cat walks across the splash — a wink at the
famous "déjà vu" black cat — with no caption, expressed purely in
animation.

Today the Easter-egg preference is a **single global boolean**
(`EasterEggsStore.key = 'easter_eggs'`). With a second egg entering the app
the PO wants **per-egg switches**: "Karl Klammer" and "Deja-vu Cat" must be
toggleable independently. The October gating is a month check, not a
persisted flag: outside October the cat is dormant even when switched on
(and returns next October).

## What Changes

- **Per-egg persistence refactor:** `EasterEggsStore` moves from one bool to
  **flat per-egg keys** (`easter_eggs.karl_klammer`, `easter_eggs.dejavu_cat`)
  with an `EasterEggId` enum. Flat keys survive partial writes and are
  readable/removable individually (Decision D1).
- **Legacy-flag migration:** on first launch after the update the legacy
  `easter_eggs` bool seeds every per-egg value that is not already stored,
  then the legacy key is removed. A read failure falls back to default ON
  per egg, preserving the visible-error pattern.
- **Per-egg notifier:** a `NotifierProvider.family` keyed by `EasterEggId`
  replaces the single `easterEggsProvider`. Karl Klammer watches its own
  egg; the splash cat watches `dejavu_cat`. Reactivity contract unchanged
  (immediate, no restart, persistence failures surface visibly).
- **Settings screen:** the single switch becomes a **list of per-egg
  switches** under the existing "Easter eggs" section header, with
  localized egg names + short descriptions (de/en).
- **Deja-vu Cat (October only):** a new `CustomPainter` black cat that
  loops across the `SplashView` content area while the splash is visible.
  Gated by `dejaVuCatActive(enabled:, now:)` — a pure, injectable-clock
  month check (`now.month == DateTime.october`). The animation loops; the
  restore duration is never stretched. The walk includes a subtle
  "déjà vu" pause/glance beat. The system "remove animations" setting
  renders a static pose (no controller). No binary assets, no Matrix film
  assets/titles — original own AGPL work, design-token colors only.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `flutter-easter-eggs`: adds the per-egg configuration requirement
  (flat-key persistence + legacy migration + per-egg notifier + settings
  rows) and the **Deja-vu Cat** requirement (October gate, splash stage,
  looping walk, remove-animations fallback). The Karl Klammer requirement
  is refined to watch its own egg flag instead of a global toggle.
- `flutter-settings-screen`: the "General App Settings Section"
  requirement's Easter-eggs member changes from a single switch to a list
  of per-egg switches.

> **Archive ordering:** this change MODIFIES requirements first ADDED by
> the still-unarchived change `add-karl-klammer-easter-egg` (issue #516).
> Archive #516 (and #614) before archiving this change so the base
> `flutter-easter-eggs` / `flutter-settings-screen` specs exist in
> `openspec/specs/`.

## Impact

- `frontend-flutter/lib/data/settings/easter_eggs_store.dart` — store +
  `EasterEggId` enum + per-egg notifier family + hydration variant.
- `frontend-flutter/lib/features/easter_eggs/dejavu_cat_gate.dart` — pure
  October gate + walk math (Tier-1, no Flutter imports).
- `frontend-flutter/lib/features/easter_eggs/dejavu_cat.dart` — cat painter
  + splash overlay + injectable clock provider.
- `frontend-flutter/lib/app.dart` — `SplashView` hosts the cat overlay;
  `bootstrap()` migrates + hydrates all eggs.
- `frontend-flutter/lib/features/ai_import/clippy/karl_klammer_overlay.dart`
  — watches `EasterEggId.karlKlammer`.
- `frontend-flutter/lib/features/settings/settings_screen.dart` — per-egg
  switch rows.
- `frontend-flutter/lib/l10n/app_{de,en}.arb` — per-egg name/subtitle keys;
  `flutter gen-l10n`.
- `docs/design/screens/settings.md` + `docs/design/glossary.md` — per-egg
  rows and copy keys; the cat sketch lives in this change's `design.md`.
- Tests + goldens: store/migration, gate, cat widget, settings, Karl
  Klammer overlay.
- **No backend/API change** — `backend/openapi.yaml` untouched, no Dart
  client regeneration; no `*.g.dart`/`*.freezed.dart` hand-edits.
