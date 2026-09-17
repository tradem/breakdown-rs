<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

## 1. Screen Spec & Glossary

- [x] 1.1 Create the screen spec `docs/design/screens/
      season-setup-wizard.md` from the template (nine sections; Salt
      wireframes per step in the Layout section; abort/dispatch
      behavior in the Interactions/States sections, not in the
      diagram)
- [x] 1.2 Glossary: add the copy keys for wizard texts (step labels,
      abort dialog, partial failure, completion CTA "AI-Import
      starten", AI-configuration prerequisite info card)

## 2. Wizard State & Controller (Unit Tier)

- [x] 2.1 `lib/features/seasons/setup/setup_wizard_state.dart`:
      freezed `SetupWizardState` (step, seasonNumber, seasonName,
      blocks: List<BlockDraft>, phase, createdRefs) + pure
      validation functions (number > 0, ≥1 block, episode count >
      0)
- [x] 2.2 `setup_wizard_controller.dart`: `@riverpod` controller;
      state transitions (step forward/back, draft editing, template
      application, abort reset) — unit tests without Flutter
      imports, Ok and Err branches
- [x] 2.3 Smart-default season number (max+1 from the seasons state)
      as a pure function + unit tests (empty list, collision, gaps)

## 3. Dispatch Sequence (Unit/Widget Tier)

- [x] 3.1 Dispatch reduction over the existing repositories
      (`SeasonRepository` → `BlockRepository` → `EpisodeRepository`
      per block): ids flow exclusively from responses into the
      subsequent commands (CQRS boundary), AUTHZ-GATE comments per
      dispatch (`grep AUTHZ-GATE` stays green)
- [x] 3.2 Progress state per command (`dispatching` phase with
      sub-step display); partial-failure reduction (created-so-far
      summary + retry of the remaining commands, in-session) —
      unit tests focused on the reduction with fake repositories
      (Err branches: conflict, transport)
- [x] 3.3 Abort semantics: `PopScope` + confirmation dialog in
      editing/review; disabled during dispatch — widget tests for
      both paths

## 4. Step Widgets (Widget Tier)

- [x] 4.1 Season step: number field (smart default), optional name,
      live "Season n" preview — widget tests including validation
      copy per error code
- [x] 4.2 Blocks step: repeatable block drafts (episode count,
      optional title, removal), template suggestions ("4 Blöcke à
      8 Episoden", "3 Blöcke à 6") as expandable chips — widget
      tests for template application and draft editing
- [x] 4.3 Review step: summary (season + blocks + total episodes),
      confirm CTA — goldens
- [x] 4.4 Completion screen: result overview; conditional CTA
      "AI-Import starten" (AI configuration read before render, no
      CTA without configuration — instead an info card linking to
      the AI configuration screen) — widget tests for both CTA
      states
- [x] 4.5 Progress indicator "Schritt x von n" + directional step
      transitions (semantic labels, correct dark/light)

## 5. Entry Points & Integration

- [x] 5.1 Wizard page pushed on the Season tab's navigator; entry
      from the empty-state CTA (coordination with
      `redesign-seasons-home`) and from the create-flow menu
      (alongside the quick-create sheet)
- [x] 5.2 Gherkin `features-spec/setup/season-wizard.feature`: happy
      path, template application, partial failure + retry, abort
      with discard (runs on device via flutter_gherkin)
- [x] 5.3 Integration test on an emulator: full wizard run against
      the dev backend (season → 2 blocks → review → completion)
      including the abort path

## 6. Tests, Goldens & Wrap-up

- [x] 6.1 Goldens: all 4 steps + completion (light/dark), validation
      and error states
- [x] 6.2 `flutter analyze` + `breakdown_lints`, format, coverde
      threshold on changed code green
- [x] 6.3 `openspec validate add-season-setup-wizard` — change
      valid; update the screen spec if the implementation deviates
