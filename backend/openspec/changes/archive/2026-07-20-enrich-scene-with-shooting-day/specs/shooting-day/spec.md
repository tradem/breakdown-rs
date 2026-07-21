## ADDED Requirements

### Requirement: ShootingDay is an Episode-scoped aggregate
A `ShootingDay` SHALL be its own event-sourced aggregate scoped to exactly one `Episode` via `episode_id: EpisodeId`. It SHALL NOT carry any Series/Season/Block reference. A `ShootingDay` SHALL carry `id: Uuid` (UUIDv7), `label: Option<String>`, `order_key: LexicalSortKey`, `date: Option<NaiveDate>`, `source: ShootingDaySource`, `archived: bool`, and `version: AggregateVersion`.

#### Scenario: Creating a shooting day
- **WHEN** a `CreateShootingDay { id, episode_id, label, order_key, date?, source }` command is dispatched to a new stream
- **THEN** the aggregate SHALL emit `ShootingDayCreated { id, episode_id, label, order_key, date, source, version }` with `archived = false` and `version = AggregateVersion::INITIAL`

#### Scenario: Shooting day references no production scope above Episode
- **WHEN** a `ShootingDayCreated` event is inspected
- **THEN** it SHALL carry `episode_id` and SHALL NOT carry `series_id`, `season_id`, or `block_id`

### Requirement: LexicalSortKey is a validated shared Value Object with fractional midpoint insertion
The system SHALL provide a `LexicalSortKey(String)` value object in `core::shared`, shared between `shooting_day` and other ordering use cases (`costume-category`). It SHALL reject empty strings, whitespace, characters outside a fixed printable-ASCII alphabet, and strings exceeding a bounded length. Comparison SHALL be lexicographic byte order over the validated alphabet. The system SHALL provide a midpoint operation producing a key strictly between two existing keys; inserting an entity between two siblings SHALL emit exactly one event (not N renumbering events).

#### Scenario: Inserting between two existing keys is a single mutation
- **WHEN** a `ReorderShootingDay` command places a new `order_key` between keys `a` and `b` of two sibling ShootingDays
- **THEN** the aggregate SHALL emit exactly one `ShootingDayReordered` event whose `order_key` satisfies `a < new_key < b`, and SHALL NOT emit events for the sibling aggregates

#### Scenario: Invalid keys are rejected
- **WHEN** a `LexicalSortKey` is constructed from an empty string, a string containing whitespace, or a non-ASCII character
- **THEN** construction SHALL fail with a validation error

### Requirement: ShootingDay ordering is by order_key, decoupled from the human label
Listing ShootingDays within an Episode SHALL order by `order_key` lexicographically. The `label` SHALL be a free-form display string with no ordering semantics. Renaming a ShootingDay SHALL NOT change its `order_key`.

#### Scenario: Listing shooting days of an episode in canonical order
- **WHEN** a query requests all ShootingDays of `Episode E`
- **THEN** the read model SHALL return them ordered by `order_key ASC`

#### Scenario: Renaming preserves order
- **WHEN** a `RenameShootingDay { id, label, version }` command is dispatched
- **THEN** the aggregate SHALL emit `ShootingDayRenamed` and SHALL NOT alter `order_key`

### Requirement: ShootingDay records import provenance
Every `ShootingDayCreated` event SHALL carry a `source: ShootingDaySource` discriminator of either `Manual` or `AiExtracted { document_id, external_ref?, confidence }`. The AI extraction feature itself is out of scope, but the field SHALL exist from day one so AI-imported events need no future schema migration.

#### Scenario: Manually created shooting day
- **WHEN** a ShootingDay is created by a user
- **THEN** `source` SHALL be `ShootingDaySource::Manual`

#### Scenario: AI-imported shooting day carries document provenance
- **WHEN** an AI extraction increment creates a ShootingDay
- **THEN** `source` SHALL be `ShootingDaySource::AiExtracted { document_id, external_ref, confidence }` with `document_id` being a non-`None` UUID

