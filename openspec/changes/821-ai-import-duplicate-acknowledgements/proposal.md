<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# 821 — A duplicate `(scene_index, field)` acknowledgement is a no-op, not a dead end

## Why

Issue #821 (live 2026-11-04). A script apply failed with the opaque
`422 domain.validation` ("Das Anwenden ist fehlgeschlagen (domain.validation).")
and **nothing was written**: the refusal happens at the API edge, before the
worker's first command.

The stored preview carried 90 uncertainties — 62 advisory `dropped_row` plus 28
blocking `field_ambiguity` — but only **8 distinct `(scene_index, field)`
pairs** (e.g. 12 entries for `(0, category)`). Two independent faults met:

1. **Client (the actual defect).** The acknowledgement state is a set over the
   `(scene_index, field)` key, but
   `AiApplyState.buildAcknowledgements()` iterated the preview's **entries** and
   emitted one `UncertaintyAcknowledgement` per entry. One tap acknowledged all
   entries of a pair (the gate went false for all of them at once), and the wire
   request then repeated the pair — 28 wire entries for 8 questions, 20
   duplicates. The panel rendered one checkbox per entry (28 tiles), so the
   duplication was visible but read as harmless redundancy.
2. **Server.** `apply_ai_import` refused a repeated pair with
   `ApiError::Validation`, which always renders the content-free
   `422 domain.validation` — the reason never reached the client, so the apply
   card fell back to its generic copy.

Because apply is only enabled once *all* blockers are checked, the failure was
guaranteed rather than a race: any preview whose extraction asked several
questions about the same field of the same scene could never be applied.

## What Changes

- **Client — one decision per pair.** `AiApplyState.blockingUncertaintyGroups`
  collapses the preview's blocking entries into one group per
  `(scene_index, field)` pair, in preview order. The gate
  (`hasUnacknowledgedBlockers`), the acknowledge panel and
  `buildAcknowledgements()` all read that single view, so the per-entry/per-key
  divergence cannot reappear. The wire list carries **one** acknowledgement per
  acknowledged pair.
- **Client — one panel row per pair.** The acknowledge panel renders one
  checkbox per group (the first entry supplies the note; the preview screen
  still lists every entry with its own note). A preview with 28 blocking
  entries over 8 pairs now shows 8 questions, not 28.
- **Server — acknowledgements are idempotent (decision, issue #821).** The
  acknowledgement payload is the pair itself: `ensure_script_applyable` matches
  by `(scene_index, field)` and there is no ordering or last-write semantics to
  lose, so a repeat is a no-op. The API edge now **skips** a repeated pair
  instead of answering `422 domain.validation`. The existence check ("must
  reference a blocking uncertainty the preview carries") still runs on every
  entry, so a duplicate can never smuggle in an unknown pair. **Decision
  recorded:** repeated acknowledgements become idempotent server-side; no new
  problem code is registered (nothing left to explain — the request is valid),
  and the client never relies on the tolerance (it dedupes).

Non-goals: no change to the advisory `dropped_row` handling (#745), no change to
the `ai-import.apply-blocked` gate or its `blocking_uncertainties` extension
(#663), no new ARB keys.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ai-import`: acknowledgement set semantics — a repeated
  `(scene_index, field)` pair is idempotent, the pair stays the acknowledgement
  unit.
- `flutter-ai-import-workflow`: one acknowledgement row per blocking decision
  and exactly one wire acknowledgement per pair.

## Impact

- `frontend-flutter/lib/features/ai_import/import_jobs/apply_controller.dart` —
  `BlockingUncertaintyGroup`, `AiApplyState.blockingUncertaintyGroups`, gate +
  `buildAcknowledgements()`, single-build dispatch.
- `frontend-flutter/lib/features/ai_import/import_jobs/apply_screen.dart` — one
  acknowledge row per group.
- `frontend-flutter/test/features/ai_import/preview_apply_test.dart` — unit test
  pinning the ack payload for repeated pairs; widget test pinning one row, one
  wire acknowledgement and a dispatch that reaches the worker.
- `backend/crates/api/src/handlers/mod.rs` — the duplicate-pair refusal is
  dropped; the existence check stays.
- `backend/crates/api/tests/handler_ai_import_ports.rs` — the duplicate test is
  inverted into an acceptance test.
- No `backend/openapi.yaml` change (the request schema is unchanged, no problem
  code added), therefore no Dart client regeneration.
