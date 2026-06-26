## Why

The four domain bounded contexts in `crates/core` (scene, character, costume, calculation) are fully modelled — events, commands, aggregates — yet `crates/infra` is an empty shell and `crates/api` has no read or write surface. ADR-002 prescribes CQRS/Event Sourcing and ADR-015 fixes the concrete split: **SierraDB as the event store, PostgreSQL for read-model projections**, driven by `kameo_es`. We need the persistence layer's first concrete design and an end-to-end-but-Postgres-runnable slice so the frontend can read and mutate a production's scenes, characters, costumes and calculations.

## What Changes

- Resolve the **Repository vs Processor** design question: the event store has no custom Port in `core` (`kameo_es`' `CommandService` + `EntityActor` already *are* the repository); instead `core` gains **per-aggregate command ports** + **per-aggregate read `Repository` ports** returning flat `*View` DTOs. Projection update is an `infra`-internal concern using `kameo_es`' `PostgresProcessor` + `EntityEventHandler` (no core port).
- Add `core` read-model DTOs: `SceneView`, `CharacterView`, `CostumeView` (+ detail/photo), `CalculationView` (+ items). Each carries `id`, `project_id`, `version` (for optimistic-locking round-trips on the command path), `updated_at` (derived from `Event.timestamp`).
- Add `core` write ports: `SceneCommands`, `CharacterCommands`, `CostumeCommands`, `CalculationCommands` (async, mockable, per-aggregate).
- Add `core` read ports: `SceneRepository`, `CharacterRepository`, `CostumeRepository`, `CalculationRepository`.
- Add `infra` write adapter: `kameo_es` `CommandService` wiring + per-aggregate `EntityActor` spawn (thin lifecycle wrapper, not a port).
- Add `infra` projectors: one `EntityEventHandler<PgTx>` per aggregate (`SceneProjector`, `CharacterProjector`, `CostumeProjector`, `CalculationProjector`), each spawned as its own `PostgresProcessor` with an independent checkpoint stream; idempotent `ON CONFLICT (id) DO UPDATE` upserts (at-least-once + idempotent replay, per ADR-015).
- Add `infra` projection `sqlx` migrations: `projection_scene`, `projection_scene_character`, `projection_character`, `projection_costume`, `projection_costume_detail`, `projection_costume_photo`, `projection_calculation`, `projection_calculation_item`, plus the `PostgresProcessor` `checkpoints` table.
- Add `infra` read adapters: `sqlx` Repository impls (`find_by_id`, `list_by_project`, `costumes_by_character`, `scenes_by_character` via JOIN, …).
- Add `api` wire-up: `AppState { CommandService, PgPool }`, Axum handlers for the first read/write endpoints, annotated with `utoipa` `#[utoipa::path]` per ADR-006.
- Add `main.rs` composition root (Poor Man's DI): build `CommandService`(SierraDB conn) + `PgPool` + spawn the four `PostgresProcessor` actors + assemble `AppState`.
- Add a minimal **dev** `docker-compose.dev.yml` for Postgres only (unblocks projector/repo development + migration apply). NOT production-grade.
- Define the four-tier test strategy: Tier 1 `Given` aggregate tests (exist), Tier 2 mocked-port API handler unit tests, Tier 3 testcontainers-PG projector/repository integration tests, Tier 4 SierraDB round-trip (**deferred to the `sierradb-runtime-and-round-trip` follow-up spec**).

## Capabilities

### New Capabilities

- `persistence-write-ports`: Per-aggregate async command ports (`SceneCommands`, `CharacterCommands`, `CostumeCommands`, `CalculationCommands`) defined in `core` as mockable seams transforming commands into aggregate replies; the event store itself is owned by `kameo_es`/SierraDB and is deliberately not a core port.
- `persistence-read-ports`: Per-aggregate read `Repository` ports in `core` returning flat `*View` DTOs (`SceneView`, `CharacterView`, `CostumeView`, `CalculationView`) including `version` for optimistic locking and `updated_at` from `Event.timestamp`.
- `persistence-projections`: Normalized PostgreSQL projections for the four current bounded contexts, updated by per-aggregate `EntityEventHandler` impls behind `kameo_es` `PostgresProcessor`, with idempotent upserts and per-projector checkpoints (ADR-015). Scope covers all currently-defined events in `core::{scene,character,costume,calculation}::events`.
- `persistence-dev-runtime`: Minimal developer-facing `docker-compose.dev.yml` (Postgres only) plus documented local-run instructions to run projections and the read/write path against a live Postgres. Production-grade runtime (SierraDB compose, hardening) is a non-goal and deferred.

### Modified Capabilities

- *(none — no existing specs are present in `openspec/specs/` yet.)*

## Impact

- **Code**: `crates/core` gains ports + DTOs (no infra deps, hexagonal boundary preserved). `crates/infra` gains the `event_store` lifecycle wrapper, `projectors/*`, `queries/*`, and projection `migrations/`. `crates/api` gains `AppState` + handlers + utoipa annotations. `main.rs` becomes the composition root.
- **APIs**: First concrete REST endpoints (CRUD-ish read + write) for scenes, characters, costumes, calculations, documented via utoipa-generated OpenAPI (ADR-006) for frontend codegen.
- **Dependencies (runtime)**: `kameo_es` git dep already present (`postgres` feature, activates the projection backend per ADR-003/015); `sqlx` already a workspace dep. No new crate deps expected for v1 beyond dev tooling.
- **Boundaries**: Event store stays SierraDB-owned (no `EventStore` Port in core) — this is the explicit resolution of the Repository-vs-Processor question. Projection update is infra-internal (no core port). Only write-command and read-repository surfaces cross the hexagonal boundary as ports.
- **Scope boundary (documented)**: Actor / CastMember / Availability / Schedule aggregate + its projection (actor sickness, rescheduling) is a **future** bounded context, out of scope here. `SceneEvent::CharacterAssigned` is the sole authoritative source of the scene↔character roster; the reverse read is satisfied by `JOIN projection_scene_character ⋈ projection_scene`. The current scene scheduling fields (`scene_number`, `is_schedule_set`, `location`, `mood`) are placeholders the future scheduling context will enrich without restructuring the roster projections.
- **Tests**: Tiers 1–3 defined; Tier 4 (SierraDB round-trip) + SierraDB dev/prod compose deferred to the `sierradb-runtime-and-round-trip` follow-up spec (tracked, separate proposal).
- **ADRs**: Honours ADR-001 (hexagonal), ADR-002 (ES+CQRS), ADR-004 (UUIDv7), ADR-006 (utoipa), ADR-015 (SierraDB store + Postgres projections). No new ADR required for v1.