### Requirement: ShootingDay uses soft-archive, not hard-delete
A `ShootingDay` SHALL support `ArchiveShootingDay { id, version }` emitting `ShootingDayArchived { id, version }` with `archived = true`. There SHALL be no unarchive command (archive is terminal). Mutation commands dispatched to an archived aggregate (`RenameShootingDay`, `RescheduleShootingDay`, `ReorderShootingDay`) SHALL be rejected with `ShootingDayError::ArchivedCannotBeMutated`. Archived ShootingDays SHALL remain referenceable by Scenes that already link them; archived days SHALL be hidden from picker/list queries used for new scheduling.

#### Scenario: Archiving a referenced shooting day succeeds
- **WHEN** a `ShootingDay` referenced by one or more Scenes receives `ArchiveShootingDay`
- **THEN** the aggregate SHALL emit `ShootingDayArchived` and existing Scene references SHALL remain resolvable in the read model

#### Scenario: Mutating an archived shooting day is rejected
- **WHEN** a `RenameShootingDay` command targets an archived ShootingDay
- **THEN** the aggregate SHALL reject with `ShootingDayError::ArchivedCannotBeMutated` and SHALL emit no event

#### Scenario: Archived days are hidden from picker queries
- **WHEN** a query lists ShootingDays available for scheduling a Scene on Episode E
- **THEN** only ShootingDays with `archived = false` SHALL be returned

### Requirement: Scene schedules onto ShootingDays as a many-to-many relationship
A `Scene` SHALL maintain `shooting_day_ids: Vec<ShootingDayId>`. The Scene aggregate SHALL own the link (the ShootingDay aggregate has no knowledge of referencing Scenes). `ScheduleSceneOnShootingDay { id, shooting_day_id, version }` SHALL emit `ShootingDayScheduled { id, shooting_day_id, version }` and be idempotent: re-adding an existing id SHALL be rejected as already-scheduled rather than emitting a duplicate event. `UnscheduleSceneFromShootingDay { id, shooting_day_id, version }` SHALL emit `ShootingDayUnscheduled` and SHALL reject if the id is not currently scheduled.

#### Scenario: Scheduling a scene on a shooting day
- **WHEN** a `ScheduleSceneOnShootingDay` command targets a Scene that does not yet link the given ShootingDay
- **THEN** the aggregate SHALL emit `ShootingDayScheduled` and append the id to `shooting_day_ids`

#### Scenario: Double-scheduling is rejected without a duplicate event
- **WHEN** a `ScheduleSceneOnShootingDay` command targets a Scene that already links the given ShootingDay
- **THEN** the aggregate SHALL reject as already-scheduled and SHALL emit no event

#### Scenario: Unscheduling requires prior scheduling
- **WHEN** an `UnscheduleSceneFromShootingDay` command targets a Scene whose `shooting_day_ids` does not contain the id
- **THEN** the aggregate SHALL reject and SHALL emit no event

### Requirement: ShootingDay projection stores source as structured JSON
The `projection_shooting_day` table SHALL store `source` as JSONB covering both the `Manual` and `AiExtracted { document_id, external_ref, confidence }` shapes. It SHALL be queryable by Episode ordered by `order_key` via an index on `(episode_id, order_key)`.

#### Scenario: Projection schema
- **WHEN** the `projection_shooting_day` schema is inspected
- **THEN** it SHALL contain `id, episode_id, label, order_key, date, source (JSONB), archived, version, updated_at` and an index on `(episode_id, order_key)`

### Requirement: Scene–ShootingDay join projection
The read model SHALL maintain a `projection_scene_shooting_day` join keyed on `(scene_id, shooting_day_id)`, updated by the scene projector on `ShootingDayScheduled`/`ShootingDayUnscheduled` events. It SHALL support reverse queries ("all scenes filming on ShootingDay D") via an index on `shooting_day_id`.

#### Scenario: Reverse query — scenes of a shooting day
- **WHEN** a query requests all Scenes filming on `ShootingDay D`
- **THEN** the read model SHALL return Scenes joined via `projection_scene_shooting_day` where `shooting_day_id = D`
