<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — Flutter AI import header card + Decision Model disclosure (issue #760)

## 1. Shared resolution

- [x] 1.1 `lib/features/ai_import/naming_line.dart`: extract
  `aiNamingSentence(AppLocalizations, AsyncValue<AiConfigView?>)` — the ONE
  transparency sentence (configured `aiNamingLine`, unconfigured/failed
  `aiDisclosureNamingBodyUnconfigured`, loading
  `aiDisclosureNamingBodyLoading`, `skipLoadingOnReload: true`).
- [x] 1.2 `AiNamingLine` keeps its compact `bodySmall` rendering for the submit
  disclosure and the apply section, now delegating to the shared sentence.

## 2. Prominent header (preview)

- [x] 2.1 `AiNamingCard`: card at the top of the preview list — model
  primary (`titleSmall`, `maxLines: 1`, ellipsis), provider secondary
  (`labelLarge`), the Art. 50 sentence as caption; leading `memory_outlined`.
- [x] 2.2 Honest degradation in the card: unconfigured → one line with the
  "no AI configuration" copy and NO model/provider line; failed discovery → the
  same copy (a name is never invented); loading → the loading note; a reload
  keeps the resolved naming.
- [x] 2.3 `preview_screen.dart`: the header card replaces the flat naming line
  at the same scroll position (first child, above the payload).

## 3. Decision Model disclosure

- [x] 3.1 `AiDecisionModelWarning`: renders a non-blocking card
  (`tertiaryContainer`, `info_outline`) only for a RESOLVED configuration whose
  `decisionProvider`/`decisionModel` are unset — title, the two factual
  consequences, and the text button into `AiConfigScreen` (callback seam for
  tests).
- [x] 3.2 Silence matrix: a configured Decision Model, an unconfigured account,
  a pending discovery and a FAILED discovery all render nothing (a failed read
  is not "unset").
- [x] 3.3 Placement documented: one instance in the preview header — the apply
  section sits directly below in the same scroll view, so a second card would
  duplicate UI, not add information.
- [x] 3.4 The warning never blocks: no apply gate is added or removed.

## 4. Copy & docs

- [x] 4.1 de/en ARB keys `aiPreviewNamingProvider`,
  `aiPreviewDecisionModelWarningTitle`, `aiPreviewDecisionModelWarningBody`,
  `aiPreviewDecisionModelWarningAction`; `flutter gen-l10n` run, parity clean.
- [x] 4.2 `docs/design/glossary.md`: `memory_outlined` header row,
  `info_outline` warning/action row, and the four ARB identifiers in the
  implemented inventory (`tool/check_glossary_catalog.py` green).
- [x] 4.3 `docs/design/screens/ai-import-jobs.md`: new section for the header
  card + the Decision Model disclosure, the #767 row retargeted to the header
  card, and the test inventory extended.

## 5. Tests & gates

- [x] 5.1 `test/features/ai_import/ai_naming_line_test.dart`: card states
  (configured / unconfigured / failed / loading) and the long model id
  (`maxLines: 1`, `TextOverflow.ellipsis`, no overflow exception).
- [x] 5.2 `test/features/ai_import/decision_model_warning_test.dart` (new): the
  warning matrix incl. provider-without-model, the action callback, and the
  four silence arms.
- [x] 5.3 `test/features/ai_import/preview_apply_test.dart`: header renders
  model/provider/Art. 50 caption inside a `Card` with no warning when a
  Decision Model is configured; without one the warning names the consequences
  and the apply stays reachable after the review acknowledgement; a failed
  discovery degrades to the unconfigured copy with no warning. The shared
  fixture gained `decisionModel` / `namingDiscoveryFails` switches.
- [x] 5.4 `test/features/ai_import/preview_continuity_test.dart`: the naming
  fixture configures a Decision Model so the #760 warning stays out of the
  provenance/gap goldens.
- [x] 5.5 Preview goldens re-cut
  (`ai_preview_{continuity,merged}_{light,dark}_{android,macos}.png`).
- [x] 5.6 `dart format --set-exit-if-changed .`, `flutter analyze`,
  `flutter test`, `tool/check_glossary_catalog.py`,
  `tool/check_inline_copy.sh`, `scripts/check-design-diagrams.sh`.
- [x] 5.7 Version + changelog: `0.4.0-beta.25+117 → 0.4.0-beta.26+118`,
  `CHANGELOG.md` entry.

## Deferred

- A golden for the warning card itself: the card is a stateless disclosure whose
  states the widget tests pin exhaustively, and the preview goldens exercise the
  card in situ (warning absent). Revisit if the card gains behaviour.
