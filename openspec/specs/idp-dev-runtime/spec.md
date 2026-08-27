# idp-dev-runtime Specification

## Purpose
TBD - created by archiving change add-idp-dev-container. Update Purpose after archive.
## Requirements
### Requirement: Self-hosted IdP Compose overlay for development
The repo SHALL provide `docker-compose.idp.yml` as an opt-in Compose overlay that, combined with `docker-compose.dev.yml`, starts a self-hosted Logto instance and a dedicated `logto-db` Postgres container for local development and CI. The overlay SHALL NOT modify the existing `docker-compose.dev.yml` service set.

#### Scenario: Developer boots the dev stack with auth
- **WHEN** a developer runs `docker compose -f docker-compose.dev.yml -f docker-compose.idp.yml up -d`
- **THEN** Postgres, SierraDB, Logto, and `logto-db` SHALL all become reachable on their documented ports
- **AND** the existing `docker-compose.dev.yml`-only flow SHALL continue to work without Logto

#### Scenario: Logto has a dedicated database
- **WHEN** the `docker-compose.idp.yml` overlay is inspected
- **THEN** Logto SHALL use a dedicated `logto-db` Postgres container with its own volume
- **AND** it SHALL NOT share a database with the breakdown read-model Postgres

### Requirement: Logto healthchecks and persistence
The Logto service in the dev overlay SHALL expose a healthcheck against Logto's status endpoint, and its configuration SHALL persist across container restarts via a dedicated volume on `logto-db`.

#### Scenario: Logto health is observable
- **WHEN** the dev stack with the IdP overlay is running
- **THEN** `docker compose ps` SHALL report Logto as healthy only after its status endpoint responds successfully

#### Scenario: Configuration survives a reboot
- **WHEN** the dev stack is stopped and restarted
- **THEN** previously seeded Logto applications and users SHALL still be present without re-running the seed script

### Requirement: Idempotent OIDC application seeding
The repo SHALL provide a seed script that provisions the "breakdown dev" OIDC application via Logto's Admin API and exports the resulting `OIDC_ISS`, `OIDC_AUDIENCE`, and `OIDC_JWKS_URL` to a `.env.idp` file. The script SHALL be idempotent: re-running it on an already-seeded Logto instance SHALL reuse the existing application and refresh `.env.idp` without creating duplicates.

#### Scenario: First boot seeds and exports env vars
- **WHEN** the seed script runs against an unseeded Logto instance
- **THEN** a single "breakdown dev" OIDC application SHALL be created
- **AND** a `.env.idp` file SHALL be written containing valid `OIDC_ISS`, `OIDC_AUDIENCE`, and `OIDC_JWKS_URL` values pointing at the local Logto

#### Scenario: Re-running the seed script is idempotent
- **WHEN** the seed script runs again against the already-seeded Logto instance
- **THEN** no duplicate OIDC application SHALL be created
- **AND** `.env.idp` SHALL be refreshed with the same issuer, audience, and JWKS URL values

#### Scenario: Seed script waits for Logto readiness with bounded retry
- **WHEN** the seed script runs and Logto's status endpoint is not yet ready
- **THEN** the script SHALL poll the status endpoint with bounded retry and SHALL fail loudly if Logto does not become ready within the retry budget, rather than silently producing an invalid `.env.idp`

### Requirement: Documented dev IdP boot sequence
The dev IdP boot sequence, the overlay Compose command, and the produced environment variables SHALL be documented in `backend/AGENTS.md` §6 and the repository `README.md`, including the explicit note that production IdP runtime is governed separately by ADR-010 and is not part of this dev overlay.

#### Scenario: A new developer can boot the IdP for local auth work
- **WHEN** a developer reads `AGENTS.md` §6 or the README
- **THEN** they find the overlay Compose command, the seed script invocation, the `.env.idp` consumption instructions, and the explicit statement that dev and production IdPs may differ without code changes to the backend

### Requirement: Production IdP runtime is out of scope
This change SHALL NOT provide, configure, or document a production IdP runtime. Production IdP selection and operation SHALL remain governed by ADR-010 (Logto Cloud first, Zitadel migration later as a separate architecture decision). The dev overlay SHALL NOT be marketed or documented as production-ready.

#### Scenario: No production IdP configuration is introduced
- **WHEN** this change is delivered
- **THEN** `docker-compose.prod.yml` SHALL be unchanged
- **AND** no production-grade secrets, persistence, backups, or hardening for Logto SHALL be present in the dev overlay
- **AND** the `add-oidc-auth-and-membership` change SHALL remain the owner of the backend middleware that consumes `OIDC_ISS` / `OIDC_AUDIENCE` / `OIDC_JWKS_URL`

