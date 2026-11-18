// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Deployment View

== Development Environment

Developers run the base two-tier persistence stack with `docker-compose.dev.yml`
and run the Rust API and Flutter app directly on the workstation. Optional
Compose overlays add OIDC, Garage S3, and HashiCorp Vault on demand.

#diagram("deployment-dev", caption: [Local development stack and optional Compose overlays])

#table(
  columns: 3,
  table.header([Component], [Local Configuration], [Notes]),
  [PostgreSQL 16], [`docker-compose.dev.yml` (`:5432`)], [Init script creates `breakdown_migrator` (DDL) and `breakdown_app` (DML) roles.],
  [SierraDB 0.3.1], [`docker-compose.dev.yml` (`:9090`)], [Speaks RESP3 (`SIERRA_SYNC.IDLE_INTERVAL_MS=4`).],
  [Logto IdP overlay], [`docker-compose.idp.yml` (`:3301` HTTPS)], [Uses local `dev-certs/ca.pem` with `10.0.2.2` SAN for Android emulators.],
  [Garage AI/photo overlay], [`docker-compose.dev.ai.yml` (`:3900`)], [Started by `./scripts/enable-dev-ai-import.sh` for durable blob storage.],
  [Vault overlay], [`docker-compose.dev.vault.yml` (`:8200`)], [Started by `./scripts/enable-dev-vault.sh` with Transit and KV-v2 engines.],
  [Flutter client (`dev`)], [`flutter run --flavor dev`], [Trusts `assets/certs/dev/ca.pem` and connects to local API and Logto.],
)

== Production Environment

Production runs on a hardened Arch Linux VPS (`docker-compose.prod.yml`) with
LUKS2 disk encryption at rest (#adr-ref(num: "023", slug: "database-encryption-at-rest", title: "Encryption at Rest"),
#adr-ref(num: "026", slug: "arch-linux-vps-hardening-baseline", title: "VPS Hardening Baseline"))
and an internal `step-ca` TLS mesh (#adr-ref(num: "024", slug: "database-encryption-in-transit", title: "Encryption in Transit")).

#diagram("deployment-production", caption: [Production VPS topology with Caddy edge, step-ca TLS mesh, and Vault])

#table(
  columns: 3,
  table.header([Layer], [Production Choice], [Security and Operational Role]),
  [Host OS and disk], [Arch Linux + LUKS2 + `nftables` + `auditd`], [Encrypts all Docker volumes at rest and blocks non-edge ports (#adr-ref(num: "023", slug: "database-encryption-at-rest", title: "Encryption at Rest"), #adr-ref(num: "026", slug: "arch-linux-vps-hardening-baseline", title: "VPS Hardening"))],
  [Public edge], [Caddy (`:80` / `:443`)], [Manages ACME certificates and forwards HTTPS traffic to `api:3000` (#adr-ref(num: "025", slug: "https-edge-and-cert-rotation", title: "HTTPS Edge"))],
  [Internal PKI], [`step-ca` + `tls-provision`], [Issues 24-hour leaf certificates for Postgres, stunnel, Caddy, and Vault every 12 hours (#adr-ref(num: "024", slug: "database-encryption-in-transit", title: "Encryption in Transit"))],
  [Application], [`api` container (`api-vX.Y.Z`)], [Runs on the internal Docker network only and checks `REQUIRE_IN_TRANSIT_TLS=true` at startup],
  [Read database], [PostgreSQL 16 (`ssl=on`, `verify-full`)], [Uses 1 boot migrator pool + 20-conn app pool + 20-conn projector pool],
  [Event store], [`stunnel` (`:9091`) + SierraDB (`:9090`)], [Handles internal TLS at `stunnel` before Docker-internal RESP3],
  [Object store], [Garage v1.0.1 behind `caddy:9443`], [Serves `costume-photos`, `ai-import-payloads`, and S3 report archives over TLS],
  [Secrets vault], [HashiCorp Vault 1.20 + `vault-bootstrap`], [Runs internal TLS and mounts only a 24 h least-privilege app token into `api` (#adr-ref(num: "027", slug: "secrets-vault-for-external-credentials", title: "Secrets Vault"))],
  [Mobile client], [Signed Android APK (`prod` flavor)], [Pins stable public ACME Root CAs (`ISRG Root X1` / `X2`, #adr-ref(num: "032", slug: "flutter-client-tls-pinning-rotation", title: "Client TLS Pinning"))],
)

== Release Artifacts

#important[
  CI builds three versioned artifacts from signed git tags. Tag `api-vX.Y.Z`
  builds the backend Docker image (`.github/workflows/release-image.yml`, #adr-ref(num: "020", slug: "rust-component-versioning", title: "Rust Versioning"))
  and this arc42 PDF/HTML bundle (`docs.yml`). Client tags build the signed
  Flutter release (`flutter-release.yml`, #adr-ref(num: "033", slug: "flutter-client-versioning", title: "Flutter Versioning")).
]

== Selected Environment Variables

#table(
  columns: 3,
  table.header([Variable], [Purpose], [Default / Prod Setting]),
  [`DATABASE_URL`], [PostgreSQL DML DSN (`breakdown_app`)], [Local default, `sslmode=verify-full` in prod],
  [`MIGRATOR_DATABASE_URL`], [Boot-only DDL DSN (`breakdown_migrator`)], [Falls back to `DATABASE_URL` in dev],
  [`DATABASE_MAX_CONNECTIONS`], [App pool size (handlers, AI workers, reaper)], [`20`],
  [`PROJECTOR_DATABASE_MAX_CONNECTIONS`], [Dedicated projector pool size], [`20`],
  [`SIERRADB_URL`], [SierraDB RESP3 connection URL], [`redis://127.0.0.1:9090/?protocol=resp3` (`rediss://` in prod)],
  [`S3_ENDPOINT`], [Garage S3 endpoint for photo storage], [`http://garage:3900` (`https://caddy:9443` in prod)],
  [`VAULT_ADDR`], [HashiCorp Vault URL], [`http://127.0.0.1:8200` (`https://vault:8200` in prod)],
  [`REQUIRE_IN_TRANSIT_TLS`], [Refuses startup if any store URL lacks TLS], [`false` in dev, `true` in prod],
  [`AI_IMPORT_ENABLED`], [Enables AI import routes and workers], [`false` (`AI_PAYLOAD_S3_*` must be set when `true`)],
)
