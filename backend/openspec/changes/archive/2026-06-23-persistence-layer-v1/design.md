## Context

`crates/core` ships four fully-modelled bounded contexts (`scene`, `character`, `costume`, `calculation`) — each with `events` (incl. `kameo_es::EventType`), `commands` (`CommandName`), and `aggregate` (`Entity` + `Command` + `Apply`). `crates/infra` is an empty shell (`event_store/`, `projectors/`, `queries/` are doc-comment-only `mod.rs`), `crates/api`'s `AppState {}` holds nothing, and only a single smoke migration exists in `crates/infra/migrations/`. There are no production OpenAPI endpoints yet.

The architecture is fixed by accepted ADRs:

- **ADR-001** Hexagonal architecture; `core` pure, ports defined in `core`, adapters in `infra`, Poor Man's DI in `main.rs`.
- **ADR-002** Event Sourcing (write) + CQRS (read). Commands act as `kameo_es::Command`; aggregates rebuilt from events; read models are flat projections, never queried from aggregates.
- **ADR-004** UUIDv7 for every entity and event id (`Uuid::now_v7()`).
- **ADR-006** utoipa for OpenAPI generation + frontend codegen; handlers annotated `#[utoipa::path]`.
- **ADR-015** (supersedes ADR-003) **SierraDB** is the event store (via `kameo_es` over RESP3, accessed through `redis::Client`) and **PostgreSQL** holds the CQRS projections, populated by `kameo_es`' `PostgresProcessor`. The two tiers are decoupled and eventually consistent; projectors must be idempotent.

`kameo_es`' actual surface (verified against the pinned git checkout) is decisive for the Repository-vs-Processor question:

| `kameo_es` provides | Role |
|---|---|
| `CommandService` + `EntityActor<E>` | Write-side aggregate lifecycle + optimistic-concurrency appends to SierraDB (`EAPPEND`, `EXPECTED_VERSION`, gapless versions). |
| `Apply`, `Command<C>`, `Entity`, `EventType`, `CommandName` | Core-impl traits (already used by `core`). |
| `EventProcessor<E,H>` + `PostgresProcessor<E,H>` + `Worker` | Read-side: streams events via SierraDB `ESUB`, checkpoints per partition, drives a handler inside a `sqlx::Transaction<'static, Postgres>`. |
| `EventHandler<C>`, `EntityEventHandler<E,C>`, `CompositeEventHandler<E,C,PE>` | The traits our projectors implement; context is `sqlx::Transaction<'static, Postgres>` for the Postgres backend. |
| `core::test_utils::Given::when(cmd).then(events)` | Pure in-process aggregate decision testing (already in use). |
| `InMemoryEventProcessor<H>` | **Projection-side only** in-memory processor; context is `()`, *not* `PgTx` — not usable for our SQL-bound projectors without an abstraction we don't want. There is **no in-memory event store** in `kameo_es`; the write path is structurally SierraDB-bound. |

The conclusion: the event store has no business being a `core` Port, because `kameo_es` *already is* the repository on the write side, and wrapping it leaks its internals. The projection update is likewise `infra`-internal (the API never invokes it). The only genuine hexagonal seam application code touches is **commands-in / views-out**.

## Goals / Non-Goals

**Goals:**

- First concrete persistence layer design: ports, adapters, projections, wire-up for the four current bounded contexts.
- A Postgres-runnable slice (read + write ports + projections + first REST endpoints) that the frontend can drive.
- Resolve Repository-vs-Processor as a documented decision, not folklore.
- Define a test strategy that is honest about SierraDB being un-runnable in v1 unit tests.

**Non-Goals:**

