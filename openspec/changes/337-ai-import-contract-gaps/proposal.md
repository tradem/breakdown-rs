<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->

# Proposal: AI import contract gaps (issue #337)

## Why

While grounding the Flutter AI-import screens (`flutter-ai-import`) against
the checked-in contract, three discovery/rendering gaps surfaced:

1. **No config-list route.** `GET /v1/ai-import/config/{id}` exists, but
   there is no way to discover the caller's configuration. A lost id
   degrades to "not configured yet" even though a config exists.
2. **No job-list route.** Jobs are only reachable by id; there is no
   server-side "my jobs" view.
3. **Untyped preview response.** `GET /v1/ai-import/jobs/{id}/preview`
   declares the 200 body as plain `type: object`, so generated clients
   cannot consume preview rows structurally.

No drift: none of the three exist in the current backend (`routes()` in
`crates/api/src/handlers/mod.rs` has only `GET config/{id}`,
`GET jobs/{id}`, and `GET jobs/{id}/preview → Object`).

## What changes

1. **`GET /v1/ai-import/config` — caller's configs, newest-first.**
   - `// AUTHZ-GATE:` credential-role gate first (same as `get_ai_config`),
     then `AiConfigRepository::list_for_user(caller, limit, offset)`.
   - New required trait method with a default empty impl for test-only
     backends; implemented by `AiConfigRepositoryImpl` (SQL:
     `WHERE user_id = $1 ORDER BY updated_at DESC LIMIT/OFFSET`) and the
     API `FakeAiConfigRepo`.
   - Same path as `POST /ai-import/config`, so the route-coverage path
     count is unchanged; only the inventory entry stays
     `Requirement::Authenticated` (already covered by the `/ai-import`
     prefix rule).

2. **`GET /v1/ai-import/jobs` — caller's jobs, newest-first.**
   - Owner-scoped (`WHERE user_id = $1 ORDER BY created_at DESC, id DESC`)
     with the existing `ListParams` pagination shape (`limit`/`offset`).
   - No credential-role gate (jobs are per-user work, not credential
     management); per-job season-membership filtering mirrors
     `authorize_ai_job(Read)`: `Forbidden`/`NotFound` rows are skipped,
     infra errors propagate.
   - New required trait method `AiImportQueue::list_for_user` with default
     empty impl; implemented by `PgAiImportQueue` and `FakeAiImportQueue`.
   - New path pattern → route-coverage count 75 → 76 + inventory entry
     (`Requirement::Authenticated`, covered by the prefix rule).

3. **Typed preview: `AiImportPreviewResponse`.**
   - New core types in `crates/core/src/ai/preview.rs` (all `ToSchema`):
     `AiPreviewPayload` — `#[serde(tag = "kind", content = "data")]` enum
     `{ script(ScriptContext), schedule(ShootingSchedule),
     merged(MergedPreview) }` — plus
     `AiImportPreviewResponse { job_id, document_kind, status,
     preview: AiPreviewPayload }`.
   - Handler parses the stored bytes by `job.document_kind`: `Script` →
     `ScriptContext`; `Schedule` → `MergedPreview` first, falling back to
     `ShootingSchedule` (pre-merge shape). Covers all three shapes the
     workers persist; `MergeInput` is never served (worker-internal).
   - `GET .../preview` 200 body becomes `AiImportPreviewResponse`;
     `get_ai_import_job` is unchanged.

4. **Contract + tests.**
   - Register both new handlers in `ApiDoc` paths and `routes()`;
     regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1`).
   - Handler tests in `crates/api/tests/handler_ai_import_ports.rs`
     (list scoping/pagination, preview typed shapes, foreign-owner denial);
     fakes in `crates/api/tests/common/mod.rs` and
     `crates/api/src/handlers/test_helpers.rs` gain the new methods.
   - `crates/api/CHANGELOG.md` entry. Version bumps: `api` MINOR (new
     public routes + response type), `core` MINOR (new public types +
     required trait methods), `infra` MINOR (new trait impls are additive
     surface). Per ADR-020 D2 a required trait method is MAJOR in semver
     terms, which in this workspace's 0.x scheme bumps MINOR.

## What does not change

- No write-side coupling: both list methods are read-model queries consumed
  at the API edge (CQRS boundary intact).
- No new problem codes; failures reuse `NotFound`/`Forbidden`/`Validation`.
- The Flutter `flutter-ai-import` mapper swap is a client follow-up, not
  part of this change.
