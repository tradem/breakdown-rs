# Purpose

Define the projection runtime: one projector per aggregate, exhaustive event coverage, idempotent upserts, normalized schema, and separation of projection concerns from core.

# Requirements

### Requirement: One projector per aggregate, each with its own checkpoint
`crates/infra` SHALL provide four `EntityEventHandler<sqlx::Transaction<'static, Postgres>` impls — `SceneProjector`, `CharacterProjector`, `CostumeProjector`, `CalculationProjector` — each spawned as its own `kameo_es` `PostgresProcessor` actor with an independent `sierradb_event_checkpoints` row set per partition. A single composite handler SHALL NOT be used. Each projector's SierraDB subscription stream SHALL be supervised by an in-process supervisor that restarts the stream on error or panic from its checkpoint with bounded backoff, so that a per-task failure does not silently stall the projection until the whole API process is restarted.

#### Scenario: Independent failure isolation
- **WHEN** `CharacterProjector` raises an error handling one event
- **THEN** `SceneProjector`, `CostumeProjector` and `CalculationProjector` continue processing their own event streams unaffected

#### Scenario: Independent catch-up
- **WHEN** `CostumeProjector` is restarted after a downtime
- **THEN** it replays from its own checkpoint without resetting the checkpoints of the other three projectors

#### Scenario: Per-task failure restarts within the process
- **WHEN** one projector's subscription stream task returns an error or panics while the API process keeps running
- **THEN** the supervisor for that projector restarts its subscription loop from its checkpoint without restarting the API process
- **AND** the other three projectors' subscription loops are not affected by that single task's failure

### Requirement: Spec coverage of all current events
The projectors SHALL handle every variant currently defined in `core::{scene,character,costume,calculation}::events`. An unhandled event variant SHALL fail the build (exhaustive `match`), not silently no-op.

#### Scenario: Scene projector handles all scene events
- **WHEN** the `SceneProjector`'s `handle` is compiled
- **THEN** it matches exhaustively over every `SceneEvent` variant (`SceneCreated`, `SceneDetailsUpdated`, `CharacterAssigned`, `CharacterRemoved`)

#### Scenario: Costume projector handles all costume events
- **WHEN** the `CostumeProjector`'s `handle` is compiled
- **THEN** it matches exhaustively over every `CostumeEvent` variant (`CostumeCreated`, `CostumeNotesUpdated`, `CostumeAssignedToCharacter`, `CostumeUnassigned`, `DetailAdded`, `DetailRemoved`, `PhotoLinked`, `PhotoUnlinked`)

#### Scenario: Calculation projector handles all calculation events
- **WHEN** the `CalculationProjector`'s `handle` is compiled
- **THEN** it matches exhaustively over every `CalculationEvent` variant (`CalculationCreated`, `HeaderInfoUpdated`, `CalculationItemAdded`, `CalculationItemUpdated`, `CalculationItemRemoved`, `ItemMarkedAsPaid`, `ItemMarkedAsUnpaid`)

#### Scenario: Character projector handles all character events
- **WHEN** the `CharacterProjector`'s `handle` is compiled
- **THEN** it matches exhaustively over every `CharacterEvent` variant (`CharacterCreated`, `MeasurementsUpdated`, `ContactInfoUpdated`)

### Requirement: Idempotent upsert projections
Every projector write SHALL use an idempotent `INSERT ... ON CONFLICT (...) DO UPDATE` (or `DO NOTHING` for removal-sub-rows) so that redelivery of the same event produces the same projection state. Removal events SHALL be idempotent `DELETE WHERE ...` statements.

#### Scenario: Redelivery is a no-op on the parent row
- **WHEN** the same `SceneEvent::SceneCreated` is projected twice
- **THEN** the second application does not error and leaves `projection_scene` in the same state as after the first

#### Scenario: Removal is idempotent
- **WHEN** `CostumeEvent::DetailRemoved` is projected twice for the same `detail_id`
- **THEN** the second application succeeds with zero rows affected and no error

### Requirement: Normalized projection schema
The projection migrations SHALL create the normalized tables `projection_scene`, `projection_scene_character`, `projection_character`, `projection_costume`, `projection_costume_detail`, `projection_costume_photo`, `projection_calculation`, `projection_calculation_item`, with primary/foreign keys, a `version` column per parent table mirroring the last applied aggregate version, an `updated_at` column derived from `Event.timestamp`, and the `sierradb_event_checkpoints` table managed by `PostgresProcessor`.

#### Scenario: Schema is created by migrations
- **WHEN** `sqlx::migrate!("./migrations")` is run against an empty Postgres
- **THEN** all nine tables exist with the expected columns and foreign keys
- **AND** a query against any projection table succeeds without a "relation does not exist" error

#### Scenario: Measurements and header are stored as JSONB
- **WHEN** a `CharacterEvent::CharacterCreated` with `measurements` is projected
- **THEN** the `measurements` column of `projection_character` stores the value as JSONB
- **AND** when a `CalculationEvent::CalculationCreated` with `header` is projected, `projection_calculation.header` stores the value as JSONB

### Requirement: Projectors are not a core port
Projection update SHALL be an `infra`-internal concern. `crates/core` SHALL NOT define a `ProjectionSink`, `Projector`, or similar trait. The API layer SHALL NOT invoke projectors; it reads only via the read `*Repository` ports.

#### Scenario: Core has no projector abstraction
- **WHEN** `crates/core` is built
- **THEN** no `Projector`, `ProjectionSink`, or `EventHandler` trait is exported from `core`

### Requirement: Scene provenance projection (AI transparency)
The `projection_scene` table SHALL store the scene's provenance discriminator
`source` as JSONB covering both the `Manual` and the
`AiExtracted { document_id, external_ref, confidence }` shapes (migration
`20260926000001` with a `{"Manual":null}` default). The scene projector SHALL
write the `SceneCreated` event's discriminator on insert and redelivery update;
the scene and shooting-day query adapters SHALL deserialize it into
`SceneView.source`.

#### Scenario: Projection defaults legacy rows to Manual
- **WHEN** the migration runs against rows created before #517
- **THEN** each `projection_scene.source` equals the `{"Manual":null}` default

#### Scenario: Replay of a legacy event projects Manual
- **WHEN** the scene projector processes a `SceneCreated` event whose payload
  predates the `source` field (serde default `Manual`)
- **THEN** the projection row's `source` is `Manual`

#### Scenario: AI-created scenes are distinguishable in the read model
- **WHEN** the scene projector processes a `SceneCreated` event stamped
  `SceneSource::AiExtracted { document_id, external_ref, confidence: None }`
  (AI script apply)
- **THEN** the projection row's `source` carries the `AiExtracted` object shape
- **AND** `SceneView.source` exposes it unchanged to the wire (additive field,
  ADR-021 D3 MINOR)

### Requirement: Actor/scheduling context is out of scope
The projectors SHALL NOT model actor availability, sickness windows, or schedule time ranges. The scene scheduling fields projected (`scene_number`, `is_schedule_set`, `location`, `mood`) SHALL be treated as placeholders for a future scheduling bounded context, projected as plain columns without time-range or availability semantics.

#### Scenario: No scheduling tables in v1
- **WHEN** the v1 migrations are applied
- **THEN** no `projection_scene_schedule`, availability, or actor-table exists
- **AND** `CharacterEvent` variants remain limited to `CharacterCreated`, `MeasurementsUpdated`, `ContactInfoUpdated`
