# Purpose

Define the read-side port contract: per-aggregate `*Repository` ports returning flat `*View` DTOs with projection metadata, cross-context convenience reads, and infra-backed implementations.

# Requirements

### Requirement: Per-aggregate read Repository ports in core
The `core` crate SHALL define one async read `Repository` port per bounded context — `SceneRepository`, `CharacterRepository`, `CostumeRepository`, `CalculationRepository` — returning flat read-model `*View` DTOs, never domain aggregates (ADR-002 forbids querying aggregates for views). The name `Repository` denotes a read-model port, not a DDD aggregate-root repository.

#### Scenario: API depends on the port, not the adapter
- **WHEN** `crates/api` is compiled
- **THEN** it references only the `*Repository` traits from `core`, never `sqlx::PgPool` or projection tables directly

### Requirement: View DTOs carry projection metadata
Each `*View` DTO (`SceneView`, `CharacterView`, `CostumeView` including its detail and photo sub-views, `CalculationView` including its item sub-views) SHALL carry: `id` (UUIDv7), `project_id`, `version` (the last applied aggregate version, to enable optimistic-locking round-trips on the command path), and `updated_at` derived from the event's `timestamp` (not from UUIDv7 extraction).

#### Scenario: Updated_at comes from the event timestamp
- **WHEN** a projection row is produced by a projector from an event whose `Event.timestamp = T`
- **THEN** the row's `updated_at` equals `T`

#### Scenario: Version enables optimistic locking round-trips
- **WHEN** a `*View` DTO is returned from a `*Repository` query
- **THEN** its `version` field equals the `AggregateVersion` carried by the most recently applied event for that aggregate
- **AND** a frontend can echo that `version` back in a subsequent command's expected version

### Requirement: Repository queries cover the first read surface
Each `*Repository` SHALL provide at minimum: `find_by_id(id)`, `list_by_project(project_id)` (paginated), and the cross-context convenience reads needed for the first frontend screens — specifically `SceneRepository::scenes_by_character(character_id)` (a `JOIN projection_scene_character ⋈ projection_scene` query), `CostumeRepository::costumes_by_character(character_id)`, and `CostumeRepository.costume_with_details_photos(id)` returning detail and photo sub-views alongside the costume.

#### Scenario: Scenes-by-character is a join, not a denormalised column
- **WHEN** `SceneRepository::scenes_by_character(c)` is executed
- **THEN** the query reads from `projection_scene_character` joined to `projection_scene`
- **AND** no projector mutates `projection_character` in response to a `SceneEvent::CharacterAssigned`

### Requirement: Roster authority is the scene aggregate
`SceneEvent::CharacterAssigned` and `SceneEvent::CharacterRemoved` SHALL be the sole authoritative source of the scene↔character roster. The `Character` aggregate SHALL NOT emit scene-assignment events.

#### Scenario: Assigning a character writes only the scene-character projection
- **WHEN** a `SceneEvent::CharacterAssigned` is projected
- **THEN** a row is inserted/upserted into `projection_scene_character`
- **AND** no `projection_character` row is mutated as a side effect

### Requirement: Infra provides the read adapter
`crates/infra` SHALL provide `sqlx`-backed implementations of the four `*Repository` ports using compile-time-checked queries against the projection tables. `crates/core` SHALL NOT depend on `sqlx`.

#### Scenario: Repository results come from projection tables
- **WHEN** a `*Repository::find_by_id` is invoked at runtime
- **THEN** it issues a `sqlx` query against the corresponding `projection_*` table
- **AND** returns a `*View` DTO reconstructed from the row(s)
