= Solution Strategy

== Overview

#important[
  This chapter describes the fundamental decisions and their rationale that shape the system's architecture.
]

== Key Decisions

=== 1. Hexagonal Architecture

*Decision*: Use Ports and Adapters pattern (see #adr-ref(num: 1, title: "Use Hexagonal Architecture")[ADR-001])

*Rationale*:
- Testability: Domain logic independent of infrastructure
- Flexibility: Swap adapters without changing core
- Clarity: Clear boundaries between layers

=== 2. Event Sourcing and CQRS

*Decision*: All state changes via Events (see #adr-ref(num: 2, title: "Use Event Sourcing and CQRS")[ADR-002])

*Rationale*:
- Audit trail: Full history of all changes
- CQRS: Optimized read models for queries
- Scalability: Event playback for new projections

=== 3. UUIDv7 for IDs

*Decision*: Use UUIDv7 for all entities (see #adr-ref(num: 4, title: "Use UUIDv7")[ADR-004])

*Rationale*:
- Time-ordered: Better index performance
- Distributed: No central ID generation
- Standard: UUID standard (no custom formats)

=== 4. Technology Stack

| Layer | Technology | ADR |
|-------|------------|-----|
| Web Framework | Axum | #adr-ref(num: 5, title: "Use Axum")[ADR-005] |
| Actor Framework | kameo/kameo_es | - |
| Database | PostgreSQL | #adr-ref(num: 3, title: "Use PostgreSQL")[ADR-003] |
| API Documentation | utoipa | #adr-ref(num: 6, title: "Use utoipa OpenAPI")[ADR-006] |

== Views

=== Runtime View (Summary)

```mermaid
sequenceDiagram
    participant U as User
    participant A as Axum API
    participant C as Command
    participant Agg as Aggregate
    participant ES as Event Store
    participant P as Projector
    participant DB as Projection

    U->>A: HTTP Request
    A->>C: Create Command
    C->>Agg: Execute Command
    Agg->>Agg: Validate & Emit Event
    Agg->>ES: Persist Event
    ES->>P: Event Published
    P->>DB: Update Projection
    A->>U: HTTP Response
```

// TODO: Add more details on each decision
// TODO: Add risks and mitigations
// TODO: Add technology evaluation summary
