## Context

ADR-010 *Authentication with OpenID Connect* decides that the production backend validates signed OIDC JWTs against a managed cloud IdP (Logto Cloud first, Zitadel later) and never ships an IdP-specific SDK. The accompanying change `add-oidc-auth-and-membership` implements the backend middleware to validate ID-Tokens against the configured IdP JWKS.

For local development and CI, however, requiring each developer (and every CI run) to authenticate against a managed Logto Cloud tenant is unsuitable:

- **Offline work** must keep functioning when the Logto Cloud tenant is unreachable.
- **Deterministic CI** must not flap with cloud IdP availability or rate limits.
- **Per-developer cloud secrets** are an avoidable operational hazard.
- **Cost / config churn** on Logto Cloud should not gate local dev.

The Dev runtime therefore needs its own self-hosted IdP, *separate* from the production IdP decision. This is consistent with ADR-010: the backend is IdP-agnostic by contract (it only validates standard OIDC JWTs), so dev and prod may legitimately use different concrete IdPs.

The existing `persistence-dev-runtime` capability established the Compose-overlay pattern in this repo (`docker-compose.dev.yml` for Postgres + SierraDB). This change follows the same pattern as an *additional* overlay (`docker-compose.idp.yml`) that developers opt into only when they need to exercise auth locally.

## Goals / Non-Goals

**Goals:**
- Provide a working, self-hosted Logto instance for local dev, with separated `logto-db`, healthchecks, and persistent configuration across dev reboots.
- Automate OIDC application provisioning so a single command leaves the dev environment ready: issuer URL, JWKS URL, and audience are exported to `.env.idp`.
- Stay strictly dev-only; production IdP runtime is out of scope (ADR-010 owns it).
- Add **zero** code to `crates/core`, `crates/infra`, or `crates/api`. This change touches only repo-root tooling and docs.

**Non-Goals:**
- Production IdP deployment (Logto Cloud, Logto self-hosted, or Zitadel self-hosted) — governed by ADR-010 and any future production-IdP ADR.
- The JWT validation middleware itself — owned by `add-oidc-auth-and-membership`.
- IdP-to-Logto Cloud migration tooling, user export/import, or schema migration — owned by a future IdP-migration change.
- The dummy-`CurrentUser` feature flag for fast unit/integration tests — owned by `add-oidc-auth-and-membership` (its Open Question 4).
- Multi-tenant Logto Organizations configuration for dev. v1 dev uses a single organization; cross-theater modeling is a Stakeholder-driven design question (see `add-oidc-auth-and-membership` design.md Open Question 2).

## Decisions

### 1. IdP for dev is self-hosted Logto, not Zitadel
**Decision.** The dev overlay runs the official `logto/logto` image with a dedicated `logto-db` Postgres container.
**Rationale.** Logto has a smaller setup footprint than Zitadel (no masterkey dance, simpler schema init) and ADR-010 names Logto first for production anyway — using Logto in dev keeps dev/prod parity maximal *at the IdP-product level*, reducing surprise drift. If `add-oidc-auth-and-membership` Open Question 4 resolves to "switch to Zitadel first", we revisit this decision in a follow-up.
**Alternatives considered.** (a) Self-hosted Zitadel in dev — rejected for setup weight and premature commitment to a production path ADR-010 has not yet adopted. (b) Mocked JWKS endpoint — rejected as the *primary* dev IdP (it would not exercise real token issuance flows); instead, `add-oidc-auth-and-membership` carries a separate dummy-`CurrentUser` feature flag for fast unit/integration tests.

### 2. Compose overlay, not modification of `docker-compose.dev.yml`
**Decision.** Add `docker-compose.idp.yml` as a standalone overlay. Devs boot the dev stack + IdP with `docker compose -f docker-compose.dev.yml -f docker-compose.idp.yml up -d`; devs who do not need auth locally continue to use `docker-compose.dev.yml` alone.
**Rationale.** Mirrors the `persistence-dev-runtime` overlay pattern and keeps the existing dev experience (Postgres + SierraDB) untouched for contributors not yet working on auth. Container lifecycle stays opt-in.
**Alternatives considered.** (a) Merge Logto into `docker-compose.dev.yml` — rejected; it would force the IdP on every contributor and slow the dev loop. (b) Replace Logto with the dummy `CurrentUser` flag only — rejected; would not exercise real OIDC flows, pushing integration problems late.

