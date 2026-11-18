<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: Muse Spark (muse-spark) -->

# Proposal: per-operation RFC 9457 error responses (issue #343)

## Context

Per ADR-031 every HTTP failure is an RFC 9457 `application/problem+json`
document with a stable `code`, but most operations in `backend/openapi.yaml`
document only their success response. The generated Dart client therefore has
no typed error contract. A drift test must prevent regression.

## Decision: per-verb minimum error sets (uniform, verb-level honest)

Every write/read handler propagates `DomainError` with `?` (any registry code
possible) and most handlers resolve parents via `find_by_id` (404) or carry a
handler-internal `AUTHZ-GATE` (403). Per-handler precision is impractical, so
the convention is a uniform minimum set per verb/category — a handler MAY
declare more where it is certain (e.g. `plan_scene_shoot` keeps its 400
body/path-mismatch response):

| Category | Minimum error set (`body = ProblemDetails`) |
|---|---|
| `POST` create / execute | `422` + `409`; plus `404` when a parent/series lookup precedes dispatch; plus `400` when body ids must match path ids; plus `403` when an `AUTHZ-GATE` exists |
| `PATCH` / `PUT` update | `404` + `422` + `409`; plus `403` when gated |
| `DELETE` | `404` + `409`; plus `403` when gated |
| `GET` single / id-addressed collection | `404`; plus `403` when gated; plus `400` when a required query/path param is validated (`require_*`) |
| `GET` collection with required query params (`require_*`) | `400` |
| Binary `GET` (PDF reports) | `403` + `404` (success keeps its binary body) |
| `POST` archive trigger (`manual_archive_reports`) | existing `403`/`404` gain `body = ProblemDetails` |

`401` is intentionally NOT declared per operation: authentication is enforced
by middleware uniformly, not per handler (the single existing `401` on
`get_season_membership` stays as-is, it is not removed).

## Changes

1. `crates/api/src/handlers/mod.rs`: add `body = ProblemDetails` error
   responses to the ~40 success-only operations listed in the drift scan
   (hierarchy creates/renames, shooting-day CRUD, character/costume writes,
   costume-category create/list, the full scene-shoot execution / notes /
   continuity-photo / wrap / report family, PDF routes, `manual_archive_reports`).
2. `crates/api/tests/openapi_drift.rs`: new test
   `every_operation_documents_an_error_response` — every operation must declare
   ≥1 non-2xx response whose content includes `application/problem+json`
   (post-`api_doc()` rewrite, which keys on the `ProblemDetails` schema ref).
   No production-code change needed for the media-type rewrite: it already
   renames any `ProblemDetails`-schema response generically.
3. Regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api
   --test openapi_drift`) and `frontend-flutter/vendor/breakdown_api/`
   (`frontend-flutter/scripts/regen-client.sh`).

## Non-goals

- No new problem codes, no handler logic changes, no success-schema changes.
- No per-handler exhaustive error enumeration (verb-level minimums only).
- No crate version bump: utoipa `responses(...)` attributes are compile-time
  documentation only; no Rust API changes.
