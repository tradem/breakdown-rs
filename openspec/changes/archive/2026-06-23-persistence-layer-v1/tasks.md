## 1. Core read-model DTOs

- [x] 1.1 Add `*View` DTOs to `crates/core`: `SceneView`, `CharacterView` (+ `CharacterMeasurements`, `ContactInfo` already exist), `CostumeView` (+ `CostumeDetailView`, `CostumePhotoView`), `CalculationView` (+ `CalculationItemView`). Each carries `id`, `project_id`, `version`, `updated_at`. Derive `Serialize` + `utoipa::ToSchema` (ADR-006).
- [x] 1.2 Add `updated_at: DateTime<Utc>` to every view, document that its source is `Event.timestamp` (not UUIDv7).
- [x] 1.3 Confirm `chrono` already a core dep; add utoipa schema derives without pulling `sqlx` into core (keep hexagonal boundary).

## 2. Core write ports

- [x] 2.1 Define `SceneCommands`, `CharacterCommands`, `CostumeCommands`, `CalculationCommands` async traits in `core`, one method per existing command in each context's `commands.rs`.
- [x] 2.2 Ensure every mutating method accepts the command's `AggregateVersion` for optimistic locking; replies use `Result<…, DomainError>` (extend `DomainError` with a `VersionConflict` variant if needed).
- [x] 2.3 Verify signatures take owned command values and leak no `&Pool`/`&CommandService`/infra types (mockable seam requirement, spec `persistence-write-ports`).

## 3. Core read ports

- [x] 3.1 Define `SceneRepository`, `CharacterRepository`, `CostumeRepository`, `CalculationRepository` async traits in `core`, returning the `*View` DTOs from group 1.
- [x] 3.2 Include the required reads: `find_by_id`, `list_by_project` (paginated), `SceneRepository::scenes_by_character`, `CostumeRepository::costumes_by_character`, `CostumeRepository::costume_with_details_photos`.
- [x] 3.3 Add `version` field exposure on every view returned, for optimistic-locking round-trips (spec `persistence-read-ports`).

## 4. Projection migrations

- [x] 4.1 Create `crates/infra/migrations/` migration for the projection parent tables: `projection_scene`, `projection_character`, `projection_costume`, `projection_calculation` (with `version`, `updated_at`, FKs, JSONB columns for `measurements`/`contact`/`header`).
- [x] 4.2 Create migration for child/join tables: `projection_scene_character`, `projection_costume_detail`, `projection_costume_photo`, `projection_calculation_item` (FK + composite uniqueness for idempotent upsert/delete).
- [x] 4.3 Create migration for the `sierradb_event_checkpoints` table consumed by `PostgresProcessor` (per ADR-015), matching the table name passed to `PostgresProcessor::new`.
- [x] 4.4 Remove the legacy `20240621000001_smoke_check` migration content (or supersede it) once the real projection schema lands; keep migrations monotonic.

## 5. Infra projectors

- [x] 5.1 Implement `SceneProjector: EntityEventHandler<SceneAggregate, sqlx::Transaction<'static, Postgres>>` with exhaustive `match` over `SceneEvent` and `ON CONFLICT` upserts / idempotent deletes on `projection_scene` + `projection_scene_character`.
- [x] 5.2 Implement `CharacterProjector` over all `CharacterEvent` variants → `projection_character` (JSONB `measurements`/`contact`).
- [x] 5.3 Implement `CostumeProjector` over all `CostumeEvent` variants → `projection_costume` + `projection_costume_detail` + `projection_costume_photo` (idempotent add/remove).
- [x] 5.4 Implement `CalculationProjector` over all `CalculationEvent` variants → `projection_calculation` (JSONB `header`) + `projection_calculation_item` (idempotent add/update/remove, paid flags).
- [x] 5.5 Wire each projector as its own `PostgresProcessor` actor spawn helper in `crates/infra/projectors/` with its own checkpoints table + projection_id.

## 6. Infra read adapters

- [x] 6.1 Implement `sqlx`-backed `SceneRepository` adapter (compile-time-checked queries) incl. `scenes_by_character` JOIN.
- [x] 6.2 Implement `CharacterRepository` adapter incl. `list_by_project`.
- [x] 6.3 Implement `CostumeRepository` adapter incl. `costumes_by_character` and `costume_with_details_photos` (multi-row → nested DTO).
- [x] 6.4 Implement `CalculationRepository` adapter incl. `calculation_with_items` (multi-row → nested DTO).

## 7. Infra write adapter (mockable + SierraDB-bound)

- [x] 7.1 Implement the `*Commands` ports in `crates/infra/event_store/` over `kameo_es::CommandService` + per-aggregate `EntityActor` spawn.
- [x] 7.2 Surface version-conflict / not-found errors from `kameo_es` as `DomainError` variants at the port boundary.
- [x] 7.3 Ensure no `EventStore` trait is added to `core`; the write adapter is the sole owner of SierraDB persistence (spec `persistence-write-ports`).

## 8. API layer + composition root

- [x] 8.1 Define `AppState { command_service, pool, repositories }` (or per-context command/repo handles) in `crates/api/src/state.rs`.
- [x] 8.2 Implement Axum handlers for the first read+write endpoints (POST/PATCH writes, GET reads) for the four contexts, annotated `#[utoipa::path]` (ADR-006).
- [x] 8.3 Wire `utoipa::OpenApi` + Swagger UI serve (ADR-006 Phase 1).
- [x] 8.4 Implement `main.rs` composition root: build `CommandService`(SierraDB conn) + `PgPool`, run `sqlx::migrate!`, spawn the four `PostgresProcessor` actors, assemble `AppState`, start Axum.

## 9. Dev runtime

- [x] 9.1 Add `docker-compose.dev.yml` (single Postgres service, sensible default tag) at repo root or `backend/`.
- [x] 9.2 Document the start + migration commands and Docker prerequisite in `backend/AGENTS.md` and repo `README.md`.
- [x] 9.3 Confirm the compose contains exactly one service (no SierraDB); cross-reference the `sierradb-runtime-and-round-trip` follow-up change.

## 10. Tests (Tiers 1–3)

- [x] 10.1 Tier 1: confirm `Given::when().then()` aggregate tests exist and pass for all four contexts (gap-fill if any command lacks a test).
- [x] 10.2 Tier 2: add `crates/api` handler unit tests using mocked `*Commands`/`*Repository` ports (hand fakes or `mockall`).
- [x] 10.3 Tier 3: add `crates/integration-tests` projector tests — seed an event via `PostgresProcessor`/direct handler call against testcontainers Postgres, assert projection rows.
- [x] 10.4 Tier 3: add `crates/integration-tests` repository tests — seed projection rows, query via the adapter, assert `*View` DTOs incl. `version`/`updated_at`.
- [x] 10.5 Tier 4: add a tracked (unchecked) reference to the `sierradb-runtime-and-round-trip` follow-up spec for the live `command → SierraDB → projector → PG` round-trip; do not implement in v1.

## 11. Follow-up tracking

- [x] 11.1 Create the `sierradb-runtime-and-round-trip` follow-up change stub (proposal + minimal design) covering: SierraDB image investigation, SierraDB dev + production-grade compose, Tier-4 round-trip integration test, live `main.rs` write-path wiring.
