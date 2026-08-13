// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Architecture Decisions

#note[
  This chapter lists all Architecture Decision Records (ADRs). The ADRs
  themselves live in Markdown in `docs/architecture/adrs/` so they render
  naturally on GitHub, and are versioned per change.
]

== Decision Lifecycle

1. *Proposal* — authored as a Markdown ADR in `proposed` state.
2. *Review* — team discusses asynchronously and in reviews.
3. *Decision* — accept, reject, defer or supersede.
4. *Publish* — status changes and links are stable.

== ADR Index

#table(
  columns: 3,
  table.header([ID], [Title], [Status]),
  [#link("../adrs/ADR-001-hexagonal-architecture.md")[001]], [Hexagonal Architecture], [Accepted],
  [#link("../adrs/ADR-002-event-sourcing-cqrs.md")[002]], [Event Sourcing and CQRS], [Accepted],
  [#link("../adrs/ADR-003-use-postgresql.md")[003]], [Use PostgreSQL], [Superseded by 015],
  [#link("../adrs/ADR-004-use-uuidv7.md")[004]], [Use UUIDv7], [Accepted],
  [#link("../adrs/ADR-005-use-axum.md")[005]], [Use Axum], [Accepted],
  [#link("../adrs/ADR-006-utoipa-openapi-codegen.md")[006]], [OpenAPI via utoipa], [Proposed],
  [#link("../adrs/ADR-007-frontend-technologies-and-api-communication.md")[007]], [Frontend / API Strategy], [Proposed],
  [#link("../adrs/ADR-008-documentation-tooling-and-structure.md")[008]], [Documentation Tooling], [Accepted],
  [#link("../adrs/ADR-009-photo-storage-opendal-s3-api.md")[009]], [Photo Storage (OpenDAL/S3)], [Accepted],
  [#link("../adrs/ADR-010-authentication-with-oidc.md")[010]], [OIDC Authentication], [Accepted],
  [#link("../adrs/ADR-011-observability-with-opentelemetry.md")[011]], [Observability (OTel)], [Proposed],
  [#link("../adrs/ADR-012-error-handling-thiserror-anyhow.md")[012]], [thiserror/anyhow Errors], [Accepted],
  [#link("../adrs/ADR-013-hybrid-llm-script-parsing-architecture.md")[013]], [Hybrid LLM Script Parsing], [Accepted],
  [#link("../adrs/ADR-014-testcontainers-integration-testing.md")[014]], [Testcontainers Integration Tests], [Accepted],
  [#link("../adrs/ADR-015-sierradb-event-store-postgres-projections.md")[015]], [SierraDB + PG CQRS Split], [Accepted],
  [#link("../adrs/ADR-016-sierradb-runtime-and-round-trip.md")[016]], [SierraDB Runtime & Round-Trip], [Accepted],
  [#link("../adrs/ADR-017-architecture-testing-strategy.md")[017]], [Architecture Testing Strategy], [Accepted],
  [#link("../adrs/ADR-018-oidc-jwt-validation-and-dev-auth-toggle.md")[018]], [OIDC JWT + Dev-Auth Toggle], [Accepted],
  [#link("../adrs/ADR-019-costume-photo-storage.md")[019]], [Costume Photo Storage], [Accepted],
  [#link("../adrs/ADR-020-rust-component-versioning.md")[020]], [Rust Component Versioning], [Accepted],
  [#link("../adrs/ADR-021-api-versioning.md")[021]], [API Versioning], [Accepted],
  [#link("../adrs/ADR-022-pdf-reporting-and-archival.md")[022]], [PDF Reporting & Archival], [Proposed],
  [#link("../adrs/ADR-023-database-encryption-at-rest.md")[023]], [Database Encryption at Rest], [Proposed],
  [#link("../adrs/ADR-024-database-encryption-in-transit.md")[024]], [Encryption in Transit], [Proposed],
  [#link("../adrs/ADR-025-https-edge-and-cert-rotation.md")[025]], [HTTPS Edge & Cert Rotation], [Proposed],
  [#link("../adrs/ADR-026-arch-linux-vps-hardening-baseline.md")[026]], [Arch Linux VPS Hardening], [Proposed],
  [#link("../adrs/ADR-027-secrets-vault-for-external-credentials.md")[027]], [Secrets Vault], [Proposed],
  [#link("../adrs/ADR-028-settings-aggregates-access-control.md")[028]], [Settings Aggregate Access], [Proposed],
  [#link("../adrs/ADR-029-gdpr-right-to-erasure-append-only-log.md")[029]], [GDPR Right-to-Erasure & Append-Only], [Proposed],
  [#link("../adrs/ADR-030-ai-import-bounded-context.md")[030]], [AI Import Bounded Context], [Accepted],
  [#link("../adrs/ADR-031-http-error-surface.md")[031]], [HTTP Error Surface], [Accepted],
)

#note[
  Status column mirrors the ADR front matter. Superseded ADRs link to their
  replacement and remain for historical context.
]

// TODO: surface deprecation dates once the first ADR is officially retired
