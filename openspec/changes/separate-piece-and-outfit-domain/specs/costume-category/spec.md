<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

## RENAMED Requirements

- FROM: `### Requirement: CostumeDetail carries optional subject; the category moved to the costume`
- TO: `### Requirement: PieceDetail carries optional subject; the category lives on the piece`

- FROM: `### Requirement: A costume belongs to exactly one category`
- TO: `### Requirement: A piece belongs to at most one category`

- FROM: `### Requirement: CostumeCategory rename propagates to the costume read model`
- TO: `### Requirement: CostumeCategory rename propagates to the piece read model`

## MODIFIED Requirements

### Requirement: CostumeCategory uses soft-archive, not hard-delete
A `CostumeCategory` SHALL support `ArchiveCostumeCategory { id, version }` emitting `CostumeCategoryArchived { id, version }` with `archived = true`. There SHALL be no unarchive command. Mutation commands dispatched to an archived aggregate (`RenameCostumeCategory`, `ReorderCostumeCategory`) SHALL be rejected with `CostumeCategoryError::ArchivedCannotBeMutated`. Archived categories SHALL remain referenceable by **piece** category references (a `Piece` carries `category_id`) and SHALL be hidden from picker queries used for new categorisation. The API edge SHALL reject a `SetPieceCategory` that targets an archived category with `409 costume-category.archived` before dispatch.

#### Scenario: Archiving a referenced category succeeds
- **WHEN** a `CostumeCategory` referenced by one or more pieces receives `ArchiveCostumeCategory`
- **THEN** the aggregate SHALL emit `CostumeCategoryArchived` and existing piece references SHALL remain resolvable in the read model with their denormalised `category_name` intact

#### Scenario: Mutating an archived category is rejected
- **WHEN** a `RenameCostumeCategory` command targets an archived CostumeCategory
- **THEN** the aggregate SHALL reject with `CostumeCategoryError::ArchivedCannotBeMutated` and SHALL emit no event

#### Scenario: Archived categories hidden from pickers
- **WHEN** a query lists CostumeCategories available for new categorisation under Season S
- **THEN** only categories with `archived = false` SHALL be returned

### Requirement: PieceDetail carries optional subject; the category lives on the piece
`PieceDetail` SHALL carry `id: Uuid`, `subject: Option<String>`, and `text: String` on the wire and in the read model (`PieceDetailView`). Because the clean cut removes the pre-#543 costume event shapes entirely, `PieceDetail` SHALL carry **no** `category_id` field at all — neither on the event payload nor on the wire; the category is exclusively `Piece.category_id`. The former `CostumeDetail.category_id` / `category_name` columns SHALL be dropped from the piece detail projection rather than carried along for replay.

#### Scenario: Adding a detail (pure description)
- **WHEN** an `AddPieceDetail { id, detail, version }` command is dispatched where `detail = { id, subject: Some("Rote Jacke"), text: "Knöpfe vorne" }`
- **THEN** the aggregate SHALL emit `PieceDetailAdded { id, detail, version }`
- **AND** the serialised payload SHALL contain no `category_id` key

#### Scenario: Existing text is not migrated into subject
- **WHEN** an existing `PieceDetail` is read
- **THEN** `subject` SHALL deserialize as `None` when absent, and `text` SHALL retain its prior value and meaning
- **AND** `projection_piece_detail` SHALL expose `piece_id`, `detail_id`, `subject`, `text` only — no category column survives the cut

