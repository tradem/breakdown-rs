# production-hierarchy Specification

## Purpose
TBD - created by archiving change introduce-season-block-episode-hierarchy. Update Purpose after archive.
## Requirements
### Requirement: Series identifier as an opaque value type
The system SHALL provide a `SeriesId` value type in `crates/core/src/shared.rs` wrapping a UUIDv7, mirroring the existing `ProjectId`/`AggregateVersion` pattern. `SeriesId` SHALL be the identifier of the show run and SHALL be referenced (not owned) by the `Season`, `Block`, and `Episode` aggregates. No `Series` aggregate or `Series` lifecycle (name, year, status, archival) SHALL be modeled in this change.

#### Scenario: Opaque identifier with UUIDv7
- **WHEN** a `SeriesId` is generated
- **THEN** it SHALL wrap a UUIDv7 value and SHALL expose no series-level domain attributes (name, dates, status)

### Requirement: Season aggregate
The system SHALL model a `Season` as an event-sourced aggregate via `kameo_es`, scoped to exactly one `SeriesId`, with state `{ id, series_id, number: i32, title: Option<String> }`. A Season SHALL be the natural production scope for season-scoped entities (Characters) and SHALL NOT own per-Block or per-Episode containment.

#### Scenario: Creating a season
- **WHEN** a `CreateSeason { id, series_id, number, title }` command is dispatched to a new Season stream
- **THEN** the aggregate SHALL emit `SeasonCreated { id, series_id, number, title, version }` and its state SHALL reflect the provided fields

### Requirement: Season number is a series-global running counter
`Season.number` SHALL be unique within a `Series` (a series-global running counter, not per-parent-reset). Uniqueness SHALL be enforced by a Postgres unique index on `(series_id, number)` in the season projection; the write-side aggregate SHALL NOT attempt preventive cross-aggregate uniqueness checks.

#### Scenario: Duplicate season number surfaces at projection
- **WHEN** two `SeasonCreated` events for the same `series_id` carry the same `number`
- **THEN** the second SHALL be rejected by the unique index during projection, surfacing a collision signal, and the aggregate itself SHALL NOT have prevented the command

### Requirement: Block aggregate
The system SHALL model a `Block` as an event-sourced aggregate via `kameo_es`, scoped to exactly one `Season`, with state `{ id, season_id, number: i32, start_date: Option<NaiveDate>, end_date: Option<NaiveDate> }`. A Block groups Episodes and is the natural rotation boundary for costume-department staff.

#### Scenario: Creating a block with a time span
- **WHEN** a `CreateBlock { id, season_id, number, start_date, end_date }` command is dispatched to a new Block stream
- **THEN** the aggregate SHALL emit `BlockCreated` carrying the provided fields and its state SHALL reflect them

#### Scenario: Creating a block without a time span
- **WHEN** a `CreateBlock` command is dispatched with `start_date = None` and `end_date = None`
- **THEN** the aggregate SHALL accept it (the time span is optional in the model even though reality always has one)

### Requirement: Block time span update
The system SHALL allow updating a Block's `start_date` and `end_date` via a command that emits a `BlockTimeSpanUpdated` event; both fields are independently optional.

#### Scenario: Updating block dates
- **WHEN** a `UpdateBlockTimeSpan { id, start_date, end_date, version }` command targets an existing Block
- **THEN** the aggregate SHALL emit `BlockTimeSpanUpdated { id, start_date, end_date, version }` and SHALL replace both date fields

### Requirement: Block number is a series-global running counter
`Block.number` SHALL be unique within a `Series` (series-global, not per-Season). Uniqueness SHALL be enforced by a Postgres unique index on `(series_id, number)` in the block projection.

#### Scenario: Duplicate block number surfaces at projection
- **WHEN** two `BlockCreated` events for the same `series_id` carry the same `number`
- **THEN** the second SHALL be rejected by the unique index during projection; the aggregate SHALL NOT prevent the command

### Requirement: Episode aggregate
The system SHALL model an `Episode` as an event-sourced aggregate via `kameo_es`, scoped to exactly one `Block`, with state `{ id, block_id: BlockId, series_id: SeriesId, number: i32, name: Option<String> }`. `series_id` SHALL be denormalized on the Episode (immutable once set; a Block never changes Season) to support series-global numbering and avoid multi-level joins on read paths.

#### Scenario: Creating an episode
- **WHEN** a `CreateEpisode { id, block_id, series_id, number, name }` command is dispatched to a new Episode stream
- **THEN** the aggregate SHALL emit `EpisodeCreated { id, block_id, series_id, number, name, version }` and its state SHALL reflect the provided fields

#### Scenario: Renaming an episode
- **WHEN** a `RenameEpisode { id, name, version }` command targets an existing Episode
- **THEN** the aggregate SHALL emit `EpisodeRenamed { id, name, version }` and SHALL replace the name

### Requirement: Episode number is a series-global running counter
`Episode.number` SHALL be unique within a `Series` — a running counter from the start of the show, NOT reset per Season, Block, or Episode parent. Uniqueness SHALL be enforced by a Postgres unique index on `(series_id, number)` in the episode projection.

#### Scenario: Episode numbers count up across seasons
- **WHEN** the last Episode of Season 2 carries `number = 47`
- **THEN** the first Episode of Season 3 MAY carry `number = 48` and MUST NOT be forced to restart at 1; uniqueness is scoped to the `Series`, not the Season

#### Scenario: Duplicate episode number surfaces at projection
- **WHEN** two `EpisodeCreated` events for the same `series_id` carry the same `number` (regardless of season/block)
- **THEN** the second SHALL be rejected by the unique index during projection; the aggregate SHALL NOT prevent the command

### Requirement: Containment is read-model-derived
The query "which Blocks belong to a Season" (and "which Episodes belong to a Block") SHALL be answered by projection queries keyed on `season_id` / `block_id`, ordered by `number`. Neither `Season` nor `Block` aggregates SHALL store a vector of child identifiers; containment SHALL be derived from events in the read model.

#### Scenario: Listing blocks of a season
- **WHEN** a query requests all Blocks of `Season S`
- **THEN** the read model SHALL return the Blocks whose `season_id = S`, ordered by `number`, without reading any child vector from the Season aggregate

### Requirement: Season, Block, and Episode categories
The new aggregates SHALL register `category()` values `"season"`, `"block"`, and `"episode"` respectively for `kameo_es::Entity`, consistent with the existing contexts (`scene`, `character`, `costume`).

#### Scenario: Aggregate categories
- **WHEN** each new aggregate's `Entity::category()` is queried
- **THEN** Season SHALL return `"season"`, Block SHALL return `"block"`, and Episode SHALL return `"episode"`

### Requirement: Production hierarchy read model and projectors
The system SHALL maintain Postgres projections for `seasons`, `blocks`, and `episodes`, each updated by a dedicated idempotent projector reacting to that context's events, exposing queries by `series_id`, `season_id`, `block_id`, and `number`. Each projector SHALL be idempotent under event redelivery, mirroring the existing projector-supervision pattern.

#### Scenario: Projecting a season
- **WHEN** a `SeasonCreated` event is delivered to the season projector
- **THEN** a row SHALL be upserted into the `seasons` projection keyed by `id`, carrying `series_id`, `number`, `title`

#### Scenario: Idempotent projection under redelivery
- **WHEN** the same `BlockCreated` event is delivered to the block projector more than once
- **THEN** the projection SHALL apply it exactly once and the read model SHALL reflect a single correct state

