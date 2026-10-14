<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 656 — Expose workspace crate versions via a meta route (About screen)

## Why

Issue #656: the client must be able to fetch the **backend workspace crate
versions** from the backend itself instead of hardcoding anything in the
Flutter app. The versions are displayed on the About screen (issue #653).
Today there is no such route — the only unauthenticated metadata surface is
`GET /v1/health` (issue #637), and the `/ops/…` tree is authenticated and
ops-oriented.

## What Changes

- **New route `GET /v1/meta/versions`** (decided: not under `/ops/…` — the
  route must be reachable by regular *clients*, and `/ops` reads as an
  operator surface).
- **Auth posture (decided): `Requirement::Authenticated`** — a valid OIDC
  token is required, no block membership. Rationale: unlike `/health` (a
  container probe that must work without any token), this route is called by
  the signed-in app's About screen; requiring authentication avoids handing
  anonymous probes a backend version fingerprint while costing the client
  nothing (it is authenticated anyway). If the fetch fails (stale token,
  network), the About screen degrades gracefully to an error state.
- **Compile-time version sourcing:** `core` and `infra` each expose
  `pub const VERSION: &str = env!("CARGO_PKG_VERSION")`; `api` reports its
  own `CARGO_PKG_VERSION` plus the two re-exported constants. No runtime
  file reads, no `Cargo.toml` parsing. The three workspace crates carry
  *independent* versions (currently core 0.28.0 / infra 0.33.0 /
  api 0.26.0), so the response reports each crate individually.
- **Response shape:** `{"api": "0.26.0", "core": "0.28.0", "infra": "0.33.0"}`
  — explicit fields (not a map) so the generated Dart client gets typed
  accessors. Additive-only: new crates may later be added as new fields.
- utoipa path + schema annotations; `backend/openapi.yaml` regenerated via
  the `openapi_drift` test (`UPDATE_OPENAPI=1`).
- **Client:** regenerate `frontend-flutter/vendor/breakdown_api/` via
  `scripts/regen-client.sh` and commit the diff. The About screen
  (`AppInfoScreen`, #653) fetches and renders the backend crate versions via
  a repository method returning `Result` (no `throw` in `data/`/`domain/`),
  with a graceful `AsyncValue` error state while loading or on failure.

## Impact

- **Affected specs:** new delta spec `api-meta` (meta surface under `/v1`).
- **Affected code:** `crates/core/src/lib.rs`, `crates/infra/src/lib.rs`,
  `crates/api/src/meta.rs` (new), `crates/api/src/handlers/mod.rs` (route),
  `crates/api/src/auth/authorization.rs` (`/meta` → Authenticated),
  `crates/api/src/lib.rs` (ApiDoc), `backend/openapi.yaml`,
  `frontend-flutter/vendor/breakdown_api/**` (generated),
  `frontend-flutter/lib/features/app_info/**` + tests + l10n.
- **No version bumps** of workspace crates are required by this change (the
  route *reports* versions; it does not change any crate's public Rust API —
  the new `VERSION` consts are additive, additive-only changes do not force a
  bump under the current lockstep discipline; recorded explicitly in the
  version-bump table).
- **Security:** no tenant data; authed to avoid anonymous version
  fingerprinting. Threat model unaffected (`docs/security/security-architecture.md`
  needs no change — no new authz predicate, no new data flow beyond an
  authenticated static response).
