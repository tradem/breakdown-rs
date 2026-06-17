= Building Block View

== Whitebox Overall System

#note[
  This chapter describes the static decomposition of the system into building blocks (modules, components, subsystems).
]

=== Workspace Structure

```mermaid
flowchart TB
    subgraph "breakdown-rs Workspace"
        CORE[crates/core<br/>Domain Logic]
        INFRA[crates/infra<br/>Infrastructure]
        API[crates/api<br/>HTTP API]
        ARCH[crates/architecture<br/>Architecture Tests]
    end

    API -->|uses| CORE
    INFRA -->|implements ports| CORE
    ARCH -->|tests| CORE
    ARCH -->|tests| INFRA
    ARCH -->|tests| API
```

=== Crate Responsibilities

| Crate | Responsibility | Dependencies |
|-------|---------------|--------------|
| `core` | Domain logic, Commands, Events, Aggregates, Ports | None (pure) |
| `infra` | Event Store, Projectors, SQLx queries | `core`, `sqlx`, `kameo_es` |
| `api` | HTTP routes, handlers, OpenAPI | `core`, `infra`, `axum`, `utoipa` |
| `architecture` | ArchUnit tests | `core`, `infra`, `api`, `arch_test` |

== Level 2: Core Crate

=== Whitebox `crates/core`

```mermaid
flowchart LR
    subgraph "core"
        CMD[commands.rs]
        EVT[events.rs]
        AGG[aggregates/]
        PORTS[ports.rs]
        DTO[read_models.rs]
    end
```

=== Key Building Blocks

| Block | Responsibility |
|-------|---------------|
| `commands` | Command structs (imperative) |
| `events` | Event enums (past tense) |
| `aggregates` | Event-sourced actors (kameo) |
| `ports` | Trait definitions for external dependencies |
| `read_models` | DTOs for query responses |

== Level 3: Aggregates

(To be expanded with specific aggregates: Scene, Costume, Actor, etc.)

// TODO: Add detailed building block descriptions
// TODO: Add interfaces and dependencies
// TODO: Add sequence diagrams for key collaborations