### Requirement: A piece belongs to at most one category
A `Piece` SHALL belong to at most one `CostumeCategory` (n:1). The category is set or cleared via `SetPieceCategory { id, category_id: Option<CostumeCategoryId>, version, project_id }`, emitting exactly one `PieceCategorySet { id, category_id, version }`; `category_id: None` clears the binding. Re-dispatching the command with the value the piece already carries SHALL be a state-based no-op (no event, `Ok`). Because the `Piece` is repertoire-scoped while `CostumeCategory` is season-scoped, the cross-aggregate season invariant `category.season_id ∈ repertoire_seasons(piece)` SHALL be pre-checked at the API edge **before dispatch**: a category from a season outside the piece's repertoire SHALL be rejected with `409 costume-category.season-mismatch` (extension `category_id`), an archived category with `409 costume-category.archived`, an unknown category with `404 costume-category.not-found`. There is no projection unique constraint for this invariant (it is not a uniqueness case); the projector resolves `category_name` best-effort (`None` on a projection miss) and cannot fail at this point.

#### Scenario: Setting a category from a permitted season
- **WHEN** a `SetPieceCategory` command targets a piece whose repertoire contains the category's season
- **THEN** the aggregate SHALL emit `PieceCategorySet { id, category_id, version }` with the piece's version incremented by exactly one

#### Scenario: Setting a category from a foreign season is rejected before dispatch
- **WHEN** the category's `season_id` is not a repertoire season of the piece
- **THEN** the API edge SHALL return `409 costume-category.season-mismatch` with the `category_id` extension and SHALL NOT dispatch the command (no event is written)

#### Scenario: Clearing the category
- **WHEN** a `SetPieceCategory` command with `category_id: None` targets a categorized piece
- **THEN** the aggregate SHALL emit `PieceCategorySet { id, category_id: None, version }` and the read model SHALL show the piece as uncategorised

#### Scenario: Re-setting the current category is a no-op
- **WHEN** a `SetPieceCategory` command carries the `category_id` the piece already has
- **THEN** the aggregate SHALL emit no event and the command SHALL succeed

### Requirement: CostumeCategory rename propagates to the piece read model
A projector subscribed to the `costume_category` stream SHALL, on `CostumeCategoryRenamed`, refresh the denormalised `category_name` column of every `projection_piece` row whose `category_id` matches the renamed category. On `CostumeCategoryArchived`, the projector SHALL set `archived = true` on `projection_costume_category` and SHALL NOT null out existing `projection_piece.category_name` references.

#### Scenario: Rename refreshes denormalised name
- **WHEN** a `CostumeCategory` named "Schuhe" is renamed to "Footwear"
- **THEN** every `projection_piece` row referencing it SHALL have `category_name = "Footwear"` after the projector catches up

#### Scenario: Archive preserves historical names
- **WHEN** a `CostumeCategoryArchived` event is processed
- **THEN** `projection_costume_category.archived` SHALL become `true` and referencing `projection_piece.category_name` values SHALL retain their last-known value

### Requirement: CostumeCategory projection schema
The `projection_costume_category` table SHALL contain `id, season_id, name, order_key, archived, version, updated_at` with an index on `(season_id, order_key)`. The `projection_piece` table SHALL carry nullable `category_id` and `category_name` columns. The `projection_piece_detail` table SHALL carry `piece_id, detail_id, subject, text` — the legacy `category_id` / `category_name` columns SHALL NOT be carried over.

#### Scenario: Projection schema
- **WHEN** the projection schema is inspected
- **THEN** `projection_costume_category` SHALL have the listed columns plus a `(season_id, order_key)` index
- **AND** `projection_piece` SHALL have nullable `category_id`/`category_name` columns
- **AND** `projection_piece_detail` SHALL NOT expose a category column

## REMOVED Requirements

### Requirement: Legacy detail categories derive the costume category on replay (first-wins)
**Reason**: The costume→piece cut is clean (no production event streams exist), so no pre-#543 costume stream can ever be replayed. The first-wins replay derivation existed only to keep legacy `CostumeDetail.category_id` values consistent between `CostumeAggregate::apply` and the costume projector; with `PieceDetail.category_id` gone there is nothing left to derive.

**Migration**: None required. Retired `"costume"` streams are inert (the piece projector does not subscribe to them); dev environments reset their volumes, and no production deployment holds costume streams. `Piece.category_id` is set exclusively through `SetPieceCategory`.
