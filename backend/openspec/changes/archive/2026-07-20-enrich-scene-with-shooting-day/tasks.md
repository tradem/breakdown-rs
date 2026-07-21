## 1. Shared value objects

- [x] 1.1 Add `ShootingDayId(Uuid)` opaque UUIDv7 id to `core/src/shared.rs` following the `EpisodeId` template (new/from_uuid/Default/serde transparent/ToSchema).
- [x] 1.2 Add `LexicalSortKey(String)` value object to `core/src/shared.rs` with: fixed printable-ASCII alphabet, non-empty/whitespace/length validation, lexicographic `Ord`, a `midpoint(a, b) -> Result<Self>` constructor, and a `shared_test.rs` block asserting `a < midpoint(a,b) < b` over sample pairs and rejection of invalid inputs.
- [x] 1.3 Export both types from `core/src/lib.rs` / module re-exports.

## 2. ShootingDay aggregate (core)

- [x] 2.1 Create `crates/core/src/shooting_day/` module with `mod.rs` re-exporting aggregate/commands/events/views/error/ports (mirror `scene/`).
- [x] 2.2 Implement `events.rs`: `ShootingDaySource` enum (`Manual` / `AiExtracted { document_id, external_ref: Option<String>, confidence: f32 }`) and `ShootingDayEvent` variants (`Created`, `Renamed`, `Rescheduled`, `Reordered`, `Archived`); implement `kameo_es::EventType`.
- [x] 2.3 Implement `commands.rs`: `CreateShootingDay`, `RenameShootingDay`, `RescheduleShootingDay`, `ReorderShootingDay`, `ArchiveShootingDay` (derive `serde::Deserialize`, `utoipa::ToSchema`, implement `kameo_es::CommandName`).
- [x] 2.4 Implement `aggregate.rs`: `ShootingDayAggregate` state, `Entity` impl (`category = "shooting_day"`), `Apply` impl for all five events, `Command` impls with version-mismatch + `ArchivedCannotBeMutated` guards (-archive rejects all mutations except `ArchiveShootingDay` which is itself idempotent-reject on already-archived).
- [x] 2.5 Implement `error.rs`: `ShootingDayError` (incl. `ArchivedCannotBeMutated`, `DuplicateOrderKey`, `ValidationError`); wire into `core/src/error.rs`.
- [x] 2.6 Implement `views.rs`: `ShootingDayView { id, episode_id, label, order_key, date, source, archived, version, updated_at }` (+ `ToSchema`).
- [x] 2.7 Implement `ports.rs`: `ShootingDayCommands` (command dispatch trait) and `ShootingDayRepository` (list-by-episode-in-order, get-by-id) port traits following the `scene/ports.rs` shape.
- [x] 2.8 Write `aggregate_test.rs`: creation, rename-preserves-order, reschedule (incl. `None`), reorder-midpoint emits exactly one event with `a < key < b`, archive flips + terminal (subsequent mutations reject), version-mismatch rejection.

## 3. Scene summary + Scene↔ShootingDay link (core)

- [x] 3.1 Add `summary: Option<String>` to `SceneDetails` in `scene/events.rs` (additive; `Default` already `None`).
- [x] 3.2 Add `shooting_day_ids: Vec<ShootingDayId>` to `SceneAggregate` state and update `SceneCreated` apply (initialise empty when not carried by the legacy event) and `Default`.
- [x] 3.3 Add `ShootingDayScheduled` / `ShootingDayUnscheduled` variants to `SceneEvent` (carry `id`, `shooting_day_id`, `version`) and update `EventType` match arms.
- [x] 3.4 Add `ScheduleSceneOnShootingDay` / `UnscheduleSceneFromShootingDay` commands (`scene/commands.rs`) with version check; `Schedule` rejects already-scheduled without emitting; `Unschedule` rejects not-scheduled.
- [x] 3.5 Implement `Command` impls on `SceneAggregate` for the two new commands emitting the matching events + `version.next()`.
- [x] 3.6 Extend `SceneView` with `summary: Option<String>` and `shooting_day_ids: Vec<ShootingDayId>`.
- [x] 3.7 Add scene-side unit tests: double-schedule rejected, unschedule-not-scheduled rejected, summary round-trips through `UpdateSceneDetails` "unchanged" guard.

## 4. Infrastructure: projection migration + projectors

- [x] 4.1 Author `crates/infra/migrations/<ts>_shooting_day_and_scene_summary.up.sql` (+ `.down.sql`): `ALTER TABLE projection_scene ADD COLUMN summary TEXT`; create `projection_shooting_day` (id, episode_id, label, order_key, date, source JSONB, archived, version, updated_at) + index `(episode_id, order_key)`; create `projection_scene_shooting_day` join (scene_id, shooting_day_id, version, PK) + index on `shooting_day_id`.
- [x] 4.2 Implement `ShootingDayCommands` adapter (SierraDB-backed `kameo_es` command dispatch) and `ShootingDayRepository` adapter (sqlx read queries: `list_by_episode(episode_id) ORDER BY order_key ASC`, `get(id)`).
- [x] 4.3 Add `ShootingDayPostgresProcessor` event handler consuming the `shooting_day` stream and upserting `projection_shooting_day`; handle all five event variants.
- [x] 4.4 Extend the scene projector's handler with `ShootingDayScheduled`/`Unscheduled` cases maintaining `projection_scene_shooting_day` and `projection_scene.summary`.
- [x] 4.5 Spawn the fifth projector in `main.rs` next to the existing four (subscribe to the `shooting_day` SierraDB stream); wire `ShootingDayCommands`/`ShootingDayRepository` into the composition root.

## 5. API surface

- [x] 5.1 Add Axum routes for ShootingDay CRUD: `POST /episodes/:episode_id/shooting-days`, `PATCH /shooting-days/:id` (rename/reschedule/reorder), `POST /shooting-days/:id/archive`; extend OpenAPI schemas.
- [x] 5.2 Add Scene scheduling routes: `POST /scenes/:id/shooting-days` (schedule), `DELETE /scenes/:id/shooting-days/:shooting_day_id` (unschedule).
- [x] 5.3 Ensure `CreateScene`/`UpdateSceneDetails` request DTOs carry `summary`; return it in scene responses; document in swagger.

## 6. Integration tests (Tier 4)

- [x] 6.1 `CreateShootingDay` → event persisted → projector catches up → `ShootingDayRepository::list_by_episode` returns it ordered by `order_key`.
- [x] 6.2 `ScheduleSceneOnShootingDay` → projector populates `projection_scene_shooting_day` → reverse query "scenes of shooting day" returns the Scene.
- [x] 6.3 `ArchiveShootingDay` while referenced → Scene view keeps resolvable `shooting_day_id`; archived day hidden from list-by-episode picker query.
- [x] 6.4 Reorder with midpoint: insert day between two existing → exactly one `ShootingDayReordered` event observed on the stream; siblings untouched.

## 7. Guardrails & docs

- [x] 7.1 Run `cargo test -p core`, `cargo test -p architecture_tests`, `cargo deny check bans`; ensure no `core → infra/api` dependency leaked.
- [x] 7.2 Run `cargo mutants --in-diff` on changed `core` modules; add kill-tests for the archived-guard and midpoint-generator survivors.
- [x] 7.3 Add SPDX headers to new `.rs`/`.sql` files via `./scripts/add-spdx-headers.sh crates/core/src/shooting_day crates/infra/migrations`.
- [x] 7.4 Update AGENTS.md production-hierarchy note to read `Series → Season → Block → Episode → Scene/Scene→ShootingDay` leaf.
