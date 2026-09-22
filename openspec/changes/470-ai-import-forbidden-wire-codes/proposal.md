<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: AI import / settings credential-role denials get scoped wire codes (issue #470)

## Problem

The AI-config screens key their 403 narrative on problem codes the backend
never emits for this path, so the actionable "administrator role required" copy
is dead code in practice. The backend gates the AI-config management handlers
and the settings credential endpoints via `credential_role_gate` →
`forbidden_ai_config()` / `ApiError::Forbidden` → the generic registry code
`domain.forbidden` (crates/api/src/problems/mod.rs, `DOMAIN_FORBIDDEN`). The
client (`aiConfigErrorCopy`,
lib/features/ai_import/ai_config/ai_config_state.dart) matches
`'ai_config.forbidden' || 'settings.forbidden'` — no such wire codes exist, so a
real credential-role denial renders as the generic
`The configuration change failed (domain.forbidden).` (observed live:
`GET /v1/ai-import/config → 403` reported as an unspecific failure).

## Decisions (user-confirmed)

- **Direction: the backend emits scoped per-aggregate codes (ADR-031 Tranche 2),
  registered ONLY via `problem_codes!`** — consistent with the established
  per-aggregate kebab naming (`ai-config.*`, `settings.*`, `ai-import.disabled`
  already exist in the registry). No parameterless standalone consts.
- **Three new codes:**
  - `ai-config.forbidden` (403) — AI-config management (create/get/list/update/
    revoke) + provider/model discovery (credential-role gates).
  - `settings.forbidden` (403) — the settings-credential endpoints
    (create/rotate/update/revoke; credential-role gates).
  - `ai-import.forbidden` (403) — the AI *job* workflow (upload block-scope,
    job status/list/preview/apply; season-role/ownership gates) — kept distinct
    so the apply/upload screens keep their accurate "active costume role in
    this season" narrative vs. the config screens' "administrator role required"
    narrative.
- **Frontend keys on the decided wire codes** in every AI-import error switch
  (`aiConfigErrorCopy`, `aiApplyErrorCopy`, `aiUploadErrorCopy`,
  `jobWatchErrorCopy`); the config-screen 403 narrative keeps pointing at the
  credential-role requirement.
- **No `openapi.yaml` change:** the 403 responses are already declared on the
  in-scope routes; problem `code` is a runtime value, not a schema enum.
  (The `create_credential` route's missing 403 declaration is a pre-existing
  doc gap, tracked as a follow-up.)

## Plan

### Backend

1. `crates/core/src/error_registry.rs`: three new `problem_codes!` entries —
   `AI_CONFIG_FORBIDDEN { "ai-config.forbidden", 403 }`,
   `AI_IMPORT_FORBIDDEN { "ai-import.forbidden", 403 }`,
   `SETTINGS_FORBIDDEN { "settings.forbidden", 403 }`; bump
   `PROBLEM_CODE_COUNT` 78 → 81.
2. `crates/api/src/problems/mod.rs`: three new `ApiError` variants —
   `AiConfigForbidden(&'static str)`, `AiImportForbidden(&'static str)`,
   `SettingsForbidden(&'static str)` — each rendered through the single
   problem builder to its registered code (no per-handler status mapping).
3. `crates/api/src/handlers/mod.rs`:
   - `forbidden_ai_config()` → `ApiError::AiConfigForbidden(...)` (keeps the
     eight config-management call sites).
   - new `forbidden_ai_job()` → `ApiError::AiImportForbidden(...)` for
     `authorize_ai_block`, `authorize_ai_job`, and the apply IDOR/scope guards.
   - `list_ai_import_jobs` match arm `Err(ApiError::Forbidden(_))` →
     `Err(ApiError::AiImportForbidden(_))` (job-list visibility filter).
   - `list_ai_providers` / `list_ai_models` → `ApiError::AiConfigForbidden(...)`.
   - five settings credential handlers →
     `ApiError::SettingsForbidden(...)`.
4. Locales: `problem-ai-config-forbidden`, `problem-ai-import-forbidden`,
   `problem-settings-forbidden` in `crates/api/locales/en/errors.ftl` +
   `de/errors.ftl` (bundle-coverage bijection).
5. Golden snapshots: regenerate three problem goldens
   (`UPDATE_GOLDEN=1 cargo test -p api --test problem_golden`).
6. Tests (wire-level, contract can't drift again):
   - `ai_import_tests.rs`: `unauthorized_response_is_forbidden` now asserts the
     scoped code; add `forbidden_ai_job` → `ai-import.forbidden`.
   - `handler_ai_import_authz.rs`: provider/model denial tests assert
     `ai-config.forbidden`; add a `create_ai_config` denial →
     `ai-config.forbidden` and a settings-credential denial →
     `settings.forbidden` handler test.
7. CHANGELOG entries under the open unreleased MINOR sections of `core`
   (`[0.11.0]`) and `api` (`[0.10.0]`); no crate version bump (additive,
   rides with the open MINOR — #409/#423/#422 convention).

### Flutter client

1. `lib/features/ai_import/ai_config/ai_config_state.dart`:
   `aiConfigErrorCopy` matches `'ai-config.forbidden' || 'settings.forbidden'`
   (was the never-emitted `'ai_config.forbidden'`).
2. `lib/features/ai_import/import_jobs/apply_controller.dart`:
   `aiApplyErrorCopy` matches `'ai-import.forbidden'` (job/apply season-scope
   denial).
3. `lib/features/ai_import/import_jobs/import_state.dart`:
   `aiUploadErrorCopy` matches `'ai-import.forbidden' || 'ai_import.forbidden'`
   (server wire code + the client pre-gate deny code from `membership_gate.dart`).
4. `lib/features/ai_import/import_jobs/job_status_controller.dart`:
   `jobWatchErrorCopy` gains an `'ai-import.forbidden'` arm (job ownership/
   scope denial).
5. Version bump per merged-PR alpha-line practice
   (`pubspec.yaml` 0.3.0-alpha.15+24 → 0.3.0-alpha.15+25).
6. Tests: update the server-simulated 403 codes in
   `test/unit/ai_import_repositories_test.dart`,
   `test/features/ai_import/ai_config_screen_test.dart`,
   `test/features/ai_import/import_jobs_test.dart`,
   `test/features/ai_import/preview_apply_test.dart` to the new wire codes;
   keep the client-gate `ai_import.forbidden` deny-code tests unchanged.

## Version-bump plan

Following the repo convention (issues #409/#422/#423): additive public-API
changes ride with the open unreleased MINOR sections; no crate version changed.

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.11.0 | 0.11.0 | none (rides with open 0.11.0 MINOR) | Additive registry consts; entries under the open `## [0.11.0] - Unreleased` CHANGELOG section |
| `api` | 0.10.0 | 0.10.0 | none (rides with open 0.10.0 MINOR) | Additive `ApiError` variants; entry under the open `## [0.10.0] - Unreleased` section |
| `infra` | 0.16.0 | 0.16.0 | none | No infra change |
| Flutter client | 0.3.0-alpha.15+24 | 0.3.0-alpha.15+25 | pre-release increment (fix) | Per merged-PR practice on the alpha line (even fixes bump `+N`); the `version-gate` ships the committed pubspec values, so `+N` must grow before any next release tag |

## Follow-ups

- Deferred (sibling to #467): the other dead AI-import switch arms
  (`ai_import.payload_too_large`, `ai_import.unsupported_media_type`,
  `ai_import.disabled`, `ai_import.not_found`, `ai_config.conflict`,
  `ai_config.orphaned_credential`) — client-internal vs. generic backend codes
  that never fire; needs its own wire-surface audit.
- Pre-existing doc gap: `create_credential` and the gdrive/credential-rotation
  routes under-declare the 403 responses in `#[utoipa::path]` annotations.
