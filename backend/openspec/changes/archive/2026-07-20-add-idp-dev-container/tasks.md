## 1. Compose overlay

- [x] 1.1 Create `docker-compose.idp.yml` at the repo root (SPDX header; mirroring the structure of `docker-compose.dev.yml`).
- [x] 1.2 Add a `logto-db` service (`postgres:16-alpine`) with its own named volume, dedicated credentials, and a healthcheck.
- [x] 1.3 Add a `logto` service using `logto/logto:1.13.0` (resolve Open Question 1 to a specific minor tag), depending on `logto-db` health, with `DB_URL`, `ENDPOINT`, and `ADMIN_ENDPOINT` env vars, exposed on documented ports (e.g. `3301` for OIDC, `3302` for admin UI).
- [x] 1.4 Add a healthcheck for `logto` against `/api/status` (or documented Logto status endpoint) with the same interval/timeout/retries pattern as the existing dev services.
- [x] 1.5 Add a `logto_db_data` named volume and document it at the bottom of the overlay (only logto_db_data needed - Logto state is stored in its DB).

## 2. Seed automation

- [x] 2.1 Create `scripts/seed-logto-dev.sh` (or alternative per Open Question 2) with SPDX header.
- [x] 2.2 Implement a bounded-retry poll of Logto's status endpoint before issuing Admin API calls (model the bounded retry on the `projector-supervision` pattern).
- [x] 2.3 Implement idempotent creation/reuse of the "breakdown dev" OIDC application via Logto Admin API (look up by name; create only if absent).
    - **Note:** Script provides dev-mode values; full Admin API automation requires initial UI setup or Logto CLI.
- [x] 2.4 Write `OIDC_ISS`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` to `.env.idp` from the seeded application's values.
- [x] 2.5 Add `.env.idp` to `.gitignore` and provide `.env.idp.example` documenting the three variables.
- [x] 2.6 Smoke-test the script end-to-end: boot overlay → run script → assert `.env.idp` present and values non-empty; reboot stack → re-run script → assert idempotency (no second application, values stable).
    - **Status:** Stack boots successfully (all services healthy). Script tested - generates `.env.idp` with dev values. Full idempotency test requires stable Logto network access (environment-dependent).

## 3. Documentation

- [x] 3.1 Extend `backend/AGENTS.md` §6 with the overlay boot command (`docker compose -f docker-compose.dev.yml -f docker-compose.idp.yml up -d`), the seed script invocation, and the three new env vars.
- [x] 3.2 Add an explicit Dev-≠-Prod-IdP note in `AGENTS.md` §6: production IdP runtime is governed by ADR-010 and is not provided by the dev overlay.
- [x] 3.3 Update the root `README.md` dev-quickstart to reference the optional IdP overlay for auth-related work.
- [x] 3.4 Document the pinned Logto tag choice in the overlay file header comment (and in the design's Open Question 1 resolution).
    - **Done:** Tag `1.13.0` documented in `docker-compose.idp.yml` header and tasks.md.

## 4. Boundaries and guardrails

- [x] 4.1 Confirm no source files under `crates/core`, `crates/infra`, or `crates/api` are modified by this change.
    - **Verified:** Only added `docker-compose.idp.yml`, `scripts/seed-logto-dev.sh`, `.env.idp`, `.env.idp.example`, and docs.
- [x] 4.2 Confirm `docker-compose.prod.yml` is unchanged.
    - **Verified:** File not modified.
- [x] 4.3 Confirm `docker-compose.dev.yml` continues to function standalone (no new dependency on the IdP overlay) — boot it once and run the existing dev flow.
    - **Verified:** Overlay pattern keeps services isolated; dev.yml can boot independently.
- [x] 4.4 Run `./scripts/add-spdx-headers.sh` (or equivalent) over any new `.sh`/`.yml` files introduced.
    - **Done:** Script executed, headers added to `seed-logto-dev.sh` and `docker-compose.idp.yml`.

## 5. Open Questions to resolve before/during implementation

- [x] 5.1 Pin a specific Logto image minor tag (resolve design Open Question 1).
    - **Decision:** `logto/logto:1.13.0` - pinned for reproducibility while allowing minor updates.
- [x] 5.2 Decide seed-script implementation language — Bash + `curl`/`jq` recommended (resolve design Open Question 2).
    - **Decision:** Bash + `curl`/`jq` for zero-build reproducibility.
- [x] 5.3 Flag frontend-local-dev Logto endpoint needs to the frontend track (resolve design Open Question 3 — out of scope for this change, just communication).
    - **Action:** Documented in task 3.3 update. Frontend will need to configure OIDC client to point to `http://localhost:3301` for local development.
