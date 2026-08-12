// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Deployment View

== Development Environment

A fully local stack is one `docker compose up` away. The compose file also
supports an IdP overlay for OIDC development.

#diagram("deployment-dev", caption: [Local development deployment])

| Decision        | Value | Notes |
|-----------------|-------|-------|
| Database        | PostgreSQL 16-alpine | init script creates least-privilege roles |
| Event store     | SierraDB (RESP3)     | pinned `tqwewe/sierradb:0.3.1` |
| Object storage  | Garage               | local S3-compatible for photos and AI payloads |
| Secrets         | none in compose      | optional Vault/LGTP overlay for OIDC flows |

== Production Environment

#diagram("deployment-production", caption: [Production deployment with TLS edge])

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Edge | Caddy with auto HTTPS | cert rotation, sane defaults (#adr-ref(num: "025", slug: "https-edge-and-cert-rotation", title: "HTTPS Edge and Cert Rotation")) |
| App | `api` Docker image, tag `api-vX.Y.Z` | reproducible from git tag (#adr-ref(num: "020", slug: "rust-component-versioning", title: "Rust Component Versioning")) |
| Event store | SierraDB, TLS via stunnel | append-only (#adr-ref(num: "024", slug: "database-encryption-in-transit", title: "Database Encryption in Transit")) |
| Read store | PostgreSQL, TLS verify-full | encryption at rest (#adr-ref(num: "023", slug: "database-encryption-at-rest", title: "Database Encryption at Rest")) / in transit (#adr-ref(num: "024", slug: "database-encryption-in-transit", title: "Database Encryption in Transit")) |
| Object storage | Garage (S3) | self-hosted |
| Secrets | Vault | external creds (#adr-ref(num: "027", slug: "secrets-vault-for-external-credentials", title: "Secrets Vault")) |
| OIDC IdP | Logto Cloud → Zitadel | #adr-ref(num: "010", slug: "authentication-with-oidc", title: "Authentication with OIDC") |

== Build and Release

#important[
  The only reliable release artifact is the Docker image built in
  `.github/workflows/release-image.yml` from the git tag `api-vX.Y.Z`.
  This document itself is *not* that artifact but explains how it's built.
]

== Environment Variables (Selected)

The full list lives in `AGENTS.md` §6; a few here for orientation:

| Variable | Purpose | Default |
|----------|---------|---------|
| `DATABASE_URL` | PostgreSQL DSN | `postgres://localhost/breakdown` |
| `SIERRADB_URL` | SierraDB RESP3 DSN | `redis://127.0.0.1:9090/?protocol=resp3` |
| `S3_ENDPOINT` | Garage endpoint | `http://garage:3900` |
| `PHOTO_GC_ENABLED` | orphan photo GC | `true` |
| `AI_IMPORT_ENABLED` | AI import routes/workers | `false` |

// TODO: add monitoring/alerting stack (Grafana/Otel collector) once deployed