- A custom `EventStore` Port in `core` (the event store is owned by `kameo_es`/SierraDB; intentionally no port).
- A `ProjectionSink` abstraction to unit-test projectors without PG (premature abstraction; projector correctness is covered by Tier-3 integration tests).
- Actor / CastMember / Availability / Schedule aggregate + projection (actor sickness / rescheduling). Future context; `SceneEvent::CharacterAssigned` is the sole roster authority and the reverse read is a JOIN.
- SierraDB dev/prod `docker-compose`, production-grade hardening, and the SierraDB end-to-end round-trip test — deferred to the `sierradb-runtime-and-round-trip` follow-up spec.
- Projection schema versioning / event upcasting policy (ADR-002 mitigation, future change).
- Authentication/authorization (ADR-010), observability wiring (ADR-011), photo storage via OpenDAL/S3 (ADR-009).

## Decisions

### D1. Port/Adapter topology (resolution of Repository vs Processor)

```
                              crates/api  (handlers, utoipa, AppState)
                                   │ depends on ports only
        ┌──────────────────────────┴──────────────────────────┐
        ▼                                                     ▼
 ┌─ core PORTS ──────────────────────────────┐    ┌─ core DTOs ─────────┐
 │ WRITE  SceneCommands / CharacterCommands │    │ SceneView           │
 │        CostumeCommands / CalculationCnt.. │    │ CharacterView       │
 │ READ   SceneRepository / CharacterRepo.. │    │ CostumeView(+detail,│
 │        CostumeRepository / CalculationR.. │    │  photo), CalcView   │
 └──────────────────────────────────────────┘    │  (+items)           │
        ▲                          ▲              │  • id, project_id   │
        │ impl                     │ impl           │  • version, updated_at│
 ┌──────┴──────────────┐   ┌────────┴──────────────────────────────┐
 │ infra (write)       │   │ infra (read)                          │
 │ kameo_es CommandSvc │   │ sqlx Repository adapters               │
 │ + EntityActor spawn │   │ find_by_id, list_by_project,          │
 │ → SierraDB (no port)│   │ costumes_by_character, scenes_by_char  │
 └─────────────────────┘   └───────────────────────────────────────┘

 ┌─ infra (projection, NO port — internal) ────────────────────────┐
 │ SceneProjector : EntityEventHandler<SceneAggregate, PgTx>       │
 │ CharacterProjector / CostumeProjector / CalculationProjector    │
 │ each spawned as its own PostgresProcessor (own checkpoint)      │
 └────────────────────────────────────────────────────────────────┘
```

**Why per-aggregate command ports (Option B) over a generic command bus (A) or no port (C):**
- (A) `trait CommandBus { async fn dispatch<C: Command>(&self, id, c: C) -> Result<C::Reply> }` is elegant but forces `Box<dyn>` over generics + async → a well-known Rust trait-object pain in ES stacks. Rejected.
- (C) `api` depends on `kameo_es::CommandService` directly → fastest to ship, but sacrifices Tier-2 mocked-port unit tests of handlers and couples the API to the concrete lib. Rejected for v1 (kept as a fallback if boilerplate hurts).
- (B) Per-aggregate `*Commands` ports are explicit, type-safe, trivially mockable (`mockall` or hand fakes), and map 1:1 to utoipa handlers. Verbose but pays back as testability. **Chosen.**

**Why no `EventStore` Port in core:** `kameo_es`' `CommandService` + `EntityActor` already load/save events to SierraDB internally with optimistic concurrency. A `core::EventStore` trait would be a leaky façade kept in sync with `kameo_es` internals for zero consumer value. The write port is therefore *command-shaped* (ask an aggregate to handle a command), not *event-store-shaped*.

**Why no `Repository` for aggregates (DDD sense):** ADR-002 forbids querying aggregates for views. Repositories here return flat `*View` DTOs (read-model projections), so the name `Repository` denotes the read-model port, not an aggregate-root repository — to be documented in code comments to avoid DDD confusion.

### D2. Projection topology — one projector per aggregate

Each bounded context gets its **own** `EntityEventHandler` struct, spawned as its own `PostgresProcessor` actor with an independent `checkpoints` row set. Benefits over a single composite handler:

