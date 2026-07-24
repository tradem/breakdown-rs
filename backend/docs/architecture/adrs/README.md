# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records (ADRs) for the Breakdown
RS project. ADRs document significant architectural decisions, their context,
and their consequences.

## How to use

- Read the relevant ADRs before making changes to the architecture.
- Follow the template in `templates/ADR-template.md` when proposing a new ADR.
- New ADRs are numbered sequentially (ADR-022, ADR-023, ...).
- Every ADR carries an **Author** field. Retrospective ADRs (ADR-001 … ADR-019)
  are attributed to `Tobias Rademacher (@tradem)`; ADR-020 and ADR-021 were
  co-authored with `GLM-5.2 (Zhipu, hosted by neuralwatt)`.


## List of ADRs

| ADR | Title | Status | Date | Author |
|-----|-------|--------|------|--------|
| [001](ADR-001-hexagonal-architecture.md) | Hexagonal Architecture | Accepted | 2026-06-16 | Tobias Rademacher (@tradem) |
| [002](ADR-002-event-sourcing-cqrs.md) | Use Event Sourcing and CQRS | Accepted | 2026-06-16 | Tobias Rademacher (@tradem) |
| [003](ADR-003-use-postgresql.md) | Use PostgreSQL as Primary Database | Superseded by ADR-015 | 2026-06-16 | Tobias Rademacher (@tradem) |
| [004](ADR-004-use-uuidv7.md) | Use UUIDv7 for all Entities and Events | Accepted | 2026-06-16 | Tobias Rademacher (@tradem) |
| [005](ADR-005-use-axum.md) | Use Axum as Web Framework | Accepted | 2026-06-16 | Tobias Rademacher (@tradem) |
| [006](ADR-006-utoipa-openapi-codegen.md) | Use utoipa for OpenAPI Specification and Frontend Code Generation | Proposed | 2026-06-17 | Tobias Rademacher (@tradem) |
| [007](ADR-007-frontend-technologies-and-api-communication.md) | Frontend Technologies and API Communication Strategy | Proposed | 2026-06-17 | Tobias Rademacher (@tradem) |
| [008](ADR-008-documentation-tooling-and-structure.md) | Documentation Tooling and Structure | Accepted | 2026-06-17 | Tobias Rademacher (@tradem) |
| [009](ADR-009-photo-storage-opendal-s3-api.md) | Photo Storage with OpenDAL and S3-Compatible API | Accepted | 2026-06-17 | Tobias Rademacher (@tradem) |
| [010](ADR-010-authentication-with-oidc.md) | Authentication with OpenID Connect (OIDC) | Accepted | 2026-06-17 | Tobias Rademacher (@tradem) |
| [011](ADR-011-observability-with-opentelemetry.md) | Observability with OpenTelemetry (Tracing & Logging) | Proposed | 2026-06-17 | Tobias Rademacher (@tradem) |
| [012](ADR-012-error-handling-thiserror-anyhow.md) | Error Handling with thiserror and anyhow in Axum | Accepted | 2026-06-17 | Tobias Rademacher (@tradem) |
| [013](ADR-013-hybrid-llm-script-parsing-architecture.md) | Hybrid Architecture for LLM-based Script Parsing | Proposed | 2026-06-17 | Tobias Rademacher (@tradem) |
| [014](ADR-014-testcontainers-integration-testing.md) | Testcontainers-based integration testing | Accepted | 2026-06-21 | Tobias Rademacher (@tradem) |
| [015](ADR-015-sierradb-event-store-postgres-projections.md) | SierraDB event store + PostgreSQL projections (CQRS split) | Accepted | 2026-06-23 | Tobias Rademacher (@tradem) |
| [016](ADR-016-sierradb-runtime-and-round-trip.md) | SierraDB runtime & round-trip (image path, dev/prod runtime, Tier-4 tests) | Accepted | 2026-06-26 | Tobias Rademacher (@tradem) |
| [017](ADR-017-architecture-testing-strategy.md) | Architecture Testing Strategy | Accepted | 2026-06-30 | Tobias Rademacher (@tradem) |
| [018](ADR-018-oidc-jwt-validation-and-dev-auth-toggle.md) | OIDC JWT Validation & Dev-Auth Toggle | Accepted | 2026-07-20 | Tobias Rademacher (@tradem) |
| [019](ADR-019-costume-photo-storage.md) | Costume Photo Storage — Aggregate, Garage, Proxy Serving, Derived Auth | Accepted | 2026-07-21 | Tobias Rademacher (@tradem) |
| [020](ADR-020-rust-component-versioning.md) | Rust Component Versioning & Release Mechanics | Proposed | 2026-07-21 | Tobias Rademacher (@tradem); GLM-5.2 (Zhipu, hosted by neuralwatt) |
| [021](ADR-021-api-versioning.md) | HTTP API Path Versioning & Deprecation Lifecycle | Proposed | 2026-07-21 | Tobias Rademacher (@tradem); GLM-5.2 (Zhipu, hosted by neuralwatt) |

## Creating a New ADR

1. Copy `templates/ADR-template.md` to `ADR-NNN-kebab-title.md` using the next
   free number.
2. Fill in the header (`Status`, `Date`, `Author`, and `Supersedes` /
   `Related` / `Source change` where applicable).
3. Write `Context`, `Decision`, `Consequences` (with `### Positive` and
   `### Negative` subsections), `Alternatives Considered`, and `Notes`.
4. Add a row to the table above.

## Tools

- [adr-tools](https://github.com/npryce/adr-tools) — CLI for managing ADRs.
- [adr-log](https://github.com/maroun-baydoun/adr-log) — generate an ADR index.

## Resources

- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
  by Michael Nygard.
- [ADR GitHub Organization](https://github.com/adr).