### 3. Dedicated `logto-db`, isolated from the breakdown Postgres
**Decision.** Logto uses its own `postgres:16-alpine` container (`logto-db`) with its own volume, distinct from the breakdown read-model Postgres.
**Rationale.** Logto manages its own schema lifecycle; co-locating in the breakdown DB would entangle IdP migrations with projection migrations and risk cross-pollution during a destructive `sqlx::migrate!`. Isolation mirrors how production would also run a separate IdP store.
**Alternatives considered.** (a) Reuse the breakdown Postgres with a separate database — acceptable but adds coupling; rejected for cleanliness.

### 4. Seed automation emits `.env.idp`, idempotent across reboots
**Decision.** A seed script (`scripts/seed-logto-dev.sh`) calls Logto's Admin API on first boot to provision the "breakdown dev" OIDC application, writes `OIDC_ISS`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` to `.env.idp`, and is idempotent: subsequent runs reuse the existing application and refresh `.env.idp`.
**Rationale.** Manual UI clicks would rot quickly and break CI reproducibility. Logto's persisted configuration across reboots (via `logto-db` volume) guarantees stable identifiers once seeded.
**Alternatives considered.** (a) Embed seeding in a container entrypoint — rejected; harder to debug and couples lifecycle weirdly. (b) Document UI clicks instead of scripting — rejected; non-reproducible.

### 5. This change is a precondition for, and decoupled from, the OIDC code change
**Decision.** This change is pure tooling/docs and carries no Stakeholder-blocking Open Questions. It may be implemented in parallel with the Stakeholder brief on `add-oidc-auth-and-membership`. The output environment variables (`OIDC_ISS` / `OIDC_AUDIENCE` / `OIDC_JWKS_URL`) are consumed verbatim by the OIDC middleware when that code change lands.
**Rationale.** Decoupling surfaces real local OIDC testing earlier and gives developers a concrete Logto instance to point a Svelte frontend at during auth development.
**Alternatives considered.** (a) Fold the dev IdP into `add-oidc-auth-and-membership` — rejected; it would tie pure tooling to the Stakeholder-blocked code change unnecessarily.

## Risks / Trade-offs

- [Logto image supply-chain surface] → Logto is Node.js/npm-based, mirroring the production ADR-010 supply-chain caveat that motivates the eventual Zitadel migration. Mitigation: pin a specific Logto image tag; the `security-audit` spec (CI) does not scan the image but the dev-only blast radius is limited to developer machines.
- [IdP drift between dev and prod] → Dev uses Logto self-hosted; prod may use Logto Cloud or later Zitadel. Mitigation: the backend never depends on IdP-specific behaviour (ADR-010), only on standard OIDC JWTs; integration tests against the dev Logto exercise the standard contract, not provider quirks.
- [Seed script failures during Logto boot races] → Admin API may not be ready when the seed script runs. Mitigation: the script polls Logto's `/api/status` healthcheck with bounded retry (the projector-supervision bounded-retry pattern is a good model).
- [Logto configuration rot across image upgrades] → a future Logto image bump may change the Admin API surface. Mitigation: pin the image tag; revisit on upgrade with the seed script as the smoke test.

## Migration Plan

- Purely additive — no existing dev/prod Compose file is modified destructively. `docker-compose.dev.yml` continues to work exactly as today.
- Rollback: `docker compose -f docker-compose.idp.yml down -v` removes the IdP and its DB volume; `docker-compose.dev.yml` continues to provide Postgres + SierraDB unaffected.
- Sequencing: this change has no migration of its own; it is itself the migration step *toward* exercising OIDC locally before the `add-oidc-auth-and-membership` code lands.

## Open Questions (Resolved)

1. **Logto image tag.** ✅ **Resolved:** `svhd/logto:1.13.0` - pinned minor tag for reproducibility. Note: The official Logto image is published as `svhd/logto`, not `logto/logto`.
2. **Seed script language.** ✅ **Resolved:** Bash + `curl`+`jq` for zero-build reproducibility. Implemented in `scripts/seed-logto-dev.sh`.
3. **Frontend developer flow.** ✅ **Resolved:** Documented in AGENTS.md §6 - frontend should configure OIDC client to point to `http://localhost:3301` for local dev.
