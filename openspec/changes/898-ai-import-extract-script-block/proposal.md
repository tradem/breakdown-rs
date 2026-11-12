<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 898 — "Block extrahieren": the script's block becomes the import target

## Why

The import target card offers *switch block* (#828) and *create block* (#828),
so the user can put the import into **a** block — but not into the block the
**script itself names**. When the target season already has a block (`Block 1`)
and the script's page header says `Block 98`, the card resolves `Block 1`, the
dispatch pins the job to `Block 1`, and the script's own block is only reported
as a mismatch hint (#827) — never used. The apply then hits the cross-block
guard (`403`), or the rows land in a block nobody chose.

The reversed state works today: a season **without** any block dispatches
block-less (#829) and the preview adopts the script's block afterwards — creating
it when the season lacks that number. That machinery is exactly what this
scenario needs. What is missing is the *choice*: the block-less dispatch is
**derived** from an empty season (`seasonHasNoBlock && target == null`), so a
season that already has a block can never reach it.

## What Changes

- The import target card gains a third action, **"Block extrahieren"**
  (`ai-import-target-extract`), next to *Block wechseln* / *Block anlegen*. It is
  offered whenever the target season is known and is not in the "no block at
  all" arm (there the block-less dispatch is already the only target that
  exists).
- The choice is **per dispatch, not a mode**: it is cleared by a kind switch and
  by a successful upload, and it is **not** implemented by clearing the ambient
  block scope (that scope is the shell's block pill and other screens' target).
- While the choice is active the card states the deferred target
  (`{season} · Block unbekannt`) plus the existing block-less hint, and offers an
  **undo** back to the resolved line — the line the user sees and the header the
  dispatch sends stay one value (issue #771's single seam).
- After extraction nothing new is needed: the job is block-less, so
  `ScriptBlockScope.targetBlockUnset` is true and the preview's target card
  adopts the script's block — the existing block when the season has that
  number, otherwise a block created with it.
- Copy (de/en ARB), widget tests, and the `ai-import-submit` screen spec.

**No wire change, no backend change**: the block-less upload, the late target
attach, and the script's block number all landed with #827 / #829.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-ai-import-workflow`: the submit screen's target card gains the
  per-dispatch "Block extrahieren" choice, the deferred-target line it renders
  while active, and the guarantee that a script-stated block becomes the target
  after extraction (reused or created).

## Impact

- `frontend-flutter/lib/features/ai_import/import_jobs/import_submit_screen.dart`
  (`_ImportTargetCard`, `_ImportTargetActions`, `_SubmitButton`).
- `frontend-flutter/lib/features/ai_import/import_jobs/import_submit_controller.dart`
  (one per-dispatch intent notifier next to `pendingDocumentProvider`).
- `frontend-flutter/lib/l10n/app_de.arb` + `app_en.arb` and the generated
  catalogs (`flutter gen-l10n`).
- `frontend-flutter/test/features/ai_import/import_submit_screen_test.dart`.
- `docs/design/screens/ai-import-submit.md`.
- Untouched by design: `preview_screen.dart` (the adoption path is reused as-is),
  `backend/**`, `backend/openapi.yaml`, `vendor/breakdown_api/**`.
