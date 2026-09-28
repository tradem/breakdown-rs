<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks — Flutter client of "One costume = one category" (issue #543)

Scope note: the backend (core/infra/api + migration + specs + openapi +
vendored client regen) and the minimal wire-break adoption landed already in
the merged PR #559 (#543 backend + wire-break adoption on `main`). This task
list covers the **explicitly deferred remainder**: the costume category
picker, the `setCategory` command surface, tests, and the design docs the
Flutter PR owns (per the user-approved scope decision recorded in the
proposal).

## 1. Wire + data layer

- [x] **1.1 Category repository write method**
      (`lib/data/costume_repository.dart`): `setCategory(String id,
      SetCostumeCategoryRequest request)` via
      `api.getHandlersApi().setCostumeCategory(...)`, `Result`-typed,
      rebuild-only — the generated `SetCostumeCategoryRequest` model already
      exists in `vendor/breakdown_api`.
- [x] **1.2 Optimistic edit helper**: `applyCategoryOptimistic(row,
      categoryId, categoryName)` alongside the existing
      `applyAssign/Unassign/Notes/AddDetail` helpers.

## 2. Controller (`costumes_controller.dart`)

- [x] **2.1 `CostumesController.setCategory({required CostumeView costume,
      required String? categoryId, String? categoryName})`**:
  - `// AUTHZ-GATE:` the `_assignGate()` capability check
    (`assign_costumes` — the same backend predicate
    `authorize_costume_scoped` derives the handler gate from) BEFORE any
    network call; denial short-circuits with the localized 403 narrative
    and a provable repository call-count of zero.
  - Idempotent client-side no-op: setting the current category id again
    (or clearing when already empty) returns `Right(version)` without a
    network call (mirrors the backend's state-based no-op).
  - `_resolveVersion` freshness fence, optimistic-after-2xx overlay
    (category swapped in a costume-level rebuild), bounded-retry
    reconcile after the ack — the same pipeline as `assign`/`addDetail`.
  - `Err` → `_setCommandError(costume, …)` → banner keyed on the stable
    problem `code`; `costume-category.season-mismatch` gets its own
    localized narrative.
- [x] **2.2 `costumeErrorCopy` routes** for
      `costume-category.season-mismatch` and `costume-category.archived`
      (new ARB keys, de and en).

## 3. UI — category picker in the editor's identity section

- [x] **3.1 `CostumeCategorySection` in `CostumeDetailPanel`** (above
      `_DetailsSection`): the costume's current category (icon + name /
      "Ohne Kategorie" fallback, fence-aware overlay key like the
      assignment tile) and the bottom-sheet picker — every option shows
      its icon next to always-visible text
      (`BreakdownMaterialIcons.forCostumeCategory`), never icon-only.
      Includes the deliberate "Ohne Kategorie" (clear) row; archived
      categories are never offered.
- [x] **3.2 Picker source**: the season's projected vocabulary via the
      existing `costumeCategoriesViewProvider(seasonId)` (read-DTO join,
      no fresh network dependency of the editor).

## 4. Specs / docs

- [x] **4.1 `docs/design/screens/costumes.md`**: Salt layout gains the
      editor identity section's category row (icon + text +
      "Kategorie wählen"), the components table rows for the category row
      and picker, interactions, input & validation for `set_category`.
      PlantUML check (`scripts/check-design-diagrams.sh`): all blocks
      compile.
- [x] **4.2 `docs/design/glossary.md`**: the `categories.icon` rule "every
      category display shows the icon next to the text" extended to the
      picker; row for the `Kategorie wählen` picker copy key.
- [x] **4.3 This `tasks.md` written as the change's write-up.**

## 5. Tests

- [x] **5.1 Controller/widget tests**
      (`test/features/costumes/costume_detail_screen_test.dart`, new
      group *CostumeDetailScreen category section (issue #543)*): set with
      version echo + optimistic overlay key; picker hides archived
      vocabulary and always offers the clear row; authz denial narrative
      with request-counter proof (`setCategoryCalls == 0`); cross-command
      version freshness (notes save then category echoes the ack version);
      409 `costume-category.season-mismatch` distinct narrative; idempotent
      clear no-op (zero network calls).
- [x] **5.2 Goldens**: the 4 screen goldens re-verified
      (`costumes_screen_{light,dark}_{android,macos}`) — tile identity
      pixels unchanged; no golden regeneration needed.
- [x] **5.3 `flutter analyze` clean; `flutter test` 1092/1092 green;
      `dart format --set-exit-if-changed` clean; `flutter gen-l10n`
      emitted (de template + en catalog, key parity).**
