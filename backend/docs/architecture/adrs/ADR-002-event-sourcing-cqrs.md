# ADR-002: Use Event Sourcing and CQRS

**Status**: Accepted  
**Date**: 2026-06-16  
**Author**: Tobias Rademacher (@tradem)

---

## Context

Breakdown RS is a collaborative scheduling application where:
- **Historical data is important**: Need to know who changed what and when
- **Audit trail required**: Costume assignments, scene changes must be trackable
- **Concurrent edits**: Multiple users may edit the same resource
- **Complex domain logic**: Business rules depend on state transitions

Traditional CRUD with mutable state has limitations:
- Loses history (updates overwrite data)
- Hard to implement audit logs retroactively
- Concurrent modifications require complex locking
- Business logic mixed with persistence concerns

## Decision

We will use **Event Sourcing (ES)** for write model and **CQRS** (Command Query Responsibility Segregation) for read model.

### Write Side (Event Sourcing):
- **Commands**: Imperative actions (e.g., `CreateScene`, `AssignCostume`)
- **Aggregates**: State machines that validate commands and emit events
- **Events**: Past-tense facts (e.g., `SceneCreated`, `CostumeAssigned`)
- **Event Store**: Append-only log of all events

### Read Side (CQRS):
- **Queries**: Read-only DTOs from flattened PostgreSQL projections
- **Projectors**: Async handlers that update projections when events occur
- **Never query aggregates directly** for views

### Implementation:
- Use `kameo_es` for event-sourced actors (aggregates as actors)
- Each aggregate is a `kameo::Actor` implementing `kameo_es::Entity`
- Commands act as `kameo_es::Command`

## Example Flow

```
User → HTTP → Command → Aggregate → Event → EventStore
                            ↓
                       Event Handler → Projector → PostgreSQL (Projection)
                            ↓
User ← HTTP ← Query ← DTO from Projection
```

## Consequences

### Positive
- ✅ **Full audit trail**: Can reconstruct state at any point in time
- ✅ **Temporal queries**: "What did the schedule look like yesterday?"
- ✅ **Scalability**: Read side can be scaled independently
- ✅ **Complex business logic**: Aggregates enforce invariants naturally
- ✅ **Debugging**: Can replay events to reproduce bugs
- ✅ **Event-driven**: Natural integration with WebSockets/SSE for real-time updates

### Negative
- ⚠️ **Complexity**: More concepts to learn (events, projectors, eventual consistency)
- ⚠️ **Eventual consistency**: Read model may lag behind write model
- ⚠️ **Schema evolution**: Events must be versioned carefully
- ⚠️ **Storage growth**: Event store grows indefinitely (need snapshots)

### Mitigation
- Use snapshots for aggregates with many events
- Document event versioning strategy
- Monitor projection lag
- Provide "force refresh" option for critical read operations

## Alternatives Considered

1. **Traditional CRUD**: Simpler but no audit trail, harder to scale
2. **Event Sourcing without CQRS**: Possible but read performance suffers
3. **Only CQRS (without ES)**: Loses historical data and audit capabilities

## Event Storming Mapping

Following EventStorming methodology:
1. **Domain Event** (past tense) → `enum` in `core`
2. **Command** (imperative) → `struct` in `core`
3. **Aggregate** (noun) → State `struct` in `core`

## Notes

- See `AGENTS.md` for code examples with `kameo_es`
- Use UUIDv7 (not v4) for all entities and events
- Event handlers must be idempotent (can receive duplicates)
- Consider using [event-catalog](https://eventcatalog.dev/) for event documentation

---

**Related ADRs**:
- [ADR-001: Use Hexagonal Architecture](./ADR-001-hexagonal-architecture.md)
- [ADR-014: Integration Testing with Testcontainers for PostgreSQL](./ADR-014-testcontainers-integration-testing.md)
