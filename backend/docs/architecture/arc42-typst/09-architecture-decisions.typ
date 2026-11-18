// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Architecture Decisions

#note[
  This chapter indexes all Architecture Decision Records (ADRs) for the
  monorepo. Every ID link points to the Markdown ADR file on GitHub for the
  git revision used to build this document.
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
  [#adr-id("001", "hexagonal-architecture")], [Hexagonal Architecture], [Accepted],
  [#adr-id("002", "event-sourcing-cqrs")], [Event Sourcing and CQRS], [Accepted],
  [#adr-id("003", "use-postgresql")], [Use PostgreSQL as Primary Database], [Superseded by 015],
  [#adr-id("004", "use-uuidv7")], [Use UUIDv7 for All Entities and Events], [Accepted],
  [#adr-id("005", "use-axum")], [Use Axum as Web Framework], [Accepted],
  [#adr-id("006", "utoipa-openapi-codegen")], [OpenAPI Specification and Codegen with utoipa], [Proposed],
  [#adr-id("007", "frontend-technologies-and-api-communication")], [Frontend Technologies and API Strategy], [Proposed],
  [#adr-id("008", "documentation-tooling-and-structure")], [Documentation Tooling and Structure], [Accepted],
  [#adr-id("009", "photo-storage-opendal-s3-api")], [Photo Storage with OpenDAL and S3 API], [Accepted],
  [#adr-id("010", "authentication-with-oidc")], [Authentication with OpenID Connect (OIDC)], [Accepted],
  [#adr-id("011", "observability-with-opentelemetry")], [Observability with OpenTelemetry], [Proposed],
  [#adr-id("012", "error-handling-thiserror-anyhow")], [Error Handling with thiserror and anyhow], [Accepted],
  [#adr-id("013", "hybrid-llm-script-parsing-architecture")], [Hybrid LLM Script Parsing Architecture], [Accepted],
  [#adr-id("014", "testcontainers-integration-testing")], [Testcontainers Integration Testing], [Accepted],
  [#adr-id("015", "sierradb-event-store-postgres-projections")], [SierraDB Event Store and PostgreSQL Projections], [Accepted],
  [#adr-id("016", "sierradb-runtime-and-round-trip")], [SierraDB Runtime and Tier-4 Round-Trip], [Accepted],
  [#adr-id("017", "architecture-testing-strategy")], [Architecture Testing Strategy], [Accepted],
  [#adr-id("018", "oidc-jwt-validation-and-dev-auth-toggle")], [OIDC JWT Validation and Dev-Auth Toggle], [Accepted],
  [#adr-id("019", "costume-photo-storage")], [Costume Photo Storage, Garage, and Derived Auth], [Accepted],
  [#adr-id("020", "rust-component-versioning")], [Rust Component Versioning and Release Mechanics], [Accepted],
  [#adr-id("021", "api-versioning")], [HTTP API Path Versioning and Deprecation], [Accepted],
  [#adr-id("022", "pdf-reporting-and-archival")], [In-Process Typst PDF Reporting and Archival], [Proposed],
  [#adr-id("023", "database-encryption-at-rest")], [Database Encryption at Rest], [Proposed],
  [#adr-id("024", "database-encryption-in-transit")], [Database Encryption in Transit (TLS)], [Proposed],
  [#adr-id("025", "https-edge-and-cert-rotation")], [HTTPS Edge Transport and Certificate Rotation], [Proposed],
  [#adr-id("026", "arch-linux-vps-hardening-baseline")], [Arch Linux VPS Hardening Baseline], [Proposed],
  [#adr-id("027", "secrets-vault-for-external-credentials")], [Secrets Vault for External Credentials], [Proposed],
  [#adr-id("028", "settings-aggregates-access-control")], [Settings Aggregates Access Control], [Proposed],
  [#adr-id("029", "gdpr-right-to-erasure-append-only-log")], [GDPR Right to Erasure in an Append-Only Log], [Proposed],
  [#adr-id("030", "ai-import-bounded-context")], [AI Import Bounded Context], [Accepted],
  [#adr-id("031", "http-error-surface")], [HTTP Error Surface (RFC 9457, Codes, i18n)], [Accepted],
  [#adr-id("032", "flutter-client-tls-pinning-rotation")], [Flutter Client TLS Certificate Pinning], [Proposed],
  [#adr-id("033", "flutter-client-versioning")], [Flutter Client Versioning and Release Mechanics], [Accepted],
  [#adr-id("034", "flutter-app-localization-gen-l10n")], [Flutter App Localization with gen-l10n], [Accepted],
  [#adr-id("035", "production-kind-flexible-hierarchy")], [Production-Kind-Flexible Hierarchy (`Project`)], [Accepted],
  [#adr-id("036", "es-native-reservation-streams-cross-aggregate-uniqueness")], [ES-Native Reservation Streams for Uniqueness], [Accepted],
  [#adr-id("037", "sceneshoot-provenance-pair-join-derivation")], [SceneShoot AI Provenance from Pair Join], [Accepted],
  [#adr-id("038", "ai-import-sse-progress-and-event-hub")], [AI Import SSE Progress and Event Hub], [Proposed],
  [#adr-id("039", "target-less-ai-import-declared-season-and-set-once-attach")], [Target-Less AI Import and Set-Once Attach], [Proposed],
  [#adr-id("040", "jiff-replaces-chrono")], [`jiff` Replaces `chrono` as Time Library], [Accepted],
)
