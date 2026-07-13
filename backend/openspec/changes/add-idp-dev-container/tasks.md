## 1. Compose overlay

- [ ] 1.1 Create `docker-compose.idp.yml` at the repo root (SPDX header; mirroring the structure of `docker-compose.dev.yml`).
- [ ] 1.2 Add a `logto-db` service (`postgres:16-alpine`) with its own named volume, dedicated credentials, and a healthcheck.
- [ ] 1.3 Add a `logto` service using `logto/logto:<pinned-tag>` (resolve Open Question 1 to a specific minor tag), depending on `logto-db` health, with `DB_URL`, `ENDPOINT`, and `ADMIN_ENDPOINT` env vars, exposed on documented ports (e.g. `3301` for OIDC, `3302` for admin UI).
- [ ] 1.4 Add a healthcheck for `logto` against `/api/status` (or documented Logto status endpoint) with the same interval/timeout/retries pattern as the existing dev services.
- [ ] 1.5 Add a `logto_db_data` and (if needed) `logto_data` named volume and document them at the bottom of the overlay.

## 2. Seed automation

- [ ] 2.1 Create `scripts/seed-logto-dev.sh` (or alternative per Open Question 2) with SPDX header.
- [ ] 2.2 Implement a bounded-retry poll of Logto's status endpoint before issuing Admin API calls (model the bounded retry on the `projector-supervision` pattern).
- [ ] 2.3 Implement idempotent creation/reuse of the "breakdown dev" OIDC application via Logto Admin API (look up by name; create only if absent).
- [ ] 2.4 Write `OIDC_ISS`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` to `.env.idp` from the seeded application's values.
- [ ] 2.5 Add `.env.idp` to `.gitignore` and provide `.env.idp.example` documenting the three variables.
- [ ] 2.6 Smoke-test the script end-to-end: boot overlay → run script → assert `.env.idp` present and values non-empty; reboot stack → re-run script → assert idempotency (no second application, values stable).

## 3. Documentation

- [ ] 3.1 Extend `backend/AGENTS.md` §6 with the overlay boot command (`docker compose -f docker-compose.dev.yml -f docker-compose.idp.yml up -d`), the seed script invocation, and the three new env vars.
- [ ] 3.2 Add an explicit Dev-≠-Prod-IdP note in `AGENTS.md` §6: production IdP runtime is governed by ADR-010 and is not provided by the dev overlay.
- [ ] 3.3 Update the root `README.md` dev-quickstart to reference the optional IdP overlay for auth-related work.
- [ ] 3.4 Document the pinned Logto tag choice in the overlay file header comment (and in the design's Open Question 1 resolution).

## 4. Boundaries and guardrails

- [ ] 4.1 Confirm no source files under `crates/core`, `crates/infra`, or `crates/api` are modified by this change.
- [ ] 4.2 Confirm `docker-compose.prod.yml` is unchanged.
- [ ] 4.3 Confirm `docker-compose.dev.yml` continues to function standalone (no new dependency on the IdP overlay) — boot it once and run the existing dev flow.
- [ ] 4.4 Run `./scripts/add-spdx-headers.sh` (or equivalent) over any new `.sh`/`.yml` files introduced.

## 5. Open Questions to resolve before/during implementation

- [ ] 5.1 Pin a specific Logto image minor tag (resolve design Open Question 1).
- [ ] 5.2 Decide seed-script implementation language — Bash + `curl`/`jq` recommended (resolve design Open Question 2).
- [ ] 5.3 Flag frontend-local-dev Logto endpoint needs to the frontend track (resolve design Open Question 3 — out of scope for this change, just communication).
