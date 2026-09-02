# scene-shoot Specification

## Purpose
TBD - created by archiving change add-shoot-day-execution-and-continuity. Update Purpose after archive.
## Requirements
### Requirement: SceneShoot aggregate models the (Scene, ShootingDay) association

The system SHALL model the association between a `Scene` and a `ShootingDay` as a `SceneShoot` aggregate (category `"scene_shoot"`). Each aggregate stream SHALL correspond to exactly one `(scene_id, shooting_day_id)` pair, identified by a UUIDv7 `SceneShootId`. A reshoot of the same scene on a different `ShootingDay` SHALL be a separate `SceneShoot` stream; the prior stream's state SHALL NOT be amended to represent the reshoot. The `SceneShoot` SHALL be scoped to the `EpisodeId` shared by its scene and shooting day.

The aggregate SHALL carry both a planned and an actual ordering, distinct fields:
- `planned_order: LexicalSortKey` — the Dispo/"Soll" sequence (the assistant director's planned order).
- `actual_order: Option<LexicalSortKey>` — the "Ist" sequence, `None` until execution data is recorded.

#### Scenario: Creating a planned scene shoot
- **WHEN** a `PlanSceneShoot { id, scene_id, shooting_day_id, planned_order }` command is dispatched on a new `SceneShoot` stream
- **THEN** the aggregate SHALL emit `SceneShootPlanned { id, scene_id, shooting_day_id, planned_order, status: Planned, version }`
- **AND** the aggregate state SHALL set `actual_order = None`, `start_dt = None`, `end_dt = None`, `status = Planned`, `notes = []`, `continuity_photos = []`

#### Scenario: Reshoot is a new pair, not an amendment
- **WHEN** a scene already has a `SceneShoot` on `ShootingDay D1` in status `Shot`, and the same scene is to be shot again on `ShootingDay D5`
- **THEN** the system SHALL create a new `SceneShoot` stream with id `D5-pair`
- **AND** SHALL NOT modify the existing `D1` stream's status, notes, or continuity photos

#### Scenario: Pair is unique
- **WHEN** a `PlanSceneShoot` is dispatched for a `(scene_id, shooting_day_id)` pair that already has an active `SceneShoot`
- **THEN** the aggregate SHALL reject the command with a `Conflict`/`AlreadyExists` domain error

### Requirement: planned_order is immutably frozen on first execution data

The `SceneShoot` aggregate SHALL reject any command that mutates `planned_order` once *either* `actual_order` is set (`Some`) *or* `start_dt` is set (`Some`). This freezing is per-`SceneShoot` (per scene, per day), not per-shooting-day. No client-driven "release plan" command or event SHALL exist; the freeze is a passive aggregate invariant derived from execution data.

#### Scenario: planned_order editable while no execution data exists
- **WHEN** a `SceneShoot` has `actual_order = None` and `start_dt = None`
- **AND** a `ReplanSceneShoot { planned_order }` command is dispatched
- **THEN** the aggregate SHALL emit `SceneShootReplanned { planned_order }` and update `planned_order`

#### Scenario: planned_order frozen after start_dt set
- **WHEN** a `SceneShoot` has `start_dt = Some(t)`
- **AND** a `ReplanSceneShoot { planned_order }` command is dispatched
- **THEN** the aggregate SHALL reject the command with a `PlannedOrderFrozen` domain error and SHALL NOT change `planned_order`

#### Scenario: planned_order frozen after actual_order set
- **WHEN** a `SceneShoot` has `actual_order = Some(k)`
- **AND** a `ReplanSceneShoot` command is dispatched
- **THEN** the aggregate SHALL reject the command with a `PlannedOrderFrozen` domain error

### Requirement: SceneShoot execution lifecycle and status

The `SceneShoot` aggregate SHALL carry a `status: SceneShootStatus` with values `Planned | Scheduled | InProgress | Shot | Skipped`. State transitions:
- `Planned → InProgress` when execution starts (`start_dt` is set) OR `actual_order` is set (whichever occurs first).
- `* → Shot` via a `FinishSceneShoot` command (terminal-ish per pair; sets `end_dt`).
- `* → Skipped` via a `SkipSceneShoot` command.
RESHOTS are modelled by creating a new pair (see above), not by reopening a `Shot` stream.

#### Scenario: First execution data promotes to InProgress
- **WHEN** a `SceneShoot` is in status `Planned` and a command sets `start_dt` or `actual_order`
- **THEN** the aggregate SHALL transition to `InProgress` (in the same event that introduces the execution data)

#### Scenario: Finishing a scene shoot
- **WHEN** a `FinishSceneShoot { end_dt }` command is dispatched on an `InProgress` `SceneShoot`
- **THEN** the aggregate SHALL emit `SceneShootFinished { end_dt }` and transition to `Shot`

#### Scenario: Skipping a scene shoot
- **WHEN** a `SkipSceneShoot` command is dispatched on a `SceneShoot` that is not yet `Shot`
- **THEN** the aggregate SHALL transition to `Skipped`

### Requirement: Executable mutation commands set execution data

The aggregate SHALL accept:
- `StartSceneShoot { start_dt }` — sets `start_dt` (idempotent: re-dispatch is a no-op if already set to the same value; rejects if already set to a different value with `AlreadyStarted`).
- `SetActualOrder { actual_order }` — sets/replaces `actual_order`.
- `FinishSceneShoot { end_dt }` — sets `end_dt`, transitions to `Shot`.
- `SkipSceneShoot` — transitions to `Skipped`.

Each of these that introduces execution data SHALL also freeze `planned_order` for that `SceneShoot` as a side effect (no separate event required).

#### Scenario: Setting start_dt records time
- **WHEN** `StartSceneShoot { start_dt }` is dispatched on a `Planned` `SceneShoot`
- **THEN** the aggregate SHALL emit `SceneShootStarted { start_dt }`, set `start_dt`, transition to `InProgress`, and henceforth reject `ReplanSceneShoot`

#### Scenario: Actual order can be re-set during the day
- **WHEN** `SetActualOrder` is dispatched on an `InProgress` `SceneShoot` with a new `actual_order`
- **THEN** the aggregate SHALL emit `SceneShootActualOrderSet { actual_order }` replacing the prior value

### Requirement: Notes are mutable and fully audited via the event stream

The `SceneShoot` aggregate SHALL carry `notes: Vec<Note>` where each `Note` has `id: Uuid` (UUIDv7), `body: String`, and optional author claim. The aggregate SHALL accept:
- `AddSceneShootNote { note_id, body, author? }` → emits `ShootDayNoteAdded`.
- `UpdateSceneShootNote { note_id, body }` → emits `ShootDayNoteUpdated`.
- `RemoveSceneShootNote { note_id }` → emits `ShootDayNoteRemoved`.

The chronological event stream SHALL be the authoritative audit log ("who changed what when"); no separate audit table SHALL exist.

#### Scenario: Adding a note
- **WHEN** `AddSceneShootNote { note_id, body, author }` is dispatched
- **THEN** the aggregate SHALL emit `ShootDayNoteAdded { note_id, body, author }` and append the note to `notes`

#### Scenario: Updating an existing note
- **WHEN** `UpdateSceneShootNote { note_id, body }` is dispatched for a `note_id` present in `notes`
- **THEN** the aggregate SHALL emit `ShootDayNoteUpdated { note_id, body }` and replace the body of that note

#### Scenario: Removing a note
- **WHEN** `RemoveSceneShootNote { note_id }` is dispatched for a note that exists
- **THEN** the aggregate SHALL emit `ShootDayNoteRemoved { note_id }` and drop the note from `notes`

#### Scenario: Updating a non-existent note fails
- **WHEN** `UpdateSceneShootNote` is dispatched for a `note_id` not present
- **THEN** the aggregate SHALL reject the command with a `NoteNotFound` error

### Requirement: SceneShoot ports

The system SHALL define:
- `SceneShootCommands` (write port): `plan`, `replan`, `start`, `set_actual_order`, `finish`, `skip`, `add_note`, `update_note`, `remove_note`, `link_continuity_photo`, `unlink_continuity_photo`. Each returns the resulting `AggregateVersion` (or `(SceneShootId, AggregateVersion)` for `plan`).
- `SceneShootRepository` (read port): `find_by_id`, `list_by_shooting_day` (all pairs of a day), `find_by_scene_and_day`, `list_by_scene` (all days a scene was shot on).

#### Scenario: Plan returns id and version
- **WHEN** `SceneShootCommands::plan` succeeds
- **THEN** it SHALL return `(SceneShootId, AggregateVersion::INITIAL)`

### Requirement: Continuity photos are linked on the SceneShoot

The `SceneShoot` aggregate SHALL carry `continuity_photos: Vec<PhotoId>`. Linking/unlinking SHALL be modelled as `LinkContinuityPhoto` / `UnlinkContinuityPhoto` commands emitting `ContinuityPhotoLinked` / `ContinuityPhotoUnlinked` events. A `PhotoId` MAY appear at most once in the list. The actual photo bytes and variant lifecycle SHALL remain the responsibility of the `Photo` aggregate (see photo-continuity-binding capability).

#### Scenario: Linking a continuity photo
- **WHEN** `LinkContinuityPhoto { photo_id }` is dispatched for a `photo_id` not already in `continuity_photos`
- **THEN** the aggregate SHALL emit `ContinuityPhotoLinked { photo_id }` and append it

#### Scenario: Duplicate link is rejected
- **WHEN** `LinkContinuityPhoto { photo_id }` is dispatched for a `photo_id` already in the list
- **THEN** the aggregate SHALL reject with `AlreadyLinked`

### Requirement: SceneShoot projection mirrors all fields

A `projection_scene_shoot` table SHALL be replay-derived from `SceneShoot` events and SHALL contain at minimum: `id`, `scene_id`, `shooting_day_id`, `episode_id`, `planned_order`, `actual_order` (nullable), `start_dt` (nullable), `end_dt` (nullable), `status`, `notes` (JSONB), `continuity_photo_ids` (array or join), `version`, `updated_at`. There SHALL be a unique constraint on `(scene_id, shooting_day_id)`.

#### Scenario: Projection is replay-derivable
- **WHEN** the Postgres read model is lost and SierraDB is intact
- **THEN** booting the `SceneShootProjector` repopulates `projection_scene_shoot` by replaying events
- **AND** no bespoke reconciliation is required

