= System Scope and Context

== Business Context

#note[
  This chapter describes the system's environment and its external interfaces.
]

=== Business Process

```mermaid
flowchart LR
    A[Production Manager] -->|Creates Show| B[Breakdown RS]
    C[Costume Designer] -->|Designs Costumes| B
    D[Wardrobe Supervisor] -->|Manages Fittings| B
    B -->|Generates Reports| E[PDF Export]
```

=== System Responsibilities

| Responsibility | Description |
|---------------|-------------|
| Costume Management | Create, update, track costumes |
| Scene Management | Organize scenes and costume changes |
| Continuity Tracking | Ensure costume consistency across scenes |
| Collaboration | Real-time multi-user editing |
| Reporting | Generate breakdown sheets and reports |

== Technical Context

=== System Interfaces

```mermaid
flowchart TB
    subgraph "Breakdown RS"
        API[Axum HTTP API]
        CORE[Domain Core]
        ES[Event Store]
        PROJ[Projections]
    end

    UI[Web Frontend] -->|HTTPS/JSON| API
    API -->|Commands| CORE
    CORE -->|Events| ES
    ES -->|Projectors| PROJ
    PROJ -->|Queries| API
    API -->|JSON| UI
```

=== External Systems

| System | Interface | Protocol |
|--------|-----------|----------|
| Web Browser | REST API | HTTPS/JSON |
| PostgreSQL | Event Store | TCP/5432 |
| Future: Mobile App | REST API | HTTPS/JSON |

// TODO: Add more detailed context diagrams
// TODO: Describe data formats in detail
// TODO: Add security context diagram
