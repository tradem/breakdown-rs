# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records for the Breakdown RS project.

## What are ADRs?

ADRs are short documents that capture important architectural decisions made along with their context and consequences.

## Format

Each ADR follows this format:
- **Title**: Short present tense description
- **Status**: Proposed | Accepted | Deprecated | Superseded
- **Context**: What is the issue we're facing?
- **Decision**: What have we decided to do?
- **Consequences**: What becomes easier or more difficult?

## List of ADRs

| ID | Title | Status | Date |
|----|-------|--------|------|
| [001](./ADR-001-hexagonal-architecture.md) | Use Hexagonal Architecture | Accepted | 2026-06-16 |
| [002](./ADR-002-event-sourcing-cqrs.md) | Use Event Sourcing and CQRS | Accepted | 2026-06-16 |
| [003](./ADR-003-use-postgresql.md) | Use PostgreSQL as Primary Database | Superseded by ADR-015 | 2026-06-16 |
| [004](./ADR-004-use-uuidv7.md) | Use UUIDv7 for all Entities | Accepted | 2026-06-16 |
| [005](./ADR-005-use-axum.md) | Use Axum as Web Framework | Accepted | 2026-06-16 |
| [006](./ADR-006-utoipa-openapi-codegen.md) | Use utoipa for OpenAPI Codegen | Accepted | 2026-06-16 |
| [007](./ADR-007-frontend-technologies-and-api-communication.md) | Frontend Technologies and API Communication | Accepted | 2026-06-16 |
| [008](./ADR-008-documentation-tooling-and-structure.md) | Documentation Tooling and Structure | Accepted | 2026-06-17 |
| [009](./ADR-009-photo-storage-opendal-s3-api.md) | Photo Storage with OpenDAL and S3-Compatible API | Accepted | 2026-06-17 |
| [010](./ADR-010-authentication-with-oidc.md) | Authentication with OpenID Connect (OIDC) | Accepted | 2024-06-17 |
| [011](./ADR-011-observability-with-opentelemetry.md) | Observability with OpenTelemetry (Tracing & Logging) | Proposed | 2026-06-17 |
| [012](./ADR-012-error-handling-thiserror-anyhow.md) | Error Handling with thiserror and anyhow in Axum | Accepted | 2026-06-17 |
| [013](./ADR-013-hybrid-llm-script-parsing-architecture.md) | Hybrid Architecture for LLM-based Script Parsing | Proposed | 2026-06-17 |
| [014](./ADR-014-testcontainers-integration-testing.md) | Integration Testing with Testcontainers for PostgreSQL | Accepted | 2026-06-21 |
| [015](./ADR-015-sierradb-event-store-postgres-projections.md) | SierraDB as Event Store, PostgreSQL for Read-Model Projections | Accepted | 2026-06-23 |

## Creating a New ADR

Use the template in `templates/ADR-template.md`:

```bash
cp templates/ADR-template.md adrs/ADR-$(printf "%03d" $(ls -1 adrs/ADR-*.md | wc -l | xargs -I {} expr {} + 1))-your-title.md
```

Or manually:
1. Copy `templates/ADR-template.md`
2. Name it `ADR-XXX-short-title.md` (use next available number)
3. Fill in the sections
4. Update this README with the new ADR

## Tools

- [adr-tools](https://github.com/npryce/adr-tools) - CLI tool for managing ADRs
- [adr-log](https://github.com/maroun-baydoun/adr-log) - Generate ADR index

## Resources

- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) by Michael Nygard
- [ADR GitHub Organization](https://github.com/adr)
