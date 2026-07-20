## Why

The `add-oidc-auth-and-membership` change will validate OIDC ID-Tokens in the backend against an IdP JWKS. ADR-010 defers IdP selection per environment: managed Logto Cloud first, self-hosted Zitadel later. But the dev/CI loop must not depend on an external cloud tenant — it should be offline, deterministic, and free of per-developer cloud configuration. This change adds a local, self-hosted IdP overlay for the dev runtime only, decoupling dev-loop velocity from the production IdP decision.

## What Changes

- Add a new dev-only Compose overlay `docker-compose.idp.yml` (used together with `docker-compose.dev.yml`) starting a self-hosted Logto instance plus its dedicated `logto-db` Postgres container.
- Provide a seed script that, on first boot, talks to Logto's Admin API, provisions an OIDC application ("breakdown dev"), and emits the resulting `OIDC_ISS`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` to a `.env.idp` file consumed by the API binary.
- Document the dev IdP boot sequence and the Dev-≠-Prod-IdP nuance (ADR-010 keeps production cloud-first; dev may self-host) in `AGENTS.md` §6 and the README.
- Establish a clear boundary: production IdP runtime is **not** part of this change and remains governed by ADR-010 (Logto Cloud first, Zitadel migration as a later, separate architecture decision).

## Capabilities

### New Capabilities
- `idp-dev-runtime`: Self-hosted OIDC identity provider for development and CI, including the Compose overlay, seed automation, and documented boot sequence. Production IdP runtime is explicitly out of scope.

### Modified Capabilities

## Impact

- **Repo root (dev tooling):** New `docker-compose.idp.yml` overlay; new `scripts/seed-logto-dev.sh` (or equivalent) helper; new `.env.idp.example`.
- **`docs/operations` / `AGENTS.md` §6:** New env vars (`OIDC_ISS`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL`) and the overlay Compose command documented.
- **Out of scope:** The `add-oidc-auth-and-membership` change (middleware, extractor, authorization) is unaffected — it will consume exactly the environment variables produced here. No `crates/core` or `crates/infra` source changes. Production `docker-compose.prod.yml` is unchanged.
- **Dependencies:** Adds the Logto container image (`logto/logto`) and a dedicated `postgres:16-alpine` for `logto-db` (isolated from the `breakdown` read-model Postgres).
