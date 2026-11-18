<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# Tasks: 821-ai-import-duplicate-acknowledgements

## 1. Client — one decision per `(scene_index, field)` pair

- [x] 1.1 `AiApplyState.blockingUncertaintyGroups`: collapse the preview's
      blocking `field_ambiguity` entries into one group per pair, in preview
      order (first entry supplies the panel note).
- [x] 1.2 Derive `hasUnacknowledgedBlockers` and `buildAcknowledgements()` from
      the groups, so the wire list carries exactly one acknowledgement per
      acknowledged pair.
- [x] 1.3 Build the acknowledgement list once per dispatch (it was built twice).
- [x] 1.4 `apply_screen.dart`: render one acknowledge row per group instead of
      one per preview entry.

## 2. Server — acknowledgement set semantics

- [x] 2.1 `apply_ai_import`: drop the duplicate-pair refusal (the payload is the
      pair, so a repeat is a no-op); keep the existence check on every entry.
- [x] 2.2 Invert the pinned test: `apply_rejects_a_duplicate_acknowledgement` →
      `apply_accepts_a_duplicate_acknowledgement` (200, mappings recorded, i.e.
      the apply reaches the worker).

## 3. Tests

- [x] 3.1 Unit: a preview with three blocking entries on `(0, location)` plus one
      on `(1, episode)` yields two groups, two decisions, and a wire list with
      no duplicate pair (and `canApply` flips only after both).
- [x] 3.2 Widget: duplicate blockers render ONE acknowledge row, the dispatch
      carries ONE acknowledgement and the outcome card renders (the apply
      reached the worker).

## 4. Docs & bookkeeping

- [x] 4.1 OpenSpec proposal + delta specs (`ai-import`,
      `flutter-ai-import-workflow`).
- [x] 4.2 Version bump `frontend-flutter/pubspec.yaml`.
- [x] 4.3 `dart format`, `flutter analyze`, `flutter test`,
      `cargo test -p api --test handlers_ai`.
