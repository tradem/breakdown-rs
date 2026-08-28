## Why

Scenes today carry no prose summary and no relationship to the shoot calendar. Scheduling decisions live entirely outside Breakdown RS, so users cannot annotate *why* a scene is scheduled the way it is, and the read model cannot answer "which scenes film on a given Drehtag" or "list the Drehtags of this episode in order". A future AI extraction increment will import Drehtags from call sheets; the model must support both manual entry and imported data from day one because retrofitting provenance onto immutable events is impossible.

## What Changes

- **Add `summary: Option<String>`** to `SceneDetails`, flowing through `SceneCreated` / `SceneDetailsUpdated` events and the `SceneView` read model.
- **Introduce a new `ShootingDay` aggregate**, scoped to exactly one `Episode` (its parent in the `Series → Season → Block → Episode → ShootingDay` leaf). A ShootingDay carries:
  - `id: Uuid` (UUIDv7)
  - `episode_id: EpisodeId`
  - `label: Option<String>` — free-form human label ("1. Tag")
  - `order_key: LexicalSortKey` — opaque, lexicographically-sortable string used as the canonical ordering within an Episode, decoupled from `label`
  - `date: Option<NaiveDate>` — the calendar date (may be unset while planning)
  - `source: ShootingDaySource` — `Manual` or `AiExtracted { document_id: Uuid, external_ref: Option<String>, confidence: f32 }`
  - `archived: bool` — soft-archive flag (default `false`)
  - `version: AggregateVersion`
- **Introduce a new shared Value Object `LexicalSortKey(String)`** in `core::shared`, with validation (non-empty, ASCII-printable, no whitespace) and lexicographic comparison semantics. Inserting a ShootingDay between two existing ones emits **one** event (midpoint key), not N renumbering events. A compaction command rebalances on the rare degenerate case.
- **Establish a many-to-many relationship between `Scene` and `ShootingDay`**: a Scene references a `Vec<ShootingDayId>` (a scene may be filmed across multiple Drehtags, and a Drehtag films many scenes). Scene gains `ScheduleSceneOnShootingDay` / `UnscheduleSceneFromShootingDay` commands emitting `ShootingDayScheduled` / `ShootingDayUnscheduled` events. The Scene aggregate owns the collection.
- **ShootingDay soft-archive**: deleting a ShootingDay is forbidden while any Scene references it (validated against the read model at command time). Instead a `ArchiveShootingDay` command flips `archived=true`; archived days remain referenceable from historical Scene views but are hidden from day-picker queries. This is the standing rule for cross-aggregate references in this codebase.
- **Projection updates**: `projection_scene` gains `summary TEXT`; new `projection_shooting_day` table; new `projection_scene_shooting_day` join table; `idx_projection_shooting_day_episode_id` for listing within an Episode ordered by `order_key`.

Not in scope: AI extraction itself, Block/Season-level Drehtags (identity is Episode-scoped; lifting the parent later is additive because references are id-based), rescheduling propagation into other aggregates.

## Capabilities

### New Capabilities
- `shooting-day`: The `ShootingDay` aggregate, its commands/events/aggregate, the `LexicalSortKey` shared Value Object, soft-archive semantics, AI-import provenance (`source`/`external_ref`), and the Scene↔ShootingDay many-to-many scheduling relationship with its commands/events and projection tables.

### Modified Capabilities
- `scene-scoping`: `SceneDetails` gains the optional `summary` field; `CreateScene` / `UpdateSceneDetails` and the `SceneView` read model carry the new field; the scene projection gains a `summary` column.

## Impact

- **`crates/core/src/scene`** — `events::SceneDetails`, `commands::CreateScene`/`UpdateSceneDetails`, `views::SceneView`, new commands `ScheduleSceneOnShootingDay` / `UnscheduleSceneFromShootingDay`, new event variants `ShootingDayScheduled` / `ShootingDayUnscheduled`, aggregate state gains `shooting_day_ids: Vec<ShootingDayId>`.
- **`crates/core/src/shooting_day/`** (new module) — aggregate, commands, events, views, error, ports. Mirrors existing module layout.
- **`crates/core/src/shared.rs`** — new `ShootingDayId(Uuid)` opaque id and `LexicalSortKey` value object.
- **`crates/infra`** — `ShootingDayCommands`/`ShootingDayRepository` adapters, a new `PostgresProcessor` projector subscribing to the `shooting_day` stream, projection migration adding `projection_shooting_day`, `projection_scene_shooting_day`, and `projection_scene.summary`.
- **`crates/api`** — HTTP routes for ShootingDay CRUD + Scene scheduling endpoints; OpenAPI schema additions.
- **`crates/integration-tests`** — Tier-4 round-trip coverage for the new aggregate and the scene↔day link.
- **No breaking deserialization risk**: the system is not yet in production; persisted SierraDB events may be discarded during development. New `Option`-typed fields on existing events deserialize cleanly from older JSON as `None` regardless.
