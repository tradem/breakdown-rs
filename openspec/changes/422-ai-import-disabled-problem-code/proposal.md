<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Proposal: AI import disabled state — dedicated problem code (issue #422)

## Problem

When `AI_IMPORT_ENABLED` is unset, the AI import endpoints return
`ApiError::NotFound("AI import is disabled")` → generic `domain.not-found`.
The Flutter client may only branch on the stable `code` (AGENTS.md §5), so it
cannot distinguish "feature disabled on this instance" (no retry) from a
genuine not-found/transport failure (retry card). The device-testing session
rendered the futile retry card.

## Decisions (user-confirmed)

- **Status 404** for the new code `ai-import.disabled` — the surface genuinely
  does not exist on this instance; not transient (503 would suggest retrying),
  not a conflict (409 mis-semantics). 422/424 were considered and rejected
  (422 is reserved for request-content validation per RFC 9110 §15.5.21 and
  the registry's `domain.validation`; 424 means failed dependency).
- **Scope: backend + Flutter client.**

## Plan

### Backend

1. `crates/core/src/error_registry.rs`: new entry
   `AI_IMPORT_DISABLED { code: "ai-import.disabled", status: 404, title:
   "AI import disabled", extensions: &[] }` in the `problem_codes!`
   invocation; bump `PROBLEM_CODE_COUNT` 77 → 78.
2. `crates/api/src/problems/mod.rs`: new `ApiError::FeatureDisabled(&'static
   str)` variant mapping to the new code (the registry-constructed path; no
   per-handler status mapping).
3. `crates/api/src/handlers/mod.rs`: replace the three
   `ApiError::NotFound("AI import is disabled")` call sites
   (`enqueue_ai_upload`, `list_ai_providers`, `list_ai_models`) with
   `ApiError::FeatureDisabled(...)`.
4. Locales: `problem-ai-import-disabled` message in
   `crates/api/locales/en/errors.ftl` + `de/errors.ftl` (bundle-coverage
   bijection).
5. `openapi.yaml`: add `(status = 404, body = ProblemDetails)` to the three
   affected `#[utoipa::path]` annotations, regenerate with
   `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`.
6. Tests: update `ai_upload_is_not_found_when_the_feature_is_disabled`
   (handler_ai_import_ports.rs) to assert `ai-import.disabled`; regenerate
   problem goldens (`UPDATE_GOLDEN=1 cargo test -p api --test
   problem_golden`).

### Flutter client

1. `lib/features/ai_import/ai_config/ai_config_screen.dart`: discovery-error
   card branches on the new code → dedicated "AI import is not enabled on
   this instance" state WITHOUT a retry affordance (new key
   `ai-config-disabled`); `_ProviderPicker` AsyncError renders the disabled
   copy without retry when code is `ai-import.disabled`.
2. `lib/features/ai_import/ai_config/ai_config_state.dart`:
   `aiConfigErrorCopy` keys on the wire code `ai-import.disabled`.
3. Widget/unit tests for the disabled state; regenerate
   `vendor/breakdown_api/` from the updated `openapi.yaml` (drift discipline).
4. Follow-up issue: local-dev enablement friction (compose override for
   Garage host-port + payload env) — documented in the issue as needed for
   AI import testing, out of scope here.

## Version-bump plan

Following the repo convention (issues #409/#423): additive public-API
changes ride with the **open unreleased MINOR** sections instead of forcing
a new version. No crate version changed.

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.11.0 | 0.11.0 | none (rides with open 0.11.0 MINOR) | Additive `AI_IMPORT_DISABLED` registry const; entry under the open `## [0.11.0] - Unreleased` CHANGELOG section |
| `api` | 0.10.0 | 0.10.0 | none (rides with open 0.10.0 MINOR) | Additive `ApiError::FeatureDisabled` variant; entry under the open `## [0.10.0] - Unreleased` section |
| `infra` | 0.16.0 | 0.16.0 | none | No infra change |
| Flutter client | 0.3.0-alpha.3+12 | 0.3.0-alpha.4+13 | pre-release increment (fix) | Per merged-PR practice on the alpha line (even fixes bump `+N`); the `version-gate` ships the committed pubspec values, so `+N` must grow before any next release tag |
