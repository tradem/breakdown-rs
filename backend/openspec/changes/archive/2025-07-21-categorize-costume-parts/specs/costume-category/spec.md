## ADDED Requirements

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
A `CostumeCategory` SHALL support `ArchiveCostumeCategory { id, version }` emitting `CostumeCategoryArchived { id, version }` with `archived = true`. There SHALL be no unarchive command. Mutation commands dispatched to an archived aggregate (`RenameCostumeCategory`, `ReorderCostumeCategory`) SHALL be rejected with `CostumeCategoryError::ArchivedCannotBeMutated`. Archived categories SHALL remain referenceable by CostumeDetails that already link them and SHALL be hidden from picker queries used for new categorisation.

#### Scenario: Archiving a referenced category succeeds
- **WHEN** a `CostumeCategory` referenced by one or more CostumeDetails receives `ArchiveCostumeCategory`
- **THEN** the aggregate SHALL emit `CostumeCategoryArchived` and existing CostumeDetail references SHALL remain resolvable in the read model with their denormalised `category_name` intact

#### Scenario: Mutating an archived category is rejected
- **WHEN** a `RenameCostumeCategory` command targets an archived CostumeCategory
- **THEN** the aggregate SHALL reject with `CostumeCategoryError::ArchivedCannotBeMutated` and SHALL emit no event

#### Scenario: Archived categories hidden from pickers
- **WHEN** a query lists CostumeCategories available for new categorisation under Season S
- **THEN** only categories with `archived = false` SHALL be returned

### Requirement: CostumeDetail carries optional subject and category_id
`CostumeDetail` SHALL carry `id: Uuid`, `subject: Option<String>`, `category_id: Option<CostumeCategoryId>`, and `text: String`. `subject` is a free-form per-detail micro-title; `category_id` references a `CostumeCategory`. Both are optional. The existing `text` field SHALL NOT be reinterpreted as `subject` during migration. The `CostumeDetailView` read model SHALL additionally carry a denormalised `category_name: Option<String>` resolved by join.

#### Scenario: Adding a categorized detail
- **WHEN** an `AddDetail { id, detail, version }` command is dispatched where `detail = { id, subject: Some("Rote Jacke"), category_id: Some(C), text: "Knöpfe vorne" }`
- **THEN** the aggregate SHALL emit `DetailAdded { id, detail, version }` carrying the full enriched `CostumeDetail`

#### Scenario: Existing text is not migrated into subject
- **WHEN** an existing `DetailAdded` event predating this change is replayed
- **THEN** `subject` SHALL deserialize as `None` and `category_id` as `None`, and `text` SHALL retain its prior value and meaning

#### Scenario: Denormalised category_name resolves by join
- **WHEN** the read model materialises a `CostumeDetailView` whose `category_id` references a non-archived category named "Schuhe"
- **THEN** `category_name` SHALL equal "Schuhe"

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

### Requirement: CostumeCategory rename propagates to the costume read model
A projector subscribed to the `costume_category` stream SHALL, on `CostumeCategoryRenamed`, refresh the denormalised `category_name` column of every `projection_costume_detail` row whose `category_id` matches the renamed category. On `CostumeCategoryArchived`, the projector SHALL set `archived = true` on `projection_costume_category` and SHALL NOT null out existing `projection_costume_detail.category_name` references.

#### Scenario: Rename refreshes denormalised name
- **WHEN** a `CostumeCategory` named "Schuhe" is renamed to "Footwear"
- **THEN** every `projection_costume_detail` row referencing it SHALL have `category_name = "Footwear"` after the projector catches up

#### Scenario: Archive preserves historical names
- **WHEN** a `CostumeCategoryArchived` event is processed
- **THEN** `projection_costume_category.archived` SHALL become `true` and referencing `projection_costume_detail.category_name` rows SHALL retain their last-known value

### Requirement: CostumeCategory projection schema
The `projection_costume_category` table SHALL contain `id, season_id, name, order_key, archived, version, updated_at` with an index on `(season_id, order_key)`. The `projection_costume_detail` table SHALL gain nullable `subject`, `category_id`, and `category_name` columns.

#### Scenario: Projection schema
- **WHEN** the projection schema is inspected
- **THEN** `projection_costume_category` SHALL have the listed columns plus a `(season_id, order_key)` index, and `projection_costume_detail` SHALL have nullable `subject`, `category_id`, `category_name` columns
