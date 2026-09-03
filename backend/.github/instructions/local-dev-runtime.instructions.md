---
description: Local dev runtime - compose stack, boot sequence, env vars, OIDC/dev-auth and local IdP overlay.
applyTo:
  - "docker-compose*"
  - "scripts/**"
  - ".env*"
  - "dev-certs/**"
---

# Local Dev Runtime

v1 ships a **Postgres-only** dev compose. SierraDB is not included; the live `command → SierraDB → projector → PG` round-trip is deferred to the `sierradb-runtime-and-round-trip` follow-up change.

### Prerequisites
- Docker (or a compatible container runtime) for the dev database **and** the SierraDB event store.

### Start the dev runtime (both tiers)
The dev compose starts the full two-tier stack from ADR-015 / ADR-016:
Postgres (read model / projections) **and** SierraDB (event store, RESP3).
From the `backend/` directory run:

```bash
docker compose -f docker-compose.dev.yml up -d
```

This starts:
- **Postgres** on `localhost:5432` — user `postgres`, password `postgres`, database `breakdown`.
  An init script (`scripts/postgres-init-roles.sh`) runs on first boot to
  create two least-privilege roles: `breakdown_migrator` (DDL, schema owner)
  and `breakdown_app` (DML only).
- **SierraDB** on `localhost:9090` (RESP3) — pinned to `tqwewe/sierradb:0.3.1`.

### Apply migrations and run the API (full boot sequence)
1. Start both tiers (above).
2. Apply Postgres projection migrations + boot the API, pointing at both tiers:

```bash
DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown \
SIERRADB_URL=redis://127.0.0.1:9090/?protocol=resp3 \
cargo run -p api
```

`main.rs` uses a **two-pool Postgres architecture**:
1. A short-lived migrator pool (`MIGRATOR_DATABASE_URL`, defaults to `DATABASE_URL`)
   runs `sqlx::migrate!("../infra/migrations")` at boot (DDL rights).
2. After migration, it enforces the INSERT-only audit restriction
   (REVOKE UPDATE/DELETE on `projection_audit` from `breakdown_app`).
3. The migrator pool is dropped, and a long-lived app pool (`DATABASE_URL`,
   DML only) serves all runtime queries.

In dev mode (single role, `DATABASE_URL` only), both pools use the same
connection — the audit REVOKE is skipped gracefully.

`main.rs` then opens a RESP3 connection to SierraDB, builds a live
`CommandService` (write path), and spawns the four `PostgresProcessor`
projectors that subscribe to SierraDB and update the Postgres projections.

### Environment variables used by the API binary
- `DATABASE_URL` – Postgres app-role connection string (DML only). Default: `postgres://postgres:postgres@localhost:5432/breakdown`. In production, connect as `breakdown_app` (least-privilege).
- `MIGRATOR_DATABASE_URL` – Postgres migrator-role connection string (DDL, schema owner). Used only during boot migration, then dropped. Falls back to `DATABASE_URL` when unset or empty (single-role dev mode). In production, connect as `breakdown_migrator`.
- `SIERRADB_URL` – SierraDB RESP3 connection string (default: `redis://127.0.0.1:9090/?protocol=resp3`). SierraDB speaks RESP3 only — keep `?protocol=resp3` (ADR-016). In production this is `rediss://stunnel:9091/?protocol=resp3` (TLS via the stunnel sidecar, ADR-024).
- `SIERRADB_TLS_ROOT_CERT` – optional PEM path of the pinned root CA for the SierraDB link (the internal step-ca root in production). When set, the redis client is built with `Client::build_with_tls` and the URL must use `rediss://`.
- `BIND_ADDR` – HTTP bind address (default: `0.0.0.0:3000`)
- `REQUIRE_IN_TRANSIT_TLS` – startup gate (default off). When `true`/`1`, `main.rs` refuses a production config whose `DATABASE_URL`/`MIGRATOR_DATABASE_URL` lack `sslmode=verify-full` + `sslrootcert`, whose `SIERRADB_URL` is not `rediss://`, whose `S3_ENDPOINT`/`REPORT_BACKUP_*_ENDPOINT`/`AI_PAYLOAD_S3_ENDPOINT` are not `https://`, or whose `AI_PAYLOAD_S3_ENDPOINT` uses `https://` without `AI_PAYLOAD_S3_TLS_ROOT_CERT` set (ADR-024). Set by `docker-compose.prod.yml`; never inferred from `OIDC_ISS` because the local IdP overlay must keep working against plaintext dev URLs.
- OpenAPI/Swagger UI is served at `http://localhost:3000/swagger-ui`

