// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Building Block View

== Workspace Structure

The workspace follows hexagonal layers as cargo crates. The `architecture`
crate runs boundary tests; the `integration-tests` crate exercises the full
command→event→projection round-trip against live containers.

#diagram("workspace-structure", caption: [Crates and dependency directions])

| Crate | Responsibility | Key dependencies |
|-------|---------------|------------------|
| `crates/core` | Commands, events, aggregates, port traits, read DTOs, error registry | `serde`, `uuid`, `chrono`, no infra |
| `crates/infra` | Event-store adapter, projectors, queries, photo storage (OpenDAL), sagas, AI import, reporting | `sqlx`, `kameo_es`, `opendal`, `typst` |
| `crates/api` | Axum routes, OIDC middleware, composition root, lifecycle | `axum`, `utoipa`, `core`, `infra` |
| `crates/architecture` | Boundary tests (`rust_arkitect`) | core, infra, api |
| `crates/integration-tests` | Tiers 1–4, black-box over live PG / SierraDB | `testcontainers` |

== Core Bounded Contexts

The core crate is organized by domain module. Each module owns its commands,
events, aggregate and projection shape; nothing crosses a module boundary
without going through a port trait.

#diagram("core-modules", caption: [Domain modules and their relationships])

=== Production Hierarchy

Four levels, series being an opaque seam for a future additive aggregate.
Each level's aggregate emits hierarchy context (`series_id`, `season_id`)
into events so audit never needs read-model lookups.

=== Costume Domain

`Character` is season-scoped, `Costume` is owned by a character, and
`CostumeCategory` is a season-scoped vocabulary. The costume projector
resolves the category name at read time.

=== Photo Context

Photos live once per *binding* (`Costume` or `Continuity`). Byte storage is
CRUD on Garage via OpenDAL (#adr-ref(num: "019", slug: "costume-photo-storage", title: "Costume Photo Storage")). Three sagas react to lifecycle events:
thumbnail generation, deletion (refcount via projection), and bytes cleanup.

=== AI Import

Optional bounded context (default off). Owners enqueue per-project
concurrency permits, heartbeat renewal, lease fencing, and terminal-state
payload GC — all visible in chapter 6 and 7.

== Persistence Strategy (Level 2 Whitebox)

| Aggregate | Event store | Projection table | Projector |
|-----------|------------|------------------|-----------|
| Scene, SceneShoot, ShootingDay, Character | SierraDB topic per category + UUIDv7 ID | `projection_scene`, etc. | PostgresProcessor per projection set |
| Photo | SierraDB on costume / scene_shoot streams | `projection_photo` | photo projector |
| AI imports | none (queue owned by infra) | `ai_import.job` | PG job table — no events |

#important[
  The projection table layout is intentionally flat and query-friendly. Do
  not denormalize back to aggregates for reads.
]

== CQRS Boundary Rule

A saga or aggregate must never resolve audit/derived context (e.g. a
`series_id`) by reading a projection. That context travels in the event data
and, when needed, is enriched at the API edge before dispatch. The one
permitted exception is the AI-import job worker: it performs deterministic
mapping lookups (preview draft → aggregate id) under explicit
`// ast-grep-ignore: cqrs-boundary` suppressions with justifications (issue
#148). This is mechanically enforced.

// TODO: describe scene_shoot and shooting_day aggregates in detail (level 3)
