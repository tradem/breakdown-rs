= Crosscutting Concepts

== Concepts Overview

#note[
  This chapter describes overarching principles and solutions that apply to multiple building blocks.
]

== Error Handling

=== Strategy

- *Domain Errors*: `Result<T, DomainError>` in core
- *HTTP Errors*: `Axum` extracts `Result` to proper HTTP status codes
- *Logging*: `tracing` crate for structured logging

=== Error Hierarchy

```rust
pub enum DomainError {
    NotFound(String),
    AlreadyExists(String),
    ValidationError(String),
    ConcurrencyConflict,
}
```

== Validation

=== Input Validation

- *API Layer*: `validator` crate or custom validators
- *Domain Layer*: Aggregates validate commands before emitting events
- *UUIDv7*: All IDs are validated for proper format

=== Invariants

- *Aggregate Invariants*: Enforced in aggregate `execute` method
- *Database Constraints*: Foreign keys, unique constraints
- *Event Ordering*: Sequence numbers ensure event ordering

== Security

=== Authentication

- *Future*: JWT or Session-based auth (not yet implemented)
- *CORS*: Configured in Axum

=== Authorization

- *Future*: Role-based access control (RBAC)
- *Aggregate Level*: Ownership checks in commands

== Logging and Tracing

=== Structured Logging

```rust
tracing::info!(
    aggregate = "SceneAggregate",
    scene_id = %scene_id,
    "Scene created"
);
```

=== Distributed Tracing

- *Future*: OpenTelemetry integration
- *Current*: `tracing-subscriber` with `RUST_LOG`

== Configuration

=== Environment-Based Config

- *Development*: `.env` file with `dotenv`
- *Production*: Environment variables
- *Secrets*: No secrets in code (gitleaks enforced)

// TODO: Add more crosscutting concepts
// TODO: Add concurrency and locking strategy
// TODO: Add caching strategy
