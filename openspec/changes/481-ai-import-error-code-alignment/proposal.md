<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: AI-import error switches key on the wire codes the backend actually emits (issue #481)

## Problem

Issue #470 fixed the 403 arms of the AI-import error switches. The remaining
non-forbidden arms still key on client-invented codes the backend never emits,
so several real errors render the generic `(${code})` fallback instead of the
maintained narrative.

| Switch arm | Client keyed on | Backend actually emits | Resolution |
|---|---|---|---|
| `aiUploadErrorCopy` payload-too-large | `ai_import.payload_too_large` | `http.payload-too-large` (413) | align (shared extractor, below) |
| `aiUploadErrorCopy` unsupported media type | `ai_import.unsupported_media_type` (+ client pre-check fabricates this) | `http.unsupported-media-type` (415) | scope → `ai-import.unsupported-media-type` + keep client code |
| `aiUploadErrorCopy` disabled | `ai_import.disabled` | `ai-import.disabled` (404) | align (already scoped, #422) |
| `jobWatchErrorCopy` not-found | `ai_import.not_found` | `domain.not-found` (404) | scope → `ai-import.not-found` |
| `aiConfigErrorCopy` conflict | `ai_config.conflict` | `concurrency.version-mismatch` (409) | scope → `ai-config.version-mismatch` |

Each was verified against the handlers/registry:

- `enqueue_ai_upload` and the route-level content-type gates emit the 415;
  `get_ai_import_job`/`get_ai_import_preview`/`apply_ai_import` emit the job
  404; `AiConfigCommandsImpl::update`/`revoke` surface a stale version as
  `ExecuteError::IncorrectExpectedVersion` → `DomainError::VersionConflict`
  → `concurrency.version-mismatch`.

## Decisions (user-confirmed)

- **Direction: the backend emits scoped per-aggregate codes (ADR-031 Tranche
  2), registered ONLY via `problem_codes!`** — consistent with issue #470 and
  the existing `ai-config.*`/`ai-import.*` kebab registry entries. No
  parameterless standalone consts.
- **Three new codes** (one per handler-owned narrative that #470's generic
  HTTP/domain/concurrency surface obscured):
  - `ai-import.unsupported-media-type` (415) — the AI-import upload
    content-type rejections (`upload_ai_script`, `upload_ai_schedule`, the
    shared `enqueue_ai_upload` fallback).
  - `ai-import.not-found` (404) — a missing/oracle-hidden AI import job
    (`get_ai_import_job`, `get_ai_import_preview`, `apply_ai_import`).
  - `ai-config.version-mismatch` (409) — the AI-config edit/revoke
    optimistic-lock conflict, preserving the typed
    `expected_version`/`current_version` extensions.
- **`ai-import.payload-too-large` is NOT added:** the 413 on the AI upload
  routes is emitted by the SHARED pre-handler `Bytes`/body-limit extractor
  (`LenLimitError` → `http.payload-too-large`) before the handler runs — a
  scoped code there would be unreachable in production. The client ALIGNS to
  `http.payload-too-large`. (Verified by `payload_too_large_is_413...` and the
  route-level `DefaultBodyLimit::max(ai_document_limit)` sharing one value
  with `ai_import_max_document_bytes`.)
- **`ai-import.disabled` already exists (issue #422)** — the disabled arm
  aligns to it.
- **One client-internal code is KEPT:** `ai_import.unsupported_media_type` is
  genuinely fabricated by the client pre-check (a non-PDF source under the
  script kind is rejected before any bytes leave the device). The switch gains
  the scoped server code as a second arm for the same copy.
- **Keep the copy keyed on the stable `code`** (never the server `detail`).

## Plan

### Backend

1. `crates/core/src/error_registry.rs`: three new `problem_codes!` entries —
   `AI_IMPORT_UNSUPPORTED_MEDIA_TYPE` (415), `AI_IMPORT_NOT_FOUND` (404),
   `AI_CONFIG_VERSION_MISMATCH` (409, extensions `expected_version`/
   `current_version`); bump `PROBLEM_CODE_COUNT` 81 → 84.
2. `crates/api/src/problems/mod.rs`: three new `ApiError` variants —
   `AiImportUnsupportedMediaType(&'static str)`,
   `AiImportNotFound(&'static str)`,
   `AiConfigVersionMismatch(AggregateVersion, AggregateVersion)` — each
   rendered through the single problem builder; the config variant keeps the
   typed extensions.
3. `crates/api/src/handlers/mod.rs`:
   - `upload_ai_script` / `upload_ai_schedule` content-type gates and the
     `enqueue_ai_upload` fallback → `AiImportUnsupportedMediaType`.
   - `get_ai_import_job` / `get_ai_import_preview` / `apply_ai_import` job
     not-found → `AiImportNotFound`.
   - `update_ai_config` / `revoke_ai_config`: translate
     `DomainError::VersionConflict` → `AiConfigVersionMismatch` at the API
     edge (keeps the typed expected/current extensions).
4. Locales: `problem-ai-config-version-mismatch` /
   `problem-ai-import-not-found` / `problem-ai-import-unsupported-media-type`
   in `crates/api/locales/en/errors.ftl` + `de/errors.ftl` (bundle-coverage
   bijection).
5. Golden snapshots: regenerate three (`UPDATE_GOLDEN=1 cargo test -p api
   --test problem_golden`).
6. Wire-level tests (contract can't drift again):
   `handler_ai_import_ports.rs` — wrong content-type →
   `ai-import.unsupported-media-type` (script + schedule), missing job →
   `ai-import.not-found`, config edit version conflict →
   `ai-config.version-mismatch` (+ extensions). `FakeAiConfigCommands` gains
   a `version_conflict` switch.
7. `openapi.yaml` `x-code-registry` refreshed (`UPDATE_OPENAPI=1 cargo test
   -p api --test openapi_drift`; extensions-only — no Dart client regen).
8. CHANGELOG entries under the open unreleased MINOR sections of `core`
   (`[0.11.0]`) and `api` (`[0.10.0]`); no crate version bump (additive,
   rides with the open MINOR — #470/#422/#423 convention).

### Flutter client

1. `lib/features/ai_import/import_jobs/import_state.dart`
   (`aiUploadErrorCopy`):
   - 413 aligns to `http.payload-too-large`.
   - 415 matches `'ai-import.unsupported-media-type' ||
     'ai_import.unsupported_media_type'` (scoped server code + the client
     pre-gate code, one narrative).
   - disabled aligns to `ai-import.disabled`.
2. `lib/features/ai_import/import_jobs/job_status_controller.dart`
   (`jobWatchErrorCopy`): not-found → `'ai-import.not-found'`; drop the stale
   "client-side 'job gone from the watch'" claim (nothing fabricates it).
3. `lib/features/ai_import/ai_config/ai_config_state.dart`
   (`aiConfigErrorCopy`): conflict → `'ai-config.version-mismatch'`.
4. `lib/data/ai_config_repository.dart`: update the `updateConfig` doc
   comment to name the scoped wire code.
5. Tests: point every server-simulated problem code at the new scoped wire
   code and extend the code-keyed copy tests
   (`import_jobs_test.dart`, `import_submit_screen_test.dart`,
   `ai_config_screen_test.dart`, `preview_apply_test.dart`,
   `ai_import_repositories_test.dart` — incl. a `jobWatchErrorCopy`
   code-keyed unit test).
6. Version bump per merged-PR alpha-line practice
   (`pubspec.yaml` 0.3.0-alpha.15+25 → 0.3.0-alpha.15+26).

## Version-bump plan

| Crate / package | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.11.0 | 0.11.0 | none (rides with open 0.11.0 MINOR) | Additive registry consts |
| `api` | 0.10.0 | 0.10.0 | none (rides with open 0.10.0 MINOR) | Additive `ApiError` variants |
| `infra` | 0.16.0 | 0.16.0 | none | No infra change |
| Flutter client | 0.3.0-alpha.15+25 | 0.3.0-alpha.15+26 | pre-release increment (fix) | Per merged-PR practice on the alpha line |

## Follow-ups

- The client's `costume.version_conflict` arm (costumes_controller.dart) is
  not in the registry and not part of #481's table — same class of stale arm;
  track separately.
