<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Flutter AI import: prominent provider/model header + Decision Model disclosure (issue #760)

## Why

Two small, closely related header/disclosure defects on `AiPreviewScreen`:

1. **Provider and model are effectively invisible.** They render as ONE
   `bodySmall` line (`AiNamingLine`, `lib/features/ai_import/naming_line.dart`)
   wedged between the app bar and the scene cards. In an import preview the
   machinery that produced the rows must be readable at a glance, and the
   current weight loses against every card below it.
2. **No configuration without a Decision Model says so.** The preview silently
   runs without the Pass-2 continuity scan and without the scene/synopsis
   ratings. The result is an import that looks defective: no wardrobe
   suggestions, no star ratings, no explanation.

Both are UI/disclosure work on the same screen and ship together. Nothing in
the wire contract changes: the Decision Model slot is already client-side on
`AiConfigView.decisionProvider` / `decisionModel` (additive fields of #722) via
`configuredAiNamingProvider`, so the necessary facts are known without a new
endpoint or an extra call.

Backend behaviour when no Decision Model is set is unchanged and benign: the
extraction runs exactly as before, and only the Pass-2 outfit-continuity /
scoring passes are skipped. The warning is therefore factual and
non-blocking, never alarming.

## What Changes

- **Header card instead of a footnote line.** `AiNamingCard` renders the
  configured naming as a card at the top of the preview list: the **model** as
  the primary line (`titleSmall`, one line, ellipsized), the **provider** as
  the secondary line (`labelLarge`), and the unchanged EU AI Act Art. 50
  sentence as the caption. A neutral leading `memory_outlined` glyph reinforces
  only (visible text stays the sole carrier).
- **One shared resolution, no duplicated copy.** The transparency wording moves
  into `aiNamingSentence(...)`, which both `AiNamingCard` (preview header) and
  the existing `AiNamingLine` (submit disclosure, apply section) call. The two
  surfaces cannot drift; the submit/apply surfaces keep their compact
  `bodySmall` weight.
- **Honest degradation preserved.** An unconfigured account renders the
  existing "no AI configuration" copy and no model/provider line; a failed
  discovery renders the same copy (never an invented name); a pending discovery
  renders the loading note; a reload keeps the last resolved naming
  (`skipLoadingOnReload`).
- **Non-blocking "no Decision Model" card.** `AiDecisionModelWarning` renders
  under the effective-Decision-Model line when — and only when — a RESOLVED
  configuration carries no `decisionProvider`/`decisionModel`. It states the two
  factual consequences (Pass-2 wardrobe continuity suggestions and the
  scene/synopsis ratings are skipped) plus that the import still runs, and
  offers a text button into `AiConfigScreen`. It never blocks the apply.
- **Failed read is not "unset".** The warning renders nothing while the
  discovery is pending, for an unconfigured account, and when the discovery
  failed: a failed read is a different fact from "no Decision Model is set",
  and the header falls back to the "unconfigured" disclosure instead.
- **One instance, deliberately.** The apply section sits in the same scroll
  view directly below the header, so a second warning at the dispatch point
  would duplicate UI rather than add information; the single card documents
  that decision.
- Copy (de + en), glossary rows (icons + ARB identifiers), the screen spec, and
  the preview goldens move with the layout.

## Impact

- Affected specs: `flutter-ai-import-workflow` (preview header + Decision Model
  disclosure).
- Affected code: `lib/features/ai_import/naming_line.dart` (shared sentence,
  `AiNamingCard`, `AiDecisionModelWarning`),
  `lib/features/ai_import/import_jobs/preview_screen.dart` (header wiring),
  `lib/l10n/app_{de,en}.arb` + generated l10n.
- Tests: `test/features/ai_import/ai_naming_line_test.dart` (card states, long
  model id), `test/features/ai_import/decision_model_warning_test.dart` (the
  warning matrix), `test/features/ai_import/preview_apply_test.dart` (header +
  warning in the real screen, apply stays enabled), preview goldens re-cut.
- No API surface, no new endpoint, no command dispatch, no Drift schema change.

## Non-goals

- Changing the backend's Decision Model behaviour or its telemetry (already
  shipped: #722, #767).
- Gating, disabling, or warning about the apply itself.
- A second Decision Model warning inside the apply card (see "one instance").
