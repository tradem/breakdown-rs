# ADR-003: Use PostgreSQL as Primary Database

**Status**: Accepted  
**Date**: 2024-01-16  
**Author**: Initial Architecture Decision

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

---

**Related ADRs**:
- [ADR-002: Use Event Sourcing and CQRS](./ADR-002-event-sourcing-cqrs.md)
- [ADR-004: Use UUIDv7 for all entities](./ADR-004-use-uuidv7.md)
