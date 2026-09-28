## Requirements

### Requirement: CostumeCategory is a Season-scoped aggregate
A `CostumeCategory` SHALL be its own event-sourced aggregate scoped to exactly one `Season` via `season_id: SeasonId`. It SHALL NOT reference Series/Block/Episode. It SHALL carry `id: Uuid` (UUIDv7), `name: String`, `order_key: LexicalSortKey`, `archived: bool`, and `version: AggregateVersion`. The category vocabulary SHALL be user-editable per season (not a fixed enum).

#### Scenario: Creating a costume category
- **WHEN** a `CreateCostumeCategory { id, season_id, name, order_key }` command is dispatched to a new stream
- **THEN** the aggregate SHALL emit `CostumeCategoryCreated { id, season_id, name, order_key, version }` with `archived = false` and `version = AggregateVersion::INITIAL`

#### Scenario: Costume category carries no scope above Season
- **WHEN** a `CostumeCategoryCreated` event is inspected
- **THEN** it SHALL carry `season_id` and SHALL NOT carry `series_id`, `block_id`, or `episode_id`

### Requirement: CostumeCategory ordering is by LexicalSortKey
Listing CostumeCategories within a Season SHALL order by `order_key` lexicographically. `name` has no ordering semantics. Renaming SHALL NOT change `order_key`. Reordering via `ReorderCostumeCategory { id, order_key, version }` SHALL emit exactly one `CostumeCategoryReordered` event whose key is strictly greater than the predecessor and strictly less than the successor when placed between two siblings, and SHALL NOT emit events for sibling aggregates.

#### Scenario: Listing categories in canonical order
- **WHEN** a query requests all CostumeCategories of `Season S`
- **THEN** the read model SHALL return them ordered by `order_key ASC`

#### Scenario: Reorder is a single mutation
- **WHEN** a `ReorderCostumeCategory` command places a new `order_key` between two siblings' keys
- **THEN** exactly one `CostumeCategoryReordered` event SHALL be emitted and no sibling event SHALL be emitted