- Independent catch-up / replay; one slow context does not stall the others.
- Failure isolation; a buggy upsert in one projector does not poison the stream for the others.
- Maps cleanly to per-context unit/integration tests (Tier 3).
- The `kameo_es` `match_event!` macro dispatches by `Entity::category()`, so a single SierraDB `ESUB` stream can fan out to multiple processors, or each processor subscribes to its own category — v1 uses **one processor per category** for the simplest wiring.

Cross-context reads ("which scenes feature character X?") are satisfied by `JOIN projection_scene_character ssc JOIN projection_scene s ON s.id = ssc.scene_id WHERE ssc.character_id = $1` in `SceneRepository`. No projector writes another context's table → no "authoritative projection" ambiguity.

### D3. Projection schema (normalized)

Postgres' strength per ADR-015 (relational scheduling queries, FK integrity). `updated_at` derived from `Event.timestamp`; `version` mirrors the aggregate version carried in events for optimistic-locking reads.

```
projection_scene(id pk, project_id, scene_number, location, mood,
                 is_schedule_set, version, updated_at)
projection_scene_character(scene_id fk, character_id, version)      -- M:N roster
projection_character(id pk, project_id, name, is_extra, is_main_character,
                     measurements jsonb, contact jsonb, version, updated_at)
projection_costume(id pk, project_id, character_id null fk, notes,
                   version, updated_at)
projection_costume_detail(costume_id fk, detail_id, text)            -- Detail Added/Removed
projection_costume_photo (costume_id fk, photo_id)                   -- Photo Linked/Unlinked
projection_calculation(id pk, project_id, header jsonb, version, updated_at)
projection_calculation_item(calculation_id fk, item_id, name,
                     quantity numeric, unit_price numeric, is_paid)   -- Item* events
-- PostgresProcessor-owned:
sierradb_event_checkpoints(projection_id, partition_id, last_sequence)
```

All projector writes use `INSERT ... ON CONFLICT (id) DO UPDATE SET ...` (idempotent upsert; at-least-once delivery + safe replay, ADR-015). Detail/photo/item sub-rows use `ON CONFLICT (parent_id, child_id) DO UPDATE` / `DO NOTHING` so removal events (`DetailRemoved`, `PhotoUnlinked`, `CalculationItemRemoved`) become idempotent `DELETE WHERE ...`.

### D4. Character (fixed) vs Actor (sick) vs rescheduling boundary

The Character aggregate models the **role/persona** (identity, measurements, contact) — stable for a production. The **actor** (the human, availability, sickness windows) is a *future* bounded context (e.g. `Availability`/`Schedule` aggregate), out of scope here. Consequences:

- `SceneEvent::CharacterAssigned` is the **sole** authoritative source of the scene↔character roster. The `Character` aggregate emits only its own lifecycle events; it never emits "assigned to scene". Roster lives in `projection_scene_character`.
- The future scheduling context enriches scenes with time ranges/availability via a *new* table (e.g. `projection_scene_schedule`) alongside the roster projections — no restructuring of v1 projections needed.
- v1 scene scheduling fields (`scene_number`, `is_schedule_set`, `location`, `mood`) are placeholders for that enrichment.

### D5. Test strategy — mocking as the unit-test seam

```
Tier 1 — PURE UNIT (rstest, zero I/O) ──────────────
  core aggregate command→event     Given::when(cmd).then(events)   (exists ✓)
Tier 2 — MOCKED-PORT UNIT (trait fakes, no DB) ─────
  api handlers (HTTP→command, HTTP→repo)
  • ports are exactly the mockable surface (mockall or hand fakes)
Tier 3 — TESTCONTAINERS PG INTEGRATION ─────────────
  infra projectors (seed event → handler → assert rows)
  infra repositories (seed rows → query → assert *View)
  • sqlx is PG-dialect-bound + compile-time-checked; no honest substitute
Tier 4 — SIERRADB ROUND-TRIP  (DEFERRED → follow-up spec) ─
  command → SierraDB → projector → PG; needs sierradb testcontainer
```

