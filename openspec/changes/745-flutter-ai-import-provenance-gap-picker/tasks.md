<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.4 (opencode-go) -->

# Tasks — Flutter AI import Pass-2 provenance & gap picker (issue #745)

## 1. Pure derivation

- [x] 1.1 `lib/features/ai_import/import_jobs/continuity_gap.dart`:
  `characterIdentity()` (backend mirror), `draftRowRef()`, `ContinuityGap`,
  `continuityGapsOf(ScriptContext)` implementing design D4.
- [x] 1.2 Never offer a non-gap: an inferred-only candidate list, a gap without
  candidates, a non-`outfits` field, an out-of-range scene index and a
  duplicate gap all resolve to nothing / one entry.
- [x] 1.3 Tier-1 tests (`test/unit/continuity_gap_test.dart`): identity mirror,
  row-ref fallback, pairing through the source row, ambiguity handling, the
  already-dressed figure, plain notices, duplicates, out-of-range index.

## 2. Preview surface

- [x] 2.1 `PreviewOutfit` carries `origin` + `provenance`; the preview seeds it
  from `DraftOutfit`.
- [x] 2.2 `_OutfitOriginBadge`: one localized label per origin (D1); the
  continuation names the source scene from the provenance, degrading to
  "an earlier scene"; absent/unknown origin renders nothing.
- [x] 2.3 The source-quote line renders only for a quote-carrying origin (D2).
- [x] 2.4 `_ContinuityGapCard`: the server's note verbatim + one `ChoiceChip`
  per candidate (look name + confidence) + the leave-empty chip; the plain
  notice stays for gaps without candidates (D3).

## 3. Apply surface & wire

- [x] 3.1 `AiApplyState`: `continuityGaps`, `continuitySelections`,
  `gapKey`/`candidateFor`, `buildContinuitySelections()`; a pick counts in
  `editDistance` (D5).
- [x] 3.2 `AiApplyController.decideContinuityGap` + seeding the gaps from the
  typed payload; `apply()` sends `continuity_selections` (absent when empty).
- [x] 3.3 `AiApplyState.copyWith` replaces the hand-written re-constructions,
  fixing the dropped `dayDecisions` on the command-error paths (D6).
- [x] 3.4 Apply card: per-gap summary line at the dispatch; localized
  `ai-import.apply-unknown-continuity-candidate` copy.

## 4. Copy & docs

- [x] 4.1 de/en ARB keys (`aiPreviewOutfitOrigin*`, `aiPreviewContinuity*`,
  `aiApplyContinuityGap*`, `aiApplyErrorUnknownContinuityCandidate`);
  `flutter gen-l10n` parity clean.
- [x] 4.2 `docs/design/glossary.md`: inventory row + badge/picker icon rows.
- [x] 4.3 `docs/design/screens/ai-import-jobs.md`: provenance + gap picker
  section (elements, semantics, copy keys).

## 5. Tests & gates

- [x] 5.1 Widget tests (`test/features/ai_import/preview_continuity_test.dart`):
  four badges, no badge on an origin-less preview, quote suppression, gap
  picker rendering, pick → `continuity_selections` + edit distance, unresolved
  gap applies unchanged, stale-pick 409 copy.
- [x] 5.2 Goldens: `ai_preview_continuity_{light,dark}_{android,macos}.png`.
- [x] 5.3 `features-spec/ai_import_continuity_gap.feature` (`@pending`, with the
  reason and the substituting tests documented) + `features-spec/README.md`.
- [x] 5.4 `dart format --set-exit-if-changed .`, `flutter analyze`,
  `flutter test`, `tool/check_glossary_catalog.py`, `tool/check_gherkin.sh`,
  `scripts/check-design-diagrams.sh`.
- [x] 5.5 Version + changelog: `0.4.0-beta.18+110 → 0.4.0-beta.19+111`,
  `CHANGELOG.md` entry.
