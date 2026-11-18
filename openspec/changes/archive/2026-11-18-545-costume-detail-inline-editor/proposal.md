<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# 545-costume-detail-inline-editor

## Why

`CostumeDetail` rows are append-only from the UI: the only affordance is the
`＋ Detail hinzufügen` button, which opens a `showDialog` form (`_AddDetailForm`,
`costume_detail_screen.dart`). Three problems, none depending on the (already
landed) data-model change #543:

1. **Cumbersomeness / focus loss** — tap button → dialog → fill → Add → dialog
   closes → snackbar, repeated per detail. And although #544 merged
   `updateDetail` / `removeDetail` on the controller + repository, no UI call
   site exists yet: there is no edit and no delete on a row. The editor is an
   append-only drop box with a detour.
2. **Required fields are not recognisable** — `text` is the only required
   field but is nowhere marked as such; `autovalidateMode` is missing, so the
   error appears only after submit; the action stays enabled with an empty
   required field; the (already pure-description) subject is never marked
   optional.
3. **The modal competes with the keyboard** — `showDialog` caps the dialog
   height while the keyboard claims the same space; inline (the page scrolls)
   has no such collision.

## What Changes

- **Inline editor instead of the modal.** `_AddDetailForm` (dialog content)
  becomes `_DetailEditor` — a `ConsumerStatefulWidget` embedded in the row
  list inside `_DetailsSection`, with `initial: CostumeDetailView?`
  (`null` = create mode). One widget, one test set, both modes.
- **Container state** `String? _editingDetailId` in a stateful
  `_DetailsSection` controls which row's editor is open; the create entry is
  a `＋` row at the end of the list that opens the same editor in create
  mode (no duplicate form, no FAB). `Scrollable.ensureVisible` on open.
- **Row affordances** (mirroring `_ShootNotes` in
  `scene_shoots_screen.dart`): `ListTile` with `title` = `subject ?? text`,
  `subtitle` = the composed remainder; `trailing` = edit `IconButton`
  (tooltip `commonEdit`, key `costume-detail-edit-<id>`) + delete
  `IconButton` (tooltip `commonDelete`, key
  `costume-detail-delete-<id>`) **with a confirmation dialog** (destructive
  action, glossary rule `common.delete`: always with confirm dialog).
- **Validation invariants** (independent of the layout):
  - `text` field marked **required** (`InputDecoration` `helperText`
    `costumeDetailTextRequiredHint`, `"*" Text` suffix in `label`), plus
    `autovalidateMode: AutovalidateMode.onUserInteraction` so the
    `costumeDetailTextRequired` error appears after first input, not only
    after submit.
  - `subject` field marked **optional** (`helperText`
    `costumeDetailSubjectOptional`) — consistent with the required marking.
  - Save button `onPressed: null` while `text.trim().isEmpty` (visual
    disabled state — the affordance itself validates).
- **No category field** (satisfied already since the #543 follow-up; the
  category moved to the identity section) — recorded, tested for absence.
- **Side finding:** the doc comment on `_PhotosSectionState._detail`
  (`costume_detail_screen.dart`) claims the list query returns no
  `details`/`photos` and the view only comes from the cache. Stale:
  `list_by_season` batch-enriches pages since the #543/#544 tranche
  (`crates/infra/src/queries/costume.rs` `enrich_many`, 3 queries per page,
  details included). Corrected at the call sites.
- **Docs:** `docs/design/screens/costumes.md` (layout Salt wireframe,
  components table, interactions, input/validation) and
  `docs/design/glossary.md` (new copy keys, edit/delete affordances)
  extended in the same PR; `scripts/check-design-diagrams.sh` green.

## Impact

- **Affected specs:** deltas under
  `openspec/changes/545-costume-detail-inline-editor/specs/`
  (`flutter-costumes-screen` — inline detail editor + required-field
  affordance requirements). Main specs untouched until archive.
- **Affected code:**
  `frontend-flutter/lib/features/costumes/costume_detail_screen.dart` (only
  behavioral changes in the details surface), stale doc-comment corrections
  in `costume_detail_screen.dart` / tests. No wire-contract change:
  `updateDetail`/`removeDetail` (merged for #544) are consumed as-is; 
  `backend/openapi.yaml` is not touched, no client regeneration is needed.
- **New ARB keys** (de/en): `costumeDetailEditDetail`,
  `costumeDetailDeleteTitle`, `costumeDetailDeleteMessage`,
  `costumeDetailTextRequiredHint`, `costumeDetailSubjectOptional`.
  Existing `costumeDetailAddDetail`, `costumeDetailSubject`,
  `costumeDetailText`, `costumeDetailTextRequired`, `commonEdit`,
  `commonDelete`, `commonSave`, `commonCancel` reused.
- **Tests:** widget tier for the editor (create opens via `＋` row, edit
  opens via `✎`, save disabled / error-with-input, delete confirm, `Result`
  Err branch → command-error banner, subject toggle consistency);
  new open-editor goldens (`costumes_screen` variants re-run, the collapsed
  detail rows unchanged → the 4 existing goldens stay valid); tier-1 unit
  tests for the row-text composition and the reused pure helpers.