**Mocking, not in-memory, for unit tests around the persistence layer:** verified against `kameo_es` — there is *no* in-memory event store (write path is SierraDB-bound), and `InMemoryEventProcessor<H>` is projection-side with context `()`, not `PgTx`, so it cannot drive our SQL projectors without extracting a `ProjectionSink` trait (premature). Aggregate decision testing (Tier 1) already has the in-process `Given` helper. Everything else around the layer is port-mocked.

**Design consequence enforced in specs:** ports must be mockable — async methods taking owned command/view values, no `&Pool`/`&CommandService` leaking into signatures. Projector decision logic stays thin; any growing branch is extracted into a pure rstest-tested helper, not into a `ProjectionSink` abstraction.

### D6. Dev runtime — Postgres-only `docker-compose.dev.yml`

v1 ships a minimal dev compose for Postgres (unblocks projector/repo development + `sqlx migrate`). It is explicitly **not production-grade** (no pinned tags beyond the testcontainers default, no volumes, no backup, no monitoring). SierraDB dev compose + production-grade compose (postgres+sierradb, pinned, hardened, OTel hooks per ADR-011) belong with the SierraDB round-trip concern in the `sierradb-runtime-and-round-trip` follow-up spec, because the same SierraDB image investigation is the prerequisite for both the live write path *and* Tier-4 testing.

## Risks / Trade-offs

- **[SierraDB not runnable in v1 tests]** → Mitigation: write ports are mockable (D5 Tier 2), so the whole read side + write-side ports/adapters/API are delivered and tested without a live SierraDB. v1 cannot demonstrate a live `command→SierraDB→projection` round-trip; that gap is the explicit scope of the follow-up spec.
- **[SierraDB docker image availability unknown]** → ADR-015 pins the Cargo dep but not a container tag (v0.3.x, ~326★). First task of the follow-up is to investigate image availability / build-from-source. v1 is structured so this unknown does not block it.
- **[Eventually consistent reads]** → Projections lag the event store (ADR-015). Mitigation: `version` exposed on `*View` DTOs so the frontend can detect staleness and retry; ADR-002 "force refresh" path deferred to a future change.
- **[Projector boilerplate ×4]** → One `EntityEventHandler` per context is deliberately chosen (D2) for isolation/testability over DRY. Revisit if boilerplate becomes painful.
- **[No transactional projection update]** → A projector crash between append and projection update is recoverable only via idempotent replay from the checkpoint, not a single-DB transaction (ADR-015 consequence). Mitigation: idempotent upserts + per-processor checkpoints; this is by design.
- **[`Repository` naming vs DDD]** → Could confuse contributors expecting aggregate-root repositories. Mitigation: documented in code comments and this design.
- **[`updated_at` from `Event.timestamp`, not from UUIDv7]** → Two plausible sources. Event timestamp is first-class in `kameo_es::Event`; UUIDv7 stays as the event id only (ADR-004). Mitigation: none needed; documented decision.

## Migration Plan

- No production data to migrate (greenfield).
- Rollout is additive: new `projection_*` migrations + infra modules + api handlers behind new routes. No existing endpoints are removed (there are none).
- Rollback: drop the new projection tables + remove the new routes; the event store (SierraDB) is untouched by v1's projection-only DDL.
- Database migrations applied via `sqlx::migrate!` (`crates/infra/migrations/`), already wired in `infra::testing::spawn_postgres` and to be applied by `main.rs` at boot.

## Open Questions

- **SierraDB container image:** Does upstream publish a usable image, or must we build from source? Resolved in the follow-up spec; does not block v1.
- **One SierraDB `ESUB` subscription fanning out to four processors vs four category-scoped subscriptions:** v1 uses per-category subscriptions for simplicity; revisit if throughput/latency data later suggests fan-out.
- **Whether to expose a generic `CommandGateway` later** to collapse per-aggregate `*Commands` ports if boilerplate hurts: open, deferred — measure first.
