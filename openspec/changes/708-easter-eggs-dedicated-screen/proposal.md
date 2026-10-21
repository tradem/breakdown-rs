<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->

# Proposal: move Easter-eggs management to a dedicated screen (issue #708)

## Why

The settings screen embeds the complete Easter-eggs functionality
inline: the per-egg switches (issue #615) and the Easter-eggs gallery
(issue #640). This makes the screen very long and clutters the
"General" chapter away from its actual purpose. The AI configuration
already established the counter-model (issue #643): a single entry tile
pushing a dedicated screen.

## What Changes

- **New dedicated screen** `lib/features/easter_eggs/easter_eggs_screen.dart`
  with its own `Scaffold` + `AppBar`, hosting the moved functionality
  **unchanged**: per-egg switches (#615) and gallery (#640), including
  all gates (switch = master gate; `disableAnimations` → static pose;
  October month-gate bypass limited to the gallery).
- **Settings keep only an entry tile** in the general section (leading
  icon, title + subtitle, chevron) pushing the new screen — no
  membership gate: the preferences are local-only `shared_preferences`,
  no network call, no backend authorization surface.
- **No provider/store changes:** `easterEggProvider` /
  `EasterEggsStore` stay exactly as they are — surface relocation only.
- **Shared `SectionHeader`** extracted to `lib/design/components/` —
  both screens render one identical grouping affordance instead of a
  duplicated private widget.
- **L10n:** new keys `settingsEasterEggsEntryTitle` /
  `settingsEasterEggsEntrySubtitle` / `settingsEasterEggsScreenTitle`
  (extend the `settingsEasterEggs*` namespace in both ARBs; existing
  strings move along).
- **Widget keys:** the per-egg keys (`settings-egg-*`,
  `settings-egg-preview-*`) carry over to the new screen unchanged; the
  settings screen keeps only the new `settings-easter-eggs-entry` key.
- **Tests:** per-egg switch + gallery widget tests and goldens migrate
  to `test/features/easter_eggs/easter_eggs_screen_test.dart` (plus new
  root-build and `easter_eggs_{light,dark}` goldens); the settings test
  asserts the entry tile (present + push) and its goldens are
  regenerated for the shorter screen.
- **Design docs:** glossary rows updated (entry tile + new screen
  title), `settings.md` amended to the entry-tile layout (also fixing
  the stale AI-imports entry removed by #672), new
  `docs/design/screens/easter-eggs.md` spec authored per the template.

## Impact

- **No wire-contract change:** `backend/openapi.yaml` untouched — no
  OpenAPI client regeneration, no drift-check run.
- **No codegen change:** no `@freezed` / `@riverpod` / drift schema
  edits — no `build_runner` run. Only `flutter gen-l10n` output moves.
- **Affected areas:** `frontend-flutter/lib` (settings, easter_eggs,
  design/components, l10n), `frontend-flutter/test` (settings,
  easter_eggs, shell/profile-menu), `docs/design/` (glossary, screen
  specs), `openspec/changes/708-easter-eggs-dedicated-screen/`.

## Risks

- Low: pure surface relocation; behavior gates are copied verbatim and
  covered by the migrated tests (same assertions, new host screen).

## Tasks

1. Extract shared `SectionHeader`; create `EasterEggsScreen`; replace
   the inline settings sections with `_EasterEggsEntryTile`.
2. Add ARB keys (de/en), run `flutter gen-l10n`.
3. Migrate/extend tests; regenerate settings goldens; add screen
   goldens.
4. Update glossary + `settings.md`; author `easter-eggs.md`; validate
   PlantUML via `scripts/check-design-diagrams.sh`.
5. Full gate run: `dart format --set-exit-if-changed .`, `flutter
   analyze`, `flutter test`.
