<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# 545-costume-detail-inline-editor — Tasks

## 1. Inline editor widget

- [x] 1.1 Replace `_AddDetailForm` + `showDialog` with `_DetailEditor`
      (`ConsumerStatefulWidget`, `initial: CostumeDetailView?`, create vs
      edit mode), embedded in the details section.
- [x] 1.2 Make `_DetailsSection` stateful; add `String? _editingDetailId`
      container state; add the `＋` create row that opens the same editor in
      create mode; `Scrollable.ensureVisible` on open.
- [x] 1.3 Row affordances — `ListTile` `trailing` edit + delete
      `IconButton`s with contract keys and localized tooltips; delete asks
      for confirmation (destructive glossary rule) before dispatching.
- [x] 1.4 Required-field affordance — required `text` (asterisk label +
      helper), optional `subject` helper, `autovalidateMode` on first
      interaction, save disabled while `text.trim().isEmpty`.
- [x] 1.5 Dispatch through `CostumesController.updateDetail` /
      `removeDetail` / `addDetail` (`Result`-typed, handled errors left to
      the command-error provider); keep the per-state `TextEditingController`
      lifecycle correct without a modal route around it.

## 2. Side finding

- [x] 2.1 Correct the stale `_PhotosSectionState._detail` doc comment
      (batch-enriched list rows since #543/#544) and the matching stale
      comments in the test fake + screen comments.

## 3. ARB + generated localizations

- [x] 3.1 Add the new de/en keys: `costumeDetailEditDetail`,
      `costumeDetailDeleteTitle`, `costumeDetailDeleteMessage`,
      `costumeDetailTextRequiredHint`, `costumeDetailSubjectOptional`.
- [x] 3.2 Re-run `flutter gen-l10n` and commit the regenerated catalogs.

## 4. Tests

- [x] 4.1 Widget tier (detail screen): create opens via the `＋` row,
      edit opens via `✎`, save disabled while `text` empty, error appears
      after input (autovalidate), delete asks + dispatches, command error
      surfaces via the banner (Err branch), category remains absent.
- [x] 4.2 Widget tier (screen): goldens — verify the 4 existing
      collapsed-state goldens stay valid, add an open-editor golden.
- [x] 4.3 Tier-1 unit: no new pure helpers needed (row composition is
      widget-side state), so the tier-1 set covers the (already-tested)
      controller seam reused as-is.

## 5. Docs / design

- [x] 5.1 Update `docs/design/screens/costumes.md` (layout Salt wireframe
      inline editor block, components rows, interactions + input/validation
      paragraphs, tests paragraph) and `docs/design/glossary.md` (new keys,
      edit affordance row, delete-with-confirm row).
- [x] 5.2 `scripts/check-design-diagrams.sh` green.

## 6. Validation

- [x] 6.1 `dart format --set-exit-if-changed .` clean
- [x] 6.2 `flutter analyze` clean (incl. `breakdown_lints` runner)
- [x] 6.3 `flutter test` green (home directory + all costume tests);
      `coverde` line/branch coverage unchanged or improved on changed code
- [x] 6.4 `scripts/check-design-diagrams.sh` + glossary check
      (`tool/check_glossary_catalog.py`) clean
- [x] 6.5 OpenAPI drift: N/A — `backend/openapi.yaml` untouched this change
      (the #544 routes were already merged and the committed client covers
      them); verified against the base branch with the merge-base diff.
