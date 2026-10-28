<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.4 (opencode-go) -->

# Flutter AI import: Pass-2 outfit provenance & wardrobe-gap candidate picker (issue #745)

## Why

The backend change `ai-import-decision-outfit-continuity` shipped Pass 2 (the
Decision-Model cross-scene outfit continuity scan) and published its wire
contract, but the Flutter client was explicitly out of scope (`tasks.md` → §7).
The client can already *decode* the contract — PR #746 regenerated
`vendor/breakdown_api` and pinned the four origin values with a regression test
— yet renders the pre-Pass-2 surface:

- a look the pass **continued** from an earlier scene or **inferred** from the
  scene's context renders indistinguishably from a quoted one, and its
  (deliberately empty) `source_quote` renders as an empty evidence line, which
  reads as if the script had stated the look;
- a wardrobe gap — the pass's Option C outcome, a `dropped_row` uncertainty on
  `outfits` — renders as server prose with no way to act on it, even when the
  script supports concrete candidates;
- `ApplyAiImportRequest.continuitySelections` is never populated, so a reviewer
  cannot resolve a gap at all.

Issue #745 is the Flutter half: say where each look came from, and let the
reviewer resolve a gap in one interaction with ONLY script-derivable options.

## What Changes

- **`lib/features/ai_import/import_jobs/continuity_gap.dart` (new, pure):**
  `continuityGapsOf(ScriptContext)` derives the reviewer-selectable gaps — the
  Pass-2 `dropped_row`/`outfits` uncertainties whose candidate list the script
  supports — and pairs each one with the scene figure it belongs to, plus
  `characterIdentity()` (the backend's case-folded, whitespace-collapsed
  matching key) so the apply request can address the selection.
- **`preview_screen.dart`:** ONE provenance badge per outfit row
  (*wörtlich aus dem Skript* / *aus dem Skript abgeleitet* / *übernommen aus
  Szene N* / *aus dem Szenenkontext abgeleitet*), no source-quote line for a
  Pass-2 look, and a one-tap candidate picker for a gap (one chip per
  candidate, one chip for "leave the scene without a look"). A gap WITHOUT
  candidates keeps the existing plain notice.
- **`apply_controller.dart`:** `PreviewOutfit` carries the origin + provenance;
  `AiApplyState` carries the gaps and the reviewer's picks, builds
  `continuity_selections`, and counts a pick as a review edit
  (`accept_as_is` stays truthful). `copyWith` replaces the hand-written
  re-constructions, which silently dropped the #706 day decisions on two paths.
- **`apply_screen.dart`:** each gap's resolution is repeated at the dispatch
  (EU AI Act review gate); `409 ai-import.apply-unknown-continuity-candidate`
  is localized as "refresh the preview and re-apply".
- **l10n / docs:** new de/en ARB keys, glossary inventory + icon rows, and a
  section in `docs/design/screens/ai-import-jobs.md`.
- **Tests:** tier-1 gap-derivation tests, widget + golden tests for the four
  badges, the suppressed quote and the picker→wire path, and a `@pending`
  Gherkin feature for the end-to-end flow.

## Non-goals

- No backend change: the contract is an input of this change (the client tree
  is already byte-identical to `scripts/regen-client.sh`).
- The apply worker's shared-`OutfitId` behaviour (two scenes cast ONE outfit) is
  server-side and already covered by the backend tests; the client only sends
  the selection and shows the resulting outcome counts.
- No offline command queue: picks are dispatched with the apply request, as all
  other reviewer decisions are.

## Impact

- **Capabilities:** `flutter-ai-import-workflow` (delta: preview/apply surface),
  `flutter-gherkin-hybrid` (one more non-critical `@pending` feature).
- **Version:** `0.4.0-beta.18+110 → 0.4.0-beta.19+111`; `CHANGELOG.md` entry.
- **Risk:** low — additive UI over an already-published contract. A client that
  cannot resolve a gap simply keeps applying the preview unchanged (the
  pre-#745 behaviour), so nothing regresses when the backend sends no
  candidates.
