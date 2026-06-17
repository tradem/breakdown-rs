= Runtime View

== Runtime Scenario: Create Scene

#note[
  This chapter describes how building blocks interact at runtime to fulfill scenarios.
]

=== Scenario Description

*Goal*: User creates a new scene in the breakdown.

=== Sequence Diagram

```mermaid
sequenceDiagram
    participant User
    participant API as Axum API
    participant Cmd as CreateScene Command
    participant Agg as SceneAggregate
    participant ES as Event Store
    participant Proj as SceneProjector
    participant DB as PostgreSQL

    User->>API: POST /api/scenes
    API->>Cmd: CreateScene { name, act, ... }
    Cmd->>Agg: execute(command, state)
    Agg->>Agg: validate (name unique?)
    Agg->>ES: append(SceneCreated event)
    ES->>Proj: publish event
    Proj->>DB: INSERT INTO scenes_projection
    API->>User: 201 Created { scene_id }
```

=== What to Observe

- *Command Validation*: Aggregate validates before emitting event
- *Event Persistence*: Event Store appends event (immutable)
- *Projection Update*: Projector updates read model asynchronously
- *Reply*: User gets scene_id (UUIDv7)

== Runtime Scenario: Query Scenes

=== Scenario Description

*Goal*: User views all scenes in a show.

=== Sequence Diagram

```mermaid
sequenceDiagram
    participant User
    participant API as Axum API
    participant Query as ListScenes Query
    participant DB as PostgreSQL

    User->>API: GET /api/shows/{id}/scenes
    API->>Query: execute(pool, show_id)
    Query->>DB: SELECT * FROM scenes_projection
    DB->>Query: Rows
    Query->>API: Vec<SceneDto>
    API->>User: 200 OK { scenes: [...] }
```

=== What to Observe

- *No Aggregate*: Query reads directly from projection
- *CQRS*: Read side is separated from write side
- *Performance*: Projection is optimized for this query

// TODO: Add more runtime scenarios
// TODO: Add error handling flows
// TODO: Add concurrency scenarios
