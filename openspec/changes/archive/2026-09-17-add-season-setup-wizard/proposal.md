<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Why

Creating a production hierarchy today requires many disconnected
steps: a season via bottom-sheet form, then block-by-block creation
on the blocks screen, then episodes one by one. As usage shifts
toward daily planning and AI import, setup friction is the main
entry barrier for new productions. The research report (§5)
recommends a Yazio/Hevy-style linear wizard; team decisions: no
resume (abort discards, decision 3) and the completion offer for AI
import is conditional on existing AI configuration (decision 6).

## What Changes

- Add a **season setup wizard**: a linear multi-step flow —
  (1) Season (number with smart default `max+1`, optional name,
  live preview), (2) Blocks (repeatable block drafts: episode count
  with default, optional title; block templates as suggestions),
  (3) Review/summary → dispatch, (4) Completion screen with results
  and the conditional AI-import call to action.
- Progress indicator ("Schritt x von n") and directional
  step transitions; smart defaults throughout.
- On submit: existing commands (`POST /v1/seasons`, `POST /v1/blocks`,
  episode creation per block) dispatch sequentially with the
  established optimistic/bounded-retry reconciliation per step;
  partial failure stops the wizard with a resumable-free but clearly
  reported state (created-so-far summary + retry of the failed
  step's remaining commands, in-session only).
- Abort is destructive (team decision 3): leaving the wizard
  discards drafts after an explicit confirmation dialog; nothing is
  persisted pre-submit.
- Completion CTA "AI-Import starten" renders **only when an AI
  provider/model configuration exists** (checked client-side before
  render); otherwise an info card links to the AI configuration
  screen (team decision 6).
- Entry points: empty-state CTA on the Season tab (from
  `redesign-seasons-home`) and an action in the Season tab's
  create flow.

## Capabilities

### New Capabilities
- `flutter-season-setup-wizard`: the wizard flow contract — steps,
  defaults, validation, dispatch/reconciliation per step,
  abort semantics, conditional completion CTA.

### Modified Capabilities
- None. (The wizard reuses existing command endpoints, repositories,
  and the shell's create entry; `flutter-first-screen` /
  `flutter-seasons-home` are referenced, not modified — their
  empty-state CTAs already anticipate this route.)

## Impact

- **Code:** new `lib/features/seasons/setup/` (wizard controller,
  step widgets, wizard state as freezed model); reuse of
  `SeasonRepository`, `BlockRepository`, `EpisodeRepository` and
  reconciliation machinery unchanged. `create_season_sheet.dart`
  remains for the quick-create path (wizard is additive, not a
  replacement).
- **Tests:** unit (wizard state machine incl. partial-failure
  reduction), widget per step + goldens, Gherkin for the full
  setup flow (designated critical flow per flutter-gherkin-hybrid).
- **Dependencies:** sequenced after
  `redesign-seasons-home` (empty-state entry) — no other coupling.
- **API:** none (existing routes only, existing AUTHZ-GATE checks
  travel with each command dispatch).
