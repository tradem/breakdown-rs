// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Solution Strategy

== Overview

The system follows one overarching pattern: *event sourcing with CQRS,
delivered through a hexagonal workspace.* All state is derived from events;
commands validate in aggregates; read models are projections. Four concrete
decisions carry the most weight and shape everything else.

== Key Decisions

=== 1. Hexagonal Architecture

#adr-ref(num: "001", slug: "hexagonal-architecture", title: "Hexagonal Architecture")

- `crates/core` contains domain logic only — commands, events, aggregates,
  port traits, read-model DTOs. No `sqlx`, no `axum`, no infra imports.
- `crates/infra` implements all ports and owns persistence details.
- `crates/api` wires HTTP routes and middleware to ports and commands,
  acting as composition root.
- Enforced by `rust_arkitect` via `crates/architecture` (#adr-ref(num: "017", slug: "architecture-testing-strategy", title: "Architecture-Testing Strategy")).

=== 2. Event Sourcing with CQRS

#adr-ref(num: "002", slug: "event-sourcing-cqrs", title: "Event Sourcing and CQRS")

- *Write side*: commands → aggregate validation → events appended to SierraDB
  (#adr-ref(num: "015", slug: "sierradb-event-store-postgres-projections", title: "SierraDB EventStore"),
  #adr-ref(num: "016", slug: "sierradb-runtime-and-round-trip", title: "SierraDB Round-Trip")).
- *Read side*: projectors replay events into flat PostgreSQL projections;
  repositories read from them directly.
- *Guarantees*: write order is total per aggregate stream; projections are
  eventually consistent; idempotency and redelivery are designed for via
  version guards.
- *Hard rule*: the CQRS boundary never crosses upward — write-side
  sagas/adapters must not resolve audit or derived context by reading a
  projection. A narrow, documented exception exists for AI-import mapping
  lookups (`schedule_apply.rs` / `workers.rs`), which deterministically
  match preview drafts to aggregate ids and carry an explicit
  `// ast-grep-ignore: cqrs-boundary` suppression with justification. This
  is enforced by `ast-grep` CI rules (issue #148).

=== 3. UUIDv7 Identity

#adr-ref(num: "004", slug: "use-uuidv7", title: "Use UUIDv7")

- All entity and event IDs are UUIDv7 — time-ordered, index-friendly, no
  coordination needed.
- Applied uniformly: aggregates, projections, photos, jobs, report artifacts.

=== 4. Stateless, Auth-by-Group API

#adr-ref(num: "005", slug: "use-axum", title: "Use Axum"),
#adr-ref(num: "010", slug: "authentication-with-oidc", title: "Authentication with OIDC")

- Axum for HTTP; stateless handlers, shared state via extensions.
- OIDC JWT authentication (#adr-ref(num: "018", slug: "oidc-jwt-validation-and-dev-auth-toggle", title: "OIDC JWT Validation and Dev-Auth Toggle")) with dev-auth toggle for local runs without an IdP.
- API versioned — breaking changes get new routes (#adr-ref(num: "021", slug: "api-versioning", title: "HTTP API Path Versioning")).

== Command-Flow Summary

#diagram("command-processing-sequence", caption: [Command → event → projection round-trip])

== Additional Design Rules

| Rule                             | Enforcement |
|----------------------------------|-------------|
| Write side never queries projections | `ast-grep` rule `cqrs-boundary` in CI |
| No panics in prod adapters/sagas   | `clippy` lints deny `unwrap`/`expect`/`panic` |
| No string-interpolated SQL         | `ast-grep` rule `no-string-interpolation-sql` |
| No discarded fallible results      | `ast-grep` rule `discard-result` |
| Release reproducible from git tag   | `release-image.yml` + cargo-release (#adr-ref(num: "020", slug: "rust-component-versioning", title: "Rust Component Versioning")) |

== Views Referenced Later

- *Building blocks*: crates and bounded contexts (chapter 5)
- *Runtime flow*: sequence diagrams (chapter 6)
- *Deployment*: dev/prod infra (chapter 7)

// TODO: add risk/mitigation table for CQRS lag and event schema evolution
