---
description: Local dev runtime - compose stack, boot sequence, env vars, OIDC/dev-auth and local IdP overlay.
applyTo:
  - "docker-compose*"
  - "scripts/**"
  - ".env*"
  - "dev-certs/**"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

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

```bash
DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown \
SIERRADB_URL=redis://127.0.0.1:9090/?protocol=resp3 \
cargo run -p api
```

> **E2E/Gherkin fault injection (issue #443):** the on-device Gherkin suite
> (`frontend-flutter tool/run_gherkin.sh`) arms a server-side one-shot fault
> via `POST /v1/__faults/block-conflict`. This route exists ONLY when the API
> is booted with `cargo run -p api --features api/test-support`; without the
> feature the route is compile-time absent (arming returns 404). Never enable
> the feature in production boot scripts.

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
- `VAULT_ADDR` – base URL of the secrets vault (ADR-027). Default `http://127.0.0.1:8200` (the dev overlay URL); production uses `https://vault:8200` (internal DNS, ADR-024). The `VaultClient` is built lazily: endpoints that need a credential return `503` until the Vault is reachable.
- `VAULT_APP_TOKEN_FILE` – path to a least-privilege Vault app token file (`breakdown-app` policy, 24 h). The dev overlay (`scripts/enable-dev-vault.sh` + `docker-compose.dev.vault.yml`, issue #468) writes it under `.vault-dev/app-token/app.token` (git-ignored).
- `VAULT_TLS_ROOT_CERT` – optional PEM path of the pinned root CA for an `https://` `VAULT_ADDR` (the internal step-ca root in production).
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


### Optional: Dev Vault overlay (issue #468)

ADR-027 (Vault) is prod-only; without a Vault, a host-run `cargo run -p api`
cannot reach the transit + KV-v2 engines the `/settings` credential and
AI-config `vault_key_id` flows need, so those endpoints return `503`. One
command provisions a local Vault for the host-run API:

```bash
./scripts/enable-dev-vault.sh
```

This boots the Vault overlay (`docker-compose.dev.vault.yml`, mirroring the
IdP/AI overlay pattern) and publishes Vault's HTTP API on loopback
`127.0.0.1:8200` — **dev-only plaintext** (`tls_disable` in
`vault/config.dev.hcl`; never acceptable in production, ADR-024/ADR-027). The
overlay reuses the prod `vault-bootstrap` one-shot (same image + `breakdown-app`
policy, parameterized so TLS is opt-in): it initializes/unseals, enables
Transit + KV-v2, and persists the unseal key + a least-privilege 24 h app token
into the git-ignored `.vault-dev/` host directory, then writes
`.env.dev-vault.local` (git-ignored, chmod 600):

- `VAULT_ADDR=http://127.0.0.1:8200`
- `VAULT_APP_TOKEN_FILE=<abs path to .vault-dev/app-token/app.token>`

The script is idempotent (re-runs renew the app token instead of
re-provisioning). Reset: `docker compose -f docker-compose.dev.vault.yml down
-v && rm -rf .vault-dev`.

> **Photo SSE-C policy (found while testing issue #468):** the `breakdown-app`
> policy grants `create` **and** `update` on `transit/keys/photo-sse-c` —
> Vault's Transit key-creation endpoint requires both, so the API's
> on-first-use `ensure_key` can provision the photo SSE-C bucket key without
> a 403.

> **Sealed-restart (found while testing issue #468):** `vault status` exits 2
> for both a never-initialized and an initialized-but-sealed Vault. The shared
> `vault-bootstrap.sh` now runs `operator init` only when the report shows
> `Initialized false`; a sealed restart falls through to the unseal path and
> renews the app token. Before this, a container restart made the one-shot
> abort with "Vault is already initialized" in prod and dev.

### Optional: dev credential role (issue #468)

The AI-config (`/v1/ai-import/config*`) and settings-credential (`/settings*`)
handlers are AUTHZ-GATED via `has_active_credential_role` (an active
`costume_designer`/`costume_assistant` in any block); these handler gates
deliberately ignore `AUTHZ_ENFORCE`, so a fresh DB leaves the dev user with
`403` even in dev-auth mode. The ADR-018/ADR-028-consistent dev path is a real
membership bootstrap: creating a block dispatches `BootstrapOwner`, which makes
the creator an active `CostumeAssistant` — a credential role. After the API is
up (dev auth), one command drives `series → season → block` and waits for the
membership projector:

```bash
DEV_AUTH_SUB=dev-user ./scripts/bootstrap-dev-credential-role.sh
```

It exits early when the role is already active (idempotent). The same step is
folded into `enable-dev-ai-import.sh --run` (below), so the full one-command
stack also bootstraps the role.

### Optional: AI import for the host-run dev API (issue #428/#468)

`AI_IMPORT_ENABLED=1` for a **host-run** `cargo run -p api` fails closed (#181)
until durable payload storage is configured, and the base dev Garage is
internal-only (no host ports). One command sets up the **whole** stack —
Garage payload storage, the Vault the settings/AI-config credential
gate flows need (issue #468), and the dev credential-role bootstrap:

```bash
./scripts/enable-dev-ai-import.sh            # boot + provision + env file
# or: ./scripts/enable-dev-ai-import.sh --run   (also starts the API afterwards
#                                             and bootstraps the dev role)
```

The script:

1. Enables the Vault overlay first (`scripts/enable-dev-vault.sh` + the
   `docker-compose.dev.vault.yml` overlay, see above) — init/unseal/engines/
   policy/app-token persisting into `.vault-dev/`, `VAULT_ADDR` +
   `VAULT_APP_TOKEN_FILE` written to `.env.dev-vault.local`.
2. Boots `docker-compose.dev.yml` + the AI overlay `docker-compose.dev.ai.yml`,
   which publishes Garage's S3 API (`localhost:3900`) and admin API
   (`localhost:3902`) to the host — **dev-only plaintext** (`REQUIRE_IN_TRANSIT_TLS`
   stays unset; never acceptable in production, ADR-024).
3. Provisions Garage via `docker compose exec` against the bare-binary image
   (no shell in the image): single-node layout, `costume-photos` +
   `ai-import-payloads` buckets, and a fixed dev-only S3 key
   (`GK…` derived deterministically from a dev-only constant — gitleaks-clean
   by derivation, never valid outside this local dev Garage).
4. Verifies the Garage + Vault ports are reachable from the host.
5. Writes `.env.dev-ai.local` (git-ignored via `.env.*.local`, chmod 600) with
   the full host-run env: `AI_IMPORT_ENABLED=1`, the `AI_PAYLOAD_S3_*` trio,
   the merged `VAULT_ADDR`/`VAULT_APP_TOKEN_FILE`, and DB/SierraDB URLs — the
   #181 fail-closed startup gate is *not* weakened; the one-liner simply
   satisfies it durably.

Then start the API with the generated env (in dev auth mode, `DEV_AUTH_SUB`
from `.env.local`). Source `.env.local` **first** so the generated
`.env.dev-ai.local` takes precedence on any overlapping variable — the same
order the `--run` branch uses:

```bash
set -a; . ./.env.local; . ./.env.dev-ai.local; set +a; cargo run -p api
```

With `--run`, the script starts the API in the background, waits for it, and
then runs `scripts/bootstrap-dev-credential-role.sh` so the AUTHZ-GATED
`/v1/ai-import/*` + `/settings*` endpoints are reachable. From there the
app's settings UI (or `curl`) stores a real provider key via
`POST /v1/settings/credentials` and the AI-config wizard references its
`vault_key_id` — a full end-to-end AI import round trip.

The script is idempotent (existing buckets/keys are tolerated; the Vault
renews its app token; the env file is rewritten deterministically). To reset
everything: `docker compose -f docker-compose.dev.yml -f
docker-compose.dev.ai.yml -f docker-compose.dev.vault.yml down -v && rm -rf
.vault-dev` (drops the Garage + Vault volumes and the dev Vault state), then
re-run the script.

> **Garage config rendering (issue #428 fix):** the base dev compose now
> renders the Garage TOML via the same `garage-config` one-shot pattern as
> prod (`scripts/garage-config.sh` mounted into an alpine one-shot, digest
> pinned). The dev RPC secret default is derived deterministically inside
> `garage-config.sh` when `$GARAGE_RPC_SECRET` is unset (Garage validates a
> 32-byte value; a hex literal default would trip gitleaks). Before this, the
> dev Garage service crash-looped ("Invalid RPC secret key") and its
> CMD-SHELL healthcheck could never spawn (no shell in the image) — the
> exec-form healthcheck fixes that too.

