# ADR-015: SierraDB as Event Store, PostgreSQL for Read-Model Projections

**Status**: Accepted  
**Date**: 2026-06-23  
**Author**: Architecture Revision  
**Supersedes**: [ADR-003: Use PostgreSQL as Primary Database](./ADR-003-use-postgresql.md)

---

## Context

ADR-003 was written under the assumption that a single PostgreSQL instance would
serve both the Event Store (write model) and the CQRS projections (read model).
During the implementation described in ADR-014 (Testcontainers integration tests)
we discovered that this assumption does **not** match the actual behaviour of our
chosen event-sourcing stack:

- **`kameo_es`** ([sierra-db/kameo_es](https://github.com/sierra-db/kameo_es),
  last commit 2026-02-25) is our event-sourcing library. It is built on top of
  the actor framework **`kameo`** ([tqwewe/kameo](https://github.com/tqwewe/kameo),
  actively maintained) and persists events in **SierraDB**.
- **SierraDB** ([sierra-db/sierradb](https://github.com/sierra-db/sierradb),
  v0.3.1, ~326★, actively developed, not archived) is a purpose-built,
  distributed, append-only event store. It speaks the **RESP3 protocol** — i.e.
  it is wire-compatible with Redis clients — but it is **not Redis**: it is a
  dedicated event store with a Cassandra/ScyllaDB-style distributed
  architecture (libp2p clustering, bucket/partition layout, segment files,
  gapless monotonic versions, CRC32C checksums) and custom commands such as
  `EAPPEND` / `ESCAN` / `ESUB` with optimistic concurrency (`EXPECTED_VERSION`).
- The `postgres` feature flag of `kameo_es` (enabled in our `Cargo.toml`) does
  **not** switch the event store to PostgreSQL. It only enables the
  **`PostgresProcessor`** projection backend, i.e. the read-model / event-handler
  side. The event store itself is bound to SierraDB via a `redis::Client`
  connection (`redis://…:9090/`); there is no PostgreSQL code path on the write
  side.

Consequently the architecture now has **two dedicated persistence tiers** instead
of one, and ADR-003's single-database premise no longer holds. This ADR codifies
the real split and re-evaluates the choice of store for the projection tier
(see *Alternatives Considered* — MongoDB vs. PostgreSQL).

## Decision

1. **Event Store (write model): SierraDB**, accessed through `kameo_es` over the
   RESP3/Redis client protocol. No Redis server is deployed; SierraDB is the
   server. Connection example: `redis://127.0.0.1:9090/`.
2. **Read-Model Projections (read model): PostgreSQL**, populated by
   `kameo_es`' `PostgresProcessor` (event-handler backend). `sqlx` with
   compile-time-checked queries and `sqlx migrate` remain the tooling of choice
   (as in ADR-003's *Notes*).
3. **No cross-tier transactions.** Event append (SierraDB) and projection update
   (Postgres) are decoupled and eventually consistent. Idempotency of projectors
   is mandatory (events may be delivered more than once); the projection's
   `ON CONFLICT (id) DO UPDATE` upsert pattern plus a checkpoint per handler
   provides at-least-once + idempotent semantics.

### Why SierraDB for the event store?

We did not choose SierraDB directly — it is mandated by `kameo_es`, which is in
turn mandated by ADR-002 (event sourcing + CQRS) and the AGENTS.md `kameo_es`
aggregate pattern. Re-evaluation of the event store is therefore tied to a
re-evaluation of `kameo_es` itself, which is out of scope here. The properties we
gain (and accept) with SierraDB:

- ✅ Purpose-built append-only store with optimistic concurrency and gapless
  ordering guarantees per stream.
- ✅ Real-time subscriptions (`ESUB`) with seamless historical→live transition —
  ideal for projector catch-up.
- ✅ Distributed, horizontally scalable, replication factor configurable; can
  start single-node and grow.
- ✅ Wire-compatible with the mature Rust `redis` client — no bespoke driver to
  maintain.

## Consequences

### Positive
- ✅ **Separation of concerns**: each tier is specialised for its workload
  (append-only log vs. relational query views).
- ✅ **Independent scaling**: event-store write throughput and read-model query
  load no longer compete for the same database resources (ADR-003 risk
  „Event store and read models compete for resources" is resolved by design).
- ✅ **PostgreSQL kept for its strengths**: relational scheduling queries, range
  overlap / conflict detection, FK integrity, `sqlx` compile-time checks.
- ✅ **SierraDB subscriptions** give a clean streaming path for projectors
  without `LISTEN/NOTIFY` polling hacks.

### Negative
- ⚠️ **Two databases to operate** (SierraDB + Postgres) instead of one —
  backup, monitoring, version pinning, and migrations across both tiers. This
  is the inverse of ADR-003's „single database" benefit.
- ⚠️ **Operational maturity risk**: SierraDB is young (v0.3.x, ~326★) compared
  to PostgreSQL; pin to a tested version and keep disaster-recovery drills on
  the backlog.
- ⚠️ **Eventually consistent read model**: projections may lag the event store;
  clients must tolerate staleness or trigger forced refresh (see ADR-002
  mitigation).
- ⚠️ **No transactional projection update**: a projector crash between append
  and projection update is recoverable only via idempotent replay from the
  checkpoint — not via a single DB transaction as ADR-003 assumed.
- ⚠️ **RESP3 ≠ Redis**: tooling/monitoring that assumes real Redis semantics
  (e.g. `EXPIRE`, arbitrary keyspace) will not behave as expected against
  SierraDB; only event-stream commands (`EAPPEND`/`ESCAN`/`ESUB`/…) are
  meaningful.

### Mitigation
- Track the `kameo_es` and `sierradb` upstream versions in `Cargo.toml` (git
  dependency); run the SierraDB image with a pinned tag in production.
- Per-projector `last_checkpoint` stored in Postgres; idempotent upserts make
  replay safe.
- Health checks for *both* tiers in the observability stack (ADR-011).
- Integration tests (ADR-014) cover the SierraDB-backed round-trip once a
  sierradb testcontainer is available; the harness is already structured for it.

## Alternatives Considered

### 1. Redis instead of SierraDB (real Redis server, RESP3-compatible)
**Rejected.** `kameo_es` talks RESP3 to *a* server, but its event API
(`EAPPEND`/`ESCAN`/…, partitioned segments, expected-version semantics) is
SierraDB-specific. Plain Redis does not implement these commands and would not
satisfy the contract. We would have to fork `kameo_es` to target a Redis backend
— not worth the divergence.

### 2. Fork `kameo_es` to use a PostgreSQL event store
**Rejected for now.** Restores the ADR-003 single-database ideal (Postgres only),
but throws away SierraDB's purpose-built features (segmented append, real-time
subscriptions, distributed clustering) and forces us to maintain a fork of an
upstream dependency. Revisit only if SierraDB maturity or licensing becomes
blocking.

### 3. PostgreSQL for projections vs. MongoDB for projections
This is the question ADR-003 never explicitly answered, because back then
Postgres was assumed to be “the database". With the write side now on SierraDB,
the read side is free to choose independently. Re-evaluation:

| Criterion | PostgreSQL (chosen) | MongoDB (alternative) |
|---|---|---|
| Upsert idiom | `INSERT … ON CONFLICT (id) DO UPDATE` — atomic, idempotent, row-locked | `updateOne(filter, doc, {upsert:true})` — atomic per doc |
| Scheduling / conflict queries | **Strength**: `OVERLAPS`, GiST range exclusion, joins (scene↔costume↔production), CTEs | Aggregation pipeline / `$lookup`; weaker for multi-hop joins, conflict detection needs heavy denormalisation |
| Referential integrity | Foreign keys + `sqlx` compile-time checks | None; consistency only app-enforced |
| Schema evolution | `sqlx migrate`, typed DTOs | Schemaless — flexible but risk of untyped reads |
| Consistency | ACID by default | Multi-doc transactions available but costlier |
| `kameo_es` backend | `PostgresProcessor` ✅ | `mongodb` feature ✅ — both first-class |
| Ops footprint | SierraDB + Postgres | SierraDB + Mongo (Postgres removed) |

**Decision: stay on PostgreSQL for projections.** The operational appeal of
dropping Postgres entirely (SierraDB + Mongo only) is marginal, because the
core domain value of Breakdown RS — schedule conflicts, date overlaps,
referential relations between scenes / costumes / productions — is exactly
PostgreSQL's home turf and MongoDB's weak spot. Mongo's upsert ergonomics are
already matched by Postgres `ON CONFLICT`. We revisit only if projections become
highly schema-volatile **and** the dominant query shape shifts from
relational-set to key-lookup — neither is expected for a scheduling tool.

## Notes

- This ADR **supersedes** [ADR-003](./ADR-003-use-postgresql.md); ADR-003 is kept
  unchanged for history, marked `Superseded`.
- The `postgres` feature in `Cargo.toml` (`kameo_es = { git = …, features =
  ["postgres"] }`) is correct as-is — it activates the projection backend, not an
  event-store backend. No feature change required.
- ADR-014 notes that the SierraDB-backed `command → event → sierradb → projector
  → Postgres projection` round-trip is deferred to a follow-up branch; that
  remains valid and this ADR does not block it.
- When a `sierradb` testcontainer image becomes available, extend the
  integration-test harness in `crates/integration-tests` rather than adding a
  second harness.

---

**Related ADRs**:
- [ADR-002: Use Event Sourcing and CQRS](./ADR-002-event-sourcing-cqrs.md)
- [ADR-003: Use PostgreSQL as Primary Database](./ADR-003-use-postgresql.md) (superseded)
- [ADR-004: Use UUIDv7 for all entities](./ADR-004-use-uuidv7.md)
- [ADR-011: Observability with OpenTelemetry](./ADR-011-observability-with-opentelemetry.md)
- [ADR-014: Integration Testing with Testcontainers](./ADR-014-testcontainers-integration-testing.md)
