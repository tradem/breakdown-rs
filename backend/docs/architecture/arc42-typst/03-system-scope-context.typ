// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= System Scope and Context

== Business Context

Breakdown RS connects pre-production costume planning with daily set operations.
Production managers, costume designers, wardrobe supervisors, continuity staff,
actors, and operators work against one shared production history.

#diagram("business-context", caption: [Business context: human roles and core use cases])

=== Business Responsibilities

#table(
  columns: 2,
  table.header([Responsibility], [Description]),
  [Production structure], [Organize seasons, blocks, episodes, scenes, and shooting days under a `ProjectId`.],
  [Wardrobe management], [Keep fundus `Piece` records per season repertoire and compose character `Outfit` looks.],
  [Scene casting and continuity], [Assign outfit beats to scenes and compare `SceneShoot` planned order (`Soll`) with actual order (`Ist`).],
  [Photo documentation], [Store original images and strip EXIF metadata to generate `Thumb` and `Medium` variants.],
  [PDF reporting and backup], [Render `Dispo`, `Shoot Day`, and `Soll-Ist` PDFs and archive day reports to S3 or Google Drive.],
  [AI script and schedule import], [Extract draft episodes, scenes, characters, and schedules for human review before command execution.],
)

== Technical Context

=== Subsystems and External Interfaces

The Flutter client communicates exclusively with the Breakdown RS HTTP API and
the configured OIDC Identity Provider (IdP). Only the Rust backend connects to
databases, object stores, Vault, external backup targets, and LLM gateways.

#diagram("technical-context", caption: [Technical context: monorepo subsystems and external interfaces])

#table(
  columns: 4,
  table.header([Partner / Subsystem], [Interface], [Protocol], [Security Control]),
  [Flutter Client (`frontend-flutter/`)], [`/v1` REST JSON, RFC 9457, SSE], [HTTPS (`:443`)], [OIDC Bearer JWT + pinned Root CA (#adr-ref(num: "032", slug: "flutter-client-tls-pinning-rotation", title: "Client TLS Pinning"))],
  [OIDC Identity Provider], [PKCE login and JWKS key set], [HTTPS], [RS256 signature, `iss`, `aud`, and `exp` checks (#adr-ref(num: "018", slug: "oidc-jwt-validation-and-dev-auth-toggle", title: "OIDC Validation"))],
  [SierraDB], [Event and reservation streams], [RESP3 over TLS], [`rediss://` through `stunnel` with pinned `step-ca` root (#adr-ref(num: "024", slug: "database-encryption-in-transit", title: "Encryption in Transit"))],
  [PostgreSQL 16], [Projections, `ai_import` queue, `NOTIFY`], [SQL over TLS], [`sslmode=verify-full` + split `migrator` and `app` roles],
  [Garage], [Photos, AI blobs, S3 report archive], [S3 API over HTTPS], [Internal Caddy `:9443` TLS proxy + S3 access key],
  [HashiCorp Vault], [Transit DEKs and KV-v2 ciphertexts], [HTTPS (`:8200`)], [Pinned `step-ca` root + 24 h least-privilege app token (#adr-ref(num: "027", slug: "secrets-vault-for-external-credentials", title: "Secrets Vault"))],
  [Google Drive / External S3], [Automated PDF report backup], [HTTPS (OpenDAL)], [Owner-scoped credentials decrypted on demand from Vault (#adr-ref(num: "022", slug: "pdf-reporting-and-archival", title: "PDF Reporting"))],
  [Curated LLM Gateways], [Schema-constrained script parsing], [HTTPS], [Hardcoded provider hosts, DNS pinning, no redirects, Vault keys (#adr-ref(num: "030", slug: "ai-import-bounded-context", title: "AI Import"))],
)

#note[
  SierraDB uses the RESP3 wire protocol only. All connections must keep the
  `?protocol=resp3` query parameter in `SIERRADB_URL`.
]
