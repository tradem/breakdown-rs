= Architecture Decisions

== Decision Overview

#note[
  This chapter lists and links to all Architecture Decision Records (ADRs).
]

== ADR Index

| ID | Title | Status | Date |
|----|-------|--------|------|
| #link("../adrs/ADR-001-hexagonal-architecture.md")[001] | Hexagonal Architecture | Accepted | 2024-01-16 |
| #link("../adrs/ADR-002-event-sourcing-cqrs.md")[002] | Event Sourcing and CQRS | Accepted | 2024-01-16 |
| #link("../adrs/ADR-003-use-postgresql.md")[003] | Use PostgreSQL | Accepted | 2024-01-16 |
| #link("../adrs/ADR-004-use-uuidv7.md")[004] | Use UUIDv7 | Accepted | 2024-01-16 |
| #link("../adrs/ADR-005-use-axum.md")[005] | Use Axum | Accepted | 2024-01-16 |
| #link("../adrs/ADR-006-utoipa-openapi-codegen.md")[006] | utoipa OpenAPI Codegen | Accepted | 2024-01-16 |
| #link("../adrs/ADR-007-frontend-technologies-and-api-communication.md")[007] | Frontend Technologies | Accepted | 2024-01-16 |
| #link("../adrs/ADR-008-documentation-tooling-and-structure.md")[008] | Documentation Tooling | Accepted | 2024-06-17 |

== Decision Context

=== How Decisions Are Made

1. *Proposal*: Create ADR in `proposed` state
2. *Review*: Team reviews and discusses
3. *Decision*: Accept, reject, or request changes
4. *Document*: Update status and merge

=== Decision Log Location

All ADRs are stored in: `docs/architecture/adrs/`

Format: Markdown (not Typst) for better GitHub rendering

== Key Decisions Summary

=== Architectural Style

- *Pattern*: Hexagonal Architecture (Ports and Adapters)
- *Data Flow*: Event Sourcing with CQRS

=== Technology Stack

- *Language*: Rust (Edition 2021)
- *Web*: Axum
- *Database*: PostgreSQL
- *Actor Framework*: kameo

=== Documentation

- *ADRs*: Markdown
- *arc42*: Typst (this document)
- *API*: OpenAPI (utoipa)

// TODO: Add decision matrix or decision trees
// TODO: Add deprecated or superseded decisions
// TODO: Add decision impact analysis
