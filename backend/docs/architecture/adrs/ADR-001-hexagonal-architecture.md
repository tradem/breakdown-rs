# ADR-001: Hexagonal Architecture

**Status**: Accepted
**Date**: 2026-06-16
**Author**: Tobias Rademacher (@tradem)
**Related**: ADR-017 (Architecture Testing Strategy)

---

## Context

Breakdown RS needs a clear architectural boundary between domain logic and
infrastructure to remain maintainable, testable, and adaptable to different
deployment targets. A hexagonal (ports & adapters) architecture provides these
properties by inverting dependencies: domain logic in the centre, driven by
abstract ports, with concrete adapters on the outside.

## Decision

Adopt a three-crate workspace structure with strict dependency direction:

### Crate layout

| Crate | Role | May depend on |
|---|---|---|
| `crates/core` | Domain model, event-sourcing logic, port traits | Nothing outside workspace |
| `crates/api` | Axum HTTP server, request/response translation | `core` |
| `crates/infra` | Infrastructure implementations (PostgreSQL, event store) | `core`, `api` (types only) |
| `crates/architecture` | Architecture tests (see ADR-017) | `core`, `api`, `infra` (test-only) |

### Rules

1. **`crates/core` must not depend on `crates/api` or `crates/infra`.**
   It must not import `sqlx`, `axum`, `redis`, or any other infrastructure
   crate. It defines ports (traits) that outer layers implement.

2. **`crates/api`** translates HTTP requests into core Commands (write side)
   and reads from Postgres projections via infra repository implementations
   (read side).

3. **`crates/infra`** provides concrete implementations of the port traits
   defined in core. It may depend on `core` for types and traits.

### Enforcement

Architecture tests in `crates/architecture` enforce the rules using
`rust_arkitect` and `cargo-deny` (see ADR-017). These tests run in CI and
locally via `cargo test -p architecture_tests` and `cargo deny check bans`.

## Alternatives Considered

- **Single crate with feature flags:** Would not enforce compile-time
  boundaries between domain and infrastructure.
- **Separate workspace with published core crate:** Overkill for the current
  scale; path-based dependencies are sufficient.

## Consequences

**Positive:**

- Clear dependency direction: outer layers depend on inner layers, never the
  reverse.
- Domain logic remains free of infrastructure concerns, making it testable
  without Docker or a database.
- Port traits in core allow swapping implementations (e.g., in-memory vs.
  Postgres) without changing domain code.

**Negative:**

- More boilerplate due to port trait definitions.
- Requires discipline to keep infrastructure dependencies out of core —
  automated by architecture tests (ADR-017).
