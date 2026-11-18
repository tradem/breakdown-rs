// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Architecture Decisions

#note[
  This chapter indexes all Architecture Decision Records (ADRs) for the
  monorepo. Full ADR texts live in `backend/docs/architecture/adrs/` as
  versioned Markdown files.
]

== Decision Lifecycle

+ *Proposal*: an author writes `ADR-NNN-kebab-title.md` with status `Proposed`.
+ *Review*: maintainers discuss context, trade-offs, and OpenSpec alignment.
+ *Decision*: maintainers mark the ADR `Accepted`, `Rejected`, or `Superseded`.
+ *Traceability*: superseded ADRs stay in the repository and link to their replacement.

== ADR Index (ADR-001 to ADR-040)

#table(
  columns: 3,
  table.header([ID], [Title], [Status]),
  [#link("../adrs/ADR-001-hexagonal-architecture.md")[001]], [Hexagonal Architecture], [Accepted],
  [#link("../adrs/ADR-002-event-sourcing-cqrs.md")[002]], [Event Sourcing and CQRS], [Accepted],
  [#link("../adrs/ADR-003-use-postgresql.md")[003]], [Use PostgreSQL as Primary Database], [Superseded by 015],
  [#link("../adrs/ADR-004-use-uuidv7.md")[004]], [Use UUIDv7 for All Entities and Events], [Accepted],
  [#link("../adrs/ADR-005-use-axum.md")[005]], [Use Axum as Web Framework], [Accepted],
  [#link("../adrs/ADR-006-utoipa-openapi-codegen.md")[006]], [OpenAPI Specification and Codegen with utoipa], [Proposed],
  [#link("../adrs/ADR-007-frontend-technologies-and-api-communication.md")[007]], [Frontend Technologies and API Strategy], [Proposed],
  [#link("../adrs/ADR-008-documentation-tooling-and-structure.md")[008]], [Documentation Tooling and Structure], [Accepted],
  [#link("../adrs/ADR-009-photo-storage-opendal-s3-api.md")[009]], [Photo Storage with OpenDAL and S3 API], [Accepted],
  [#link("../adrs/ADR-010-authentication-with-oidc.md")[010]], [Authentication with OpenID Connect (OIDC)], [Accepted],
  [#link("../adrs/ADR-011-observability-with-opentelemetry.md")[011]], [Observability with OpenTelemetry], [Proposed],
  [#link("../adrs/ADR-012-error-handling-thiserror-anyhow.md")[012]], [Error Handling with thiserror and anyhow], [Accepted],
  [#link("../adrs/ADR-013-hybrid-llm-script-parsing-architecture.md")[013]], [Hybrid LLM Script Parsing Architecture], [Accepted],
  [#link("../adrs/ADR-014-testcontainers-integration-testing.md")[014]], [Testcontainers Integration Testing], [Accepted],
  [#link("../adrs/ADR-015-sierradb-event-store-postgres-projections.md")[015]], [SierraDB Event Store and PostgreSQL Projections], [Accepted],
  [#link("../adrs/ADR-016-sierradb-runtime-and-round-trip.md")[016]], [SierraDB Runtime and Tier-4 Round-Trip], [Accepted],
  [#link("../adrs/ADR-017-architecture-testing-strategy.md")[017]], [Architecture Testing Strategy], [Accepted],
  [#link("../adrs/ADR-018-oidc-jwt-validation-and-dev-auth-toggle.md")[018]], [OIDC JWT Validation and Dev-Auth Toggle], [Accepted],
  [#link("../adrs/ADR-019-costume-photo-storage.md")[019]], [Costume Photo Storage, Garage, and Derived Auth], [Accepted],
  [#link("../adrs/ADR-020-rust-component-versioning.md")[020]], [Rust Component Versioning and Release Mechanics], [Accepted],
  [#link("../adrs/ADR-021-api-versioning.md")[021]], [HTTP API Path Versioning and Deprecation], [Accepted],
  [#link("../adrs/ADR-022-pdf-reporting-and-archival.md")[022]], [In-Process Typst PDF Reporting and Archival], [Proposed],
  [#link("../adrs/ADR-023-database-encryption-at-rest.md")[023]], [Database Encryption at Rest], [Proposed],
  [#link("../adrs/ADR-024-database-encryption-in-transit.md")[024]], [Database Encryption in Transit (TLS)], [Proposed],
  [#link("../adrs/ADR-025-https-edge-and-cert-rotation.md")[025]], [HTTPS Edge Transport and Certificate Rotation], [Proposed],
  [#link("../adrs/ADR-026-arch-linux-vps-hardening-baseline.md")[026]], [Arch Linux VPS Hardening Baseline], [Proposed],
  [#link("../adrs/ADR-027-secrets-vault-for-external-credentials.md")[027]], [Secrets Vault for External Credentials], [Proposed],
  [#link("../adrs/ADR-028-settings-aggregates-access-control.md")[028]], [Settings Aggregates Access Control], [Proposed],
  [#link("../adrs/ADR-029-gdpr-right-to-erasure-append-only-log.md")[029]], [GDPR Right to Erasure in an Append-Only Log], [Proposed],
  [#link("../adrs/ADR-030-ai-import-bounded-context.md")[030]], [AI Import Bounded Context], [Accepted],
  [#link("../adrs/ADR-031-http-error-surface.md")[031]], [HTTP Error Surface (RFC 9457, Codes, i18n)], [Accepted],
  [#link("../adrs/ADR-032-flutter-client-tls-pinning-rotation.md")[032]], [Flutter Client TLS Certificate Pinning], [Proposed],
  [#link("../adrs/ADR-033-flutter-client-versioning.md")[033]], [Flutter Client Versioning and Release Mechanics], [Accepted],
  [#link("../adrs/ADR-034-flutter-app-localization-gen-l10n.md")[034]], [Flutter App Localization with gen-l10n], [Accepted],
  [#link("../adrs/ADR-035-production-kind-flexible-hierarchy.md")[035]], [Production-Kind-Flexible Hierarchy (`Project`)], [Accepted],
  [#link("../adrs/ADR-036-es-native-reservation-streams-cross-aggregate-uniqueness.md")[036]], [ES-Native Reservation Streams for Uniqueness], [Accepted],
  [#link("../adrs/ADR-037-sceneshoot-provenance-pair-join-derivation.md")[037]], [SceneShoot AI Provenance from Pair Join], [Accepted],
  [#link("../adrs/ADR-038-ai-import-sse-progress-and-event-hub.md")[038]], [AI Import SSE Progress and Event Hub], [Proposed],
  [#link("../adrs/ADR-039-target-less-ai-import-declared-season-and-set-once-attach.md")[039]], [Target-Less AI Import and Set-Once Attach], [Proposed],
  [#link("../adrs/ADR-040-jiff-replaces-chrono.md")[040]], [`jiff` Replaces `chrono` as Time Library], [Accepted],
)
