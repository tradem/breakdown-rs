<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Proposal: Surface the Deja-vu Cat beyond the sub-second splash (issue #640)

## Why

The Deja-vu Cat (issue #615) renders only inside `SplashView` while the
session restore is in flight. In a dev build that restore is near-instant,
so the cat flashes for a few frames and is effectively invisible — an
Easter egg with no payoff ("implemented but unreachable"). Issue #640
asks for a PO/design decision on which surfaces host the cat.

## Decision (PO, recorded via ask-user handshake)

**Option 4 — combination:**

1. **Splash (unchanged):** the cat keeps crossing the launch splash.
2. **Empty-surface visitor:** the cat also crosses the **Seasons home
   empty state** (`SeasonsEmptyState`) — the app's canonical idle
   surface. Same `DejaVuCatOverlay`, so October gate, per-egg switch and
   the "remove animations" behavior are preserved by construction.
3. **Easter-eggs gallery in Settings:** a **Vorschau** (preview) section
   under the existing per-egg switches renders each egg's figure —
   `KarlKlammerFigure` and the `DejaVuCatWalker` — **regardless of
   month**, visible only while that egg's switch is ON, honoring the
   system "remove animations" setting. This makes every egg discoverable
   and testable year-round (the gallery bypasses only the October month
   gate, never the preference).

### Deliberately excluded surfaces

- **Fatal-config error screen:** it renders *before* `ProviderScope` /
  bootstrap — the egg hydration never ran, so the per-egg switch cannot
  be honored there (the acceptance criterion requires it). A fail-closed
  error surface also should stay sober.
- **Omni-search empty state:** the empty narrative is a small text block
  inside a scrollable list; the full-band walker would clip against the
  list viewport, and search is a transient state, not an idle surface.

## What Changes

- `SeasonsScreen`'s empty state is wrapped in `DejaVuCatOverlay`
  (splash behavior untouched).
- `SettingsScreen` gains the gallery preview section with per-egg
  preview cards (new copy keys `settings.easterEggsPreview` /
  `settings.easterEggsPreviewSubtitle`, glossary + ARB catalogs
  updated).
- `dejavu_cat.dart` stays the single owner of the walker/overlay; the
  gallery consumes `DejaVuCatWalker` directly with a bounded box.
- Design docs updated first (this change's design step):
  `docs/design/screens/settings.md`, `docs/design/screens/seasons-home.md`,
  `docs/design/glossary.md`.

## Impact

- No API / wire-contract change; no generated-client regen.
- New widget tests + goldens for both hosting surfaces; the October
  gate stays Tier-1 unit-tested (`dejavu_cat_gate_test.dart`).
