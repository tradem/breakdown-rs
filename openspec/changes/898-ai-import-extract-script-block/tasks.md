<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 898 — Tasks

One PR, frontend only. The backend path (block-less upload, late attach) and
the preview's adoption of the script's block already exist (#827 / #829) and are
**not** touched.

## 1. Per-dispatch intent

- [x] 1.1 `import_submit_controller.dart`: add the `Notifier<bool>`
      `aiImportExtractBlockProvider` next to `pendingDocumentProvider`, with the
      doc comment stating "per dispatch, never a mode, never a scope mutation"
      (design D1).
- [x] 1.2 `import_submit_controller.dart`: clear the intent wherever the pending
      document is cleared (`selectKind` and the successful dispatch), so no stale
      choice survives its dispatch (D1).
- [x] 1.3 `import_submit_screen.dart` `_ImportTargetActions`: third visible text
      button `ai-import-target-extract` labelled `aiImportTargetExtractBlock`,
      offered when a season is known and the resolution is not the
      "no block at all" arm (D2).
- [x] 1.4 `import_submit_screen.dart` `_ImportTargetCard`: while the intent is
      active render `{season} · Block unbekannt` plus `aiImportTargetBlockLess`,
      and turn the action into its undo (restores the resolved line without
      touching `activeBlockProvider`) (D3).
- [x] 1.5 `import_submit_screen.dart` `_SubmitButton`: `blockLess` reads the
      intent (plus the existing empty-season derivation) and passes it to
      `submit(...)`; the controller path stays unchanged (D4).

## 2. Copy & i18n

- [x] 2.1 `lib/l10n/app_de.arb`: `aiImportTargetExtractBlock`,
      `aiImportTargetExtractBlockActive` (undo label) and the hint that the block
      is taken after the upload and created when missing (D6).
- [x] 2.2 `lib/l10n/app_en.arb`: the same keys in English.
- [x] 2.3 `flutter gen-l10n` and the de/en key-parity check; the generated
      catalogs are rebuilt, never hand-edited.

## 3. Tests

- [x] 3.1 A season **with** a block renders all three actions (the third one
      under `ai-import-target-extract`).
- [x] 3.2 Selecting it and submitting sends the declared season and **no**
      `X-Active-Block` (`repo.lastSendActiveBlock == false`) while
      `activeBlockProvider` keeps its block.
- [x] 3.3 The deferred line renders `Block unbekannt` while the intent is active,
      and the undo restores the resolved line without changing the scope.
- [x] 3.4 The intent is cleared by `selectKind` and by a successful dispatch (a
      follow-up dispatch carries `X-Active-Block` again).
- [x] 3.5 The existing default path still sends the resolved block (the #829
      review finding: nothing turns block-less behind the user's back).
- [x] 3.6 A season **without** blocks renders no duplicate extract action (the
      block-less dispatch is already implicit there).

## 4. Docs

- [x] 4.1 `docs/design/screens/ai-import-submit.md`: third target-card action in
      the element table, the deferred-target state, and the note that the
      script's number is only known after extraction.
- [x] 4.2 Cross-reference this change from the target-card section so the
      #828/#829 lineage stays readable.
