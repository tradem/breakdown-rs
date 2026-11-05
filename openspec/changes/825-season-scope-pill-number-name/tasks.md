<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — issue #825

## 1. Copy keys

- [x] 1.1 Add `seasonNumberName` (`{number} · {name}`) to `app_de.arb` and
      `app_en.arb` (de/en parity).
- [x] 1.2 Remove `scopeChipSeason` (`Season: {season}`) from both catalogs —
      its single call site is retired by 2.1.
- [x] 1.3 Regenerate `lib/l10n/generated/` (`flutter gen-l10n`); no hand edits.

## 2. Shared composition

- [x] 2.1 Add `seasonDisplayLabel(l10n, number:, title:)` under
      `lib/features/seasons/` — blank (`null` / `''` / whitespace) takes the
      number-only arm.
- [x] 2.2 Use it for the season pill label (`SeasonScopeChip`).
- [x] 2.3 Use it for the season scope picker rows.

## 3. Tests

- [x] 3.1 Flip `scope_pill_test.dart` (`'Season: Shell Season'` →
      `'1 · Shell Season'`).
- [x] 3.2 Flip `three_views_test.dart` (`'Season: Season One'` →
      `'1 · Season One'`).
- [x] 3.3 Pin the three arms explicitly: named → `1 · <name>`, `null` title →
      `Season 1`, empty title → `Season 1`, plus a whitespace-only case.
- [x] 3.4 Assert the picker row shape matches the pill.
- [x] 3.5 Re-baseline the three scope-pill goldens — their setup set the scope
      before the first pump, so they had been capturing the neutral pill under
      a "selected" name; they now pin the selected labels.

## 4. Docs

- [x] 4.1 `docs/design/screens/navigation-shell.md` — Salt wireframe label
      (three morphologies) and the components-table copy keys + semantics.
- [x] 4.2 `docs/design/glossary.md` — inventory (`scopeChipSeason` out,
      `seasonNumberName` in), a glossary row for the number-plus-name label,
      and the known „Season" vs „Staffel" drift note.
- [x] 4.3 `python3 tool/check_glossary_catalog.py` and
      `scripts/check-design-diagrams.sh` pass.

## 5. Verification

- [x] 5.1 `dart format --set-exit-if-changed .` clean.
- [x] 5.2 `flutter analyze` clean.
- [x] 5.3 `flutter test` — full suite green.

## Follow-ups (not this change)

- [ ] Unify the German wording for the season level („Season" vs „Staffel")
      across the whole catalog as one copy decision.
- [ ] Converge the remaining `title ?? seasonsDefaultTitle(number)` sites
      (production overview, location strip, seasons cards, blocks AppBar,
      fundus, piece detail) on `seasonDisplayLabel`.
- [ ] Backend: consider normalizing an empty season title to `null` at the
      projection boundary.