### Requirement: CostumeCategory uses soft-archive, not hard-delete
A `CostumeCategory` SHALL support `ArchiveCostumeCategory { id, version }` emitting `CostumeCategoryArchived { id, version }` with `archived = true`. There SHALL be no unarchive command. Mutation commands dispatched to an archived aggregate (`RenameCostumeCategory`, `ReorderCostumeCategory`) SHALL be rejected with `CostumeCategoryError::ArchivedCannotBeMutated`. Archived categories SHALL remain referenceable by costume-category references (issue #543: the costume carries `category_id`) and SHALL be hidden from picker queries used for new categorisation. The API edge SHALL reject a `SetCostumeCategory` that targets an archived category with `409 costume-category.archived` before dispatch (issue #543).

#### Scenario: Archiving a referenced category succeeds
- **WHEN** a `CostumeCategory` referenced by one or more costumes receives `ArchiveCostumeCategory`
- **THEN** the aggregate SHALL emit `CostumeCategoryArchived` and existing costume references SHALL remain resolvable in the read model with their denormalised `category_name` intact

#### Scenario: Mutating an archived category is rejected
- **WHEN** a `RenameCostumeCategory` command targets an archived CostumeCategory
- **THEN** the aggregate SHALL reject with `CostumeCategoryError::ArchivedCannotBeMutated` and SHALL emit no event

#### Scenario: Archived categories hidden from pickers
- **WHEN** a query lists CostumeCategories available for new categorisation under Season S
- **THEN** only categories with `archived = false` SHALL be returned

### Requirement: CostumeDetail carries optional subject; the category moved to the costume
`CostumeDetail` SHALL carry `id: Uuid`, `subject: Option<String>`, and `text: String` on the wire and in the read model (`CostumeDetailView`, issue #543). The event payload keeps the legacy `category_id: Option<CostumeCategoryId>` field with `serde(default)` so pre-#543 events replay; newly added details carry `None`. The `text` field SHALL NOT be reinterpreted as `subject` during migration.

#### Scenario: Adding a detail (pure description)
- **WHEN** an `AddDetail { id, detail, version }` command is dispatched where `detail = { id, subject: Some("Rote Jacke"), text: "Knöpfe vorne" }`
- **THEN** the aggregate SHALL emit `DetailAdded { id, detail, version }` carrying `category_id: None` on the wire

#### Scenario: Existing text is not migrated into subject
- **WHEN** an existing `DetailAdded` event predating this change is replayed
- **THEN** `subject` SHALL deserialize as `None` and `category_id` as `None` when absent, and `text` SHALL retain its prior value and meaning

### Requirement: Default categories are seeded via a replay-safe saga on SeasonCreated
A subscriber to `SeasonCreated` events SHALL dispatch `CreateCostumeCategory` commands for each entry of a configurable default seed set (v1 default: Oberteil, Unterteil, Schuhe, Jacke, Accessoires). The seed source SHALL be configurable (toml file overridable by env var), not hardcoded in `core`. The saga SHALL be idempotent: on replay of the same `SeasonCreated` event, it SHALL skip seeding when the season already has categories.

#### Scenario: Seeding a brand-new season
- **WHEN** a `SeasonCreated` event is observed for a Season that has zero CostumeCategories
- **THEN** the saga SHALL dispatch one `CreateCostumeCategory` command per seed entry, each with a sequential `order_key`

#### Scenario: Replayed SeasonCreated does not double-seed
- **WHEN** the same `SeasonCreated` event is reprocessed (e.g. projector restart)
- **THEN** the saga SHALL detect the season already has categories and SHALL dispatch zero `CreateCostumeCategory` commands

#### Scenario: Default seed is configurable
- **WHEN** the seed configuration source provides `[Hut, Mantel]` instead of the built-in defaults
- **THEN** the saga SHALL seed `[Hut, Mantel]` for new seasons

### Requirement: A costume belongs to exactly one category
A `Costume` SHALL belong to at most one `CostumeCategory` (n:1; issue #543). The category is set or cleared via `SetCostumeCategory { id, category_id: Option<CostumeCategoryId>, version, series_id }`, emitting exactly one `CostumeCategorySet { id, category_id, version }`; `category_id: None` clears the binding. Re-dispatching the command with the value the costume already carries SHALL be a state-based no-op (no event, `Ok` — issue #515 precedent). Because the `Costume` is scope-free while `CostumeCategory` is season-scoped, the cross-aggregate season invariant `category.season_id ∈ (repertoire_seasons(costume) ∪ season(character))` SHALL be pre-checked at the API edge **before dispatch**: a category from a season outside the permitted set SHALL be rejected with `409 costume-category.season-mismatch` (extension `category_id`), an archived category with `409 costume-category.archived`, an unknown category with `404 costume-category.not-found`. There is no projection unique constraint for this invariant (it is not a uniqueness case); the projector resolves `category_name` best-effort (`None` on a projection miss) and cannot fail at this point.

#### Scenario: Setting a category from a permitted season
- **WHEN** a `SetCostumeCategory` command targets a costume whose repertoire-or-character season set contains the category's season
- **THEN** the aggregate SHALL emit `CostumeCategorySet { id, category_id, version }` with the costume's version incremented by exactly one

#### Scenario: Setting a category from a foreign season is rejected before dispatch
- **WHEN** the category's `season_id` is neither a repertoire season of the costume nor the season of the costume's character
- **THEN** the API edge SHALL return `409 costume-category.season-mismatch` with the `category_id` extension and SHALL NOT dispatch the command (no event is written)

#### Scenario: Clearing the category
- **WHEN** a `SetCostumeCategory` command with `category_id: None` targets a categorized costume
- **THEN** the aggregate SHALL emit `CostumeCategorySet { id, category_id: None, version }` and the read model SHALL show the costume as uncategorised

#### Scenario: Re-setting the current category is a no-op
- **WHEN** a `SetCostumeCategory` command carries the `category_id` the costume already has
- **THEN** the aggregate SHALL emit no event and the command SHALL succeed

### Requirement: Legacy detail categories derive the costume category on replay (first-wins)
A legacy event stream (`CostumeCreated` / `DetailAdded` with `detail.category_id != None`, no `CostumeCategorySet`) SHALL derive the costume's category deterministically: the first detail category in event order — within one event, the detail with the lowest `detail_id` — is adopted while the costume still has no category; a later categorized detail SHALL NOT overwrite an adopted category, and an explicit `CostumeCategorySet` always wins. The rule SHALL be executed identically by `CostumeAggregate::apply` and by the costume projector (the projection stays a pure function of the events; an SQL backfill is forbidden because it would diverge aggregate and projection on replay).

#### Scenario: Legacy stream yields the same value in aggregate and projector
- **WHEN** a legacy stream containing only `CostumeCreated` with `details: [{category_id: X}]` is replayed
- **THEN** the aggregate state and `projection_costume.category_id` SHALL both equal X (no divergence)

#### Scenario: Contradictory detail categories in one event
- **WHEN** a single `CostumeCreated` event carries details with different `category_id` values
- **THEN** the detail with the lowest `detail_id` SHALL win

### Requirement: CostumeCategory rename propagates to the costume read model
A projector subscribed to the `costume_category` stream SHALL, on `CostumeCategoryRenamed`, refresh the denormalised `category_name` column of every `projection_costume` row whose `category_id` matches the renamed category (issue #543: the category lives on the costume). On `CostumeCategoryArchived`, the projector SHALL set `archived = true` on `projection_costume_category` and SHALL NOT null out existing `projection_costume.category_name` references.

#### Scenario: Rename refreshes denormalised name
- **WHEN** a `CostumeCategory` named "Schuhe" is renamed to "Footwear"
- **THEN** every `projection_costume` row referencing it SHALL have `category_name = "Footwear"` after the projector catches up

#### Scenario: Archive preserves historical names
- **WHEN** a `CostumeCategoryArchived` event is processed
- **THEN** `projection_costume_category.archived` SHALL become `true` and referencing `projection_costume.category_name` values SHALL retain their last-known value

### Requirement: CostumeCategory projection schema
The `projection_costume_category` table SHALL contain `id, season_id, name, order_key, archived, version, updated_at` with an index on `(season_id, order_key)`. The `projection_costume` table SHALL carry nullable `category_id` and `category_name` columns (issue #543). The `projection_costume_detail` table's legacy `subject`, `category_id`, and `category_name` columns remain for replay; a later migration removes the category columns.

#### Scenario: Projection schema
- **WHEN** the projection schema is inspected
- **THEN** `projection_costume_category` SHALL have the listed columns plus a `(season_id, order_key)` index, `projection_costume` SHALL have nullable `category_id`/`category_name` columns, and `projection_costume_detail` SHALL still expose its legacy `subject`/`category_id`/`category_name` columns
