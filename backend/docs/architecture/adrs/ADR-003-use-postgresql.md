# ADR-003: Use PostgreSQL as Primary Database

**Status**: Superseded by [ADR-015](./ADR-015-sierradb-event-store-postgres-projections.md)  
**Date**: 2026-06-16  
**Superseded**: 2026-06-23 by ADR-015  
**Author**: Tobias Rademacher (@tradem)

> **Supersession notice (2026-06-23).** This ADR was accepted under the incorrect
> assumption that PostgreSQL would serve as the *single* database for both the
> Event Store and the CQRS read-model projections. Subsequent implementation
> (see ADR-014 integration-test discovery) revealed that the chosen event-sourcing
> library `kameo_es` persists events exclusively in **SierraDB** (RESP3/Redis-
> protocol but not Redis), while PostgreSQL is used only for the
> projection/read-model side. The decision is therefore revised in
> [ADR-015](./ADR-015-sierradb-event-store-postgres-projections.md), which keeps
> PostgreSQL for projections (re-evaluated against MongoDB) and documents SierraDB
> as the event store. This document is retained unchanged for history.

---

## Context

Breakdown RS requires a database that supports:
- **Event Sourcing**: Append-only event store with high write throughput
- **CQRS Read Models**: Flattened projections for fast queries
- **ACID Compliance**: Strong consistency for financial/costume data
- **Complex Queries**: Costume scheduling involves date ranges, assignments, conflicts
- **Relational Integrity**: Foreign keys between projections (scenes → costumes)

Alternatives considered:
- NoSQL databases (MongoDB, Cassandra) - eventually consistent, less suitable for relational queries
- In-memory event store (EventStoreDB) - separate system to maintain
- SQLite - not suitable for production/concurrent access

## Decision

We will use **PostgreSQL** as the single database for both:
1. **Event Store** (write model)
2. **Projections** (read model / CQRS views)

### Why PostgreSQL?

- ✅ **JSONB Support**: Store events as JSONB for flexibility
- ✅ **ACID**: Strong consistency for financial/costume data
- ✅ **Mature Ecosystem**: `sqlx`, great tooling, managed services available
- ✅ **Single Database**: Simpler operations (backup, migration, monitoring)
- ✅ **Extensions**: `pgcrypto` for UUIDv7, `ltree` for hierarchies if needed

### Event Store Schema (planned)

```sql
CREATE TABLE events (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_id UUID NOT NULL,
    aggregate_type VARCHAR(255) NOT NULL,
    sequence_number BIGINT NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(aggregate_id, sequence_number)
);

CREATE INDEX idx_events_aggregate ON events(aggregate_id, sequence_number);
```

### Projection Schema (example)

```sql
CREATE TABLE projection_scenes (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    production_id UUID NOT NULL,
    status VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
```

## Consequences

### Positive
- ✅ **Operational Simplicity**: One database to backup, monitor, scale
- ✅ **Strong Consistency**: Read models updated transactionally (can use same DB transaction)
- ✅ **Rich Queries**: SQL for complex scheduling queries (date overlaps, conflicts)
- ✅ **Cost**: PostgreSQL is free, managed services available (Supabase, Neon, etc.)
- ✅ **Ecosystem**: `sqlx` crate excellent for Rust, migrations with `sqlx-cli`

### Negative
- ⚠️ **Event Store Not Specialized**: Unlike EventStoreDB, no built-in projections, subscriptions
- ⚠️ **Scaling**: Event store and read models compete for resources (can partition later)
- ⚠️ **JSONB Query Performance**: Complex event queries may be slower than specialized stores

### Mitigation
- Use `NOTIFY/LISTEN` for real-time projections (or polling with `last_processed_event_id`)
- Add read replicas for heavy read workloads
- Consider separating event store if write throughput becomes bottleneck

## Alternatives Considered

1. **EventStoreDB**: Purpose-built for event sourcing, but separate system to maintain
2. **MongoDB**: Flexible schema, but eventually consistent, weaker relational queries
3. **MySQL/MariaDB**: Less JSON support, fewer extensions
4. **Separate Databases**: Event store (EventStoreDB) + Read models (PostgreSQL) - more operational complexity

## Notes

- Use `sqlx` with compile-time checked queries
- Run migrations with `sqlx migrate` 
- Consider `pgcrypto` extension for UUIDv7 generation (see ADR-004)
- For production: Use connection pooling (`deadpool-postgres` or `sqlx-pool`)

### Implementation note (discovered during ADR-014 / Testcontainers work)

During the implementation of the integration-test harness for ADR-014, we discovered that the current `kameo_es` dependency does **not** use PostgreSQL as the event-store backend. Instead, `kameo_es` persists events in **sierradb**, which reuses the Redis client protocol but is a separate event-store implementation. The `postgres` feature of `kameo_es` is used only for the projection/event-handler side (`PostgresProcessor`), i.e. for building read models from the event stream.

As a result, PostgreSQL in this architecture is the store for **projections / read models only**, while the **event store itself lives in sierradb**. This ADR should be fully revised in the follow-up implementation branch to reflect that split; for now, this note captures the discovered state.

---

**Related ADRs**:
- [ADR-002: Use Event Sourcing and CQRS](./ADR-002-event-sourcing-cqrs.md)
- [ADR-004: Use UUIDv7 for all entities](./ADR-004-use-uuidv7.md)
- [ADR-014: Integration Testing with Testcontainers for PostgreSQL](./ADR-014-testcontainers-integration-testing.md)
