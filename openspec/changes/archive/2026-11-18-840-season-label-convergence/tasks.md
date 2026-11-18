<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — issue #840

## 1. Converge the label sites on the shared helper

- [x] 1.1 `shell/production_overview_screen.dart` — season row title.
- [x] 1.2 `shell/location_strip.dart` — `L10nPlanningLocationCopy.seasonLabel`
      (the tier-1 `PlanningLocationCopy` interface and the ladder stay pure).
- [x] 1.3 `seasons/seasons_screen.dart` — projected card arm and the optimistic
      overlay arm (the overlay keeps an explicit `number == null` branch).
- [x] 1.4 `seasons/seasons_view_widget.dart` — cache-backed list rows (drops the
      stray `wizardReviewSeason` reuse).
- [x] 1.5 `blocks/blocks_screen.dart` — AppBar title and the reports entry
      label.
- [x] 1.6 `fundus/fundus_screen.dart` — season filter chips and the repertoire
      row names.
- [x] 1.7 `pieces/piece_detail_screen.dart` — repertoire rows and the picker
      list tiles.
- [x] 1.8 Document the helper as the single composition rule (doc comment).

## 2. One German word for the level

- [x] 2.1 Rewrite every German value that named the level: `Staffel` →
      `Season`, `Staffeln` → `Seasons` (40 values, `blockSeasonNumber`
      included).
- [x] 2.2 Verify the English catalog needs no change (it said `Season`
      everywhere) and that both catalogs stay key-identical.
- [x] 2.3 Regenerate `lib/l10n/generated/` (`flutter gen-l10n`); no hand edits.

## 3. Design docs

- [x] 3.1 Replace the „Known terminology drift" section of
      `docs/design/glossary.md` with the decision record (word, rationale,
      single composition rule, both-catalog parity).
- [x] 3.2 Correct the glossary rows that quoted „Staffel" copy (blocks AppBar
      back affordance, season-number fallback title, membership chip).
- [x] 3.3 Update the quoted copy in `docs/design/screens/fundus.md`,
      `pieces.md` and `ai-import-submit.md`.

## 4. Tests

- [x] 4.1 New widget test: the blocks AppBar renders „Season 1" for an empty
      and for a whitespace-only title, and keeps „1 · Dreharbeiten" for a
      titled season.
- [x] 4.2 New widget tests: the location strip renders „Season 1" for both
      blank-title arms.
- [x] 4.3 Update the assertions that expected a bare title (`'Spring'`,
      `'Summer'`, `'Later'`, `'Autumn'`, `'Sommerkomödie'`, `'Shell Season'`,
      `'Season Two'`, the fundus repertoire line) to the composed label.
- [x] 4.4 Re-baseline the 26 goldens whose labels changed (blocks, seasons,
      shell, fundus, AI-import target card) and inspect the diff.

## 5. Verification

- [x] 5.1 `dart format --set-exit-if-changed .` — clean.
- [x] 5.2 `flutter analyze` — no issues.
- [x] 5.3 `flutter test` — 2358 passed.
- [x] 5.4 `dart run bin/run_lints.dart ../..` (custom runner) — no violations.
- [x] 5.5 `tool/check_inline_copy.sh` + `tool/check_glossary_catalog.py` —
      clean.
- [x] 5.6 `scripts/add-spdx-headers.sh --check` — clean.