#### OIDC / authorization (added by `add-oidc-auth-and-membership`)
- `OIDC_ISS` – IdP issuer URL (expected `iss` claim). Production-only; when
  absent **and** `DEV_AUTH_SUB` is set, the API runs in **dev auth mode** (see below).
- `OIDC_AUDIENCE` – resource indicator / expected `aud` claim for this API.
- `OIDC_JWKS_URL` – IdP JWKS document URL used to fetch RSA signing keys.
- `AUTHZ_ENFORCE` – `false`/`0` disables authorization enforcement
  (denials are logged, requests allowed — staged rollout / log-only); any other value
  (or unset) enforces, returning `403` for non-members. **Dev auth mode defaults
  enforcement OFF** so local development works without seeded membership.
- `DEV_AUTH_SUB` – when set (and `OIDC_ISS` unset), auth runs in dev mode:
  tokens are NOT verified and a fixed dummy `CurrentUser` (`sub = DEV_AUTH_SUB`)
  is injected. **Never set in production.** `DEV_AUTH_EMAIL` optionally supplies the
  dummy user's email.

> Dev auth mode is an explicit, env-gated bypass used only for local development
> and tests. `main.rs` only ever enters it when `OIDC_ISS` is absent and
> `DEV_AUTH_SUB` is present; production deployments set `OIDC_ISS` and therefore
> can never reach dev mode.

### Optional: Local IdP for OIDC Development

For auth-related work, you can boot a self-hosted Logto IdP using the IdP overlay. **This is dev-only**; production IdP runtime is governed by ADR-010 (Logto Cloud first, Zitadel migration later) and is not provided by this dev overlay.

```bash
# Generate the dev CA + leaf certs (IdP + API) — creates dev-certs/
./scripts/generate-dev-certs.sh

# Boot the full stack with IdP
docker compose -f docker-compose.dev.yml -f docker-compose.idp.yml up -d

# Seed the OIDC application (generates .env.idp)
./scripts/seed-logto-dev.sh
```

This starts:
- **Logto OIDC** on `https://localhost:3301` — issuer URL for OIDC flows (HTTPS, cert signed by the dev CA)
- **Logto Admin UI** on `https://localhost:3302` — admin console and Admin API (HTTPS)
- **logto-db** — dedicated Postgres for Logto state (isolated from breakdown read-model)

After seeding, the `.env.idp` file contains:
- `OIDC_ISS` — Issuer URL (e.g., `https://localhost:3301`)
- `OIDC_AUDIENCE` — Resource indicator for your API (e.g., `https://api.breakdown.local`)
- `OIDC_JWKS_URL` — JWKS endpoint for key discovery (e.g., `https://localhost:3301/.well-known/jwks`)

**Dev IdP TLS (D1 primary):** The IdP serves HTTPS on `:3301` with a leaf cert signed by the dev CA (`dev-certs/ca.pem`). The same CA signs the API cert (`dev-certs/api.pem`), so the Flutter client pins one CA set for both hosts. The leaf certs include `10.0.2.2` as a SAN for Android emulator reachability — the emulator connects to the IdP at `https://10.0.2.2:3301`.

> **First-time setup:** Run `./scripts/generate-dev-certs.sh` before booting the IdP overlay — `docker-compose.idp.yml` mounts `dev-certs/idp.{pem,key}` into the Logto container. The generated certs are git-ignored (see `.gitignore`).

**Dev ≠ Prod IdP:** The backend validates standard OIDC JWTs and is IdP-agnostic. Dev uses self-hosted Logto for convenience; production may use Logto Cloud or Zitadel per ADR-010. No code changes are needed to switch IdPs — only the environment variables change.

**Frontend note:** Local frontend dev should configure the OIDC client to point to `https://localhost:3301` for the issuer. The dev CA (`dev-certs/ca.pem`) replaces the placeholder in `frontend-flutter/assets/certs/dev/ca.pem` — copy it there so the Flutter client trusts the dev IdP + API.

